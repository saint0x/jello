(* parse.ml — Frontend argument parser.
   Transforms raw argv into structured flags + inputs.
   Handles -Wl, forwarding, response files, and all major GCC/Clang flags. *)

open Types

let src = Logs.Src.create "jello.parse" ~doc:"Argument parser"

module Log = (val Logs.src_log src : Logs.LOG)

let ( let* ) = Result.bind

(* Expand response files (@file.rsp) into their contents *)
let expand_response_file path =
  match Bos.OS.File.read (Fpath.v path) with
  | Ok contents ->
      (* Response files use whitespace-separated tokens *)
      let tokens =
        contents |> String.split_on_char '\n'
        |> List.concat_map (String.split_on_char ' ')
        |> List.filter (fun s -> String.length s > 0)
      in
      Ok tokens
  | Error (`Msg msg) ->
      Error (Parse_error (Printf.sprintf "cannot read response file %s: %s" path msg))

(* Expand -Wl,a,b,c into [a; b; c] *)
let expand_wl s =
  let prefix = "-Wl," in
  if String.starts_with ~prefix s then
    let rest = String.sub s (String.length prefix) (String.length s - String.length prefix) in
    String.split_on_char ',' rest
  else [ s ]

(* Classify a file by extension *)
let classify_file path =
  if String.ends_with ~suffix:".o" path then Object path
  else if String.ends_with ~suffix:".obj" path then Object path
  else if String.ends_with ~suffix:".a" path then Archive path
  else if String.ends_with ~suffix:".so" path then Shared_object path
  else if String.ends_with ~suffix:".dylib" path then Shared_object path
  else if String.ends_with ~suffix:".dll" path then Shared_object path
  else if String.ends_with ~suffix:".ld" path then Linker_script path
  else if String.ends_with ~suffix:".lds" path then Linker_script path
  else Raw_input path

(* Take a value from the next arg, or error *)
let take_next args name =
  match args with
  | v :: rest -> Ok (v, rest)
  | [] ->
      Error (Parse_error (Printf.sprintf "flag %s requires a value" name))

(* Parse a single -l flag: -lfoo or -l foo *)
let parse_l_flag arg rest =
  if String.length arg > 2 then
    (* -lfoo *)
    let name = String.sub arg 2 (String.length arg - 2) in
    Ok (Link_lib (Named name), rest)
  else
    (* -l foo *)
    let* v, rest = take_next rest "-l" in
    Ok (Link_lib (Named v), rest)

(* Parse a single -L flag: -L/path or -L /path *)
let parse_search_path arg rest =
  if String.length arg > 2 then
    let path = String.sub arg 2 (String.length arg - 2) in
    Ok (Search_path path, rest)
  else
    let* v, rest = take_next rest "-L" in
    Ok (Search_path v, rest)

(* Main recursive parser *)
let rec parse_args acc_flags acc_inputs args =
  match args with
  | [] -> Ok (List.rev acc_flags, List.rev acc_inputs)
  (* Response files *)
  | arg :: rest when String.starts_with ~prefix:"@" arg ->
      let path = String.sub arg 1 (String.length arg - 1) in
      let* expanded = expand_response_file path in
      parse_args acc_flags acc_inputs (expanded @ rest)
  (* -Wl, forwarding: expand and re-parse *)
  | arg :: rest when String.starts_with ~prefix:"-Wl," arg ->
      let expanded = expand_wl arg in
      parse_args acc_flags acc_inputs (expanded @ rest)
  (* -Xlinker: next arg is a linker flag *)
  | "-Xlinker" :: arg :: rest -> parse_args acc_flags acc_inputs (arg :: rest)
  (* Output *)
  | "-o" :: v :: rest ->
      parse_args (Output v :: acc_flags) acc_inputs rest
  (* Library flags *)
  | arg :: rest when String.starts_with ~prefix:"-l" arg ->
      let* flag, rest = parse_l_flag arg rest in
      parse_args (flag :: acc_flags) acc_inputs rest
  (* Search paths *)
  | arg :: rest when String.starts_with ~prefix:"-L" arg ->
      let* flag, rest = parse_search_path arg rest in
      parse_args (flag :: acc_flags) acc_inputs rest
  (* Sysroot *)
  | arg :: rest when String.starts_with ~prefix:"--sysroot=" arg ->
      let v = String.sub arg 10 (String.length arg - 10) in
      parse_args (Sysroot v :: acc_flags) acc_inputs rest
  | "--sysroot" :: v :: rest ->
      parse_args (Sysroot v :: acc_flags) acc_inputs rest
  (* Dynamic linker *)
  | "--dynamic-linker" :: v :: rest | "-dynamic-linker" :: v :: rest ->
      parse_args (Dynamic_linker v :: acc_flags) acc_inputs rest
  (* Rpath *)
  | "-rpath" :: v :: rest | "--rpath" :: v :: rest ->
      parse_args (Rpath v :: acc_flags) acc_inputs rest
  | arg :: rest when String.starts_with ~prefix:"-rpath=" arg ->
      let v = String.sub arg 7 (String.length arg - 7) in
      parse_args (Rpath v :: acc_flags) acc_inputs rest
  (* Archive grouping *)
  | "--whole-archive" :: rest ->
      parse_args (Whole_archive :: acc_flags) acc_inputs rest
  | "--no-whole-archive" :: rest ->
      parse_args (No_whole_archive :: acc_flags) acc_inputs rest
  | "--start-group" :: rest | "-(" :: rest ->
      parse_args (Start_group :: acc_flags) acc_inputs rest
  | "--end-group" :: rest | "-)" :: rest ->
      parse_args (End_group :: acc_flags) acc_inputs rest
  (* As-needed *)
  | "--as-needed" :: rest ->
      parse_args (As_needed :: acc_flags) acc_inputs rest
  | "--no-as-needed" :: rest ->
      parse_args (No_as_needed :: acc_flags) acc_inputs rest
  (* Static/dynamic *)
  | "-Bstatic" :: rest | "--Bstatic" :: rest ->
      parse_args (B_static :: acc_flags) acc_inputs rest
  | "-Bdynamic" :: rest | "--Bdynamic" :: rest ->
      parse_args (B_dynamic :: acc_flags) acc_inputs rest
  (* Push/pop state *)
  | "--push-state" :: rest ->
      parse_args (Push_state :: acc_flags) acc_inputs rest
  | "--pop-state" :: rest ->
      parse_args (Pop_state :: acc_flags) acc_inputs rest
  (* GC sections *)
  | "--gc-sections" :: rest ->
      parse_args (Gc_sections :: acc_flags) acc_inputs rest
  | "--no-gc-sections" :: rest ->
      parse_args (No_gc_sections :: acc_flags) acc_inputs rest
  (* ICF *)
  | arg :: rest when String.starts_with ~prefix:"--icf=" arg ->
      let v = String.sub arg 6 (String.length arg - 6) in
      parse_args (Icf v :: acc_flags) acc_inputs rest
  (* Export dynamic *)
  | "--export-dynamic" :: rest | "-E" :: rest ->
      parse_args (Export_dynamic :: acc_flags) acc_inputs rest
  (* Link mode flags *)
  | "-pie" :: rest | "--pie" :: rest ->
      parse_args (Set_pie :: acc_flags) acc_inputs rest
  | "-no-pie" :: rest | "--no-pie" :: rest ->
      parse_args (Set_no_pie :: acc_flags) acc_inputs rest
  | "-shared" :: rest ->
      parse_args (Set_shared :: acc_flags) acc_inputs rest
  | "-static" :: rest ->
      parse_args (Set_static :: acc_flags) acc_inputs rest
  | "-r" :: rest | "--relocatable" :: rest ->
      parse_args acc_flags acc_inputs rest (* handled in link_mode *)
  (* Stdlib control *)
  | "-nostdlib" :: rest ->
      parse_args (Nostdlib :: acc_flags) acc_inputs rest
  | "-nostartfiles" :: rest ->
      parse_args (Nostartfiles :: acc_flags) acc_inputs rest
  | "-nodefaultlibs" :: rest ->
      parse_args (Nodefaultlibs :: acc_flags) acc_inputs rest
  | arg :: rest when String.starts_with ~prefix:"-stdlib=" arg ->
      let v = String.sub arg 8 (String.length arg - 8) in
      parse_args (Stdlib v :: acc_flags) acc_inputs rest
  (* Target / arch *)
  | "--target" :: v :: rest | "-target" :: v :: rest ->
      parse_args (Set_target v :: acc_flags) acc_inputs rest
  | arg :: rest when String.starts_with ~prefix:"--target=" arg ->
      let v = String.sub arg 9 (String.length arg - 9) in
      parse_args (Set_target v :: acc_flags) acc_inputs rest
  | arg :: rest when String.starts_with ~prefix:"-march=" arg ->
      let v = String.sub arg 7 (String.length arg - 7) in
      parse_args (Set_arch v :: acc_flags) acc_inputs rest
  | "-m32" :: rest -> parse_args (M32 :: acc_flags) acc_inputs rest
  | "-m64" :: rest -> parse_args (M64 :: acc_flags) acc_inputs rest
  (* LTO *)
  | "-flto" :: rest -> parse_args (Lto :: acc_flags) acc_inputs rest
  | arg :: rest when String.starts_with ~prefix:"-flto=" arg ->
      parse_args (Lto :: acc_flags) acc_inputs rest
  (* Backend selection *)
  | arg :: rest when String.starts_with ~prefix:"-fuse-ld=" arg ->
      let v = String.sub arg 9 (String.length arg - 9) in
      parse_args (Use_linker v :: acc_flags) acc_inputs rest
  (* -z flags *)
  | "-z" :: v :: rest ->
      parse_args (Z_flag v :: acc_flags) acc_inputs rest
  (* Soname *)
  | "-soname" :: v :: rest | "--soname" :: v :: rest | "-h" :: v :: rest ->
      parse_args (Soname v :: acc_flags) acc_inputs rest
  | arg :: rest when String.starts_with ~prefix:"--soname=" arg ->
      let v = String.sub arg 9 (String.length arg - 9) in
      parse_args (Soname v :: acc_flags) acc_inputs rest
  (* Version script *)
  | "--version-script" :: v :: rest ->
      parse_args (Version_script v :: acc_flags) acc_inputs rest
  | arg :: rest when String.starts_with ~prefix:"--version-script=" arg ->
      let v = String.sub arg 17 (String.length arg - 17) in
      parse_args (Version_script v :: acc_flags) acc_inputs rest
  (* Linker script *)
  | "-T" :: v :: rest ->
      parse_args (Linker_script_flag v :: acc_flags) acc_inputs rest
  (* Map file *)
  | arg :: rest when String.starts_with ~prefix:"-Map=" arg ->
      let v = String.sub arg 5 (String.length arg - 5) in
      parse_args (Map_file v :: acc_flags) acc_inputs rest
  | "-Map" :: v :: rest ->
      parse_args (Map_file v :: acc_flags) acc_inputs rest
  (* Diagnostics *)
  | "--verbose" :: rest | "-verbose" :: rest ->
      parse_args (Verbose :: acc_flags) acc_inputs rest
  | "-t" :: rest ->
      parse_args (Trace :: acc_flags) acc_inputs rest
  | "--print-map" :: rest | "-M" :: rest ->
      parse_args (Print_map :: acc_flags) acc_inputs rest
  (* Strip *)
  | "-s" :: rest | "--strip-all" :: rest ->
      parse_args (Strip_all :: acc_flags) acc_inputs rest
  | "-S" :: rest | "--strip-debug" :: rest ->
      parse_args (Strip_debug :: acc_flags) acc_inputs rest
  (* Debug *)
  | "-g" :: rest -> parse_args (Debug_flag :: acc_flags) acc_inputs rest
  (* Framework (macOS) *)
  | "-framework" :: v :: rest ->
      parse_args (Link_lib (Framework v) :: acc_flags) acc_inputs rest
  (* Rpath-link *)
  | "-rpath-link" :: v :: rest | "--rpath-link" :: v :: rest ->
      parse_args (Rpath_link v :: acc_flags) acc_inputs rest
  (* Skip compiler-only flags that don't affect linking *)
  | arg :: rest
    when String.starts_with ~prefix:"-O" arg
         || String.starts_with ~prefix:"-W" arg
            && not (String.starts_with ~prefix:"-Wl," arg)
         || String.starts_with ~prefix:"-f" arg
            && not (String.starts_with ~prefix:"-flto" arg)
            && not (String.starts_with ~prefix:"-fuse-ld=" arg)
         || String.starts_with ~prefix:"-D" arg
         || String.starts_with ~prefix:"-I" arg
         || String.starts_with ~prefix:"-std=" arg
         || arg = "-c"
         || arg = "-pipe" ->
      Log.debug (fun m -> m "Skipping compiler flag: %s" arg);
      parse_args acc_flags acc_inputs rest
  (* Positional: files *)
  | arg :: rest when not (String.starts_with ~prefix:"-" arg) ->
      let input = classify_file arg in
      parse_args acc_flags (input :: acc_inputs) rest
  (* Unknown flags: passthrough *)
  | arg :: rest ->
      Log.debug (fun m -> m "Passing through unknown flag: %s" arg);
      parse_args (Passthrough arg :: acc_flags) acc_inputs rest

(* Determine link mode from flags *)
let determine_link_mode flags =
  let has f = List.exists (fun x -> x = f) flags in
  if has Set_shared then Shared
  else if has Set_pie then Pie
  else if has Set_static then Static
  else Executable

(* Extract output path from flags *)
let extract_output flags =
  List.find_map
    (fun f -> match f with Output v -> Some v | _ -> None)
    flags

(* Extract search paths from flags, preserving order *)
let extract_search_paths flags =
  List.filter_map
    (fun f -> match f with Search_path v -> Some v | _ -> None)
    flags

(* Main entry point: parse raw args into an invocation *)
let args raw_args =
  let* flags, inputs = parse_args [] [] raw_args in
  let link_mode = determine_link_mode flags in
  let output = extract_output flags in
  let search_paths = extract_search_paths flags in
  Ok
    {
      raw_args;
      flags;
      inputs;
      output;
      link_mode;
      search_paths;
    }
