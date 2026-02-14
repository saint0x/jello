(* diagnose.ml — Error diagnosis and fix suggestions.
   Pattern-matches linker error output against known failure modes.
   Produces structured diagnostics with evidence and suggested fixes. *)

open Types

let src = Logs.Src.create "jello.diagnose" ~doc:"Error diagnoser"

module Log = (val Logs.src_log src : Logs.LOG)

(* A pattern rule: regex, diagnostic builder *)
type rule = {
  code : string;
  re : Re.re;
  build : Re.Group.t -> string -> diagnostic;
}

(* Helper to compile a PCRE pattern *)
let pcre s = Re.Pcre.re s |> Re.compile

(* --- Pattern rules --- *)

let undefined_ref_rule =
  {
    code = "E001";
    re = pcre {|undefined reference to [`']([^']+)'|};
    build =
      (fun g _line ->
        let sym = Re.Group.get g 1 in
        let is_cxx =
          String.starts_with ~prefix:"std::" sym
          || String.starts_with ~prefix:"__cxa_" sym
          || String.starts_with ~prefix:"__gxx_" sym
          || String.starts_with ~prefix:"operator " sym
          || String.starts_with ~prefix:"typeinfo " sym
          || String.starts_with ~prefix:"vtable " sym
        in
        let is_math =
          List.mem sym
            [ "sin"; "cos"; "tan"; "sqrt"; "pow"; "log"; "exp"; "floor";
              "ceil"; "fmod"; "round"; "fabs"; "asin"; "acos"; "atan";
              "atan2"; "sinh"; "cosh"; "tanh" ]
        in
        let is_pthread =
          String.starts_with ~prefix:"pthread_" sym
        in
        let fixes =
          if is_cxx then
            [
              {
                description =
                  "C++ symbols detected — link with g++/clang++ or add \
                   -lstdc++";
                confidence = High;
                action = Use_cxx_driver;
              };
              {
                description = "Add -lstdc++ to link command";
                confidence = High;
                action = Add_flag (Link_lib (Named "stdc++"));
              };
            ]
          else if is_math then
            [
              {
                description = "Math function — add -lm";
                confidence = High;
                action = Add_flag (Link_lib (Named "m"));
              };
            ]
          else if is_pthread then
            [
              {
                description = "pthread function — add -pthread";
                confidence = High;
                action = Add_flag (Passthrough "-pthread");
              };
            ]
          else if sym = "__stack_chk_fail" || sym = "__stack_chk_guard" then
            [
              {
                description =
                  "Stack protector symbol — link against libc or add -lssp";
                confidence = High;
                action = Add_flag (Link_lib (Named "ssp"));
              };
            ]
          else []
        in
        {
          severity = Sev_error;
          code = "E001";
          message =
            Printf.sprintf "Undefined reference to '%s'" sym;
          evidence = [ sym ];
          fixes;
        });
  }

let cannot_find_lib_rule =
  {
    code = "E002";
    re = pcre {|cannot find -l(\S+)|unable to find library -l(\S+)|library not found for -l(\S+)|};
    build =
      (fun g _line ->
        let lib =
          (try Re.Group.get g 1
           with _ ->
             try Re.Group.get g 2
             with _ -> Re.Group.get g 3)
        in
        {
          severity = Sev_error;
          code = "E002";
          message = Printf.sprintf "Cannot find library: -l%s" lib;
          evidence = [ lib ];
          fixes =
            [
              {
                description =
                  Printf.sprintf
                    "Install the development package for lib%s" lib;
                confidence = Medium;
                action = Suggest_package (Printf.sprintf "lib%s-dev" lib);
              };
              {
                description =
                  "Add the directory containing the library with -L";
                confidence = Medium;
                action = Add_search_path "";
              };
            ];
        });
  }

let dso_missing_rule =
  {
    code = "E003";
    re = pcre {|(\S+\.so\S*):.*DSO missing from command line|};
    build =
      (fun g _line ->
        let dso = Re.Group.get g 1 in
        let lib_name =
          let base = Filename.basename dso in
          if String.starts_with ~prefix:"lib" base then
            let without_prefix =
              String.sub base 3 (String.length base - 3)
            in
            match String.split_on_char '.' without_prefix with
            | name :: _ -> name
            | [] -> base
          else base
        in
        {
          severity = Sev_error;
          code = "E003";
          message =
            Printf.sprintf
              "Shared library %s is needed but not on the command line" dso;
          evidence = [ dso ];
          fixes =
            [
              {
                description =
                  Printf.sprintf "Add -l%s to the link command" lib_name;
                confidence = High;
                action = Add_flag (Link_lib (Named lib_name));
              };
            ];
        });
  }

let relocation_rule =
  {
    code = "E004";
    re =
      pcre
        {|relocation (R_\S+) .*(can not be used|cannot be used).*recompile with -fPIC|};
    build =
      (fun g line ->
        let reloc = Re.Group.get g 1 in
        (* Try to extract the file name *)
        let file =
          match Re.exec_opt (pcre {|(\S+\.o)|}) line with
          | Some fg -> Re.Group.get fg 1
          | None -> "<unknown>"
        in
        {
          severity = Sev_error;
          code = "E004";
          message =
            Printf.sprintf
              "Relocation %s requires position-independent code" reloc;
          evidence = [ reloc; file ];
          fixes =
            [
              {
                description =
                  Printf.sprintf "Recompile %s with -fPIC" file;
                confidence = High;
                action =
                  Suggest_recompile { file; flags = [ "-fPIC" ] };
              };
            ];
        });
  }

let arch_mismatch_rule =
  {
    code = "E005";
    re =
      pcre
        {|skipping incompatible (\S+)|incompatible .+ when searching for -l(\S+)|is incompatible with .+ output|};
    build =
      (fun g _line ->
        let target =
          try Re.Group.get g 1 with _ ->
          try Re.Group.get g 2 with _ -> "<unknown>"
        in
        {
          severity = Sev_error;
          code = "E005";
          message =
            Printf.sprintf
              "Architecture mismatch: %s is incompatible with target"
              target;
          evidence = [ target ];
          fixes =
            [
              {
                description =
                  "Ensure all object files and libraries match the target \
                   architecture";
                confidence = Medium;
                action = Suggest_recompile { file = target; flags = [] };
              };
            ];
        });
  }

let multiple_def_rule =
  {
    code = "E006";
    re = pcre {|multiple definition of [`']([^']+)'|};
    build =
      (fun g _line ->
        let sym = Re.Group.get g 1 in
        {
          severity = Sev_error;
          code = "E006";
          message =
            Printf.sprintf "Multiple definition of '%s'" sym;
          evidence = [ sym ];
          fixes =
            [
              {
                description =
                  "Check for duplicate symbol definitions across \
                   translation units";
                confidence = Low;
                action = Remove_flag Whole_archive;
              };
            ];
        });
  }

let file_not_recognized_rule =
  {
    code = "E007";
    re = pcre {|(\S+): file not recognized: (.+)|};
    build =
      (fun g _line ->
        let file = Re.Group.get g 1 in
        let reason = Re.Group.get g 2 in
        {
          severity = Sev_error;
          code = "E007";
          message =
            Printf.sprintf "File not recognized: %s (%s)" file reason;
          evidence = [ file; reason ];
          fixes =
            [
              {
                description =
                  Printf.sprintf
                    "Check that %s is a valid object file for the target \
                     architecture"
                    file;
                confidence = Medium;
                action = Suggest_recompile { file; flags = [] };
              };
            ];
        });
  }

let no_entry_rule =
  {
    code = "E008";
    re = pcre {|cannot find entry symbol (\S+)|};
    build =
      (fun g _line ->
        let sym = Re.Group.get g 1 in
        {
          severity = Sev_warning;
          code = "E008";
          message =
            Printf.sprintf "Cannot find entry symbol '%s'" sym;
          evidence = [ sym ];
          fixes =
            [
              {
                description =
                  "Define _start or use -e to specify an entry point";
                confidence = Medium;
                action = Add_flag (Passthrough "-e");
              };
            ];
        });
  }

let version_node_rule =
  {
    code = "E009";
    re = pcre {|version .+ not found for symbol (\S+)|};
    build =
      (fun g _line ->
        let sym = Re.Group.get g 1 in
        {
          severity = Sev_error;
          code = "E009";
          message =
            Printf.sprintf "Version node not found for symbol '%s'" sym;
          evidence = [ sym ];
          fixes =
            [
              {
                description =
                  "Rebuild against the correct library version";
                confidence = Medium;
                action = Suggest_recompile { file = ""; flags = [] };
              };
            ];
        });
  }

let hidden_symbol_rule =
  {
    code = "E010";
    re = pcre {|hidden symbol [`']([^']+)' .+ is referenced by DSO|};
    build =
      (fun g _line ->
        let sym = Re.Group.get g 1 in
        {
          severity = Sev_error;
          code = "E010";
          message =
            Printf.sprintf
              "Hidden symbol '%s' referenced by shared library" sym;
          evidence = [ sym ];
          fixes =
            [
              {
                description =
                  "Mark symbol with \
                   __attribute__((visibility(\"default\")))";
                confidence = High;
                action = Suggest_recompile { file = ""; flags = [] };
              };
            ];
        });
  }

let discarded_section_rule =
  {
    code = "E011";
    re = pcre {|defined in discarded section|};
    build =
      (fun _g line ->
        {
          severity = Sev_error;
          code = "E011";
          message = "Reference to symbol in discarded section";
          evidence = [ line ];
          fixes =
            [
              {
                description =
                  "Check for ODR violations or use \
                   __attribute__((used))";
                confidence = Low;
                action = Add_flag No_gc_sections;
              };
            ];
        });
  }

let tls_mismatch_rule =
  {
    code = "E012";
    re = pcre {|TLS (definition|reference) in .+ mismatches non-TLS|};
    build =
      (fun _g line ->
        {
          severity = Sev_error;
          code = "E012";
          message = "TLS / non-TLS mismatch between object files";
          evidence = [ line ];
          fixes =
            [
              {
                description =
                  "Ensure consistent __thread / _Thread_local usage";
                confidence = High;
                action = Suggest_recompile { file = ""; flags = [] };
              };
            ];
        });
  }

let text_reloc_rule =
  {
    code = "E013";
    re = pcre {|read-only segment has dynamic relocations|creating DT_TEXTREL|};
    build =
      (fun _g _line ->
        {
          severity = Sev_warning;
          code = "E013";
          message =
            "Text relocations in shared library (non-PIC code)";
          evidence = [];
          fixes =
            [
              {
                description = "Recompile all objects with -fPIC";
                confidence = High;
                action =
                  Suggest_recompile { file = ""; flags = [ "-fPIC" ] };
              };
            ];
        });
  }

let lto_mismatch_rule =
  {
    code = "E014";
    re = pcre {|plugin needed to handle lto object|bytecode stream .+ generated with LTO version|};
    build =
      (fun _g _line ->
        {
          severity = Sev_error;
          code = "E014";
          message = "LTO version mismatch or missing LTO plugin";
          evidence = [];
          fixes =
            [
              {
                description =
                  "Use consistent compiler versions for compile and link";
                confidence = High;
                action = Suggest_recompile { file = ""; flags = [] };
              };
              {
                description = "Pass -fuse-linker-plugin at link time";
                confidence = Medium;
                action = Add_flag (Passthrough "-fuse-linker-plugin");
              };
            ];
        });
  }

let cannot_open_output_rule =
  {
    code = "E015";
    re = pcre {|cannot open output file (.+): (.+)|};
    build =
      (fun g _line ->
        let file = Re.Group.get g 1 in
        let reason = Re.Group.get g 2 in
        {
          severity = Sev_error;
          code = "E015";
          message =
            Printf.sprintf "Cannot open output file %s: %s" file reason;
          evidence = [ file; reason ];
          fixes = [];
        });
  }

let region_overflow_rule =
  {
    code = "E016";
    re = pcre {|region `.+' overflowed|will not fit in region|};
    build =
      (fun _g line ->
        {
          severity = Sev_error;
          code = "E016";
          message = "Memory region overflow";
          evidence = [ line ];
          fixes =
            [
              {
                description =
                  "Optimize for size (-Os) or increase memory region";
                confidence = Low;
                action = Suggest_recompile { file = ""; flags = [ "-Os" ] };
              };
            ];
        });
  }

let got_overflow_rule =
  {
    code = "E017";
    re = pcre {|GOT .+ (overflow|exceeds)|too many GOT entries|};
    build =
      (fun _g _line ->
        {
          severity = Sev_error;
          code = "E017";
          message = "GOT overflow — too many global symbols";
          evidence = [];
          fixes =
            [
              {
                description = "Use -mcmodel=medium or -fvisibility=hidden";
                confidence = Medium;
                action =
                  Suggest_recompile
                    {
                      file = "";
                      flags = [ "-mcmodel=medium"; "-fvisibility=hidden" ];
                    };
              };
            ];
        });
  }

let linker_script_error_rule =
  {
    code = "E018";
    re = pcre {|(.+\.ld\S*):(\d+): syntax error|};
    build =
      (fun g _line ->
        let file = Re.Group.get g 1 in
        let line_num = Re.Group.get g 2 in
        {
          severity = Sev_error;
          code = "E018";
          message =
            Printf.sprintf "Syntax error in linker script %s:%s" file
              line_num;
          evidence = [ file; line_num ];
          fixes = [];
        });
  }

(* All rules in priority order *)
let all_rules =
  [
    undefined_ref_rule;
    cannot_find_lib_rule;
    dso_missing_rule;
    relocation_rule;
    arch_mismatch_rule;
    multiple_def_rule;
    file_not_recognized_rule;
    no_entry_rule;
    version_node_rule;
    hidden_symbol_rule;
    discarded_section_rule;
    tls_mismatch_rule;
    text_reloc_rule;
    lto_mismatch_rule;
    cannot_open_output_rule;
    region_overflow_rule;
    got_overflow_rule;
    linker_script_error_rule;
  ]

(* Match a single line against all rules *)
let match_line line =
  List.find_map
    (fun rule ->
      match Re.exec_opt rule.re line with
      | Some g -> Some (rule.build g line)
      | None -> None)
    all_rules

(* Deduplicate diagnostics by code + evidence *)
let dedup diags =
  let seen = Hashtbl.create 16 in
  List.filter
    (fun d ->
      let key = d.code ^ ":" ^ String.concat "," d.evidence in
      if Hashtbl.mem seen key then false
      else (
        Hashtbl.replace seen key ();
        true))
    diags

(* Main entry point: diagnose linker output *)
let errors result =
  let lines = String.split_on_char '\n' result.stderr in
  let diags = List.filter_map match_line lines |> dedup in
  Log.info (fun m ->
      m "Diagnosed %d issues from %d lines of output" (List.length diags)
        (List.length lines));
  { result with post_diagnostics = diags }

(* Get all auto-fixable diagnostics *)
let auto_fixable result =
  result.post_diagnostics
  |> List.filter (fun d ->
         List.exists (fun f -> f.confidence = High) d.fixes)
