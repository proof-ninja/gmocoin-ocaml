open Common

type channel = Ticker | Orderbooks | Trades

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

val ticker_of_json : Json.t -> ticker

type level = { price : numeric; size : numeric }

(* REST版と異なり、板情報は差分ではなく毎回スナップショット全体が届く。 *)
type orderbook = {
  channel : string;
  asks : level list;
  bids : level list;
  symbol : string;
  timestamp : string;
  grouping : string option;
}

val orderbook_of_json : Json.t -> orderbook

type trade = {
  channel : string;
  price : numeric;
  side : side;
  size : numeric;
  timestamp : string;
  symbol : string;
}

val trade_of_json : Json.t -> trade

type update = Ticker of ticker | Orderbook of orderbook | Trade of trade

val update_of_json : Json.t -> update option

(* [updates ~symbol channels] はPublic WebSocket API (wss://api.coin.z.com/ws/public/v1)
   に接続し、指定した [symbol] について [channels] をすべて購読して、
   受信するたびに [update Lwt_stream.t] として流す。 *)
val updates : symbol:symbol -> channel list -> update Lwt_stream.t Lwt.t

(* 単一チャンネルだけを購読し、[update]でのパターンマッチ不要でその型のストリームを直接返す。
   内部的には [updates] を1チャンネルだけで呼び出しているだけ。 *)
val ticker_updates : symbol:symbol -> ticker Lwt_stream.t Lwt.t
val orderbook_updates : symbol:symbol -> orderbook Lwt_stream.t Lwt.t
val trade_updates : symbol:symbol -> trade Lwt_stream.t Lwt.t

(* Private WebSocket API (wss://api.coin.z.com/ws/private/v1/<token>)。
   symbolによる絞り込みは無く全銘柄共通。 *)
type private_channel =
  | ExecutionEvents
  | OrderEvents
  | PositionEvents
  | PositionSummaryEvents

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
  positionId : int option;
  orderTimestamp : string;
  executionTimestamp : string;
  lossGain : numeric;
  fee : numeric;
  orderPrice : numeric option;
  orderSize : numeric;
  orderExecutedSize : numeric;
  timeInForce : string;
  msgType : string; (* "ER" *)
}

val execution_event_of_json : Json.t -> execution_event

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
  cancelType : string option;
  orderTimestamp : string;
  orderPrice : numeric option;
  orderSize : numeric;
  orderExecutedSize : numeric;
  losscutPrice : numeric;
  timeInForce : string;
  msgType : string; (* "NOR" | "ROR" | "COR" | "ER" *)
}

val order_event_of_json : Json.t -> order_event

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
  msgType : string; (* "OPR" | "UPR" | "ULR" | "CPR" *)
}

val position_event_of_json : Json.t -> position_event

type position_summary_event = {
  channel : string;
  symbol : string;
  side : side;
  averagePositionRate : numeric;
  positionLossGain : numeric;
  sumOrderQuantity : numeric;
  sumPositionQuantity : numeric;
  timestamp : string;
  msgType : string; (* "INIT" | "UPDATE" | "PERIODIC" *)
}

val position_summary_event_of_json : Json.t -> position_summary_event

type private_update =
  | ExecutionEvent of execution_event
  | OrderEvent of order_event
  | PositionEvent of position_event
  | PositionSummaryEvent of position_summary_event

val private_update_of_json : Json.t -> private_update option

(* [private_updates ~token channels] はPrivate WebSocket APIに接続し、
   [channels]を購読して受信するたびに[private_update Lwt_stream.t]として流す。
   [token]はPrivateApi.ws_auth_postで取得したアクセストークン(有効期限60分)。

   公開チャンネル用の[updates]と違い、接続が切れても内部で自動再接続はしない
   (トークンが期限切れで無効になっている可能性があり、その場合はいくら
   再接続を試みても無意味なため)。接続が切れた場合はストリームの読み出しが
   例外で終わるので、呼び出し側で新しいトークンを取得してから改めて呼び直すこと。 *)
val private_updates :
  token:string -> private_channel list -> private_update Lwt_stream.t Lwt.t
