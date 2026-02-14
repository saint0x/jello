(** Symbol table extraction via nm. *)

val extract : string -> (Types.symbol list, Types.error) result
val undefined : Types.symbol list -> Types.symbol list
val defined : Types.symbol list -> Types.symbol list

val providers :
  (string * Types.symbol list) list -> (string, string list) Hashtbl.t

val requirements :
  (string * Types.symbol list) list -> (string, string list) Hashtbl.t
