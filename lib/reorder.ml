(* reorder.ml — Static library reordering.
   Builds a dependency graph from symbol tables,
   topologically sorts libraries, detects cycles. *)

open Types

let src = Logs.Src.create "jello.reorder" ~doc:"Library reorder"

module Log = (val Logs.src_log src : Logs.LOG)

module StringSet = Set.Make (String)
module StringMap = Map.Make (String)

(* Build a dependency graph: lib A depends on lib B if A has undefined
   symbols that B defines. Returns adjacency list: lib -> set of libs it needs *)
let build_graph files =
  let provider_map = Symbols.providers files in
  let graph = Hashtbl.create 16 in
  List.iter
    (fun (path, syms) ->
      let undefs = Symbols.undefined syms in
      let deps =
        List.fold_left
          (fun acc sym ->
            match Hashtbl.find_opt provider_map sym.name with
            | Some providers ->
                List.fold_left
                  (fun acc p ->
                    if p <> path then StringSet.add p acc else acc)
                  acc providers
            | None -> acc)
          StringSet.empty undefs
      in
      Hashtbl.replace graph path deps)
    files;
  graph

(* Topological sort with cycle detection.
   Returns Ok sorted_list or Error cycle_members *)
let topo_sort graph nodes =
  let visited = Hashtbl.create 16 in
  let in_stack = Hashtbl.create 16 in
  let result = ref [] in
  let has_cycle = ref false in
  let cycle_members = ref StringSet.empty in
  let rec visit node =
    if Hashtbl.mem in_stack node then (
      has_cycle := true;
      cycle_members := StringSet.add node !cycle_members)
    else if not (Hashtbl.mem visited node) then (
      Hashtbl.replace visited node ();
      Hashtbl.replace in_stack node ();
      let deps =
        match Hashtbl.find_opt graph node with
        | Some s -> StringSet.elements s
        | None -> []
      in
      List.iter visit deps;
      Hashtbl.remove in_stack node;
      result := node :: !result)
  in
  List.iter visit nodes;
  if !has_cycle then Error (StringSet.elements !cycle_members)
  else Ok !result

(* Reorder a list of library paths based on dependency analysis.
   Libraries that are depended upon come after their dependents. *)
let libs lib_paths =
  (* Extract symbols for each library *)
  let files =
    List.filter_map
      (fun path ->
        match Symbols.extract path with
        | Ok syms -> Some (path, syms)
        | Error e ->
            Log.warn (fun m ->
                m "Could not extract symbols from %s: %s" path
                  (error_to_string e));
            None)
      lib_paths
  in
  if files = [] then Ok (lib_paths, [])
  else
    let graph = build_graph files in
    let nodes = List.map fst files in
    match topo_sort graph nodes with
    | Ok sorted ->
        if sorted <> lib_paths then
          Log.info (fun m -> m "Reordered %d libraries" (List.length sorted));
        Ok (sorted, [])
    | Error cycle ->
        Log.warn (fun m ->
            m "Cycle detected among %d libraries, using --start-group"
              (List.length cycle));
        (* When there's a cycle, keep original order but wrap in group *)
        let fix =
          {
            description =
              Printf.sprintf
                "Dependency cycle detected among: %s. Wrapping in \
                 --start-group/--end-group."
                (String.concat ", " (List.map Filename.basename cycle));
            confidence = High;
            action =
              Add_group
                (List.map (fun p -> Path p) cycle);
          }
        in
        Ok (lib_paths, [ fix ])
