let (!%) s = Printf.sprintf s

let list_add_opt o xs =
  match o with
  | Some x -> x :: xs
  | None -> xs

(* 取扱銘柄コード (例: "BTC", "BTC_JPY") *)
type symbol = string

type side = Buy | Sell

let side_of_string = function
  | "BUY" -> Buy
  | "SELL" -> Sell
  | other -> failwith (!%"Common.side_of_string: '%s'" other)

let string_of_side = function
  | Buy -> "BUY"
  | Sell -> "SELL"

(* GMOコインのワイヤーフォーマットは素の文字列 ("BUY"/"SELL") であり、
   [@@deriving yojson] がバリアント型に対して生成するものとは異なるため、
   [side] を他のレコードに埋め込めるように手書きする。 *)
let side_to_yojson side : Yojson.Safe.t = `String (string_of_side side)

let side_of_yojson json =
  match json with
  | `String s ->
     (try Ok (side_of_string s) with Failure msg -> Error msg)
  | _ -> Error "side_of_yojson: expected a string"

module Log = Dolog.Log

module Json = Yojson.Safe

type pagination = {
    currentPage: int;
    count: int;
} [@@deriving yojson]
