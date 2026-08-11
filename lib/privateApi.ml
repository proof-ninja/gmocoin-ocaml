open Lwt
open Common

(* Private API: https://api.coin.z.com/private
   すべての呼出にAPIキーによる認証が必要。 *)

type margin = {
  actualProfitLoss : numeric;
  availableAmount : numeric;
  margin : numeric;
  marginCallStatus : string; (* NORMAL | MARGIN_CALL | LOSSCUT *)
  marginRatio : numeric;
  profitLoss : numeric;
  transferableAmount : numeric;
}
[@@deriving yojson]

let margin_of_json json =
  match margin_of_yojson json with
  | Ok margin -> margin
  | Error msg -> failwith (!%"PrivateApi.margin_of_json: %s" msg)

let margin auth () =
  ApiCommon.get auth "/v1/account/margin" [] >>= fun json ->
  Lwt.return (margin_of_json json)

type asset = {
  amount : numeric;
  available : numeric;
  conversionRate : numeric;
  symbol : string;
}
[@@deriving yojson]

let assets_of_json json =
  match [%of_yojson: asset list] json with
  | Ok assets -> assets
  | Error msg -> failwith (!%"PrivateApi.assets_of_json: %s" msg)

let assets auth () =
  ApiCommon.get auth "/v1/account/assets" [] >>= fun json ->
  Lwt.return (assets_of_json json)

type trading_volume_limit = {
  symbol : string;
  todayLimitOpenSize : numeric option; [@default None]
  todayLimitBuySize : numeric option; [@default None]
  todayLimitSellSize : numeric option; [@default None]
  takerFee : numeric;
  makerFee : numeric;
}
[@@deriving yojson]

type trading_volume = {
  jpyVolume : numeric;
  tierLevel : int;
  limit : trading_volume_limit list;
}
[@@deriving yojson]

let trading_volume_of_json json =
  match trading_volume_of_yojson json with
  | Ok trading_volume -> trading_volume
  | Error msg -> failwith (!%"PrivateApi.trading_volume_of_json: %s" msg)

let trading_volume auth () =
  ApiCommon.get auth "/v1/account/tradingVolume" [] >>= fun json ->
  Lwt.return (trading_volume_of_json json)

type fiat_history_entry = {
  amount : numeric;
  fee : numeric;
  status : string;
  symbol : string;
  timestamp : string;
}
[@@deriving yojson]

let fiat_history_entry_of_json json =
  match [%of_yojson: fiat_history_entry list] json with
  | Ok entries -> entries
  | Error msg -> failwith (!%"PrivateApi.fiat_history_entry_of_json: %s" msg)

let fiat_history_query ~from_timestamp ?to_timestamp () =
  [ ("fromTimestamp", from_timestamp) ]
  |> list_add_opt (Option.map (fun t -> ("toTimestamp", t)) to_timestamp)

let fiat_deposit_history auth ~from_timestamp ?to_timestamp () =
  let query = fiat_history_query ~from_timestamp ?to_timestamp () in
  ApiCommon.get auth "/v1/account/fiatDeposit/history" query >>= fun json ->
  Lwt.return (fiat_history_entry_of_json json)

let fiat_withdrawal_history auth ~from_timestamp ?to_timestamp () =
  let query = fiat_history_query ~from_timestamp ?to_timestamp () in
  ApiCommon.get auth "/v1/account/fiatWithdrawal/history" query >>= fun json ->
  Lwt.return (fiat_history_entry_of_json json)

type crypto_history_entry = {
  address : string;
  amount : numeric;
  fee : numeric option; [@default None]
  status : string;
  symbol : string;
  timestamp : string;
  txHash : string;
}
[@@deriving yojson]

let crypto_history_entry_of_json json =
  match [%of_yojson: crypto_history_entry list] json with
  | Ok entries -> entries
  | Error msg -> failwith (!%"PrivateApi.crypto_history_entry_of_json: %s" msg)

let crypto_history_query ~symbol ~from_timestamp ?to_timestamp () =
  [ ("symbol", symbol); ("fromTimestamp", from_timestamp) ]
  |> list_add_opt (Option.map (fun t -> ("toTimestamp", t)) to_timestamp)

let deposit_history auth ~symbol ~from_timestamp ?to_timestamp () =
  let query = crypto_history_query ~symbol ~from_timestamp ?to_timestamp () in
  ApiCommon.get auth "/v1/account/deposit/history" query >>= fun json ->
  Lwt.return (crypto_history_entry_of_json json)

let withdrawal_history auth ~symbol ~from_timestamp ?to_timestamp () =
  let query = crypto_history_query ~symbol ~from_timestamp ?to_timestamp () in
  ApiCommon.get auth "/v1/account/withdrawal/history" query >>= fun json ->
  Lwt.return (crypto_history_entry_of_json json)

(* 注文情報。price は MARKET 注文では、cancelType は CANCELLING/CANCELED/EXPIRED
   状態のときのみ含まれるため option。 *)
type order_info = {
  rootOrderId : int;
  orderId : int;
  symbol : string;
  side : side;
  orderType : string; (* NORMAL | LOSSCUT *)
  executionType : string; (* MARKET | LIMIT | STOP *)
  settleType : string; (* OPEN | CLOSE *)
  size : numeric;
  executedSize : numeric;
  price : numeric option; [@default None]
  losscutPrice : numeric;
  status : string;
      (* WAITING|ORDERED|MODIFYING|CANCELLING|CANCELED|EXECUTED|EXPIRED *)
  cancelType : string option; [@default None]
  timeInForce : string; (* FAK|FAS|FOK|SOK *)
  timestamp : string;
}
[@@deriving yojson]

type orders_response = { list : order_info list } [@@deriving yojson]

let orders_response_of_json json =
  match orders_response_of_yojson json with
  | Ok response -> response
  | Error msg -> failwith (!%"PrivateApi.orders_response_of_json: %s" msg)

(* [order_ids] はカンマ区切りで最大10件まで指定可能。 *)
let orders auth ~order_ids () =
  let query = [ ("orderId", String.concat "," order_ids) ] in
  ApiCommon.get auth "/v1/orders" query >>= fun json ->
  Lwt.return (orders_response_of_json json).list

type active_orders_response = {
  pagination : pagination;
  list : order_info list;
}
[@@deriving yojson]

let active_orders_response_of_json json =
  match active_orders_response_of_yojson json with
  | Ok response -> response
  | Error msg ->
      failwith (!%"PrivateApi.active_orders_response_of_json: %s" msg)

let active_orders auth ~symbol ?page ?count () =
  let query =
    [ ("symbol", symbol) ]
    |> list_add_opt (Option.map (fun p -> ("page", !%"%d" p)) page)
    |> list_add_opt (Option.map (fun c -> ("count", !%"%d" c)) count)
  in
  ApiCommon.get auth "/v1/activeOrders" query >>= fun json ->
  Lwt.return (active_orders_response_of_json json)

(* positionId はレバレッジ取引の場合のみ含まれる。 *)
type execution = {
  executionId : int;
  orderId : int;
  positionId : int option; [@default None]
  symbol : string;
  side : side;
  settleType : string; (* OPEN | CLOSE *)
  size : numeric;
  price : numeric;
  lossGain : numeric;
  fee : numeric;
  timestamp : string;
}
[@@deriving yojson]

type executions_response = { list : execution list } [@@deriving yojson]

let executions_response_of_json json =
  match executions_response_of_yojson json with
  | Ok response -> response
  | Error msg -> failwith (!%"PrivateApi.executions_response_of_json: %s" msg)

type order_ref = ById of int | ByExecutionIds of int list

(* orderId または executionId のどちらか一方を指定する
   (executionId はカンマ区切りで最大10件まで指定可能)。 *)
let executions auth order_ref =
  let query =
    match order_ref with
    | ById id -> [ ("orderId", !%"%d" id) ]
    | ByExecutionIds ids ->
        [ ("executionId", String.concat "," (List.map !%"%d" ids)) ]
  in
  ApiCommon.get auth "/v1/executions" query >>= fun json ->
  Lwt.return (executions_response_of_json json).list

type latest_executions_response = {
  pagination : pagination;
  list : execution list;
}
[@@deriving yojson]

let latest_executions_response_of_json json =
  match latest_executions_response_of_yojson json with
  | Ok response -> response
  | Error msg ->
      failwith (!%"PrivateApi.latest_executions_response_of_json: %s" msg)

(* 直近1日分の約定情報を返す。 *)
let latest_executions auth ~symbol ?page ?count () =
  let query =
    [ ("symbol", symbol) ]
    |> list_add_opt (Option.map (fun p -> ("page", !%"%d" p)) page)
    |> list_add_opt (Option.map (fun c -> ("count", !%"%d" c)) count)
  in
  ApiCommon.get auth "/v1/latestExecutions" query >>= fun json ->
  Lwt.return (latest_executions_response_of_json json)

type position = {
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
}
[@@deriving yojson]

type open_positions_response = { pagination : pagination; list : position list }
[@@deriving yojson]

let open_positions_response_of_json json =
  match open_positions_response_of_yojson json with
  | Ok response -> response
  | Error msg ->
      failwith (!%"PrivateApi.open_positions_response_of_json: %s" msg)

(* 対象: レバレッジ取引 *)
let open_positions auth ~symbol ?page ?count () =
  let query =
    [ ("symbol", symbol) ]
    |> list_add_opt (Option.map (fun p -> ("page", !%"%d" p)) page)
    |> list_add_opt (Option.map (fun c -> ("count", !%"%d" c)) count)
  in
  ApiCommon.get auth "/v1/openPositions" query >>= fun json ->
  Lwt.return (open_positions_response_of_json json)

type position_summary = {
  averagePositionRate : numeric;
  positionLossGain : numeric;
  side : side;
  sumOrderQuantity : numeric;
  sumPositionQuantity : numeric;
  symbol : string;
}
[@@deriving yojson]

type position_summary_response = { list : position_summary list }
[@@deriving yojson]

let position_summary_response_of_json json =
  match position_summary_response_of_yojson json with
  | Ok response -> response
  | Error msg ->
      failwith (!%"PrivateApi.position_summary_response_of_json: %s" msg)

(* 対象: レバレッジ取引。symbol を省略すると保有している全銘柄分を返す。 *)
let position_summary auth ?symbol () =
  let query = [] |> list_add_opt (Option.map (fun s -> ("symbol", s)) symbol) in
  ApiCommon.get auth "/v1/positionSummary" query >>= fun json ->
  Lwt.return (position_summary_response_of_json json).list

type execution_type = Market | Limit | Stop

let string_of_execution_type = function
  | Market -> "MARKET"
  | Limit -> "LIMIT"
  | Stop -> "STOP"

type time_in_force = FAK | FAS | FOK | SOK

let string_of_time_in_force = function
  | FAK -> "FAK"
  | FAS -> "FAS"
  | FOK -> "FOK"
  | SOK -> "SOK"

(* 新規注文をします。対象: 現物取引、レバレッジ取引。
   - price: executionType が LIMIT/STOP の場合は必須。
   - losscutPrice: レバレッジ取引で executionType が LIMIT/STOP の場合のみ指定可能。
   戻り値は発注されたorderId。 *)
let order auth ~symbol ~side ~execution_type ?time_in_force ?price
    ?losscut_price ?(cancel_before = false) ~size () =
  let fields =
    [
      ("symbol", `String symbol);
      ("side", side_to_yojson side);
      ("executionType", `String (string_of_execution_type execution_type));
      ("size", `String size);
    ]
    |> list_add_opt
         (Option.map
            (fun t -> ("timeInForce", `String (string_of_time_in_force t)))
            time_in_force)
    |> list_add_opt (Option.map (fun p -> ("price", `String p)) price)
    |> list_add_opt
         (Option.map (fun p -> ("losscutPrice", `String p)) losscut_price)
  in
  let fields =
    if cancel_before then ("cancelBefore", `Bool true) :: fields else fields
  in
  let data = `Assoc fields |> Json.to_string in
  ApiCommon.post auth "/v1/order" data >>= fun json ->
  Lwt.return (Json.Util.to_string json |> int_of_string)

(* 有効な注文を取消します。 *)
let cancel_order auth ~order_id () =
  let data = `Assoc [ ("orderId", `Int order_id) ] |> Json.to_string in
  ApiCommon.post auth "/v1/cancelOrder" data >>= fun _json -> Lwt.return ()

type transfer_type = Withdrawal | Deposit

let string_of_transfer_type = function
  | Withdrawal -> "WITHDRAWAL"
  | Deposit -> "DEPOSIT"

type transfer_result = { transferredAmount : numeric } [@@deriving yojson]

let transfer_result_of_json json =
  match [%of_yojson: transfer_result list] json with
  | Ok results -> results
  | Error msg -> failwith (!%"PrivateApi.transfer_result_of_json: %s" msg)

let transfer auth ~amount ~transfer_type () =
  let data =
    `Assoc
      [
        ("amount", `String amount);
        ("transferType", `String (string_of_transfer_type transfer_type));
      ]
    |> Json.to_string
  in
  ApiCommon.post auth "/v1/account/transfer" data >>= fun json ->
  Lwt.return (transfer_result_of_json json)

let change_order auth ~order_id ~price ?losscut_price () =
  let fields =
    [ ("orderId", `Int order_id); ("price", `String price) ]
    |> list_add_opt
         (Option.map (fun p -> ("losscutPrice", `String p)) losscut_price)
  in
  let data = `Assoc fields |> Json.to_string in
  ApiCommon.post auth "/v1/changeOrder" data >>= fun _json -> Lwt.return ()

type cancel_orders_failure = {
  message_code : string;
  message_string : string;
  orderId : int;
}
[@@deriving yojson]

type cancel_orders_result = {
  success : int list;
  failed : cancel_orders_failure list;
}
[@@deriving yojson]

let cancel_orders_result_of_json json =
  match cancel_orders_result_of_yojson json with
  | Ok result -> result
  | Error msg -> failwith (!%"PrivateApi.cancel_orders_result_of_json: %s" msg)

let cancel_orders auth ~order_ids () =
  let data =
    `Assoc [ ("orderIds", `List (List.map (fun id -> `Int id) order_ids)) ]
    |> Json.to_string
  in
  ApiCommon.post auth "/v1/cancelOrders" data >>= fun json ->
  Lwt.return (cancel_orders_result_of_json json)

let cancel_bulk_order auth ~symbols ?side ?settle_type ?desc () =
  let fields =
    [ ("symbols", `List (List.map (fun s -> `String s) symbols)) ]
    |> list_add_opt (Option.map (fun s -> ("side", side_to_yojson s)) side)
    |> list_add_opt
         (Option.map (fun s -> ("settleType", `String s)) settle_type)
    |> list_add_opt (Option.map (fun d -> ("desc", `Bool d)) desc)
  in
  let data = `Assoc fields |> Json.to_string in
  ApiCommon.post auth "/v1/cancelBulkOrder" data >>= fun json ->
  match [%of_yojson: int list] json with
  | Ok order_ids -> Lwt.return order_ids
  | Error msg -> failwith (!%"PrivateApi.cancel_bulk_order: %s" msg)

type settle_position = { positionId : int; size : string }

let json_of_settle_position { positionId; size } =
  `Assoc [ ("positionId", `Int positionId); ("size", `String size) ]

let close_order auth ~symbol ~side ~execution_type ?time_in_force ?price
    ~settle_position ?(cancel_before = false) () =
  let fields =
    [
      ("symbol", `String symbol);
      ("side", side_to_yojson side);
      ("executionType", `String (string_of_execution_type execution_type));
      ("settlePosition", json_of_settle_position settle_position);
    ]
    |> list_add_opt
         (Option.map
            (fun t -> ("timeInForce", `String (string_of_time_in_force t)))
            time_in_force)
    |> list_add_opt (Option.map (fun p -> ("price", `String p)) price)
  in
  let fields =
    if cancel_before then ("cancelBefore", `Bool true) :: fields else fields
  in
  let data = `Assoc fields |> Json.to_string in
  ApiCommon.post auth "/v1/closeOrder" data >>= fun json ->
  Lwt.return (Json.Util.to_string json |> int_of_string)

let close_bulk_order auth ~symbol ~side ~execution_type ?time_in_force ?price
    ~size () =
  let fields =
    [
      ("symbol", `String symbol);
      ("side", side_to_yojson side);
      ("executionType", `String (string_of_execution_type execution_type));
      ("size", `String size);
    ]
    |> list_add_opt
         (Option.map
            (fun t -> ("timeInForce", `String (string_of_time_in_force t)))
            time_in_force)
    |> list_add_opt (Option.map (fun p -> ("price", `String p)) price)
  in
  let data = `Assoc fields |> Json.to_string in
  ApiCommon.post auth "/v1/closeBulkOrder" data >>= fun json ->
  Lwt.return (Json.Util.to_string json |> int_of_string)

let change_losscut_price auth ~position_id ~losscut_price () =
  let data =
    `Assoc
      [
        ("positionId", `Int position_id); ("losscutPrice", `String losscut_price);
      ]
    |> Json.to_string
  in
  ApiCommon.post auth "/v1/changeLosscutPrice" data >>= fun _json ->
  Lwt.return ()

let ws_auth_post auth () =
  ApiCommon.post auth "/v1/ws-auth" "" >>= fun json ->
  Lwt.return (Json.Util.to_string json)

let ws_auth_put auth ~token () =
  let data = `Assoc [ ("token", `String token) ] |> Json.to_string in
  ApiCommon.put auth "/v1/ws-auth" data >>= fun _json -> Lwt.return ()

let ws_auth_delete auth ~token () =
  let data = `Assoc [ ("token", `String token) ] |> Json.to_string in
  ApiCommon.delete auth "/v1/ws-auth" data >>= fun _json -> Lwt.return ()
