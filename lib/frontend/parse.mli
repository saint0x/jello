(** Frontend argument parser.
    Transforms raw argv into structured invocation. *)

val args : string list -> (Types.invocation, Types.error) result
