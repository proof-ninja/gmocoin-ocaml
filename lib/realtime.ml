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
  client_of_uri uri >>= fun client ->
  Websocket_lwt_unix.connect client uri

type channel = Ticker | Orderbooks | Trades

let string_of_channel = function
  | Ticker -> "ticker"
  | Orderbooks -> "orderbooks"
  | Trades -> "trades"

let send_subscribe conn ~channel ~symbol =
  let request = `Assoc [
      ("command", `String "subscribe");
      ("channel", `String (string_of_channel channel));
      ("symbol", `String symbol);
    ]
  in
  Websocket_lwt_unix.write conn
    (Websocket.Frame.create ~content:(Json.to_string request) ())

type ticker = {
    channel: string;
    ask: numeric;
    bid: numeric;
    high: numeric;
    last: numeric;
    low: numeric;
    symbol: string;
    timestamp: string;
    volume: numeric;
} [@@deriving yojson]

let ticker_of_json json =
  match ticker_of_yojson json with
  | Ok ticker -> ticker
  | Error msg -> failwith (!%"Realtime.ticker_of_json: %s" msg)

type level = {
    price: numeric;
    size: numeric;
} [@@deriving yojson]

(* REST版と異なり、板情報は差分ではなく毎回スナップショット全体が届く。
   grouping はドキュメントに記載がないが実際のレスポンスに含まれるフィールド
   (価格のグルーピング幅と見られる)。念のため option にしておく。 *)
type orderbook = {
    channel: string;
    asks: level list;
    bids: level list;
    symbol: string;
    timestamp: string;
    grouping: string option [@default None];
} [@@deriving yojson]

let orderbook_of_json json =
  match orderbook_of_yojson json with
  | Ok orderbook -> orderbook
  | Error msg -> failwith (!%"Realtime.orderbook_of_json: %s" msg)

type trade = {
    channel: string;
    price: numeric;
    side: side;
    size: numeric;
    timestamp: string;
    symbol: string;
} [@@deriving yojson]

let trade_of_json json =
  match trade_of_yojson json with
  | Ok trade -> trade
  | Error msg -> failwith (!%"Realtime.trade_of_json: %s" msg)

type update =
  | Ticker of ticker
  | Orderbook of orderbook
  | Trade of trade

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

(* [updates ~symbol channels] はWebSocketに接続し、指定した [symbol] について
   [channels] をすべて購読して、受信するたびに [update Lwt_stream.t] として流す。 *)
let updates ~symbol channels =
  connect () >>= fun conn ->
  Lwt_list.iter_s (fun channel -> send_subscribe conn ~channel ~symbol) channels >>= fun () ->
  let rec next () =
    Websocket_lwt_unix.read conn >>= fun frame ->
    match frame.Websocket.Frame.opcode with
    | Websocket.Frame.Opcode.Ping ->
       Websocket_lwt_unix.write conn
         (Websocket.Frame.create ~opcode:Websocket.Frame.Opcode.Pong ())
       >>= next
    | Websocket.Frame.Opcode.Close -> Lwt.return_none
    | _ ->
       (match text_of_frame frame with
        | None -> next ()
        | Some content ->
           match update_of_json (Json.from_string content) with
           | Some update -> Lwt.return_some update
           | None -> next ())
  in
  Lwt.return (Lwt_stream.from next)

let single_channel_updates ~symbol channel of_update =
  updates ~symbol [channel] >>= fun stream ->
  Lwt.return (Lwt_stream.filter_map of_update stream)

(* 最新レート (ticker) だけを購読する。 *)
let ticker_updates ~symbol =
  single_channel_updates ~symbol Ticker (function Ticker t -> Some t | _ -> None)

(* 板情報 (orderbooks) だけを購読する。全チャンネルまとめて受ける [updates] と違い、
   呼び出し側で [update] をパターンマッチして絞り込む必要がない。 *)
let orderbook_updates ~symbol =
  single_channel_updates ~symbol Orderbooks (function Orderbook ob -> Some ob | _ -> None)

(* 取引履歴 (trades) だけを購読する。 *)
let trade_updates ~symbol =
  single_channel_updates ~symbol Trades (function Trade tr -> Some tr | _ -> None)
