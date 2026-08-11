open Lwt
open Common

let host = "api.coin.z.com"
let public_base = "/public"
let private_base = "/private"

(* Private APIの呼出上限 (Tier 1): GET/POSTそれぞれ同一アカウントから1秒間に20回まで。
   取引高が多いアカウントはTier 2 (30回/秒) まで引き上げられるが、
   安全側の下限であるTier 1を既定値として採用する。
   see: https://api.coin.z.com/docs/#outline 制限 *)
let get_limiter = RateLimiter.create ~capacity:20 ~window:1.0
let post_limiter = RateLimiter.create ~capacity:20 ~window:1.0

(* レスポンスは {"status": 0, "data": ..., "responsetime": "..."} という
   共通のエンベロープを持つ。status が 0 以外はエラーで、
   {"status": N, "messages": [{"message_code": "ERR-....", "message_string": "..."}]}
   という形になる。 *)
type message = { message_code : string; message_string : string }
type api_error = { status : int; messages : message list }

exception Api_error of api_error

let () =
  Printexc.register_printer (function
    | Api_error e ->
        let messages =
          e.messages
          |> List.map (fun m -> !%"%s: %s" m.message_code m.message_string)
          |> String.concat "; "
        in
        Some (!%"GmoCoin.ApiCommon.Api_error(status=%d): %s" e.status messages)
    | _ -> None)

(* エラーレスポンスの形がドキュメント通りとは限らない可能性を考慮し、
   member はキー欠落時に `Null を返す (例外を投げない) ことを利用して緩やかに読む。 *)
let api_error_of_json json =
  let open Json.Util in
  let status = member "status" json |> to_int in
  let messages =
    member "messages" json
    |> ( function `List l -> l | _ -> [] )
    |> List.filter_map (fun m ->
        match (member "message_code" m, member "message_string" m) with
        | `String message_code, `String message_string ->
            Some { message_code; message_string }
        | _ -> None)
  in
  { status; messages }

let data_of_envelope json =
  match Json.Util.member "status" json with
  | `Int 0 -> Json.Util.member "data" json
  | _ -> raise (Api_error (api_error_of_json json))

let get_public pathname query =
  let uri =
    Uri.make ~scheme:"https" ~host ~path:(public_base ^ pathname) ()
    |> fun uri -> Uri.with_query' uri query
  in
  Http.get uri >>= fun body ->
  Json.from_string body |> data_of_envelope |> Lwt.return

(* [pathname] は "/v1/..." 形式 ("/private" もクエリも含まない)。署名対象パスと一致させる。 *)
let get auth pathname query =
  let uri =
    Uri.make ~scheme:"https" ~host ~path:(private_base ^ pathname) ()
    |> fun uri -> Uri.with_query' uri query
  in
  let headers = Auth.make_header auth "GET" pathname "" in
  RateLimiter.acquire get_limiter >>= fun () ->
  Http.get ~headers uri >>= fun body ->
  Json.from_string body |> data_of_envelope |> Lwt.return

let post auth pathname data =
  let uri = Uri.make ~scheme:"https" ~host ~path:(private_base ^ pathname) () in
  let headers = Auth.make_header auth "POST" pathname data in
  RateLimiter.acquire post_limiter >>= fun () ->
  Http.post ~headers uri data >>= fun body ->
  Json.from_string body |> data_of_envelope |> Lwt.return
