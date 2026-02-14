(** Top-level driver pipeline. *)

type config = {
  fix_mode : Types.fix_mode;
  emit_plan : bool;
  plan_dir : string;
  dry_run : bool;
  explain : bool;
  backend_override : Types.backend option;
  backend_preference : Types.backend list option;
  extra_search_paths : string list;
  nm_override : string option;
  silent : bool;
}

val default_config : config
val link : config -> string list -> (Types.exec_result, Types.error) result

(** Full passthrough to the real compiler driver. Finds the real compiler
    (skipping [$CC]/[$CXX] to avoid self-reference) and executes it with
    all args verbatim. Used for all [jellocc]/[jelloc++] invocations —
    compile, link, preprocess, introspection. Returns process exit code. *)
val passthrough : [ `C | `Cxx ] -> config -> string list -> int
