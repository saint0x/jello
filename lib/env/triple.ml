(* triple.ml — Target triple parsing and detection. *)

open Types

let src = Logs.Src.create "jello.triple" ~doc:"Target triple"

module Log = (val Logs.src_log src : Logs.LOG)

let ( let* ) = Result.bind

(* Parse a triple string like "x86_64-unknown-linux-gnu" *)
let parse s =
  let parts = String.split_on_char '-' s in
  match parts with
  | [ a; v; o; e ] ->
      let* arch =
        arch_of_string a
        |> Option.to_result ~none:(Parse_error (Printf.sprintf "unknown arch: %s" a))
      in
      let* os =
        os_of_string o
        |> Option.to_result ~none:(Parse_error (Printf.sprintf "unknown os: %s" o))
      in
      let env = env_of_string e in
      Ok { arch; vendor = Some v; os; env }
  | [ a; b; c ] ->
      let* arch =
        arch_of_string a
        |> Option.to_result ~none:(Parse_error (Printf.sprintf "unknown arch: %s" a))
      in
      (* Disambiguate: if b is a valid OS, treat as arch-os-env;
         otherwise treat as arch-vendor-os *)
      (match os_of_string b with
      | Some os ->
          let env = env_of_string c in
          Ok { arch; vendor = None; os; env }
      | None ->
          let* os =
            os_of_string c
            |> Option.to_result ~none:(Parse_error (Printf.sprintf "unknown os: %s" c))
          in
          Ok { arch; vendor = Some b; os; env = None })
  | [ a; o ] ->
      let* arch =
        arch_of_string a
        |> Option.to_result ~none:(Parse_error (Printf.sprintf "unknown arch: %s" a))
      in
      let* os =
        os_of_string o
        |> Option.to_result ~none:(Parse_error (Printf.sprintf "unknown os: %s" o))
      in
      Ok { arch; vendor = None; os; env = None }
  | _ -> Error (Parse_error (Printf.sprintf "cannot parse triple: %s" s))

(* Run a command and capture its trimmed stdout *)
let run_capture cmd =
  let open Bos in
  OS.Cmd.(run_out cmd |> to_string) |> Result.map String.trim

(* Detect triple from the compiler *)
let detect_from_compiler compiler =
  let open Bos in
  let compiler_cmd = Cmd.v compiler in
  (* Try clang --print-effective-triple first *)
  let clang_result =
    run_capture Cmd.(compiler_cmd % "--print-effective-triple")
  in
  match clang_result with
  | Ok s when String.length s > 0 ->
      Log.debug (fun m -> m "Triple from --print-effective-triple: %s" s);
      parse s
  | _ ->
      (* Fall back to gcc -dumpmachine *)
      let gcc_result = run_capture Cmd.(compiler_cmd % "-dumpmachine") in
      (match gcc_result with
      | Ok s when String.length s > 0 ->
          Log.debug (fun m -> m "Triple from -dumpmachine: %s" s);
          parse s
      | _ ->
          Error
            (Discovery_error
               (Printf.sprintf "cannot detect triple from compiler: %s"
                  compiler)))

(* Detect triple from host system via uname *)
let detect_from_host () =
  let open Bos in
  let* machine = run_capture Cmd.(v "uname" % "-m") in
  let* sysname = run_capture Cmd.(v "uname" % "-s") in
  let arch =
    match arch_of_string (String.lowercase_ascii machine) with
    | Some a -> a
    | None ->
        Log.warn (fun m ->
            m "Unknown architecture '%s' from uname, defaulting to x86_64" machine);
        X86_64
  in
  let os =
    match String.lowercase_ascii sysname with
    | "linux" -> Linux
    | "darwin" -> Darwin
    | "freebsd" -> FreeBSD
    | other ->
        Log.warn (fun m ->
            m "Unknown OS '%s' from uname, defaulting to linux" other);
        Linux
  in
  let env =
    match os with
    | Linux -> Some Gnu
    | Darwin -> Some Macho
    | _ -> None
  in
  Ok { arch; vendor = None; os; env }

(* Detect triple: try compiler first, fall back to host *)
let detect ?compiler () =
  let compiler = Option.value compiler ~default:"cc" in
  match detect_from_compiler compiler with
  | Ok t -> Ok t
  | Error _ ->
      Log.info (fun m ->
          m "Could not detect triple from compiler, falling back to host");
      detect_from_host ()
      |> Result.map_error (fun (`Msg s) -> Discovery_error s)

(* Check if two triples have compatible architectures *)
let arch_compatible a b = a.arch = b.arch

(* Check if a triple targets a POSIX-like system *)
let is_posix t =
  match t.os with Linux | Darwin | FreeBSD -> true | _ -> false

(* Check if a triple uses musl libc *)
let is_musl t =
  match t.env with Some Musl | Some Musleabihf -> true | _ -> false
