(** Target triple parsing and detection. *)

val parse : string -> (Types.triple, Types.error) result
val detect : ?compiler:string -> unit -> (Types.triple, Types.error) result
val detect_from_compiler : string -> (Types.triple, Types.error) result
val detect_from_host : unit -> (Types.triple, [> `Msg of string ]) result
val arch_compatible : Types.triple -> Types.triple -> bool
val is_posix : Types.triple -> bool
val is_musl : Types.triple -> bool
