(** Configuration loading and merging.

    Config hierarchy: env vars > project file > user file > defaults.
    All config loading is pure (returns results), side effects only
    at the boundary (reading files / env). *)

(** Log level for jello's own output. *)
type log_level =
  | Log_quiet
  | Log_error
  | Log_warning
  | Log_info
  | Log_debug

(** A partial config — every field optional.
    Represents a single config source (file, env, etc.).
    [None] means "not specified in this source, fall through." *)
type partial = {
  backend : Types.backend option;
  backend_preference : Types.backend list option;
  fix_mode : Types.fix_mode option;
  emit_plan : bool option;
  plan_dir : string option;
  explain : bool option;
  dry_run : bool option;
  search_paths : string list option;
  nm : string option;
  log_level : log_level option;
  silent : bool option;
}

(** The resolved, fully-concrete config. *)
type t = {
  backend : Types.backend option;
  backend_preference : Types.backend list option;
  fix_mode : Types.fix_mode;
  emit_plan : bool;
  plan_dir : string;
  explain : bool;
  dry_run : bool;
  search_paths : string list;
  nm : string option;
  log_level : log_level;
  silent : bool;
}

(** The empty partial — all fields [None]. *)
val empty : partial

(** Default resolved config values. *)
val defaults : t

(** Merge two partials. Left wins (higher priority overrides lower). *)
val merge : partial -> partial -> partial

(** Resolve a partial against defaults to produce a concrete config. *)
val resolve : partial -> t

(** Parse a JSON string into a partial config. Pure. *)
val of_json : string -> (partial, string) result

(** Read env vars into a partial config. *)
val of_env : unit -> partial

(** Discover and read a project-level config file.
    Walks from [start_dir] upward looking for [.jello.json].
    Returns [empty] if no file found. *)
val of_project : start_dir:string -> (partial, string) result

(** Read user-level config from [~/.config/jello/config.json].
    Returns [empty] if no file found. *)
val of_user : unit -> (partial, string) result

(** Load the full config stack: env > project > user > defaults. *)
val load : unit -> (t, string) result

(** Path to the project config file found, if any. *)
val find_project_config : string -> string option

(** Convert log_level to Logs.level option for integration. *)
val to_logs_level : log_level -> Logs.level option
