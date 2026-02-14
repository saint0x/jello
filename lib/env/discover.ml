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

(* Default backend preference order *)
let default_preference = [ Mold; Lld; Gold; Bfd; System ]

(* Select the best available backend.
   ~override: force a specific backend (from config)
   ~preferred: -fuse-ld=X flag value (from CLI args)
   ~preference: ordered list to try (from config, defaults to discovery) *)
let backend ?override ?preferred ?preference () =
  (* Config override takes precedence over -fuse-ld *)
  let forced =
    match override with
    | Some b -> Some b
    | None -> (
        match preferred with
        | Some "mold" -> Some Mold
        | Some "lld" -> Some Lld
        | Some "gold" -> Some Gold
        | Some "bfd" -> Some Bfd
        | Some p ->
            if Sys.file_exists p then Some System else None
        | None -> None)
  in
  match forced with
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
      (* Auto-select: use preference list if provided, otherwise discover *)
      let order =
        match preference with Some p -> p | None -> default_preference
      in
      let found =
        List.find_map
          (fun b ->
            match find_backend_path b with
            | Some path -> Some (b, path)
            | None -> None)
          order
      in
      (match found with
      | Some (b, path) ->
          Log.info (fun m ->
              m "Auto-selected backend %s at %s" (backend_to_string b) path);
          Ok (b, path)
      | None -> Error (Discovery_error "no linker backend found"))

(* Find nm binary. ~override: force a specific path from config. *)
let nm ?override () =
  match override with
  | Some path when Sys.file_exists path -> Ok path
  | _ -> (
      match which "llvm-nm" with
      | Some p -> Ok p
      | None -> (
          match which "nm" with
          | Some p -> Ok p
          | None -> Error (Discovery_error "nm not found")))

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
