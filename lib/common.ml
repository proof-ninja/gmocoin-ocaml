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

module Json = Yojson.Safe

type pagination = {
    currentPage: int;
    count: int;
} [@@deriving yojson]

(* GMOコインは price/size/amount 等の数値も JSON 上は文字列 (例: "455659") で
   返してくる。[float] のまま [@@deriving yojson] すると `String を受け付けないため、
   [numeric] という別名を用意し、文字列からのパース/文字列への変換を手書きする。
   これを使えば呼び出し側は普通の float としてそのまま演算・比較できる。 *)
type numeric = float

let numeric_of_yojson json =
  match json with
  | `String s ->
     (try Ok (float_of_string s) with _ -> Error (!%"numeric_of_yojson: invalid numeric string '%s'" s))
  | `Int i -> Ok (float_of_int i)
  | `Float f -> Ok f
  | `Intlit s ->
     (try Ok (float_of_string s) with _ -> Error (!%"numeric_of_yojson: invalid numeric string '%s'" s))
  | _ -> Error "numeric_of_yojson: expected a numeric string"

let numeric_to_yojson (n : numeric) : Yojson.Safe.t = `String (string_of_float n)
