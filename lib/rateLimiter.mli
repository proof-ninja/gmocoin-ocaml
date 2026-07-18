type t

(* [create ~capacity ~window] は、直近 [window] 秒間に [capacity] 回まで
   [acquire] を許可するレートリミッターを作る。 *)
val create : capacity:int -> window:float -> t

(* 呼出枠が空くまで待機してから、呼出を1回分記録する。 *)
val acquire : t -> unit Lwt.t
