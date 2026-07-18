val (!%) : ('a, unit, string) format -> 'a

val list_add_opt : 'a option -> 'a list -> 'a list

type symbol = string

module Log = Dolog.Log
module Json = Yojson.Safe

type side = Buy | Sell
val side_of_string : string -> side
val string_of_side : side -> string
val side_to_yojson : side -> Json.t
val side_of_yojson : Json.t -> (side, string) result

type pagination = {
    currentPage: int;
    count: int;
}
val pagination_of_yojson : Json.t -> (pagination, string) result
val pagination_to_yojson : pagination -> Json.t

(* GMOコインが文字列で返す数値 (例: "455659") 用。実体は float なので
   そのまま演算・比較に使える。 *)
type numeric = float
val numeric_of_yojson : Json.t -> (numeric, string) result
val numeric_to_yojson : numeric -> Json.t
