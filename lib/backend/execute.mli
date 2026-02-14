(** Backend execution. *)

val run : Types.link_plan -> (Types.exec_result, Types.error) result
val dry_run : Types.link_plan -> string
