type t

val make_header :
  t -> string -> string -> string -> (string * string) list

val from_file : ?filename:string -> unit -> t

val auth : unit -> t
