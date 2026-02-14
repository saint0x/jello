(* resolve.ml — Library and path resolution.
   Resolves -lfoo to concrete file paths.
   Verifies architecture compatibility.
   Handles static vs dynamic preference. *)

open Types

let src = Logs.Src.create "jello.resolve" ~doc:"Library resolver"

module Log = (val Logs.src_log src : Logs.LOG)

(* Check if a file exists *)
let file_exists path =
  match Bos.OS.File.exists (Fpath.v path) with
  | Ok true -> true
  | _ -> false

(* Check if s contains sub anywhere *)
let string_contains s sub =
  let sl = String.length s and bl = String.length sub in
  if bl > sl then false
  else
    let rec check i =
      if i > sl - bl then false
      else if String.sub s i bl = sub then true
      else check (i + 1)
    in
    check 0

(* Detect architecture from a file using the `file` command *)
let detect_arch path =
  let cmd = Bos.Cmd.(v "file" % path) in
  match Bos.OS.Cmd.(run_out cmd |> to_string) with
  | Ok output ->
      let lower = String.lowercase_ascii output in
      if string_contains lower "x86-64"
         || string_contains lower "x86_64" then
        Some X86_64
      else if string_contains lower "aarch64"
              || string_contains lower "arm64" then
        Some Aarch64
      else if string_contains lower "80386" then Some I686
      else if string_contains lower "arm" then Some Armv7
      else None
  | Error _ -> None

(* Search for a library file in a list of directories *)
let find_lib name search_paths ~prefer_static =
  let static_name = Printf.sprintf "lib%s.a" name in
  let shared_names =
    [ Printf.sprintf "lib%s.so" name;
      Printf.sprintf "lib%s.dylib" name ]
  in
  let try_dir dir =
    if prefer_static then
      let sp = Filename.concat dir static_name in
      if file_exists sp then Some (sp, Static_lib)
      else
        List.find_map
          (fun sn ->
            let dp = Filename.concat dir sn in
            if file_exists dp then Some (dp, Shared_lib) else None)
          shared_names
    else
      let found_shared =
        List.find_map
          (fun sn ->
            let dp = Filename.concat dir sn in
            if file_exists dp then Some (dp, Shared_lib) else None)
          shared_names
      in
      match found_shared with
      | Some _ as r -> r
      | None ->
          let sp = Filename.concat dir static_name in
          if file_exists sp then Some (sp, Static_lib) else None
  in
  List.find_map try_dir search_paths

(* Resolve a single library reference *)
let resolve_one search_paths ~prefer_static ref =
  match ref with
  | Path p ->
      if file_exists p then
        let kind =
          if String.ends_with ~suffix:".a" p then Static_lib else Shared_lib
        in
        let detected_arch = detect_arch p in
        Ok { reference = ref; path = p; kind; detected_arch }
      else Error (Resolve_error { lib = p; searched = [] })
  | Named name -> (
      match find_lib name search_paths ~prefer_static with
      | Some (path, kind) ->
          let detected_arch = detect_arch path in
          Log.info (fun m -> m "Resolved -l%s -> %s" name path);
          Ok { reference = ref; path; kind; detected_arch }
      | None ->
          Log.err (fun m ->
              m "Cannot find -l%s (searched %d dirs)" name
                (List.length search_paths));
          Error (Resolve_error { lib = name; searched = search_paths }))
  | Framework name ->
      (* macOS: search framework paths *)
      let fw_paths =
        [ Printf.sprintf "/System/Library/Frameworks/%s.framework/%s" name name;
          Printf.sprintf "/Library/Frameworks/%s.framework/%s" name name ]
      in
      (match List.find_opt file_exists fw_paths with
      | Some path ->
          Ok
            {
              reference = ref;
              path;
              kind = Shared_lib;
              detected_arch = detect_arch path;
            }
      | None ->
          Error (Resolve_error { lib = name; searched = fw_paths }))

(* Determine static preference from flags *)
let is_static_preferred (flags : flag list) =
  (* Walk flags in order, track current static/dynamic state *)
  let rec walk static = function
    | [] -> static
    | B_static :: rest -> walk true rest
    | B_dynamic :: rest -> walk false rest
    | Set_static :: rest -> walk true rest
    | _ :: rest -> walk static rest
  in
  walk false flags

(* Extract all library references from flags and inputs *)
let collect_lib_refs (inv : invocation) =
  let from_flags =
    List.filter_map
      (fun (f : flag) -> match f with Link_lib r -> Some r | _ -> None)
      inv.flags
  in
  let from_inputs =
    List.filter_map
      (fun i -> match i with Lib r -> Some r | _ -> None)
      inv.inputs
  in
  from_flags @ from_inputs

(* Build the full search path list *)
let build_search_paths (inv : invocation) =
  let explicit = inv.search_paths in
  let system = Discover.search_paths () in
  explicit @ system

(* Main entry point: resolve all libraries in an invocation *)
let libs (inv : invocation) =
  let search_paths = build_search_paths inv in
  let prefer_static = is_static_preferred inv.flags in
  let refs = collect_lib_refs inv in
  Log.info (fun m ->
      m "Resolving %d libraries across %d search paths" (List.length refs)
        (List.length search_paths));
  let results =
    List.map (resolve_one search_paths ~prefer_static) refs
  in
  let resolved, errors =
    List.partition_map
      (fun r -> match r with Ok v -> Left v | Error e -> Right e)
      results
  in
  match errors with
  | [] -> Ok (resolved, search_paths)
  | errs -> Error (Multiple errs)
