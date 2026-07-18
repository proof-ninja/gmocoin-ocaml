open Common

type channel = Ticker | Orderbooks | Trades

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
}
val ticker_of_json : Json.t -> ticker

type level = {
    price: numeric;
    size: numeric;
}

(* REST版と異なり、板情報は差分ではなく毎回スナップショット全体が届く。 *)
type orderbook = {
    channel: string;
    asks: level list;
    bids: level list;
    symbol: string;
    timestamp: string;
    grouping: string option;
}
val orderbook_of_json : Json.t -> orderbook

type trade = {
    channel: string;
    price: numeric;
    side: side;
    size: numeric;
    timestamp: string;
    symbol: string;
}
val trade_of_json : Json.t -> trade

type update =
  | Ticker of ticker
  | Orderbook of orderbook
  | Trade of trade

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
