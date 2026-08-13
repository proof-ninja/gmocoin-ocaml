open Lwt
open Common

(* GMOコイン Public WebSocket API
   wss://api.coin.z.com/ws/public/v1
   subscribe: {"command":"subscribe","channel":"ticker"|"orderbooks"|"trades","symbol":"<symbol>"}
   受信メッセージは {"channel":"...", ...} というフラットなJSON。
   サーバーから1分に1回pingが飛んでくるので、pongを返さないと3回連続無応答で切断される。 *)

let endpoint = "wss://api.coin.z.com/ws/public/v1"

(* api.coin.z.com は既定のTLSバックエンド (ocaml-tls) だと断続的に ECONNRESET で
   切断されることを確認済み (lib/http.ml 参照)。ここでは resolver を経由せず、
   直接 OpenSSL バックエンドのクライアントを組み立てる。 *)
let client_of_uri uri =
  let host = Uri.host_with_default ~default:"" uri in
  let port = match Uri.port uri with Some p -> p | None -> 443 in
  Lwt_unix.gethostbyname host >>= fun entry ->
  let ip = Ipaddr_unix.of_inet_addr entry.h_addr_list.(0) in
  Lwt.return (`OpenSSL (`Hostname host, `IP ip, `Port port))

let connect () =
  let uri = Uri.of_string endpoint in
  client_of_uri uri >>= fun client -> Websocket_lwt_unix.connect client uri

type channel = Ticker | Orderbooks | Trades

let string_of_channel = function
  | Ticker -> "ticker"
  | Orderbooks -> "orderbooks"
  | Trades -> "trades"

let send_subscribe conn ~channel ~symbol =
  let request =
    `Assoc
      [
        ("command", `String "subscribe");
        ("channel", `String (string_of_channel channel));
        ("symbol", `String symbol);
      ]
  in
  Websocket_lwt_unix.write conn
    (Websocket.Frame.create ~content:(Json.to_string request) ())

type ticker = {
  channel : string;
  ask : numeric;
  bid : numeric;
  high : numeric;
  last : numeric;
  low : numeric;
  symbol : string;
  timestamp : string;
  volume : numeric;
}
[@@deriving yojson]

let ticker_of_json json =
  match ticker_of_yojson json with
  | Ok ticker -> ticker
  | Error msg -> failwith (!%"Realtime.ticker_of_json: %s" msg)

type level = { price : numeric; size : numeric } [@@deriving yojson]

(* REST版と異なり、板情報は差分ではなく毎回スナップショット全体が届く。
   grouping はドキュメントに記載がないが実際のレスポンスに含まれるフィールド
   (価格のグルーピング幅と見られる)。念のため option にしておく。 *)
type orderbook = {
  channel : string;
  asks : level list;
  bids : level list;
  symbol : string;
  timestamp : string;
  grouping : string option; [@default None]
}
[@@deriving yojson]

let orderbook_of_json json =
  match orderbook_of_yojson json with
  | Ok orderbook -> orderbook
  | Error msg -> failwith (!%"Realtime.orderbook_of_json: %s" msg)

type trade = {
  channel : string;
  price : numeric;
  side : side;
  size : numeric;
  timestamp : string;
  symbol : string;
}
[@@deriving yojson]

let trade_of_json json =
  match trade_of_yojson json with
  | Ok trade -> trade
  | Error msg -> failwith (!%"Realtime.trade_of_json: %s" msg)

type update = Ticker of ticker | Orderbook of orderbook | Trade of trade

let update_of_json json =
  match Json.Util.member "channel" json with
  | `String "ticker" -> Some (Ticker (ticker_of_json json))
  | `String "orderbooks" -> Some (Orderbook (orderbook_of_json json))
  | `String "trades" -> Some (Trade (trade_of_json json))
  | _ -> None

let text_of_frame (frame : Websocket.Frame.t) =
  match frame.opcode with
  | Websocket.Frame.Opcode.Text -> Some frame.content
  | _ -> None

(* ネットワーク経路が明示的なCloseもRST/FINも送らずに黙って死んだ場合
   (Wi-Fiのスリープ復帰やNATのセッションタイムアウトなど)、[Websocket_lwt_unix.read]
   は例外にならずただ無期限にpendingし続け、再接続ロジックが一切働かなくなる。
   サーバーは60秒おきにpingを送ってくる仕様なので、それより十分長い時間
   何も届かなければ接続が死んでいるとみなして例外を投げ、再接続させる。 *)
let read_timeout = 90.0

type read_result = Received of Websocket.Frame.t | Timed_out

let read_with_timeout conn =
  Lwt.pick
    [
      (Websocket_lwt_unix.read conn >|= fun frame -> Received frame);
      (Lwt_unix.sleep read_timeout >|= fun () -> Timed_out);
    ]

(* [updates ~symbol channels] はWebSocketに接続し、指定した [symbol] について
   [channels] をすべて購読して、受信するたびに [update Lwt_stream.t] として流す。
   接続が切れて(または無応答が続いて)も内部では再接続しない。bitflyer-ocamlの
   [Realtime.updates]と同じく、再接続は呼び出し側の責務とする(以前はここで
   指数バックオフしながら内部で無限リトライしていたが、bitFlyer側と挙動が
   非対称で分かりにくいため統一した)。接続が切れた場合は[next]がそのまま例外を
   投げ、[Lwt_stream.from]の性質によりストリームの読み出しがその例外で終わる。 *)
let updates ~symbol channels =
  connect () >>= fun conn ->
  Lwt_list.iter_s (fun channel -> send_subscribe conn ~channel ~symbol) channels
  >>= fun () ->
  let rec next () =
    read_with_timeout conn >>= function
    | Timed_out ->
        Lwt.fail_with
          (!%"Realtime: no data received within %.0fs, treating connection as \
              dead"
             read_timeout)
    | Received frame -> (
        match frame.Websocket.Frame.opcode with
        | Websocket.Frame.Opcode.Ping ->
            Websocket_lwt_unix.write conn
              (Websocket.Frame.create ~opcode:Websocket.Frame.Opcode.Pong ())
            >>= next
        | Websocket.Frame.Opcode.Close ->
            Lwt.fail_with "Realtime: server closed the connection"
        | _ -> (
            match text_of_frame frame with
            | None -> next ()
            | Some content -> (
                match update_of_json (Json.from_string content) with
                | Some update -> Lwt.return_some update
                | None -> next ())))
  in
  Lwt.return (Lwt_stream.from next)

let single_channel_updates ~symbol channel of_update =
  updates ~symbol [ channel ] >>= fun stream ->
  Lwt.return (Lwt_stream.filter_map of_update stream)

(* 最新レート (ticker) だけを購読する。 *)
let ticker_updates ~symbol =
  single_channel_updates ~symbol Ticker (function
    | Ticker t -> Some t
    | _ -> None)

(* 板情報 (orderbooks) だけを購読する。全チャンネルまとめて受ける [updates] と違い、
   呼び出し側で [update] をパターンマッチして絞り込む必要がない。 *)
let orderbook_updates ~symbol =
  single_channel_updates ~symbol Orderbooks (function
    | Orderbook ob -> Some ob
    | _ -> None)

(* 取引履歴 (trades) だけを購読する。 *)
let trade_updates ~symbol =
  single_channel_updates ~symbol Trades (function
    | Trade tr -> Some tr
    | _ -> None)

(* Private WebSocket API
   wss://api.coin.z.com/ws/private/v1/<token>
   subscribe: {"command":"subscribe","channel":"executionEvents"|"orderEvents"|
               "positionEvents"|"positionSummaryEvents"} (symbolによる絞り込みは無い)。
   tokenはPrivateApi.ws_auth_postで取得する(有効期限60分)。 *)
let private_endpoint_prefix = "wss://api.coin.z.com/ws/private/v1"

type private_channel =
  | ExecutionEvents
  | OrderEvents
  | PositionEvents
  | PositionSummaryEvents

let string_of_private_channel = function
  | ExecutionEvents -> "executionEvents"
  | OrderEvents -> "orderEvents"
  | PositionEvents -> "positionEvents"
  | PositionSummaryEvents -> "positionSummaryEvents"

let send_private_subscribe conn channel =
  let request =
    `Assoc
      [
        ("command", `String "subscribe");
        ("channel", `String (string_of_private_channel channel));
      ]
  in
  Websocket_lwt_unix.write conn
    (Websocket.Frame.create ~content:(Json.to_string request) ())

(* positionIdはレバレッジ取引の場合のみ、orderPriceはMARKET注文の場合は
   含まれないためoption。 *)
type execution_event = {
  channel : string;
  orderId : int;
  executionId : int;
  symbol : string;
  settleType : string;
  executionType : string;
  side : side;
  executionPrice : numeric;
  executionSize : numeric;
  positionId : int option; [@default None]
  orderTimestamp : string;
  executionTimestamp : string;
  lossGain : numeric;
  fee : numeric;
  orderPrice : numeric option; [@default None]
  orderSize : numeric;
  orderExecutedSize : numeric;
  timeInForce : string;
  msgType : string;
}
[@@deriving yojson]

let execution_event_of_json json =
  match execution_event_of_yojson json with
  | Ok event -> event
  | Error msg -> failwith (!%"Realtime.execution_event_of_json: %s" msg)

(* cancelTypeはorderStatusがCANCELED/EXPIREDの場合のみ、orderPriceはMARKET注文の
   場合は含まれないためoption。 *)
type order_event = {
  channel : string;
  orderId : int;
  symbol : string;
  settleType : string;
  executionType : string;
  side : side;
  orderStatus : string;
  cancelType : string option; [@default None]
  orderTimestamp : string;
  orderPrice : numeric option; [@default None]
  orderSize : numeric;
  orderExecutedSize : numeric;
  losscutPrice : numeric;
  timeInForce : string;
  msgType : string;
}
[@@deriving yojson]

let order_event_of_json json =
  match order_event_of_yojson json with
  | Ok event -> event
  | Error msg -> failwith (!%"Realtime.order_event_of_json: %s" msg)

type position_event = {
  channel : string;
  positionId : int;
  symbol : string;
  side : side;
  size : numeric;
  orderdSize : numeric;
  price : numeric;
  lossGain : numeric;
  leverage : numeric;
  losscutPrice : numeric;
  timestamp : string;
  msgType : string;
}
[@@deriving yojson]

let position_event_of_json json =
  match position_event_of_yojson json with
  | Ok event -> event
  | Error msg -> failwith (!%"Realtime.position_event_of_json: %s" msg)

type position_summary_event = {
  channel : string;
  symbol : string;
  side : side;
  averagePositionRate : numeric;
  positionLossGain : numeric;
  sumOrderQuantity : numeric;
  sumPositionQuantity : numeric;
  timestamp : string;
  msgType : string;
}
[@@deriving yojson]

let position_summary_event_of_json json =
  match position_summary_event_of_yojson json with
  | Ok event -> event
  | Error msg -> failwith (!%"Realtime.position_summary_event_of_json: %s" msg)

type private_update =
  | ExecutionEvent of execution_event
  | OrderEvent of order_event
  | PositionEvent of position_event
  | PositionSummaryEvent of position_summary_event

let private_update_of_json json =
  match Json.Util.member "channel" json with
  | `String "executionEvents" ->
      Some (ExecutionEvent (execution_event_of_json json))
  | `String "orderEvents" -> Some (OrderEvent (order_event_of_json json))
  | `String "positionEvents" ->
      Some (PositionEvent (position_event_of_json json))
  | `String "positionSummaryEvents" ->
      Some (PositionSummaryEvent (position_summary_event_of_json json))
  | _ -> None

(* 公開チャンネル用の[updates]と違い、接続が切れても内部で自動再接続はしない
   (トークンが期限切れで無効になっている可能性があり、その場合はいくら
   再接続を試みても無意味なため)。接続が切れた場合は[next]がそのまま例外を
   投げ、[Lwt_stream.from]の性質によりストリームの読み出しがその例外で終わる。 *)
let private_updates ~token channels =
  let uri = Uri.of_string (private_endpoint_prefix ^ "/" ^ token) in
  client_of_uri uri >>= fun client ->
  Websocket_lwt_unix.connect client uri >>= fun conn ->
  Lwt_list.iter_s (send_private_subscribe conn) channels >>= fun () ->
  let rec next () =
    read_with_timeout conn >>= function
    | Timed_out ->
        Lwt.fail_with
          (!%"Realtime: no data received within %.0fs, treating connection as \
              dead"
             read_timeout)
    | Received frame -> (
        match frame.Websocket.Frame.opcode with
        | Websocket.Frame.Opcode.Ping ->
            Websocket_lwt_unix.write conn
              (Websocket.Frame.create ~opcode:Websocket.Frame.Opcode.Pong ())
            >>= next
        | Websocket.Frame.Opcode.Close ->
            Lwt.fail_with "Realtime: server closed the connection"
        | _ -> (
            match text_of_frame frame with
            | None -> next ()
            | Some content -> (
                match private_update_of_json (Json.from_string content) with
                | Some update -> Lwt.return_some update
                | None -> next ())))
  in
  Lwt.return (Lwt_stream.from next)
