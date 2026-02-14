(* plan.ml — LinkPlan construction.
   Combines resolved invocation, backend, triple, and reordering
   into the final immutable plan artifact. *)

open Types

let src = Logs.Src.create "jello.plan" ~doc:"Plan builder"

module Log = (val Logs.src_log src : Logs.LOG)

(* Extract preferred linker from flags *)
let preferred_linker flags =
  List.find_map
    (fun f -> match f with Use_linker v -> Some v | _ -> None)
    flags

(* Build the backend argument list from the plan *)
let build_backend_args plan =
  let args = ref [] in
  let add s = args := s :: !args in
  (* Output *)
  add "-o";
  add plan.output;
  (* Link mode flags *)
  (match plan.link_mode with
  | Shared -> add "-shared"
  | Pie -> add "-pie"
  | Static -> add "-static"
  | Relocatable -> add "-r"
  | Executable -> ());
  (* Search paths *)
  List.iter (fun p -> add "-L"; add p) plan.search_paths;
  (* Sysroot *)
  (match plan.sysroot with
  | Some s -> add (Printf.sprintf "--sysroot=%s" s)
  | None -> ());
  (* Dynamic linker *)
  (match plan.dynamic_linker with
  | Some dl -> add "--dynamic-linker"; add dl
  | None -> ());
  (* Process flags in order, skipping ones we've already handled *)
  List.iter
    (fun f ->
      match f with
      | Output _ | Search_path _ | Set_shared | Set_pie | Set_static
      | Set_no_pie | Sysroot _ | Dynamic_linker _ | Use_linker _
      | Set_target _ | Set_arch _ | M32 | M64 | Lto | Nostdlib
      | Nostartfiles | Nodefaultlibs | Stdlib _ | Debug_flag ->
          ()
      | Rpath v -> add "-rpath"; add v
      | Rpath_link v -> add "-rpath-link"; add v
      | Whole_archive -> add "--whole-archive"
      | No_whole_archive -> add "--no-whole-archive"
      | Start_group -> add "--start-group"
      | End_group -> add "--end-group"
      | As_needed -> add "--as-needed"
      | No_as_needed -> add "--no-as-needed"
      | B_static -> add "-Bstatic"
      | B_dynamic -> add "-Bdynamic"
      | Push_state -> add "--push-state"
      | Pop_state -> add "--pop-state"
      | Gc_sections -> add "--gc-sections"
      | No_gc_sections -> add "--no-gc-sections"
      | Icf v -> add (Printf.sprintf "--icf=%s" v)
      | Export_dynamic -> add "--export-dynamic"
      | Z_flag v -> add "-z"; add v
      | Soname v -> add "-soname"; add v
      | Version_script v -> add "--version-script"; add v
      | Linker_script_flag v -> add "-T"; add v
      | Map_file v -> add (Printf.sprintf "-Map=%s" v)
      | Verbose -> add "--verbose"
      | Trace -> add "-t"
      | Print_map -> add "--print-map"
      | Strip_all -> add "-s"
      | Strip_debug -> add "-S"
      | Link_lib (Named n) -> add (Printf.sprintf "-l%s" n)
      | Link_lib (Path p) -> add p
      | Link_lib (Framework f) -> add "-framework"; add f
      | Passthrough s -> add s)
    plan.flags;
  (* Input files *)
  List.iter
    (fun i ->
      match i with
      | Object p | Archive p | Shared_object p | Linker_script p
      | Raw_input p ->
          add p
      | Response_file p -> add (Printf.sprintf "@%s" p)
      | Lib (Named n) -> add (Printf.sprintf "-l%s" n)
      | Lib (Path p) -> add p
      | Lib (Framework f) -> add "-framework"; add f)
    plan.inputs;
  List.rev !args

(* Build a LinkPlan from all resolved components *)
let build ~inv ~triple ~backend ~backend_path ~resolved_libs ~search_paths
    ~fixes =
  let sysroot =
    List.find_map
      (fun f -> match f with Sysroot v -> Some v | _ -> None)
      inv.flags
  in
  let dynamic_linker =
    List.find_map
      (fun f -> match f with Dynamic_linker v -> Some v | _ -> None)
      inv.flags
  in
  let output = Option.value inv.output ~default:"a.out" in
  let diagnostics = [] in
  let plan =
    {
      backend;
      backend_path;
      triple;
      link_mode = inv.link_mode;
      output;
      inputs = inv.inputs;
      flags = inv.flags;
      search_paths;
      resolved_libs;
      sysroot;
      dynamic_linker;
      fixes_applied = fixes;
      diagnostics;
      raw_args = inv.raw_args;
      normalized_args = [];
      backend_args = [];
    }
  in
  let backend_args = build_backend_args plan in
  let plan = { plan with backend_args } in
  Log.info (fun m ->
      m "Built plan: backend=%s output=%s mode=%s"
        (backend_to_string backend) output
        (link_mode_to_string inv.link_mode));
  Ok plan
