(** Backend execution. *)

val run : Types.link_plan -> (Types.exec_result, Types.error) result
val dry_run : Types.link_plan -> string

(** Run an arbitrary command, capturing exit code, stdout, and stderr.
    Used for compile passthrough and other non-link executions. *)
val run_cmd : Bos.Cmd.t -> (int * string * string, [`Msg of string]) result
