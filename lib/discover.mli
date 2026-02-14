(** Backend and toolchain discovery. *)

val backend :
  ?preferred:string -> unit -> (Types.backend * string, Types.error) result

val nm : unit -> (string, Types.error) result
val compiler : [ `C | `Cxx ] -> (string, Types.error) result
val search_paths : unit -> string list
val sysroot : string -> string option
val which : string -> string option
val linker_version : string -> string option
