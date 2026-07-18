open Lwt
open Common

(* Public API: https://api.coin.z.com/public *)

(* 取引所ステータスの取得は「取引所が今使えるか」を調べるためのものなので、
   メンテナンス等でAPI全体が応答不能な場合 (Api_error) も例外にはせず、
   Error として結果に含めて返す。 *)
let status () =
  Lwt.catch
    (fun () ->
       ApiCommon.get_public "/v1/status" [] >>= fun json ->
       Lwt.return (Ok (Json.Util.member "status" json |> Json.Util.to_string)))
    (function
      | ApiCommon.Api_error e -> Lwt.return (Error e)
      | exn -> Lwt.fail exn)

type ticker = {
    ask: numeric;
    bid: numeric;
    high: numeric;
    last: numeric;
    low: numeric;
    symbol: string;
    timestamp: string;
    volume: numeric;
} [@@deriving yojson]

let tickers_of_json json =
  match [%of_yojson: ticker list] json with
  | Ok tickers -> tickers
  | Error msg -> failwith (!%"PublicApi.tickers_of_json: %s" msg)

let ticker ?symbol () =
  let query = [] |> list_add_opt (Option.map (fun s -> ("symbol", s)) symbol) in
  ApiCommon.get_public "/v1/ticker" query >>= fun json ->
  Lwt.return (tickers_of_json json)

type level = {
    price: numeric;
    size: numeric;
} [@@deriving yojson]

type orderbook = {
    asks: level list;
    bids: level list;
    symbol: string;
} [@@deriving yojson]

let orderbook_of_json json =
  match orderbook_of_yojson json with
  | Ok orderbook -> orderbook
  | Error msg -> failwith (!%"PublicApi.orderbook_of_json: %s" msg)

let orderbooks ~symbol () =
  ApiCommon.get_public "/v1/orderbooks" [("symbol", symbol)] >>= fun json ->
  Lwt.return (orderbook_of_json json)

type trade = {
    price: numeric;
    side: side;
    size: numeric;
    timestamp: string;
} [@@deriving yojson]

type trades = {
    pagination: pagination;
    list: trade list;
} [@@deriving yojson]

let trades_of_json json =
  match trades_of_yojson json with
  | Ok trades -> trades
  | Error msg -> failwith (!%"PublicApi.trades_of_json: %s" msg)

let trades ~symbol ?page ?count () =
  let query =
    [("symbol", symbol)]
    |> list_add_opt (Option.map (fun p -> ("page", !%"%d" p)) page)
    |> list_add_opt (Option.map (fun c -> ("count", !%"%d" c)) count)
  in
  ApiCommon.get_public "/v1/trades" query >>= fun json ->
  Lwt.return (trades_of_json json)

type interval =
  | Min1 | Min5 | Min10 | Min15 | Min30
  | Hour1 | Hour4 | Hour8 | Hour12
  | Day1 | Week1 | Month1

let string_of_interval = function
  | Min1 -> "1min" | Min5 -> "5min" | Min10 -> "10min"
  | Min15 -> "15min" | Min30 -> "30min"
  | Hour1 -> "1hour" | Hour4 -> "4hour" | Hour8 -> "8hour" | Hour12 -> "12hour"
  | Day1 -> "1day" | Week1 -> "1week" | Month1 -> "1month"

type kline = {
    openTime: string;
    open_: numeric [@key "open"];
    high: numeric;
    low: numeric;
    close: numeric;
    volume: numeric;
} [@@deriving yojson]

let klines_of_json json =
  match [%of_yojson: kline list] json with
  | Ok klines -> klines
  | Error msg -> failwith (!%"PublicApi.klines_of_json: %s" msg)

(* [date] は interval に応じて "YYYYMMDD" または "YYYY" 形式で指定する。 *)
let klines ~symbol ~interval ~date () =
  let query = [
      ("symbol", symbol);
      ("interval", string_of_interval interval);
      ("date", date);
    ] in
  ApiCommon.get_public "/v1/klines" query >>= fun json ->
  Lwt.return (klines_of_json json)

type symbol_rule = {
    symbol: string;
    minOrderSize: numeric;
    maxOrderSize: numeric;
    sizeStep: numeric;
    tickSize: numeric;
    takerFee: numeric;
    makerFee: numeric;
} [@@deriving yojson]

let symbols_of_json json =
  match [%of_yojson: symbol_rule list] json with
  | Ok symbols -> symbols
  | Error msg -> failwith (!%"PublicApi.symbols_of_json: %s" msg)

let symbols () =
  ApiCommon.get_public "/v1/symbols" [] >>= fun json ->
  Lwt.return (symbols_of_json json)
