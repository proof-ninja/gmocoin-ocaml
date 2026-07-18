open Common

(* 取引所ステータス: "OPEN" | "PRE_OPEN" | "MAINTENANCE" など。
   API全体が応答不能な場合 (メンテナンス等) も例外にはせず Error として返す。 *)
val status : unit -> (string, ApiCommon.api_error) result Lwt.t

type ticker = {
    ask: string;
    bid: string;
    high: string;
    last: string;
    low: string;
    symbol: string;
    timestamp: string;
    volume: string;
}

val tickers_of_json : Json.t -> ticker list

(* symbol を省略すると全銘柄分を返す。 *)
val ticker : ?symbol:symbol -> unit -> ticker list Lwt.t

type level = {
    price: string;
    size: string;
}

type orderbook = {
    asks: level list;
    bids: level list;
    symbol: string;
}

val orderbook_of_json : Json.t -> orderbook

val orderbooks : symbol:symbol -> unit -> orderbook Lwt.t

type trade = {
    price: string;
    side: side;
    size: string;
    timestamp: string;
}

type trades = {
    pagination: pagination;
    list: trade list;
}

val trades_of_json : Json.t -> trades

val trades : symbol:symbol -> ?page:int -> ?count:int -> unit -> trades Lwt.t

type interval =
  | Min1 | Min5 | Min10 | Min15 | Min30
  | Hour1 | Hour4 | Hour8 | Hour12
  | Day1 | Week1 | Month1

type kline = {
    openTime: string;
    open_: string;
    high: string;
    low: string;
    close: string;
    volume: string;
}

val klines_of_json : Json.t -> kline list

(* [date] は interval に応じて "YYYYMMDD" または "YYYY" 形式で指定する。 *)
val klines : symbol:symbol -> interval:interval -> date:string -> unit -> kline list Lwt.t

type symbol_rule = {
    symbol: string;
    minOrderSize: string;
    maxOrderSize: string;
    sizeStep: string;
    tickSize: string;
    takerFee: string;
    makerFee: string;
}

val symbols_of_json : Json.t -> symbol_rule list

val symbols : unit -> symbol_rule list Lwt.t
