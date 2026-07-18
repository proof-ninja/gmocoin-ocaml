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
