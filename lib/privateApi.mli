open Common

(* 余力情報を取得 *)
type margin = {
    actualProfitLoss: string;
    availableAmount: string;
    margin: string;
    marginCallStatus: string;
    marginRatio: string;
    profitLoss: string;
    transferableAmount: string;
}
val margin_of_json : Json.t -> margin
val margin : Auth.t -> unit -> margin Lwt.t

(* 資産残高を取得 *)
type asset = {
    amount: string;
    available: string;
    conversionRate: string;
    symbol: string;
}
val assets_of_json : Json.t -> asset list
val assets : Auth.t -> unit -> asset list Lwt.t

type order_info = {
    rootOrderId: int;
    orderId: int;
    symbol: string;
    side: side;
    orderType: string;
    executionType: string;
    settleType: string;
    size: string;
    executedSize: string;
    price: string option;
    losscutPrice: string;
    status: string;
    cancelType: string option;
    timeInForce: string;
    timestamp: string;
}

type orders_response = {
    list: order_info list;
}
val orders_response_of_json : Json.t -> orders_response

(* 注文情報取得。[order_ids] はカンマ区切りで最大10件まで指定可能。 *)
val orders : Auth.t -> order_ids:string list -> unit -> order_info list Lwt.t

type active_orders_response = {
    pagination: pagination;
    list: order_info list;
}
val active_orders_response_of_json : Json.t -> active_orders_response

(* 有効注文一覧 *)
val active_orders :
  Auth.t -> symbol:symbol -> ?page:int -> ?count:int -> unit -> active_orders_response Lwt.t

type execution = {
    executionId: int;
    orderId: int;
    positionId: int option;
    symbol: string;
    side: side;
    settleType: string;
    size: string;
    price: string;
    lossGain: string;
    fee: string;
    timestamp: string;
}

type executions_response = {
    list: execution list;
}
val executions_response_of_json : Json.t -> executions_response

type order_ref = ById of int | ByExecutionIds of int list

(* 約定情報取得。orderId または executionId のどちらか一方を指定する。 *)
val executions : Auth.t -> order_ref -> execution list Lwt.t

type latest_executions_response = {
    pagination: pagination;
    list: execution list;
}
val latest_executions_response_of_json : Json.t -> latest_executions_response

(* 最新の約定一覧 (直近1日分) *)
val latest_executions :
  Auth.t -> symbol:symbol -> ?page:int -> ?count:int -> unit -> latest_executions_response Lwt.t

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
}

type open_positions_response = {
    pagination: pagination;
    list: position list;
}
val open_positions_response_of_json : Json.t -> open_positions_response

(* 建玉一覧を取得。対象: レバレッジ取引 *)
val open_positions :
  Auth.t -> symbol:symbol -> ?page:int -> ?count:int -> unit -> open_positions_response Lwt.t

type position_summary = {
    averagePositionRate: string;
    positionLossGain: string;
    side: side;
    sumOrderQuantity: string;
    sumPositionQuantity: string;
    symbol: string;
}

type position_summary_response = {
    list: position_summary list;
}
val position_summary_response_of_json : Json.t -> position_summary_response

(* 建玉サマリーを取得。対象: レバレッジ取引。symbol省略時は全銘柄分。 *)
val position_summary : Auth.t -> ?symbol:symbol -> unit -> position_summary list Lwt.t

type execution_type = Market | Limit | Stop
type time_in_force = FAK | FAS | FOK | SOK

(* 新規注文。対象: 現物取引、レバレッジ取引。戻り値は発注されたorderId。
   - price: execution_type が Limit/Stop の場合は必須。
   - losscut_price: レバレッジ取引で execution_type が Limit/Stop の場合のみ指定可能。 *)
val order :
  Auth.t ->
  symbol:symbol ->
  side:side ->
  execution_type:execution_type ->
  ?time_in_force:time_in_force ->
  ?price:string ->
  ?losscut_price:string ->
  ?cancel_before:bool ->
  size:string ->
  unit ->
  int Lwt.t

(* 注文キャンセル *)
val cancel_order : Auth.t -> order_id:int -> unit -> unit Lwt.t
