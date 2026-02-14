(* normalize.ml — Normalize parsed invocation.
   Removes redundant flags, resolves conflicts,
   standardizes across GCC/Clang differences. *)

open Types

let src = Logs.Src.create "jello.normalize" ~doc:"Flag normalizer"

module Log = (val Logs.src_log src : Logs.LOG)

(* Remove duplicate search paths, preserving first occurrence *)
let dedup_search_paths paths =
  let seen = Hashtbl.create 16 in
  List.filter
    (fun p ->
      if Hashtbl.mem seen p then false
      else (
        Hashtbl.replace seen p ();
        true))
    paths

(* Remove redundant flags — last-wins for conflicting pairs *)
let resolve_conflicts flags =
  let rec go acc = function
    | [] -> List.rev acc
    (* Last -pie / -no-pie wins *)
    | Set_pie :: rest when List.exists (fun f -> f = Set_no_pie) rest ->
        go acc rest
    | Set_no_pie :: rest when List.exists (fun f -> f = Set_pie) rest ->
        go acc rest
    (* Last -Bstatic / -Bdynamic is what matters for subsequent libs *)
    (* These are positional, so we keep them *)
    | f :: rest -> go (f :: acc) rest
  in
  go [] flags

(* Remove flags that are completely redundant *)
let remove_redundant flags =
  let rec go acc = function
    | [] -> List.rev acc
    | f :: rest ->
        if List.mem f acc then (
          Log.debug (fun m -> m "Removing redundant flag");
          go acc rest)
        else go (f :: acc) rest
  in
  go [] flags

(* Ensure output has a default if not specified *)
let default_output (inv : invocation) =
  match inv.output with
  | Some _ -> inv
  | None ->
      let default = "a.out" in
      { inv with output = Some default }

(* Main entry point *)
let invocation (inv : invocation) =
  Log.debug (fun m -> m "Normalizing %d flags, %d inputs"
    (List.length inv.flags) (List.length inv.inputs));
  let flags = inv.flags |> resolve_conflicts |> remove_redundant in
  let search_paths = dedup_search_paths inv.search_paths in
  let inv : invocation = { inv with flags; search_paths } in
  let inv = default_output inv in
  Ok inv
