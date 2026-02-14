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

(** Like [compiler], but skips [$CC]/[$CXX] env vars to avoid self-referencing
    loops when jello itself is set as CC. Searches PATH for known compiler
    names only, filtering out any that resolve to jello/jellocc/jelloc++. *)
val real_compiler : [ `C | `Cxx ] -> (string, Types.error) result
val search_paths : unit -> string list
val sysroot : string -> string option
val which : string -> string option
val linker_version : string -> string option
