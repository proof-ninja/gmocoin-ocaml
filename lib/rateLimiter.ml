open Lwt

(* 直近 [window] 秒間に [capacity] 回まで [acquire] を許可するスライディングウィンドウ型の
   レートリミッター。上限に達している間は、次に枠が空くまで自動的に待機する。 *)
type t = {
    capacity: int;
    window: float; (* seconds *)
    mutable timestamps: float list; (* 直近 window 秒以内の呼出時刻 *)
}

let create ~capacity ~window = { capacity; window; timestamps = [] }

let rec acquire t =
  let now = Unix.gettimeofday () in
  let cutoff = now -. t.window in
  t.timestamps <- List.filter (fun ts -> ts > cutoff) t.timestamps;
  if List.length t.timestamps < t.capacity then begin
    t.timestamps <- now :: t.timestamps;
    Lwt.return ()
  end else begin
    let oldest = List.fold_left min now t.timestamps in
    let wait = oldest +. t.window -. now in
    Lwt_unix.sleep (Float.max wait 0.01) >>= fun () ->
    acquire t
  end
