(* config.ml — Configuration loading and merging.
   Pure core with effectful boundary for file/env reads.
   Config hierarchy: env vars > project file > user file > defaults. *)

open Types

let src = Logs.Src.create "jello.config" ~doc:"Configuration"

module Log = (val Logs.src_log src : Logs.LOG)

type log_level =
  | Log_quiet
  | Log_error
  | Log_warning
  | Log_info
  | Log_debug

type partial = {
  backend : backend option;
  backend_preference : backend list option;
  fix_mode : fix_mode option;
  emit_plan : bool option;
  plan_dir : string option;
  explain : bool option;
  dry_run : bool option;
  search_paths : string list option;
  nm : string option;
  log_level : log_level option;
  silent : bool option;
}

type t = {
  backend : backend option;
  backend_preference : backend list option;
  fix_mode : fix_mode;
  emit_plan : bool;
  plan_dir : string;
  explain : bool;
  dry_run : bool;
  search_paths : string list;
  nm : string option;
  log_level : log_level;
  silent : bool;
}

let empty : partial =
  {
    backend = None;
    backend_preference = None;
    fix_mode = None;
    emit_plan = None;
    plan_dir = None;
    explain = None;
    dry_run = None;
    search_paths = None;
    nm = None;
    log_level = None;
    silent = None;
  }

let defaults =
  {
    backend = None;
    backend_preference = None;
    fix_mode = Auto_fix;
    emit_plan = true;
    plan_dir = ".jello";
    explain = false;
    dry_run = false;
    search_paths = [];
    nm = None;
    log_level = Log_quiet;
    silent = true;
  }

(* --- Pure merge: left wins --- *)

let first a b = match a with Some _ -> a | None -> b

let merge (hi : partial) (lo : partial) : partial =
  {
    backend = first hi.backend lo.backend;
    backend_preference = first hi.backend_preference lo.backend_preference;
    fix_mode = first hi.fix_mode lo.fix_mode;
    emit_plan = first hi.emit_plan lo.emit_plan;
    plan_dir = first hi.plan_dir lo.plan_dir;
    explain = first hi.explain lo.explain;
    dry_run = first hi.dry_run lo.dry_run;
    search_paths = first hi.search_paths lo.search_paths;
    nm = first hi.nm lo.nm;
    log_level = first hi.log_level lo.log_level;
    silent = first hi.silent lo.silent;
  }

(* --- Resolve partial to concrete --- *)

let resolve (p : partial) : t =
  {
    backend = p.backend;
    backend_preference = p.backend_preference;
    fix_mode = (match p.fix_mode with Some v -> v | None -> defaults.fix_mode);
    emit_plan =
      (match p.emit_plan with Some v -> v | None -> defaults.emit_plan);
    plan_dir =
      (match p.plan_dir with Some v -> v | None -> defaults.plan_dir);
    explain = (match p.explain with Some v -> v | None -> defaults.explain);
    dry_run = (match p.dry_run with Some v -> v | None -> defaults.dry_run);
    search_paths =
      (match p.search_paths with Some v -> v | None -> defaults.search_paths);
    nm = p.nm;
    log_level =
      (match p.log_level with Some v -> v | None -> defaults.log_level);
    silent = (match p.silent with Some v -> v | None -> defaults.silent);
  }

(* --- Log level conversions --- *)

let log_level_of_string = function
  | "quiet" -> Some Log_quiet
  | "error" -> Some Log_error
  | "warning" -> Some Log_warning
  | "info" -> Some Log_info
  | "debug" -> Some Log_debug
  | _ -> None

let log_level_to_string = function
  | Log_quiet -> "quiet"
  | Log_error -> "error"
  | Log_warning -> "warning"
  | Log_info -> "info"
  | Log_debug -> "debug"

let to_logs_level = function
  | Log_quiet -> None
  | Log_error -> Some Logs.Error
  | Log_warning -> Some Logs.Warning
  | Log_info -> Some Logs.Info
  | Log_debug -> Some Logs.Debug

(* --- JSON parsing (pure) --- *)

let member_string key json =
  match Yojson.Safe.Util.member key json with
  | `String s -> Some s
  | _ -> None

let member_bool key json =
  match Yojson.Safe.Util.member key json with
  | `Bool b -> Some b
  | _ -> None

let member_string_list key json =
  match Yojson.Safe.Util.member key json with
  | `List items ->
      let strs =
        List.filter_map
          (fun j -> match j with `String s -> Some s | _ -> None)
          items
      in
      Some strs
  | _ -> None

let of_json raw =
  match Yojson.Safe.from_string raw with
  | json ->
      let backend =
        Option.bind (member_string "backend" json) backend_of_string
      in
      let backend_preference =
        Option.map
          (List.filter_map backend_of_string)
          (member_string_list "backend_preference" json)
      in
      let fix_mode =
        Option.bind (member_string "fix_mode" json) fix_mode_of_string
      in
      let emit_plan = member_bool "emit_plan" json in
      let plan_dir = member_string "plan_dir" json in
      let explain = member_bool "explain" json in
      let dry_run = member_bool "dry_run" json in
      let search_paths = member_string_list "search_paths" json in
      let nm = member_string "nm" json in
      let log_level =
        Option.bind (member_string "log_level" json) log_level_of_string
      in
      let silent = member_bool "silent" json in
      Ok
        ({
          backend;
          backend_preference;
          fix_mode;
          emit_plan;
          plan_dir;
          explain;
          dry_run;
          search_paths;
          nm;
          log_level;
          silent;
        } : partial)
  | exception Yojson.Json_error msg -> Error (Printf.sprintf "invalid JSON: %s" msg)

(* --- Environment variable parsing --- *)

let parse_bool_env value =
  match String.lowercase_ascii value with
  | "true" | "1" | "yes" -> Some true
  | "false" | "0" | "no" -> Some false
  | _ -> None

let of_env () : partial =
  let get var = Sys.getenv_opt var in
  let backend =
    Option.bind (get "JELLO_BACKEND") backend_of_string
  in
  let backend_preference =
    Option.map
      (fun s ->
        s |> String.split_on_char ','
        |> List.map String.trim
        |> List.filter_map backend_of_string)
      (get "JELLO_BACKEND_PREFERENCE")
  in
  let fix_mode =
    Option.bind (get "JELLO_FIX_MODE") fix_mode_of_string
  in
  let emit_plan =
    Option.bind (get "JELLO_EMIT_PLAN") parse_bool_env
  in
  let plan_dir = get "JELLO_PLAN_DIR" in
  let explain =
    Option.bind (get "JELLO_EXPLAIN") parse_bool_env
  in
  let dry_run =
    Option.bind (get "JELLO_DRY_RUN") parse_bool_env
  in
  let search_paths =
    Option.map
      (String.split_on_char ':')
      (get "JELLO_SEARCH_PATHS")
  in
  let nm = get "JELLO_NM" in
  let log_level =
    Option.bind (get "JELLO_LOG_LEVEL") log_level_of_string
  in
  let silent =
    Option.bind (get "JELLO_SILENT") parse_bool_env
  in
  {
    backend;
    backend_preference;
    fix_mode;
    emit_plan;
    plan_dir;
    explain;
    dry_run;
    search_paths;
    nm;
    log_level;
    silent;
  }

(* --- File discovery --- *)

let find_project_config start_dir =
  let rec walk dir =
    let candidate = Filename.concat dir ".jello.json" in
    if Sys.file_exists candidate then Some candidate
    else
      let parent = Filename.dirname dir in
      if parent = dir then None
      else walk parent
  in
  walk start_dir

let user_config_path () =
  let base =
    match Sys.getenv_opt "XDG_CONFIG_HOME" with
    | Some xdg when String.length xdg > 0 -> Some xdg
    | _ -> (
        match Sys.getenv_opt "HOME" with
        | Some home -> Some (Filename.concat home ".config")
        | None -> None)
  in
  Option.map (fun b -> Filename.concat (Filename.concat b "jello") "config.json") base

let read_config_file path =
  match Bos.OS.File.read (Fpath.v path) with
  | Ok contents -> of_json contents
  | Error (`Msg msg) -> Error msg

let of_project ~start_dir =
  match find_project_config start_dir with
  | Some path ->
      Log.debug (fun m -> m "Found project config: %s" path);
      read_config_file path
  | None -> Ok empty

let of_user () =
  match user_config_path () with
  | Some path when Sys.file_exists path ->
      Log.debug (fun m -> m "Found user config: %s" path);
      read_config_file path
  | _ -> Ok empty

(* --- Main entry point --- *)

let load () =
  let env_cfg = of_env () in
  let project_cfg =
    match of_project ~start_dir:(Sys.getcwd ()) with
    | Ok p -> p
    | Error msg ->
        Log.warn (fun m -> m "Bad project config: %s" msg);
        empty
  in
  let user_cfg =
    match of_user () with
    | Ok p -> p
    | Error msg ->
        Log.warn (fun m -> m "Bad user config: %s" msg);
        empty
  in
  let merged = merge env_cfg (merge project_cfg user_cfg) in
  Ok (resolve merged)

let _ = log_level_to_string
