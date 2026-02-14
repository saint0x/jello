(** Normalize a parsed invocation.
    Resolves conflicts, removes redundancy, applies defaults. *)

val invocation : Types.invocation -> (Types.invocation, Types.error) result
