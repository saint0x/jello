(* discover.ml — Backend and toolchain discovery.
   Finds available linker backends, nm, compiler paths.
   Selects the best backend based on availability and compatibility. *)

open Types

let src = Logs.Src.create "jello.discover" ~doc:"Backend discovery"

module Log = (val Logs.src_log src : Logs.LOG)

let run_capture cmd =
  let open Bos in
  OS.Cmd.(run_out ~err:err_null cmd |> to_string)
  |> Result.map String.trim

(* Check if a command exists on PATH *)
let which name =
  let open Bos in
  match OS.Cmd.find_tool Cmd.(v name) with
  | Ok (Some p) -> Some (Fpath.to_string p)
  | _ -> None

(* Detect which linker a path actually is by checking --version *)
let identify_linker path =
  match run_capture Bos.Cmd.(v path % "--version") with
  | Ok output ->
      let lower = String.lowercase_ascii output in
      if String.length lower > 0 then
        if String.is_prefix ~affix:"mold" lower then Some Mold
        else if String.is_prefix ~affix:"lld" lower
                || String.is_prefix ~affix:"llvm" lower then Some Lld
        else if String.is_prefix ~affix:"gnu gold" lower then Some Gold
        else if String.is_prefix ~affix:"gnu ld" lower then Some Bfd
        else Some System
      else Some System
  | Error _ -> None

and is_prefix ~affix s =
  String.length s >= String.length affix
  && String.sub s 0 (String.length affix) = affix

(* Try to find a backend binary *)
let find_backend_path backend =
  let names =
    match backend with
    | Mold -> [ "mold"; "ld.mold" ]
    | Lld -> [ "ld.lld"; "lld" ]
    | Gold -> [ "ld.gold" ]
    | Bfd -> [ "ld.bfd" ]
    | System -> [ "ld" ]
  in
  List.find_map which names

(* Backend preference order *)
let preference = [ Mold; Lld; Gold; Bfd; System ]

(* Select the best available backend *)
let backend ?preferred () =
  (* If user specified -fuse-ld=X, honor it *)
  let explicit =
    match preferred with
    | Some "mold" -> Some Mold
    | Some "lld" -> Some Lld
    | Some "gold" -> Some Gold
    | Some "bfd" -> Some Bfd
    | Some p ->
        (* Treat as a path *)
        if Sys.file_exists p then Some System else None
    | None -> None
  in
  match explicit with
  | Some b -> (
      match find_backend_path b with
      | Some path ->
          Log.info (fun m ->
              m "Using requested backend %s at %s" (backend_to_string b) path);
          Ok (b, path)
      | None ->
          Error
            (Discovery_error
               (Printf.sprintf "requested backend %s not found"
                  (backend_to_string b))))
  | None ->
      (* Auto-select best available *)
      let found =
        List.find_map
          (fun b ->
            match find_backend_path b with
            | Some path -> Some (b, path)
            | None -> None)
          preference
      in
      (match found with
      | Some (b, path) ->
          Log.info (fun m ->
              m "Auto-selected backend %s at %s" (backend_to_string b) path);
          Ok (b, path)
      | None -> Error (Discovery_error "no linker backend found"))

(* Find nm binary *)
let nm () =
  match which "llvm-nm" with
  | Some p -> Ok p
  | None -> (
      match which "nm" with
      | Some p -> Ok p
      | None -> Error (Discovery_error "nm not found"))

(* Find the compiler for a given language *)
let compiler lang =
  let env_var, defaults =
    match lang with
    | `C -> ("CC", [ "cc"; "gcc"; "clang" ])
    | `Cxx -> ("CXX", [ "c++"; "g++"; "clang++" ])
  in
  match Sys.getenv_opt env_var with
  | Some cc when String.length cc > 0 -> Ok cc
  | _ ->
      let found = List.find_map which defaults in
      (match found with
      | Some p -> Ok p
      | None ->
          Error
            (Discovery_error
               (Printf.sprintf "no %s compiler found"
                  (match lang with `C -> "C" | `Cxx -> "C++"))))

(* Get default library search paths from the system linker *)
let search_paths () =
  (* Try ld --verbose to get SEARCH_DIR directives *)
  match run_capture Bos.Cmd.(v "ld" % "--verbose") with
  | Ok output ->
      let re = Re.Pcre.re {|SEARCH_DIR\("=?([^"]+)"\)|} |> Re.compile in
      let paths =
        Re.all re output
        |> List.map (fun g -> Re.Group.get g 1)
      in
      if paths = [] then
        (* Fallback to common paths *)
        [ "/usr/lib"; "/usr/local/lib"; "/lib" ]
      else paths
  | Error _ ->
      (* macOS or ld without --verbose support *)
      [ "/usr/lib"; "/usr/local/lib"; "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib" ]

(* Get sysroot from compiler *)
let sysroot compiler_path =
  match run_capture Bos.Cmd.(v compiler_path % "--print-sysroot") with
  | Ok s when String.length s > 0 -> Some s
  | _ -> None

(* Detect the linker version for a given path *)
let linker_version path =
  match run_capture Bos.Cmd.(v path % "--version") with
  | Ok output ->
      (* Take first line *)
      (match String.split_on_char '\n' output with
      | first :: _ -> Some first
      | [] -> None)
  | Error _ -> None
