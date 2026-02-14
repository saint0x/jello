(** Backend and toolchain discovery. *)

val backend :
  ?override:Types.backend ->
  ?preferred:string ->
  ?preference:Types.backend list ->
  unit ->
  (Types.backend * string, Types.error) result

val find_backend_path : Types.backend -> string option

val nm : ?override:string -> unit -> (string, Types.error) result
val compiler : [ `C | `Cxx ] -> (string, Types.error) result
val search_paths : unit -> string list
val sysroot : string -> string option
val which : string -> string option
val linker_version : string -> string option
