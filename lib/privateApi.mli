open Common

(* 余力情報を取得 *)
type margin = {
  actualProfitLoss : numeric;
  availableAmount : numeric;
  margin : numeric;
  marginCallStatus : string;
  marginRatio : numeric;
  profitLoss : numeric;
  transferableAmount : numeric;
}

val margin_of_json : Json.t -> margin
val margin : Auth.t -> unit -> margin Lwt.t

(* 資産残高を取得 *)
type asset = {
  amount : numeric;
  available : numeric;
  conversionRate : numeric;
  symbol : string;
}

val assets_of_json : Json.t -> asset list
val assets : Auth.t -> unit -> asset list Lwt.t

(* 取引高情報を取得。limitの内訳はレバレッジ銘柄("todayLimitOpenSize")と
   現物銘柄("todayLimitBuySize"/"todayLimitSellSize")で異なるフィールドが
   使われるため、symbol/takerFee/makerFee以外はoptionにしている。 *)
type trading_volume_limit = {
  symbol : string;
  todayLimitOpenSize : numeric option;
  todayLimitBuySize : numeric option;
  todayLimitSellSize : numeric option;
  takerFee : numeric;
  makerFee : numeric;
}

type trading_volume = {
  jpyVolume : numeric;
  tierLevel : int;
  limit : trading_volume_limit list;
}

val trading_volume_of_json : Json.t -> trading_volume
val trading_volume : Auth.t -> unit -> trading_volume Lwt.t

(* 日本円の入金履歴・出金履歴で共通のレスポンス形式。 *)
type fiat_history_entry = {
  amount : numeric;
  fee : numeric;
  status : string; (* "EXECUTED" *)
  symbol : string; (* "JPY" *)
  timestamp : string;
}

val fiat_history_entry_of_json : Json.t -> fiat_history_entry list

(* 日本円の入金履歴を取得。[from_timestamp]必須(UTC、
   "YYYY-MM-DDTHH:MM:SS.SSSZ")。[to_timestamp]省略時はfrom_timestamp+30分
   (from_timestampとto_timestampの差は最大30分)。 *)
val fiat_deposit_history :
  Auth.t ->
  from_timestamp:string ->
  ?to_timestamp:string ->
  unit ->
  fiat_history_entry list Lwt.t

(* 日本円の出金履歴を取得。パラメータはfiat_deposit_historyと同様。 *)
val fiat_withdrawal_history :
  Auth.t ->
  from_timestamp:string ->
  ?to_timestamp:string ->
  unit ->
  fiat_history_entry list Lwt.t

(* 暗号資産の預入履歴・送付履歴で共通のレスポンス形式。feeはドキュメントの
   フィールド表には載っているがレスポンス例には無く、実際に省略されうるため
   optionにしている。 *)
type crypto_history_entry = {
  address : string;
  amount : numeric;
  fee : numeric option;
  status : string; (* "EXECUTED" *)
  symbol : string;
  timestamp : string;
  txHash : string;
}

val crypto_history_entry_of_json : Json.t -> crypto_history_entry list

(* 暗号資産の預入履歴を取得。[symbol]/[from_timestamp]必須。
   [to_timestamp]の省略時の扱いはfiat_deposit_historyと同様。 *)
val deposit_history :
  Auth.t ->
  symbol:symbol ->
  from_timestamp:string ->
  ?to_timestamp:string ->
  unit ->
  crypto_history_entry list Lwt.t

(* 暗号資産の送付履歴を取得。パラメータはdeposit_historyと同様。 *)
val withdrawal_history :
  Auth.t ->
  symbol:symbol ->
  from_timestamp:string ->
  ?to_timestamp:string ->
  unit ->
  crypto_history_entry list Lwt.t

type order_info = {
  rootOrderId : int;
  orderId : int;
  symbol : string;
  side : side;
  orderType : string;
  executionType : string;
  settleType : string;
  size : numeric;
  executedSize : numeric;
  price : numeric option;
  losscutPrice : numeric;
  status : string;
  cancelType : string option;
  timeInForce : string;
  timestamp : string;
}

type orders_response = { list : order_info list }

val orders_response_of_json : Json.t -> orders_response

(* 注文情報取得。[order_ids] はカンマ区切りで最大10件まで指定可能。 *)
val orders : Auth.t -> order_ids:string list -> unit -> order_info list Lwt.t

type active_orders_response = {
  pagination : pagination;
  list : order_info list;
}

val active_orders_response_of_json : Json.t -> active_orders_response

(* 有効注文一覧 *)
val active_orders :
  Auth.t ->
  symbol:symbol ->
  ?page:int ->
  ?count:int ->
  unit ->
  active_orders_response Lwt.t

type execution = {
  executionId : int;
  orderId : int;
  positionId : int option;
  symbol : string;
  side : side;
  settleType : string;
  size : numeric;
  price : numeric;
  lossGain : numeric;
  fee : numeric;
  timestamp : string;
}

type executions_response = { list : execution list }

val executions_response_of_json : Json.t -> executions_response

type order_ref = ById of int | ByExecutionIds of int list

(* 約定情報取得。orderId または executionId のどちらか一方を指定する。 *)
val executions : Auth.t -> order_ref -> execution list Lwt.t

type latest_executions_response = {
  pagination : pagination;
  list : execution list;
}

val latest_executions_response_of_json : Json.t -> latest_executions_response

(* 最新の約定一覧 (直近1日分) *)
val latest_executions :
  Auth.t ->
  symbol:symbol ->
  ?page:int ->
  ?count:int ->
  unit ->
  latest_executions_response Lwt.t

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

type open_positions_response = { pagination : pagination; list : position list }

val open_positions_response_of_json : Json.t -> open_positions_response

(* 建玉一覧を取得。対象: レバレッジ取引 *)
val open_positions :
  Auth.t ->
  symbol:symbol ->
  ?page:int ->
  ?count:int ->
  unit ->
  open_positions_response Lwt.t

type position_summary = {
  averagePositionRate : numeric;
  positionLossGain : numeric;
  side : side;
  sumOrderQuantity : numeric;
  sumPositionQuantity : numeric;
  symbol : string;
}

type position_summary_response = { list : position_summary list }

val position_summary_response_of_json : Json.t -> position_summary_response

(* 建玉サマリーを取得。対象: レバレッジ取引。symbol省略時は全銘柄分。 *)
val position_summary :
  Auth.t -> ?symbol:symbol -> unit -> position_summary list Lwt.t

type execution_type = Market | Limit | Stop
type time_in_force = FAK | FAS | FOK | SOK

(* 新規注文。対象: 現物取引、レバレッジ取引。戻り値は発注されたorderId。
   price/losscut_price/size は発注時にそのままリクエストボディへ渡す文字列のため、
   floatの丸め誤差を避けてあえて string のままにしている。
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
