(* driver.ml — Top-level orchestration pipeline.
   parse → normalize → discover → resolve → reorder → plan → execute → diagnose → emit *)

open Types

let src = Logs.Src.create "jello.driver" ~doc:"Driver pipeline"

module Log = (val Logs.src_log src : Logs.LOG)

let ( let* ) = Result.bind

type config = {
  fix_mode : fix_mode;
  emit_plan : bool;
  plan_dir : string;
  dry_run : bool;
  explain : bool;
  backend_override : backend option;
  backend_preference : backend list option;
  extra_search_paths : string list;
  nm_override : string option;
  silent : bool;
}

let default_config =
  {
    fix_mode = Auto_fix;
    emit_plan = true;
    plan_dir = ".jello";
    dry_run = false;
    explain = false;
    backend_override = None;
    backend_preference = None;
    extra_search_paths = [];
    nm_override = None;
    silent = true;
  }

(* Pretty-print a diagnostic to stderr *)
let print_diagnostic ~silent d =
  if silent then ()
  else
    let prefix =
      match d.severity with
      | Sev_error -> "error"
      | Sev_warning -> "warning"
      | Sev_info -> "info"
      | Sev_hint -> "hint"
    in
    Printf.eprintf "[jello:%s] %s: %s\n" d.code prefix d.message;
    List.iter
      (fun f ->
        let conf =
          match f.confidence with
          | High -> "fix"
          | Medium -> "suggestion"
          | Low -> "hint"
        in
        Printf.eprintf "  %s: %s\n" conf f.description)
      d.fixes

(* Print the explain trace *)
let print_explain plan =
  Printf.eprintf "\n--- jello explain ---\n";
  Printf.eprintf "Triple:     %s\n" (triple_to_string plan.triple);
  Printf.eprintf "Backend:    %s (%s)\n"
    (backend_to_string plan.backend)
    plan.backend_path;
  Printf.eprintf "Link mode:  %s\n" (link_mode_to_string plan.link_mode);
  Printf.eprintf "Output:     %s\n" plan.output;
  Printf.eprintf "Inputs:     %d files\n" (List.length plan.inputs);
  Printf.eprintf "Search:     %s\n"
    (String.concat ":" plan.search_paths);
  Printf.eprintf "Resolved:   %d libraries\n"
    (List.length plan.resolved_libs);
  List.iter
    (fun r ->
      Printf.eprintf "  %s -> %s (%s)\n"
        (lib_ref_to_string r.reference)
        r.path
        (match r.kind with Static_lib -> "static" | Shared_lib -> "shared"))
    plan.resolved_libs;
  if plan.fixes_applied <> [] then (
    Printf.eprintf "Fixes:      %d applied\n"
      (List.length plan.fixes_applied);
    List.iter
      (fun f ->
        Printf.eprintf "  [%s] %s\n"
          (confidence_to_string f.confidence)
          f.description)
      plan.fixes_applied);
  Printf.eprintf "Command:    %s %s\n" plan.backend_path
    (String.concat " " plan.backend_args);
  Printf.eprintf "--- end explain ---\n\n"

(* Collect static archive paths for reordering *)
let collect_archive_paths (inv : invocation) resolved_libs =
  let from_inputs =
    List.filter_map
      (fun i -> match i with Archive p -> Some p | _ -> None)
      inv.inputs
  in
  let from_resolved =
    List.filter_map
      (fun (r : lib_resolved) -> match r.kind with Static_lib -> Some r.path | _ -> None)
      resolved_libs
  in
  from_inputs @ from_resolved

(* Full passthrough: find the real compiler, exec with all args verbatim.
   Used for jellocc/jelloc++ wrapper mode — all invocations (compile, link,
   preprocess, introspection) go straight to the real compiler driver.
   Returns the process exit code directly — no plan, no diagnostics. *)
let passthrough lang config args =
  let compiler_result = Discover.real_compiler lang in
  match compiler_result with
  | Error e ->
      if not config.silent then
        Printf.eprintf "jello: %s\n" (error_to_string e);
      1
  | Ok compiler_path ->
      Log.info (fun m ->
          m "Passthrough: %s %s" compiler_path
            (String.concat " " args));
      let cmd =
        List.fold_left
          (fun c a -> Bos.Cmd.(c % a))
          (Bos.Cmd.v compiler_path)
          args
      in
      (match Execute.run_cmd cmd with
      | Ok (code, _stdout, stderr) ->
          if stderr <> "" && not config.silent then
            Printf.eprintf "%s" stderr;
          code
      | Error (`Msg msg) ->
          if not config.silent then
            Printf.eprintf "jello: passthrough failed: %s\n" msg;
          1)

(* The full pipeline *)
let link config args =
  Log.info (fun m -> m "Starting jello link pipeline");
  (* Phase 1: Parse *)
  let* inv = Parse.args args in
  Log.debug (fun m ->
      m "Parsed: %d flags, %d inputs" (List.length inv.flags)
        (List.length inv.inputs));
  (* Phase 2: Normalize *)
  let* inv = Normalize.invocation inv in
  (* Phase 3: Discover target triple *)
  let compiler =
    match Discover.compiler `C with Ok c -> c | Error _ -> "cc"
  in
  let* triple = Triple.detect ~compiler () in
  Log.info (fun m -> m "Target: %s" (triple_to_string triple));
  (* Phase 4: Discover backend *)
  let preferred = Plan.preferred_linker inv.flags in
  let* backend, backend_path =
    Discover.backend ?override:config.backend_override ?preferred
      ?preference:config.backend_preference ()
  in
  (* Phase 5: Resolve libraries — prepend extra search paths from config *)
  let inv =
    if config.extra_search_paths <> [] then
      { inv with search_paths = config.extra_search_paths @ inv.search_paths }
    else inv
  in
  let resolved_libs, search_paths =
    match Resolve.libs inv with
    | Ok (libs, paths) -> (libs, paths)
    | Error _ ->
        Log.warn (fun m -> m "Library resolution had errors; continuing");
        ([], inv.search_paths @ Discover.search_paths ())
  in
  (* Phase 6: Reorder static libraries *)
  let archive_paths = collect_archive_paths inv resolved_libs in
  let fixes =
    if archive_paths = [] then []
    else
      match Reorder.libs archive_paths with
      | Ok (_, fixes) -> fixes
      | Error e ->
          Log.warn (fun m ->
              m "Reorder failed: %s" (error_to_string e));
          []
  in
  (* Phase 7: Build plan *)
  let* plan =
    Plan.build ~inv ~triple ~backend ~backend_path ~resolved_libs
      ~search_paths ~fixes
  in
  (* Explain mode *)
  if config.explain then print_explain plan;
  (* Emit plan artifacts *)
  if config.emit_plan then (
    match Emit.write_artifacts ~dir:config.plan_dir plan plan.diagnostics with
    | Ok () -> ()
    | Error (`Msg msg) ->
        Log.warn (fun m -> m "Could not write plan artifacts: %s" msg));
  (* Dry run: print command and exit *)
  if config.dry_run then (
    let cmd = Execute.dry_run plan in
    Printf.printf "%s\n" cmd;
    Ok
      {
        plan;
        exit_code = 0;
        stdout = cmd;
        stderr = "";
        post_diagnostics = [];
      })
  else
    (* Phase 8: Execute *)
    let* result = Execute.run plan in
    (* Phase 9: Diagnose *)
    let result =
      if result.exit_code <> 0 then Diagnose.errors result else result
    in
    (* Print diagnostics *)
    List.iter (print_diagnostic ~silent:config.silent) result.post_diagnostics;
    Ok result
