(* main.ml — CLI entry point for jello.
   Supports direct invocation and wrapper mode (jellocc, jelloc++, jellod). *)

open Jello

let setup_logging style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (Logs_fmt.reporter ())

(* Detect invocation mode from argv[0] *)
let detect_mode () =
  let prog = Filename.basename Sys.argv.(0) in
  match prog with
  | "jellocc" -> `Cc
  | "jelloc++" -> `Cxx
  | "jellod" -> `Ld
  | _ -> `Direct

(* Convert Config.t to Driver.config *)
let config_to_driver cfg =
  {
    Driver.fix_mode = cfg.Config.fix_mode;
    emit_plan = cfg.Config.emit_plan;
    plan_dir = cfg.Config.plan_dir;
    dry_run = cfg.Config.dry_run;
    explain = cfg.Config.explain;
    backend_override = cfg.Config.backend;
    backend_preference = cfg.Config.backend_preference;
    extra_search_paths = cfg.Config.search_paths;
    nm_override = cfg.Config.nm;
    silent = cfg.Config.silent;
  }

(* Load config, silently fall back to defaults on error *)
let load_config () =
  match Config.load () with
  | Ok cfg -> cfg
  | Error msg ->
      Printf.eprintf "jello: config warning: %s\n" msg;
      Config.defaults

(* --- Link subcommand --- *)

let link_cmd =
  let open Cmdliner in
  let doc = "Link object files and libraries." in
  let info = Cmd.info "link" ~doc in
  let dry_run =
    Arg.(value & flag & info [ "n"; "dry-run" ] ~doc:"Print command without executing.")
  in
  let explain =
    Arg.(value & flag & info [ "explain" ] ~doc:"Print reasoning trace.")
  in
  let no_plan =
    Arg.(value & flag & info [ "no-plan" ] ~doc:"Skip plan artifact emission.")
  in
  let plan_dir =
    Arg.(
      value
      & opt (some string) None
      & info [ "plan-dir" ] ~docv:"DIR"
          ~doc:"Directory for plan artifacts.")
  in
  let mode =
    Arg.(
      value
      & opt (some (enum
             [
               ("auto", Types.Auto_fix);
               ("suggest", Types.Suggest);
               ("strict", Types.Hard_fail);
             ])) None
      & info [ "mode" ] ~docv:"MODE"
          ~doc:
            "Fix mode: auto (apply safe fixes), suggest (explain only), \
             strict (fail on issues).")
  in
  let backend_flag =
    Arg.(
      value
      & opt (some string) None
      & info [ "backend" ] ~docv:"BACKEND"
          ~doc:"Force linker backend: mold, lld, gold, bfd, system.")
  in
  let args =
    Arg.(value & pos_all string [] & info [] ~docv:"ARGS" ~doc:"Linker arguments.")
  in
  let link_action dry_run explain no_plan plan_dir mode backend_flag args
      _style_renderer _level =
    setup_logging _style_renderer _level;
    let cfg = load_config () in
    let driver_cfg = config_to_driver cfg in
    (* CLI flags override config *)
    let driver_cfg =
      {
        driver_cfg with
        dry_run = dry_run || driver_cfg.dry_run;
        explain = explain || driver_cfg.explain;
        emit_plan = (if no_plan then false else driver_cfg.emit_plan);
        silent = false;
      }
    in
    let driver_cfg =
      match plan_dir with
      | Some d -> { driver_cfg with plan_dir = d }
      | None -> driver_cfg
    in
    let driver_cfg =
      match mode with
      | Some m -> { driver_cfg with fix_mode = m }
      | None -> driver_cfg
    in
    let driver_cfg =
      match backend_flag with
      | Some b -> (
          match Types.backend_of_string b with
          | Some backend ->
              { driver_cfg with backend_override = Some backend }
          | None ->
              Printf.eprintf "jello: unknown backend: %s\n" b;
              driver_cfg)
      | None -> driver_cfg
    in
    match Driver.link driver_cfg args with
    | Ok result ->
        if result.Types.exit_code <> 0 then
          exit result.Types.exit_code
    | Error e ->
        Printf.eprintf "jello: %s\n" (Types.error_to_string e);
        exit 1
  in
  let term =
    Term.(
      const link_action
      $ dry_run $ explain $ no_plan $ plan_dir $ mode $ backend_flag $ args
      $ Fmt_cli.style_renderer ()
      $ Logs_cli.level ())
  in
  Cmd.v info term

(* --- Doctor subcommand --- *)

let doctor_cmd =
  let open Cmdliner in
  let doc = "Inspect the linking environment." in
  let info = Cmd.info "doctor" ~doc in
  let doctor_action _style_renderer _level =
    setup_logging _style_renderer _level;
    Printf.printf "jello doctor\n";
    Printf.printf "============\n\n";
    (* Config *)
    let cfg = load_config () in
    (match Config.find_project_config (Sys.getcwd ()) with
    | Some path -> Printf.printf "Config:       %s\n" path
    | None -> Printf.printf "Config:       none (using defaults)\n");
    Printf.printf "Fix mode:     %s\n" (Types.fix_mode_to_string cfg.fix_mode);
    Printf.printf "Emit plan:    %b\n" cfg.emit_plan;
    Printf.printf "Plan dir:     %s\n" cfg.plan_dir;
    Printf.printf "Silent:       %b\n" cfg.silent;
    Printf.printf "\n";
    (* Compiler *)
    (match Discover.compiler `C with
    | Ok cc -> Printf.printf "C compiler:   %s\n" cc
    | Error _ -> Printf.printf "C compiler:   not found\n");
    (match Discover.compiler `Cxx with
    | Ok cxx -> Printf.printf "C++ compiler: %s\n" cxx
    | Error _ -> Printf.printf "C++ compiler: not found\n");
    (* Triple *)
    (match Triple.detect () with
    | Ok t ->
        Printf.printf "Target:       %s\n" (Types.triple_to_string t)
    | Error e ->
        Printf.printf "Target:       unknown (%s)\n"
          (Types.error_to_string e));
    (* Backend *)
    Printf.printf "\nBackends:\n";
    List.iter
      (fun b ->
        let name = Types.backend_to_string b in
        match Discover.which name with
        | Some path ->
            let version =
              match Discover.linker_version path with
              | Some v -> v
              | None -> "unknown version"
            in
            Printf.printf "  %-8s %s (%s)\n" name path version
        | None -> Printf.printf "  %-8s not found\n" name)
      [ Types.Mold; Types.Lld; Types.Gold; Types.Bfd ];
    (match Discover.which "ld" with
    | Some path ->
        let version =
          match Discover.linker_version path with
          | Some v -> v
          | None -> "unknown"
        in
        Printf.printf "  %-8s %s (%s)\n" "system" path version
    | None -> Printf.printf "  %-8s not found\n" "system");
    (* nm *)
    (match Discover.nm () with
    | Ok path -> Printf.printf "\nnm:           %s\n" path
    | Error _ -> Printf.printf "\nnm:           not found\n");
    (* Search paths *)
    Printf.printf "\nDefault search paths:\n";
    List.iter
      (fun p -> Printf.printf "  %s\n" p)
      (Discover.search_paths ());
    if cfg.search_paths <> [] then (
      Printf.printf "\nExtra search paths (from config):\n";
      List.iter
        (fun p -> Printf.printf "  %s\n" p)
        cfg.search_paths)
  in
  let term =
    Term.(
      const doctor_action
      $ Fmt_cli.style_renderer ()
      $ Logs_cli.level ())
  in
  Cmd.v info term

(* --- Plan subcommand --- *)

let plan_cmd =
  let open Cmdliner in
  let doc = "Show the link plan without executing." in
  let info = Cmd.info "plan" ~doc in
  let format =
    Arg.(
      value
      & opt (enum [ ("json", `Json); ("shell", `Shell) ]) `Json
      & info [ "f"; "format" ] ~docv:"FORMAT"
          ~doc:"Output format: json or shell.")
  in
  let args =
    Arg.(value & pos_all string [] & info [] ~docv:"ARGS" ~doc:"Linker arguments.")
  in
  let plan_action format args _style_renderer _level =
    setup_logging _style_renderer _level;
    let cfg = load_config () in
    let driver_cfg =
      { (config_to_driver cfg) with dry_run = true; emit_plan = false; silent = false }
    in
    match Driver.link driver_cfg args with
    | Ok result ->
        let output =
          match format with
          | `Json -> Emit.json result.Types.plan
          | `Shell -> Emit.shell result.Types.plan
        in
        Printf.printf "%s\n" output
    | Error e ->
        Printf.eprintf "jello: %s\n" (Types.error_to_string e);
        exit 1
  in
  let term =
    Term.(
      const plan_action $ format $ args
      $ Fmt_cli.style_renderer ()
      $ Logs_cli.level ())
  in
  Cmd.v info term

(* --- Init subcommand --- *)

let init_cmd =
  let open Cmdliner in
  let doc = "Create a .jello.json config file in the current directory." in
  let info = Cmd.info "init" ~doc in
  let init_action _style_renderer _level =
    setup_logging _style_renderer _level;
    let path = ".jello.json" in
    if Sys.file_exists path then (
      Printf.eprintf "jello: %s already exists\n" path;
      exit 1)
    else
      let contents =
        {|{
  "fix_mode": "auto",
  "emit_plan": true,
  "plan_dir": ".jello",
  "silent": true
}
|}
      in
      let oc = open_out path in
      output_string oc contents;
      close_out oc;
      Printf.printf "Created %s\n" path
  in
  let term =
    Term.(
      const init_action
      $ Fmt_cli.style_renderer ()
      $ Logs_cli.level ())
  in
  Cmd.v info term

(* --- Wrapper mode (jellocc / jelloc++ / jellod) --- *)

let run_wrapper_mode mode =
  let args = Array.to_list Sys.argv |> List.tl in
  let cfg = load_config () in
  let driver_cfg = config_to_driver cfg in
  if not cfg.silent then
    setup_logging None (Config.to_logs_level cfg.log_level);
  match mode with
  | `Ld ->
      (* Raw linker replacement — jello's full pipeline *)
      (match Driver.link driver_cfg args with
      | Ok result -> exit result.Types.exit_code
      | Error e ->
          if not cfg.silent then
            Printf.eprintf "jello: %s\n" (Types.error_to_string e);
          exit 1)
  | `Cc ->
      (* Compiler wrapper — all invocations passthrough to real cc *)
      exit (Driver.passthrough `C driver_cfg args)
  | `Cxx ->
      (* Compiler wrapper — all invocations passthrough to real c++ *)
      exit (Driver.passthrough `Cxx driver_cfg args)

(* --- Main --- *)

let () =
  match detect_mode () with
  | (`Cc | `Cxx | `Ld) as mode -> run_wrapper_mode mode
  | `Direct ->
      let open Cmdliner in
      let doc = "An intelligent linker driver." in
      let info =
        Cmd.info "jello" ~version:"0.1.0" ~doc
          ~man:
            [
              `S Manpage.s_description;
              `P
                "jello is a linker driver that normalizes invocations, \
                 resolves dependencies, reorders libraries, selects \
                 backends, and produces actionable diagnostics.";
              `S Manpage.s_bugs;
              `P "Report issues at https://github.com/saint0x/jello";
            ]
      in
      let cmd =
        Cmd.group info [ link_cmd; doctor_cmd; plan_cmd; init_cmd ]
      in
      exit (Cmd.eval cmd)
