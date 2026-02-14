(* symbols.ml — Symbol table extraction via nm.
   Parses nm output into structured symbol records.
   Used for dependency graph construction and reordering. *)

open Types

let src = Logs.Src.create "jello.symbols" ~doc:"Symbol extraction"

module Log = (val Logs.src_log src : Logs.LOG)

let ( let* ) = Result.bind

(* Parse a single nm -P output line.
   Format: name type [value [size]] *)
let parse_line line =
  let parts =
    line |> String.trim |> String.split_on_char ' '
    |> List.filter (fun s -> String.length s > 0)
  in
  match parts with
  | name :: typ :: _ when String.length typ = 1 ->
      let c = typ.[0] in
      let kind =
        match c with
        | 'T' | 't' -> Sym_text
        | 'D' | 'd' -> Sym_data
        | 'B' | 'b' -> Sym_bss
        | 'R' | 'r' -> Sym_rodata
        | 'U' -> Sym_undefined
        | 'W' | 'w' | 'V' | 'v' -> Sym_weak
        | 'C' | 'c' -> Sym_common
        | _ -> Sym_other
      in
      let scope =
        if Char.uppercase_ascii c = c then Scope_global else Scope_local
      in
      Some { name; kind; scope }
  | _ -> None

(* Run nm on a file and parse all symbols *)
let extract path =
  let* nm_path = Discover.nm () in
  let cmd = Bos.Cmd.(v nm_path % "-P" % "-g" % path) in
  match Bos.OS.Cmd.(run_out ~err:err_null cmd |> to_lines) with
  | Ok lines ->
      let syms = List.filter_map parse_line lines in
      Log.debug (fun m ->
          m "Extracted %d symbols from %s" (List.length syms) path);
      Ok syms
  | Error (`Msg msg) -> Error (Symbol_error msg)

(* Get only undefined symbols *)
let undefined syms =
  List.filter (fun s -> s.kind = Sym_undefined) syms

(* Get only defined (exported) symbols *)
let defined syms =
  List.filter
    (fun s ->
      s.scope = Scope_global
      && s.kind <> Sym_undefined
      && s.kind <> Sym_other)
    syms

(* Build a map: symbol name -> list of files that define it *)
let providers files =
  let tbl = Hashtbl.create 256 in
  List.iter
    (fun (path, syms) ->
      let defs = defined syms in
      List.iter
        (fun sym ->
          let existing =
            match Hashtbl.find_opt tbl sym.name with
            | Some l -> l
            | None -> []
          in
          Hashtbl.replace tbl sym.name (path :: existing))
        defs)
    files;
  tbl

(* Build a map: file -> list of undefined symbol names *)
let requirements files =
  let tbl = Hashtbl.create 64 in
  List.iter
    (fun (path, syms) ->
      let undefs = undefined syms |> List.map (fun s -> s.name) in
      Hashtbl.replace tbl path undefs)
    files;
  tbl
