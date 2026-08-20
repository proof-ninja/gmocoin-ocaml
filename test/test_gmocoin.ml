open Gmocoin

(* JSON文字列は https://api.coin.z.com/docs/#outline のレスポンス例をそのまま使う。 *)

let test_side_roundtrip () =
  Alcotest.(check string)
    "BUY" "BUY"
    (Common.string_of_side (Common.side_of_string "BUY"));
  Alcotest.(check string)
    "SELL" "SELL"
    (Common.string_of_side (Common.side_of_string "SELL"));
  Alcotest.check_raises "invalid side" (Failure "Common.side_of_string: 'FOO'")
    (fun () -> ignore (Common.side_of_string "FOO"))

let test_numeric_of_yojson () =
  Alcotest.(check (float 0.0))
    "string" 455659.
    (Common.numeric_of_yojson (`String "455659") |> Result.get_ok);
  Alcotest.(check (float 0.0))
    "negative string" (-0.0001)
    (Common.numeric_of_yojson (`String "-0.0001") |> Result.get_ok);
  Alcotest.(check (float 0.0))
    "int" 5.
    (Common.numeric_of_yojson (`Int 5) |> Result.get_ok);
  Alcotest.(check (float 0.0))
    "float" 5.5
    (Common.numeric_of_yojson (`Float 5.5) |> Result.get_ok);
  match Common.numeric_of_yojson (`String "not-a-number") with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "expected Error for a non-numeric string"

let test_ticker () =
  let json =
    Common.Json.from_string
      {|
    [{"ask":"750760","bid":"750600","high":"762302","last":"756662","low":"704874",
      "symbol":"BTC","timestamp":"2018-03-30T12:34:56.789Z","volume":"194785.8484"}]
  |}
  in
  match PublicApi.tickers_of_json json with
  | [ t ] ->
      Alcotest.(check string) "symbol" "BTC" t.symbol;
      Alcotest.(check (float 0.0)) "bid" 750600. t.bid;
      Alcotest.(check (float 0.0)) "ask" 750760. t.ask
  | _ -> Alcotest.fail "expected exactly one ticker"

let test_orderbook () =
  let json =
    Common.Json.from_string
      {|
    {"asks":[{"price":"455659","size":"0.1"}],"bids":[{"price":"455659","size":"0.1"}],"symbol":"BTC"}
  |}
  in
  let ob = PublicApi.orderbook_of_json json in
  Alcotest.(check string) "symbol" "BTC" ob.symbol;
  Alcotest.(check int) "asks length" 1 (List.length ob.asks);
  Alcotest.(check int) "bids length" 1 (List.length ob.bids)

let test_trades () =
  let json =
    Common.Json.from_string
      {|
    {"pagination":{"currentPage":1,"count":30},
     "list":[{"price":"750760","side":"BUY","size":"0.1","timestamp":"2018-03-30T12:34:56.789Z"}]}
  |}
  in
  let tr = PublicApi.trades_of_json json in
  Alcotest.(check int) "pagination.count" 30 tr.pagination.count;
  Alcotest.(check int) "list length" 1 (List.length tr.list)

let test_klines () =
  let json =
    Common.Json.from_string
      {|
    [{"openTime":"1618588800000","open":"6418255","high":"6518250","low":"6318250","close":"6418253","volume":"0.0001"}]
  |}
  in
  match PublicApi.klines_of_json json with
  | [ k ] -> Alcotest.(check (float 0.0)) "open" 6418255. k.open_
  | _ -> Alcotest.fail "expected exactly one kline"

let test_symbols () =
  let json =
    Common.Json.from_string
      {|
    [{"symbol":"BTC","minOrderSize":"0.0001","maxOrderSize":"5","sizeStep":"0.0001","tickSize":"1","takerFee":"0.0005","makerFee":"-0.0001"}]
  |}
  in
  match PublicApi.symbols_of_json json with
  | [ s ] -> Alcotest.(check string) "symbol" "BTC" s.symbol
  | _ -> Alcotest.fail "expected exactly one symbol_rule"

let test_margin () =
  let json =
    Common.Json.from_string
      {|
    {"actualProfitLoss":"68286188","availableAmount":"57262506","margin":"1021682",
     "marginCallStatus":"NORMAL","marginRatio":"6683.6","profitLoss":"0","transferableAmount":"57262506"}
  |}
  in
  let m = PrivateApi.margin_of_json json in
  Alcotest.(check string) "marginCallStatus" "NORMAL" m.marginCallStatus

let test_assets () =
  let json =
    Common.Json.from_string
      {|
    [{"amount":"993982448","available":"993982448","conversionRate":"1","symbol":"JPY"},
     {"amount":"4.0002","available":"4.0002","conversionRate":"859614","symbol":"BTC"}]
  |}
  in
  Alcotest.(check int) "length" 2 (List.length (PrivateApi.assets_of_json json))

(* price は MARKET注文では省略され、cancelType は CANCELLING/CANCELED/EXPIRED のときのみ含まれる。
   [@default None] を付け忘れるとキー欠落時にパース自体が失敗するので、ここで確実に確認する。 *)
let test_orders_optional_fields () =
  let json =
    Common.Json.from_string
      {|
    {"list":[
      {"orderId":223456789,"rootOrderId":223456789,"symbol":"BTC_JPY","side":"BUY",
       "orderType":"NORMAL","executionType":"LIMIT","settleType":"OPEN","size":"0.02",
       "executedSize":"0.02","price":"1430001","losscutPrice":"0","status":"EXECUTED",
       "timeInForce":"FAS","timestamp":"2020-10-14T20:18:59.343Z"},
      {"rootOrderId":123456789,"orderId":123456789,"symbol":"BTC","side":"BUY",
       "orderType":"NORMAL","executionType":"LIMIT","settleType":"OPEN","size":"1",
       "executedSize":"0","price":"900000","losscutPrice":"0","status":"CANCELED",
       "cancelType":"USER","timeInForce":"FAS","timestamp":"2019-03-19T01:07:24.217Z"},
      {"orderId":1,"rootOrderId":1,"symbol":"BTC","side":"BUY","orderType":"NORMAL",
       "executionType":"MARKET","settleType":"OPEN","size":"1","executedSize":"1",
       "losscutPrice":"0","status":"EXECUTED","timeInForce":"FAK","timestamp":"2019-01-01T00:00:00.000Z"}
    ]}
  |}
  in
  match (PrivateApi.orders_response_of_json json).list with
  | [ executed; canceled; market ] ->
      Alcotest.(check (option string))
        "executed order has cancelType=None" None executed.cancelType;
      Alcotest.(check (option string))
        "canceled order has cancelType" (Some "USER") canceled.cancelType;
      Alcotest.(check (option (float 0.0)))
        "market order has no price" None market.price
  | _ -> Alcotest.fail "expected exactly three orders"

let test_executions () =
  let json =
    Common.Json.from_string
      {|
    {"list":[
      {"executionId":92123912,"orderId":223456789,"positionId":1234567,"symbol":"BTC_JPY",
       "side":"BUY","settleType":"OPEN","size":"0.02","price":"1900000","lossGain":"0",
       "fee":"223","timestamp":"2020-11-24T21:27:04.764Z"}
    ]}
  |}
  in
  let ex = PrivateApi.executions_response_of_json json in
  Alcotest.(check (option int))
    "positionId" (Some 1234567) (List.hd ex.list).positionId

let test_open_positions () =
  let json =
    Common.Json.from_string
      {|
    {"pagination":{"currentPage":1,"count":30},
     "list":[{"positionId":1234567,"symbol":"BTC_JPY","side":"BUY","size":"0.22",
              "orderdSize":"0","price":"876045","lossGain":"14","leverage":"4",
              "losscutPrice":"766540","timestamp":"2019-03-19T02:15:06.094Z"}]}
  |}
  in
  let op = PrivateApi.open_positions_response_of_json json in
  Alcotest.(check int) "list length" 1 (List.length op.list)

let test_position_summary () =
  let json =
    Common.Json.from_string
      {|
    {"list":[{"averagePositionRate":"715656","positionLossGain":"250675","side":"BUY",
              "sumOrderQuantity":"2","sumPositionQuantity":"11.6999","symbol":"BTC_JPY"}]}
  |}
  in
  let ps = PrivateApi.position_summary_response_of_json json in
  Alcotest.(check int) "list length" 1 (List.length ps.list)

(* 該当データが0件のとき、GMOコインのAPIはpagination/list等を含まないbareな
   空オブジェクト({})を返すことを実機で確認済み(activeOrders/latestExecutions)。
   [@@deriving yojson]の通常のパースだと必須フィールド欠落で失敗するため、
   空オブジェクトは明示的に空のlistとして扱う(of_json_or_empty)。 *)
let test_empty_object_response () =
  let json = Common.Json.from_string "{}" in
  let ao = PrivateApi.active_orders_response_of_json json in
  Alcotest.(check int) "active_orders: list length" 0 (List.length ao.list);
  let le = PrivateApi.latest_executions_response_of_json json in
  Alcotest.(check int) "latest_executions: list length" 0 (List.length le.list);
  let op = PrivateApi.open_positions_response_of_json json in
  Alcotest.(check int) "open_positions: list length" 0 (List.length op.list);
  let ps = PrivateApi.position_summary_response_of_json json in
  Alcotest.(check int) "position_summary: list length" 0 (List.length ps.list);
  let ors = PrivateApi.orders_response_of_json json in
  Alcotest.(check int) "orders: list length" 0 (List.length ors.list);
  let ex = PrivateApi.executions_response_of_json json in
  Alcotest.(check int) "executions: list length" 0 (List.length ex.list)

let test_api_error () =
  let json =
    Common.Json.from_string
      {|{"status":5,"messages":[{"message_code":"ERR-5201","message_string":"MAINTENANCE. Please wait for a while"}]}|}
  in
  let e = ApiCommon.api_error_of_json json in
  Alcotest.(check int) "status" 5 e.status;
  match e.messages with
  | [ m ] ->
      Alcotest.(check string) "message_code" "ERR-5201" m.message_code;
      Alcotest.(check string)
        "message_string" "MAINTENANCE. Please wait for a while" m.message_string
  | _ -> Alcotest.fail "expected exactly one message"

let test_realtime_ticker () =
  let json =
    Common.Json.from_string
      {|
    {"channel":"ticker","ask":"750760","bid":"750600","high":"762302","last":"756662",
     "low":"704874","symbol":"BTC","timestamp":"2018-03-30T12:34:56.789Z","volume":"194785.8484"}
  |}
  in
  let t = Realtime.ticker_of_json json in
  Alcotest.(check (float 0.0)) "bid" 750600. t.bid;
  Alcotest.(check (float 0.0)) "ask" 750760. t.ask

(* 実サーバーからの実際のレスポンスには、ドキュメントに記載のない "grouping" フィールドが
   含まれていた ([@default None] を付けていないと未知キーとしてパースに失敗する)。 *)
let test_realtime_orderbook () =
  let json =
    Common.Json.from_string
      {|
    {"channel":"orderbooks","asks":[{"price":"455659","size":"0.1"}],
     "bids":[{"price":"455655","size":"0.3"}],"symbol":"BTC",
     "timestamp":"2018-03-30T12:34:56.789Z","grouping":"1"}
  |}
  in
  let ob = Realtime.orderbook_of_json json in
  Alcotest.(check (option string)) "grouping" (Some "1") ob.grouping;
  Alcotest.(check int) "asks length" 1 (List.length ob.asks)

let test_realtime_orderbook_without_grouping () =
  let json =
    Common.Json.from_string
      {|
    {"channel":"orderbooks","asks":[],"bids":[],"symbol":"BTC",
     "timestamp":"2018-03-30T12:34:56.789Z"}
  |}
  in
  let ob = Realtime.orderbook_of_json json in
  Alcotest.(check (option string)) "grouping" None ob.grouping

let test_realtime_trade () =
  let json =
    Common.Json.from_string
      {|
    {"channel":"trades","price":"750760","side":"BUY","size":"0.1",
     "timestamp":"2018-03-30T12:34:56.789Z","symbol":"BTC"}
  |}
  in
  let tr = Realtime.trade_of_json json in
  Alcotest.(check (float 0.0)) "price" 750760. tr.price

let test_realtime_update_of_json_unknown_channel () =
  let json = Common.Json.from_string {|{"channel":"something_else"}|} in
  Alcotest.(check bool)
    "unknown channel is ignored" true
    (Realtime.update_of_json json = None)

let test_rate_limiter () =
  Lwt_main.run
    begin
      let open Lwt in
      let limiter = RateLimiter.create ~capacity:2 ~window:0.5 in
      let t0 = Unix.gettimeofday () in
      RateLimiter.acquire limiter >>= fun () ->
      RateLimiter.acquire limiter >>= fun () ->
      let elapsed = Unix.gettimeofday () -. t0 in
      Alcotest.(check bool) "first two calls don't block" true (elapsed < 0.2);
      let t1 = Unix.gettimeofday () in
      RateLimiter.acquire limiter >>= fun () ->
      let waited = Unix.gettimeofday () -. t1 in
      Alcotest.(check bool) "third call waits for the window" true (waited > 0.2);
      Lwt.return ()
    end

let () =
  Alcotest.run "gmocoin"
    [
      ( "Common",
        [
          Alcotest.test_case "side roundtrip" `Quick test_side_roundtrip;
          Alcotest.test_case "numeric_of_yojson" `Quick test_numeric_of_yojson;
        ] );
      ( "ApiCommon",
        [ Alcotest.test_case "api_error parsing" `Quick test_api_error ] );
      ( "PublicApi",
        [
          Alcotest.test_case "ticker" `Quick test_ticker;
          Alcotest.test_case "orderbook" `Quick test_orderbook;
          Alcotest.test_case "trades" `Quick test_trades;
          Alcotest.test_case "klines" `Quick test_klines;
          Alcotest.test_case "symbols" `Quick test_symbols;
        ] );
      ( "PrivateApi",
        [
          Alcotest.test_case "margin" `Quick test_margin;
          Alcotest.test_case "assets" `Quick test_assets;
          Alcotest.test_case "orders optional fields" `Quick
            test_orders_optional_fields;
          Alcotest.test_case "executions" `Quick test_executions;
          Alcotest.test_case "open_positions" `Quick test_open_positions;
          Alcotest.test_case "position_summary" `Quick test_position_summary;
          Alcotest.test_case "empty object response" `Quick
            test_empty_object_response;
        ] );
      ( "Realtime",
        [
          Alcotest.test_case "ticker" `Quick test_realtime_ticker;
          Alcotest.test_case "orderbook" `Quick test_realtime_orderbook;
          Alcotest.test_case "orderbook without grouping" `Quick
            test_realtime_orderbook_without_grouping;
          Alcotest.test_case "trade" `Quick test_realtime_trade;
          Alcotest.test_case "update_of_json unknown channel" `Quick
            test_realtime_update_of_json_unknown_channel;
        ] );
      ( "RateLimiter",
        [ Alcotest.test_case "sliding window" `Quick test_rate_limiter ] );
    ]
