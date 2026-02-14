(* main.ml — CLI entry point for gel.
   Supports direct invocation and wrapper mode (gelcc, gelc++, geld). *)

open Jello

let setup_logging style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (Logs_fmt.reporter ())

(* Detect invocation mode from argv[0] *)
let detect_mode () =
  let prog = Filename.basename Sys.argv.(0) in
  match prog with
  | "gelcc" -> `Cc
  | "gelc++" -> `Cxx
  | "geld" -> `Ld
  | _ -> `Direct

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
      & opt string ".gel"
      & info [ "plan-dir" ] ~docv:"DIR"
          ~doc:"Directory for plan artifacts.")
  in
  let mode =
    Arg.(
      value
      & opt
          (enum
             [
               ("auto", Types.Auto_fix);
               ("suggest", Types.Suggest);
               ("strict", Types.Hard_fail);
             ])
          Types.Auto_fix
      & info [ "mode" ] ~docv:"MODE"
          ~doc:
            "Fix mode: auto (apply safe fixes), suggest (explain only), \
             strict (fail on issues).")
  in
  let args =
    Arg.(value & pos_all string [] & info [] ~docv:"ARGS" ~doc:"Linker arguments.")
  in
  let link_action dry_run explain no_plan plan_dir mode args _style_renderer _level =
    setup_logging _style_renderer _level;
    let config =
      {
        Driver.fix_mode = mode;
        emit_plan = not no_plan;
        plan_dir;
        dry_run;
        explain;
      }
    in
    match Driver.link config args with
    | Ok result -> `Ok result.Types.exit_code
    | Error e ->
        Printf.eprintf "gel: %s\n" (Types.error_to_string e);
        `Ok 1
  in
  let term =
    Term.(
      ret
        (const (fun dr ex np pd md ar sr lv ->
             `Ok (link_action dr ex np pd md ar sr lv))
        $ dry_run $ explain $ no_plan $ plan_dir $ mode $ args
        $ Fmt_cli.style_renderer ()
        $ Logs_cli.level ()))
  in
  Cmd.v info term

(* --- Doctor subcommand --- *)

let doctor_cmd =
  let open Cmdliner in
  let doc = "Inspect the linking environment." in
  let info = Cmd.info "doctor" ~doc in
  let doctor_action _style_renderer _level =
    setup_logging _style_renderer _level;
    Printf.printf "gel doctor\n";
    Printf.printf "=========\n\n";
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
    `Ok 0
  in
  let term =
    Term.(
      ret
        (const doctor_action
        $ Fmt_cli.style_renderer ()
        $ Logs_cli.level ()))
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
    let config =
      { Driver.default_config with dry_run = true; emit_plan = false }
    in
    match Driver.link config args with
    | Ok result ->
        let output =
          match format with
          | `Json -> Emit.json result.Types.plan
          | `Shell -> Emit.shell result.Types.plan
        in
        Printf.printf "%s\n" output;
        `Ok 0
    | Error e ->
        Printf.eprintf "gel: %s\n" (Types.error_to_string e);
        `Ok 1
  in
  let term =
    Term.(
      ret
        (const plan_action $ format $ args
        $ Fmt_cli.style_renderer ()
        $ Logs_cli.level ()))
  in
  Cmd.v info term

(* --- Wrapper mode (gelcc / gelc++ / geld) --- *)

let run_wrapper_mode () =
  let args = Array.to_list Sys.argv |> List.tl in
  let config = Driver.default_config in
  match Driver.link config args with
  | Ok result -> exit result.Types.exit_code
  | Error e ->
      Printf.eprintf "gel: %s\n" (Types.error_to_string e);
      exit 1

(* --- Main --- *)

let () =
  match detect_mode () with
  | `Cc | `Cxx | `Ld -> run_wrapper_mode ()
  | `Direct ->
      let open Cmdliner in
      let doc = "An intelligent linker driver." in
      let info =
        Cmd.info "gel" ~version:"0.1.0" ~doc
          ~man:
            [
              `S Manpage.s_description;
              `P
                "gel is a linker driver that normalizes invocations, \
                 resolves dependencies, reorders libraries, selects \
                 backends, and produces actionable diagnostics.";
              `S Manpage.s_bugs;
              `P "Report issues at https://github.com/deepsaint/jello";
            ]
      in
      let cmd = Cmd.group info [ link_cmd; doctor_cmd; plan_cmd ] in
      exit (Cmd.eval cmd)
