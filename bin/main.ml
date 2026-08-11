open Gmocoin
open Common
open Lwt
module Log = Dolog.Log

let check_status () =
  PublicApi.status () >>= fun status ->
  match status with
  | Ok status ->
      print_endline ("exchange status: " ^ status);
      Lwt.return true
  | Error (e : ApiCommon.api_error) ->
      let messages =
        e.messages
        |> List.map (fun (m : ApiCommon.message) ->
            Printf.sprintf "%s: %s" m.message_code m.message_string)
        |> String.concat "; "
      in
      Printf.printf "exchange unavailable (status=%d): %s\n" e.status messages;
      Lwt.return false

let get_auth () = Auth.auth ()

(* サンプル: 現物 [symbol] (例: "BTC") の板情報を監視し、best_bidが[threshold]以下に
   なるたびに成行の現物買い注文を出す。ticker チャンネルは値動きがないと配信されない
   ことを確認したため、常にスナップショットが届く orderbooks チャンネルの best_bid
   (bids の先頭) を使う。条件を満たしている間は毎回発注するので、実際に動かす際は
   size や threshold の設定に注意すること。 *)
let watch_and_buy auth ~symbol ~threshold ~size =
  Realtime.orderbook_updates ~symbol >>= fun stream ->
  Lwt_stream.iter_s
    (fun (ob : Realtime.orderbook) ->
      match ob.bids with
      | best_bid :: _ when best_bid.Realtime.price <= threshold ->
          Log.info "best_bid %f <= %f: sending market buy order"
            best_bid.Realtime.price threshold;
          PrivateApi.order auth ~symbol ~side:Buy
            ~execution_type:PrivateApi.Market ~size ()
          >>= fun order_id ->
          Log.debug "order placed: orderId=%d" order_id;
          Lwt.return ()
      | _ -> Lwt.return ())
    stream

(* 実行する場合は下記のように呼び出す:
   Lwt_main.run (watch_and_buy (get_auth ()) ~symbol:"BTC" ~threshold:10_000_000.0 ~size:"0.001") *)

let () =
  Log.set_log_level Log.DEBUG;
  try
    Lwt_main.run
      begin
        check_status () >>= fun is_available ->
        if is_available then (
          PublicApi.ticker ~symbol:"BTC_JPY" () >>= fun tickers ->
          List.iter
            (fun (t : PublicApi.ticker) ->
              Printf.printf "%s: bid=%f ask=%f last=%f\n" t.symbol t.bid t.ask
                t.last)
            tickers;
          let auth = get_auth () in
          PrivateApi.assets auth () >>= fun assets ->
          List.iter
            (fun (asset : PrivateApi.asset) ->
              print_endline (!%"[%s] %f" asset.symbol asset.amount))
            assets;
          Lwt.return ())
        else Lwt.return ()
      end
  with e -> prerr_endline (Printexc.to_string e)
