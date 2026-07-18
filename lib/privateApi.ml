open Lwt
open Common

(* Private API: https://api.coin.z.com/private
   すべての呼出にAPIキーによる認証が必要。 *)

type margin = {
    actualProfitLoss: string;
    availableAmount: string;
    margin: string;
    marginCallStatus: string; (* NORMAL | MARGIN_CALL | LOSSCUT *)
    marginRatio: string;
    profitLoss: string;
    transferableAmount: string;
} [@@deriving yojson]

let margin_of_json json =
  match margin_of_yojson json with
  | Ok margin -> margin
  | Error msg -> failwith (!%"PrivateApi.margin_of_json: %s" msg)

let margin auth () =
  ApiCommon.get auth "/v1/account/margin" [] >>= fun json ->
  Lwt.return (margin_of_json json)

type asset = {
    amount: string;
    available: string;
    conversionRate: string;
    symbol: string;
} [@@deriving yojson]

let assets_of_json json =
  match [%of_yojson: asset list] json with
  | Ok assets -> assets
  | Error msg -> failwith (!%"PrivateApi.assets_of_json: %s" msg)

let assets auth () =
  ApiCommon.get auth "/v1/account/assets" [] >>= fun json ->
  Lwt.return (assets_of_json json)

(* 注文情報。price は MARKET 注文では、cancelType は CANCELLING/CANCELED/EXPIRED
   状態のときのみ含まれるため option。 *)
type order_info = {
    rootOrderId: int;
    orderId: int;
    symbol: string;
    side: side;
    orderType: string; (* NORMAL | LOSSCUT *)
    executionType: string; (* MARKET | LIMIT | STOP *)
    settleType: string; (* OPEN | CLOSE *)
    size: string;
    executedSize: string;
    price: string option [@default None];
    losscutPrice: string;
    status: string; (* WAITING|ORDERED|MODIFYING|CANCELLING|CANCELED|EXECUTED|EXPIRED *)
    cancelType: string option [@default None];
    timeInForce: string; (* FAK|FAS|FOK|SOK *)
    timestamp: string;
} [@@deriving yojson]

type orders_response = {
    list: order_info list;
} [@@deriving yojson]

let orders_response_of_json json =
  match orders_response_of_yojson json with
  | Ok response -> response
  | Error msg -> failwith (!%"PrivateApi.orders_response_of_json: %s" msg)

(* [order_ids] はカンマ区切りで最大10件まで指定可能。 *)
let orders auth ~order_ids () =
  let query = [("orderId", String.concat "," order_ids)] in
  ApiCommon.get auth "/v1/orders" query >>= fun json ->
  Lwt.return (orders_response_of_json json).list

type active_orders_response = {
    pagination: pagination;
    list: order_info list;
} [@@deriving yojson]

let active_orders_response_of_json json =
  match active_orders_response_of_yojson json with
  | Ok response -> response
  | Error msg -> failwith (!%"PrivateApi.active_orders_response_of_json: %s" msg)

let active_orders auth ~symbol ?page ?count () =
  let query =
    [("symbol", symbol)]
    |> list_add_opt (Option.map (fun p -> ("page", !%"%d" p)) page)
    |> list_add_opt (Option.map (fun c -> ("count", !%"%d" c)) count)
  in
  ApiCommon.get auth "/v1/activeOrders" query >>= fun json ->
  Lwt.return (active_orders_response_of_json json)

(* positionId はレバレッジ取引の場合のみ含まれる。 *)
type execution = {
    executionId: int;
    orderId: int;
    positionId: int option [@default None];
    symbol: string;
    side: side;
    settleType: string; (* OPEN | CLOSE *)
    size: string;
    price: string;
    lossGain: string;
    fee: string;
    timestamp: string;
} [@@deriving yojson]

type executions_response = {
    list: execution list;
} [@@deriving yojson]

let executions_response_of_json json =
  match executions_response_of_yojson json with
  | Ok response -> response
  | Error msg -> failwith (!%"PrivateApi.executions_response_of_json: %s" msg)

type order_ref = ById of int | ByExecutionIds of int list

(* orderId または executionId のどちらか一方を指定する
   (executionId はカンマ区切りで最大10件まで指定可能)。 *)
let executions auth order_ref =
  let query = match order_ref with
    | ById id -> [("orderId", !%"%d" id)]
    | ByExecutionIds ids -> [("executionId", String.concat "," (List.map (!%"%d") ids))]
  in
  ApiCommon.get auth "/v1/executions" query >>= fun json ->
  Lwt.return (executions_response_of_json json).list

type latest_executions_response = {
    pagination: pagination;
    list: execution list;
} [@@deriving yojson]

let latest_executions_response_of_json json =
  match latest_executions_response_of_yojson json with
  | Ok response -> response
  | Error msg -> failwith (!%"PrivateApi.latest_executions_response_of_json: %s" msg)

(* 直近1日分の約定情報を返す。 *)
let latest_executions auth ~symbol ?page ?count () =
  let query =
    [("symbol", symbol)]
    |> list_add_opt (Option.map (fun p -> ("page", !%"%d" p)) page)
    |> list_add_opt (Option.map (fun c -> ("count", !%"%d" c)) count)
  in
  ApiCommon.get auth "/v1/latestExecutions" query >>= fun json ->
  Lwt.return (latest_executions_response_of_json json)

type position = {
    positionId: int;
    symbol: string;
    side: side;
    size: string;
    orderdSize: string;
    price: string;
    lossGain: string;
    leverage: string;
    losscutPrice: string;
    timestamp: string;
} [@@deriving yojson]

type open_positions_response = {
    pagination: pagination;
    list: position list;
} [@@deriving yojson]

let open_positions_response_of_json json =
  match open_positions_response_of_yojson json with
  | Ok response -> response
  | Error msg -> failwith (!%"PrivateApi.open_positions_response_of_json: %s" msg)

(* 対象: レバレッジ取引 *)
let open_positions auth ~symbol ?page ?count () =
  let query =
    [("symbol", symbol)]
    |> list_add_opt (Option.map (fun p -> ("page", !%"%d" p)) page)
    |> list_add_opt (Option.map (fun c -> ("count", !%"%d" c)) count)
  in
  ApiCommon.get auth "/v1/openPositions" query >>= fun json ->
  Lwt.return (open_positions_response_of_json json)

type position_summary = {
    averagePositionRate: string;
    positionLossGain: string;
    side: side;
    sumOrderQuantity: string;
    sumPositionQuantity: string;
    symbol: string;
} [@@deriving yojson]

type position_summary_response = {
    list: position_summary list;
} [@@deriving yojson]

let position_summary_response_of_json json =
  match position_summary_response_of_yojson json with
  | Ok response -> response
  | Error msg -> failwith (!%"PrivateApi.position_summary_response_of_json: %s" msg)

(* 対象: レバレッジ取引。symbol を省略すると保有している全銘柄分を返す。 *)
let position_summary auth ?symbol () =
  let query = [] |> list_add_opt (Option.map (fun s -> ("symbol", s)) symbol) in
  ApiCommon.get auth "/v1/positionSummary" query >>= fun json ->
  Lwt.return (position_summary_response_of_json json).list

type execution_type = Market | Limit | Stop

let string_of_execution_type = function
  | Market -> "MARKET" | Limit -> "LIMIT" | Stop -> "STOP"

type time_in_force = FAK | FAS | FOK | SOK

let string_of_time_in_force = function
  | FAK -> "FAK" | FAS -> "FAS" | FOK -> "FOK" | SOK -> "SOK"

(* 新規注文をします。対象: 現物取引、レバレッジ取引。
   - price: executionType が LIMIT/STOP の場合は必須。
   - losscutPrice: レバレッジ取引で executionType が LIMIT/STOP の場合のみ指定可能。
   戻り値は発注されたorderId。 *)
let order auth ~symbol ~side ~execution_type
      ?time_in_force ?price ?losscut_price ?(cancel_before=false) ~size () =
  let fields =
    [
      ("symbol", `String symbol);
      ("side", side_to_yojson side);
      ("executionType", `String (string_of_execution_type execution_type));
      ("size", `String size);
    ]
    |> list_add_opt (Option.map (fun t -> ("timeInForce", `String (string_of_time_in_force t))) time_in_force)
    |> list_add_opt (Option.map (fun p -> ("price", `String p)) price)
    |> list_add_opt (Option.map (fun p -> ("losscutPrice", `String p)) losscut_price)
  in
  let fields = if cancel_before then ("cancelBefore", `Bool true) :: fields else fields in
  let data = `Assoc fields |> Json.to_string in
  ApiCommon.post auth "/v1/order" data >>= fun json ->
  Lwt.return (Json.Util.to_string json |> int_of_string)

(* 有効な注文を取消します。 *)
let cancel_order auth ~order_id () =
  let data = `Assoc [("orderId", `Int order_id)] |> Json.to_string in
  ApiCommon.post auth "/v1/cancelOrder" data >>= fun _json ->
  Lwt.return ()
