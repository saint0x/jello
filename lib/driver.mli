(** Top-level driver pipeline. *)

type config = {
  fix_mode : Types.fix_mode;
  emit_plan : bool;
  plan_dir : string;
  dry_run : bool;
  explain : bool;
}

val default_config : config
val link : config -> string list -> (Types.exec_result, Types.error) result
