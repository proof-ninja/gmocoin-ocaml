open Common

type message = {
    message_code: string;
    message_string: string;
}

type api_error = {
    status: int;
    messages: message list;
}

(* {status, data, responsetime} エンベロープの status が 0 以外だった場合に投げる。 *)
exception Api_error of api_error

val api_error_of_json : Json.t -> api_error

val get_public : string -> (string * string) list -> Json.t Lwt.t
val get : Auth.t -> string -> (string * string) list -> Json.t Lwt.t
val post : Auth.t -> string -> string -> Json.t Lwt.t
