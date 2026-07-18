open Gmocoin
open Common
open Lwt

let check_status () =
  PublicApi.status () >>= fun status ->
  match status with
  | Ok status -> print_endline ("exchange status: " ^ status); Lwt.return true
  | Error (e : ApiCommon.api_error) ->
     let messages =
       e.messages
       |> List.map (fun (m : ApiCommon.message) -> Printf.sprintf "%s: %s" m.message_code m.message_string)
       |> String.concat "; "
     in
     Printf.printf "exchange unavailable (status=%d): %s\n" e.status messages;
     Lwt.return false

let get_auth () = Auth.auth ()

let () =
  Common.Log.set_log_level Common.Log.DEBUG;
  try
    Lwt_main.run begin
        check_status() >>= fun is_available ->
        if is_available then
          PublicApi.ticker ~symbol:"BTC_JPY" () >>= fun tickers ->
          List.iter (fun (t : PublicApi.ticker) ->
              Printf.printf "%s: bid=%s ask=%s last=%s\n" t.symbol t.bid t.ask t.last)
            tickers;
          let auth = get_auth () in
          PrivateApi.assets auth () >>= fun assets ->
          List.iter (fun (asset : PrivateApi.asset) ->
              print_endline (!%"[%s] %s" asset.symbol asset.amount)) assets;
          Lwt.return ()
        else Lwt.return ()
      end
  with
  | e -> prerr_endline (Printexc.to_string e)
