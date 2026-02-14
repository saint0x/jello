(** Frontend argument parser.
    Transforms raw argv into structured invocation. *)

val args : string list -> (Types.invocation, Types.error) result

(** Lightweight pre-scan: returns [true] if args contain [-c], [-S], or [-E],
    indicating a compile-only invocation that should bypass the linker pipeline.
    Runs before full parse — O(n) scan over top-level args only. *)
val is_compile_only : string list -> bool
