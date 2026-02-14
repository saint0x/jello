(* test.ml — Core tests for jello. *)

open Jello

(* --- Parse tests --- *)

let test_parse_basic () =
  let args = [ "foo.o"; "-o"; "out"; "-lfoo"; "-L/usr/lib" ] in
  match Parse.args args with
  | Ok inv ->
      Alcotest.(check int) "one input" 1 (List.length inv.inputs);
      Alcotest.(check (option string)) "output" (Some "out") inv.output;
      Alcotest.(check int) "search paths" 1
        (List.length inv.search_paths)
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

let test_parse_wl () =
  let args = [ "foo.o"; "-Wl,--as-needed,-rpath,/opt/lib" ] in
  match Parse.args args with
  | Ok inv ->
      let has_as_needed =
        List.exists
          (fun f -> f = Types.As_needed)
          inv.flags
      in
      Alcotest.(check bool) "has as-needed" true has_as_needed
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

let test_parse_link_mode () =
  let args = [ "-shared"; "foo.o" ] in
  match Parse.args args with
  | Ok inv ->
      Alcotest.(check string) "shared mode" "shared"
        (Types.link_mode_to_string inv.link_mode)
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

let test_parse_static () =
  let args = [ "-static"; "foo.o"; "-lfoo" ] in
  match Parse.args args with
  | Ok inv ->
      Alcotest.(check string) "static mode" "static"
        (Types.link_mode_to_string inv.link_mode)
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

(* --- Triple tests --- *)

let test_triple_parse () =
  match Triple.parse "x86_64-unknown-linux-gnu" with
  | Ok t ->
      Alcotest.(check string) "arch" "x86_64"
        (Types.arch_to_string t.arch);
      Alcotest.(check string) "os" "linux"
        (Types.os_to_string t.os)
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

let test_triple_parse_short () =
  match Triple.parse "aarch64-linux-gnu" with
  | Ok t ->
      Alcotest.(check string) "arch" "aarch64"
        (Types.arch_to_string t.arch);
      Alcotest.(check string) "os" "linux"
        (Types.os_to_string t.os)
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

let test_triple_parse_darwin () =
  match Triple.parse "aarch64-apple-darwin" with
  | Ok t ->
      Alcotest.(check string) "arch" "aarch64"
        (Types.arch_to_string t.arch);
      Alcotest.(check string) "os" "darwin"
        (Types.os_to_string t.os);
      Alcotest.(check (option string)) "vendor" (Some "apple")
        t.vendor
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

(* --- Normalize tests --- *)

let test_normalize_default_output () =
  let inv =
    {
      Types.empty_invocation with
      flags = [];
      inputs = [ Types.Object "foo.o" ];
    }
  in
  match Normalize.invocation inv with
  | Ok inv ->
      Alcotest.(check (option string)) "default output" (Some "a.out")
        inv.output
  | Error e ->
      Alcotest.fail (Types.error_to_string e)

(* --- Type tests --- *)

let test_arch_roundtrip () =
  let arches =
    [
      Types.X86_64; I686; Aarch64; Armv7; Riscv64; Riscv32; Mips;
      Powerpc64; S390x; Wasm32;
    ]
  in
  List.iter
    (fun a ->
      let s = Types.arch_to_string a in
      match Types.arch_of_string s with
      | Some a' ->
          Alcotest.(check string) "roundtrip" s (Types.arch_to_string a')
      | None ->
          Alcotest.fail (Printf.sprintf "failed to parse arch: %s" s))
    arches

let test_triple_to_string () =
  let t =
    {
      Types.arch = X86_64;
      vendor = Some "unknown";
      os = Linux;
      env = Some Gnu;
    }
  in
  Alcotest.(check string) "triple string" "x86_64-unknown-linux-gnu"
    (Types.triple_to_string t)

(* --- Config tests --- *)

let test_config_of_json_full () =
  let json =
    {|{
      "backend": "lld",
      "backend_preference": ["mold", "lld", "bfd"],
      "fix_mode": "suggest",
      "emit_plan": false,
      "plan_dir": "/tmp/plans",
      "explain": true,
      "dry_run": true,
      "search_paths": ["/opt/lib", "/usr/local/lib"],
      "nm": "/usr/bin/nm",
      "log_level": "debug",
      "silent": false
    }|}
  in
  match Config.of_json json with
  | Ok (p : Config.partial) ->
      Alcotest.(check (option string)) "backend" (Some "lld")
        (Option.map Types.backend_to_string p.backend);
      Alcotest.(check (option string)) "fix_mode" (Some "suggest")
        (Option.map Types.fix_mode_to_string p.fix_mode);
      Alcotest.(check (option bool)) "emit_plan" (Some false) p.emit_plan;
      Alcotest.(check (option string)) "plan_dir" (Some "/tmp/plans") p.plan_dir;
      Alcotest.(check (option bool)) "explain" (Some true) p.explain;
      Alcotest.(check (option bool)) "dry_run" (Some true) p.dry_run;
      Alcotest.(check (option string)) "nm" (Some "/usr/bin/nm") p.nm;
      Alcotest.(check (option bool)) "silent" (Some false) p.silent;
      (match p.search_paths with
      | Some paths -> Alcotest.(check int) "search_paths count" 2 (List.length paths)
      | None -> Alcotest.fail "expected search_paths");
      (match p.backend_preference with
      | Some prefs -> Alcotest.(check int) "backend_preference count" 3 (List.length prefs)
      | None -> Alcotest.fail "expected backend_preference")
  | Error msg -> Alcotest.fail msg

let test_config_of_json_partial () =
  let json = {|{"fix_mode": "auto", "silent": true}|} in
  match Config.of_json json with
  | Ok (p : Config.partial) ->
      Alcotest.(check (option string)) "fix_mode" (Some "auto")
        (Option.map Types.fix_mode_to_string p.fix_mode);
      Alcotest.(check (option bool)) "silent" (Some true) p.silent;
      Alcotest.(check (option string)) "backend" None
        (Option.map Types.backend_to_string p.backend);
      Alcotest.(check (option bool)) "emit_plan" None p.emit_plan
  | Error msg -> Alcotest.fail msg

let test_config_of_json_empty () =
  match Config.of_json "{}" with
  | Ok (p : Config.partial) ->
      Alcotest.(check (option string)) "backend" None
        (Option.map Types.backend_to_string p.backend);
      Alcotest.(check (option string)) "fix_mode" None
        (Option.map Types.fix_mode_to_string p.fix_mode);
      Alcotest.(check (option bool)) "silent" None p.silent
  | Error msg -> Alcotest.fail msg

let test_config_of_json_malformed () =
  match Config.of_json "not json at all" with
  | Ok _ -> Alcotest.fail "expected parse error"
  | Error _ -> ()

let test_config_merge_priority () =
  let hi : Config.partial =
    { Config.empty with fix_mode = Some Types.Suggest; silent = Some false }
  in
  let lo : Config.partial =
    { Config.empty with
      fix_mode = Some Types.Hard_fail;
      silent = Some true;
      emit_plan = Some false }
  in
  let merged = Config.merge hi lo in
  Alcotest.(check (option string)) "fix_mode from hi" (Some "suggest")
    (Option.map Types.fix_mode_to_string merged.fix_mode);
  Alcotest.(check (option bool)) "silent from hi" (Some false) merged.silent;
  Alcotest.(check (option bool)) "emit_plan from lo" (Some false) merged.emit_plan

let test_config_resolve_defaults () =
  let resolved = Config.resolve Config.empty in
  Alcotest.(check string) "fix_mode" "auto"
    (Types.fix_mode_to_string resolved.fix_mode);
  Alcotest.(check bool) "emit_plan" true resolved.emit_plan;
  Alcotest.(check string) "plan_dir" ".jello" resolved.plan_dir;
  Alcotest.(check bool) "silent" true resolved.silent;
  Alcotest.(check bool) "explain" false resolved.explain;
  Alcotest.(check bool) "dry_run" false resolved.dry_run;
  Alcotest.(check (option string)) "backend" None
    (Option.map Types.backend_to_string resolved.Config.backend);
  Alcotest.(check (option string)) "backend_preference" None
    (Option.map (fun _ -> "present") resolved.Config.backend_preference)

let test_config_load_no_files () =
  match Config.load () with
  | Ok cfg ->
      Alcotest.(check string) "fix_mode" "auto"
        (Types.fix_mode_to_string cfg.Config.fix_mode);
      Alcotest.(check bool) "silent" true cfg.Config.silent
  | Error msg -> Alcotest.fail msg

(* --- Type inverse parser tests --- *)

let test_backend_roundtrip () =
  let backends = [ Types.Mold; Lld; Gold; Bfd; System ] in
  List.iter
    (fun b ->
      let s = Types.backend_to_string b in
      match Types.backend_of_string s with
      | Some b' ->
          Alcotest.(check string) "roundtrip" s (Types.backend_to_string b')
      | None ->
          Alcotest.fail (Printf.sprintf "failed to parse backend: %s" s))
    backends

let test_fix_mode_roundtrip () =
  let modes = [ Types.Auto_fix; Suggest; Hard_fail ] in
  List.iter
    (fun m ->
      let s = Types.fix_mode_to_string m in
      match Types.fix_mode_of_string s with
      | Some m' ->
          Alcotest.(check string) "roundtrip" s (Types.fix_mode_to_string m')
      | None ->
          Alcotest.fail (Printf.sprintf "failed to parse fix_mode: %s" s))
    modes

(* --- Test suite --- *)

let () =
  Alcotest.run "jello"
    [
      ( "parse",
        [
          Alcotest.test_case "basic" `Quick test_parse_basic;
          Alcotest.test_case "wl-forwarding" `Quick test_parse_wl;
          Alcotest.test_case "link-mode-shared" `Quick test_parse_link_mode;
          Alcotest.test_case "link-mode-static" `Quick test_parse_static;
        ] );
      ( "triple",
        [
          Alcotest.test_case "parse-full" `Quick test_triple_parse;
          Alcotest.test_case "parse-short" `Quick test_triple_parse_short;
          Alcotest.test_case "parse-darwin" `Quick test_triple_parse_darwin;
        ] );
      ( "normalize",
        [
          Alcotest.test_case "default-output" `Quick
            test_normalize_default_output;
        ] );
      ( "types",
        [
          Alcotest.test_case "arch-roundtrip" `Quick test_arch_roundtrip;
          Alcotest.test_case "triple-to-string" `Quick
            test_triple_to_string;
          Alcotest.test_case "backend-roundtrip" `Quick test_backend_roundtrip;
          Alcotest.test_case "fix-mode-roundtrip" `Quick test_fix_mode_roundtrip;
        ] );
      ( "config",
        [
          Alcotest.test_case "json-full" `Quick test_config_of_json_full;
          Alcotest.test_case "json-partial" `Quick test_config_of_json_partial;
          Alcotest.test_case "json-empty" `Quick test_config_of_json_empty;
          Alcotest.test_case "json-malformed" `Quick test_config_of_json_malformed;
          Alcotest.test_case "merge-priority" `Quick test_config_merge_priority;
          Alcotest.test_case "resolve-defaults" `Quick test_config_resolve_defaults;
          Alcotest.test_case "load-no-files" `Quick test_config_load_no_files;
        ] );
    ]
