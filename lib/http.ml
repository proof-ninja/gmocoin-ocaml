open Lwt
open Cohttp_lwt_unix
open Common

(* conduit-lwt-unix の既定TLSバックエンド (ocaml-tls, "native") で
   api.coin.z.com に接続すると、ハンドシェイク後に ECONNRESET で切断される
   (WAF等によるTLSフィンガープリント判定と見られる)。OpenSSLバックエンドに
   切り替えると安定して接続できることを確認済みなので、ここで強制する。
   conduit はプロセス起動後に一度 default_ctx を評価すると結果をキャッシュするため、
   他のHTTP通信より先にこの設定を効かせる必要がある。 *)
let () =
  if Sys.getenv_opt "CONDUIT_TLS" = None then
    Unix.putenv "CONDUIT_TLS" "openssl"

let curlcmd meth headers uri body =
  let headers =
    List.map (fun (k, v) -> !%"-H '%s: %s'" k v) headers |> String.concat " "
  in
  !%"curl -X %s %s --data '%s' '%s'" meth headers body (Uri.to_string uri)

exception HttpException of string * Uri.t * exn

let () =
  Printexc.register_printer (function
      | HttpException (meth, uri, inner) ->
         Some (!%"GmoCoin.Http.HttpException(%s, %s, %s)"
                 meth (Uri.to_string uri) (Printexc.to_string inner))
      | _ -> None)

(* api.coin.z.com は、OpenSSLバックエンドに切り替えた後も
   断続的に ECONNRESET でハンドシェイク/応答読み取りを打ち切ることがある
   (数回に1回程度発生することを確認済み)。認証情報の問題ではなく一時的な
   接続断なので、冪等な GET に限りリトライする。

   cohttp-lwt-unix はソケットI/Oの例外を `Io.IO_error of exn` でラップして
   投げ直すが、この Io モジュールは .mli で IO_error を非公開にしているため
   コンストラクタとしてパターンマッチできない。そのため Printexc.to_string
   の文字列に含まれる Unix エラー名で判定する。 *)
let string_contains ~needle s =
  let nlen = String.length needle and slen = String.length s in
  let rec loop i = i + nlen <= slen && (String.sub s i nlen = needle || loop (i + 1)) in
  nlen = 0 || loop 0

let is_transient exn =
  match exn with
  | Unix.Unix_error ((ECONNRESET | ECONNREFUSED | ETIMEDOUT | EPIPE), _, _) -> true
  | _ ->
     let s = Printexc.to_string exn in
     List.exists (fun needle -> string_contains ~needle s)
       ["ECONNRESET"; "ECONNREFUSED"; "ETIMEDOUT"; "EPIPE"]

let rec with_retry ?(retries=5) ?(delay=0.5) f =
  Lwt.catch f
    (fun exn ->
       if retries > 0 && is_transient exn then begin
         Log.debug "Http: transient error (%s), retrying (%d left)"
           (Printexc.to_string exn) retries;
         Lwt_unix.sleep delay >>= fun () ->
         with_retry ~retries:(retries - 1) ~delay f
       end else
         Lwt.fail exn)

let get ?(headers=[]) uri =
  let attempt () =
    Log.debug "Http.get $ %s" (curlcmd "GET" headers uri "");
    let headers = Cohttp.Header.of_list headers in
    Client.get ~headers uri >>= fun (_resp, body) ->
    Cohttp_lwt.Body.to_string body
    >>= fun body -> Log.debug "response: %s" body; Lwt.return body
  in
  try%lwt with_retry attempt
  with
  | exn -> raise (HttpException ("GET", uri, exn))

(* POST は注文・キャンセル等の非冪等な操作に使われるため、ここでは自動リトライしない。
   ECONNRESET は応答の読み取り中 (=リクエスト送信後) に起きるため、盲目的にリトライすると
   実際にはサーバー側で処理済みの注文を二重に送ってしまう危険がある。 *)
let post ?(headers=[]) uri data =
  try%lwt
     Log.debug "Http.post $ %s" (curlcmd "POST" headers uri data);
     let headers = Cohttp.Header.of_list headers in
     let body = Cohttp_lwt.Body.of_string data in
     Client.post ~headers uri ~body >>= fun (_resp, body) ->
     Cohttp_lwt.Body.to_string body
     >>= fun body -> Log.debug "response: %s" body; Lwt.return body
  with
  | exn -> raise (HttpException ("POST", uri, exn))
