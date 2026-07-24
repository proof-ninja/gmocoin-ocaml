open Common

let default_filename = "gmocoin-auth.conf"

type t = {
    api_key : string;
    secret : string;
}

let from_file ?(filename=default_filename) () =
  let ch = open_in filename in
  let api_key = input_line ch in
  let secret = input_line ch in
  close_in ch;
  {api_key; secret}

let auth () = from_file ()

let timestamp_ms () =
  Unix.gettimeofday () *. 1000.0 |> Int64.of_float |> Int64.to_string

let sign auth timestamp method_ path body =
  let text = !%"%s%s%s%s" timestamp method_ path body in
  let secret = auth.secret in
  Hacl_star.EverCrypt.HMAC.mac ~alg:SHA2_256
    ~key:(Bytes.of_string secret) ~msg:(Bytes.of_string text)
  |> Hex.of_bytes
  |> Hex.show

(* [path] は "/v1/..." のように "/private" を含まない形で渡すこと。
   GMOコインの署名対象パスはクエリ文字列も含めない。
   see: https://api.coin.z.com/docs/#outline 認証 *)
let make_header auth meth path body =
  let timestamp = timestamp_ms () in
  let s = sign auth timestamp meth path body in
  [
    ("API-KEY", auth.api_key);
    ("API-TIMESTAMP", timestamp);
    ("API-SIGN", s);
    ("Content-Type", "application/json");
  ]
