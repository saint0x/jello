(* types.ml — Core algebraic types for the linker driver.
   Every concept in the link pipeline is modeled here.
   Variants over booleans. Make invalid states unrepresentable. *)

(* --- Architecture --- *)

type arch =
  | X86_64
  | I686
  | Aarch64
  | Armv7
  | Riscv64
  | Riscv32
  | Mips
  | Mipsel
  | Powerpc64
  | Powerpc64le
  | S390x
  | Wasm32

let arch_to_string = function
  | X86_64 -> "x86_64"
  | I686 -> "i686"
  | Aarch64 -> "aarch64"
  | Armv7 -> "armv7"
  | Riscv64 -> "riscv64"
  | Riscv32 -> "riscv32"
  | Mips -> "mips"
  | Mipsel -> "mipsel"
  | Powerpc64 -> "powerpc64"
  | Powerpc64le -> "powerpc64le"
  | S390x -> "s390x"
  | Wasm32 -> "wasm32"

let arch_of_string = function
  | "x86_64" | "amd64" -> Some X86_64
  | "i686" | "i386" | "i586" -> Some I686
  | "aarch64" | "arm64" -> Some Aarch64
  | "armv7" | "armv7l" | "arm" -> Some Armv7
  | "riscv64" -> Some Riscv64
  | "riscv32" -> Some Riscv32
  | "mips" -> Some Mips
  | "mipsel" -> Some Mipsel
  | "powerpc64" | "ppc64" -> Some Powerpc64
  | "powerpc64le" | "ppc64le" -> Some Powerpc64le
  | "s390x" -> Some S390x
  | "wasm32" -> Some Wasm32
  | _ -> None

(* --- Operating system --- *)

type os =
  | Linux
  | Darwin
  | FreeBSD
  | Windows
  | Bare

let os_to_string = function
  | Linux -> "linux"
  | Darwin -> "darwin"
  | FreeBSD -> "freebsd"
  | Windows -> "windows"
  | Bare -> "none"

let os_of_string s =
  (* Strip version suffixes: darwin24.3.0 -> darwin *)
  let base =
    match String.index_opt s '.' with
    | Some i ->
        let prefix = String.sub s 0 i in
        (* Strip trailing digits: darwin24 -> darwin *)
        let len = ref (String.length prefix) in
        while !len > 0 && prefix.[!len - 1] >= '0' && prefix.[!len - 1] <= '9' do
          decr len
        done;
        if !len > 0 then String.sub prefix 0 !len else prefix
    | None ->
        let len = ref (String.length s) in
        while !len > 0 && s.[!len - 1] >= '0' && s.[!len - 1] <= '9' do
          decr len
        done;
        if !len > 0 && !len < String.length s then String.sub s 0 !len else s
  in
  match base with
  | "linux" -> Some Linux
  | "darwin" -> Some Darwin
  | "freebsd" -> Some FreeBSD
  | "windows" | "win32" -> Some Windows
  | "none" | "elf" -> Some Bare
  | _ -> None

(* --- ABI / environment --- *)

type env =
  | Gnu
  | Gnueabihf
  | Musl
  | Musleabihf
  | Android
  | Msvc
  | Mingw32
  | Eabi
  | Eabihf
  | Macho

let env_to_string = function
  | Gnu -> "gnu"
  | Gnueabihf -> "gnueabihf"
  | Musl -> "musl"
  | Musleabihf -> "musleabihf"
  | Android -> "android"
  | Msvc -> "msvc"
  | Mingw32 -> "mingw32"
  | Eabi -> "eabi"
  | Eabihf -> "eabihf"
  | Macho -> "macho"

let env_of_string = function
  | "gnu" -> Some Gnu
  | "gnueabihf" -> Some Gnueabihf
  | "musl" -> Some Musl
  | "musleabihf" -> Some Musleabihf
  | "android" | "androideabi" -> Some Android
  | "msvc" -> Some Msvc
  | "mingw32" -> Some Mingw32
  | "eabi" -> Some Eabi
  | "eabihf" -> Some Eabihf
  | "macho" -> Some Macho
  | _ -> None

(* --- Target triple --- *)

type triple = {
  arch : arch;
  vendor : string option;
  os : os;
  env : env option;
}

let triple_to_string t =
  let parts =
    [ arch_to_string t.arch ]
    @ (match t.vendor with Some v -> [ v ] | None -> [ "unknown" ])
    @ [ os_to_string t.os ]
    @ (match t.env with Some e -> [ env_to_string e ] | None -> [])
  in
  String.concat "-" parts

(* --- Link mode --- *)

type link_mode =
  | Executable
  | Shared
  | Static
  | Pie
  | Relocatable

let link_mode_to_string = function
  | Executable -> "executable"
  | Shared -> "shared"
  | Static -> "static"
  | Pie -> "pie"
  | Relocatable -> "relocatable"

(* --- Linker backend --- *)

type backend =
  | Mold
  | Lld
  | Gold
  | Bfd
  | System

let backend_to_string = function
  | Mold -> "mold"
  | Lld -> "lld"
  | Gold -> "gold"
  | Bfd -> "bfd"
  | System -> "system"

(* --- Library reference (unresolved) --- *)

type lib_ref =
  | Named of string
  | Path of string
  | Framework of string

let lib_ref_to_string = function
  | Named n -> Printf.sprintf "-l%s" n
  | Path p -> p
  | Framework f -> Printf.sprintf "-framework %s" f

(* --- Library kind (resolved) --- *)

type lib_kind =
  | Static_lib
  | Shared_lib

(* --- Resolved library --- *)

type lib_resolved = {
  reference : lib_ref;
  path : string;
  kind : lib_kind;
  detected_arch : arch option;
}

(* --- Input files --- *)

type input =
  | Object of string
  | Archive of string
  | Shared_object of string
  | Linker_script of string
  | Response_file of string
  | Lib of lib_ref
  | Raw_input of string

let input_path = function
  | Object p | Archive p | Shared_object p | Linker_script p
  | Response_file p | Raw_input p ->
      p
  | Lib r -> lib_ref_to_string r

(* --- Linker flags (canonical representation) --- *)

type flag =
  | Output of string
  | Search_path of string
  | Link_lib of lib_ref
  | Sysroot of string
  | Dynamic_linker of string
  | Rpath of string
  | Rpath_link of string
  | Whole_archive
  | No_whole_archive
  | Start_group
  | End_group
  | As_needed
  | No_as_needed
  | B_static
  | B_dynamic
  | Push_state
  | Pop_state
  | Gc_sections
  | No_gc_sections
  | Icf of string
  | Export_dynamic
  | Set_pie
  | Set_no_pie
  | Set_shared
  | Set_static
  | Nostdlib
  | Nostartfiles
  | Nodefaultlibs
  | Stdlib of string
  | Set_target of string
  | Set_arch of string
  | M32
  | M64
  | Lto
  | Use_linker of string
  | Z_flag of string
  | Soname of string
  | Version_script of string
  | Linker_script_flag of string
  | Map_file of string
  | Verbose
  | Trace
  | Print_map
  | Debug_flag
  | Strip_all
  | Strip_debug
  | Passthrough of string

(* --- Symbols --- *)

type symbol_kind =
  | Sym_text
  | Sym_data
  | Sym_bss
  | Sym_rodata
  | Sym_undefined
  | Sym_weak
  | Sym_common
  | Sym_other

type symbol_scope =
  | Scope_global
  | Scope_local

type symbol = {
  name : string;
  kind : symbol_kind;
  scope : symbol_scope;
}

(* --- Diagnostics --- *)

type severity =
  | Sev_error
  | Sev_warning
  | Sev_info
  | Sev_hint

let severity_to_string = function
  | Sev_error -> "error"
  | Sev_warning -> "warning"
  | Sev_info -> "info"
  | Sev_hint -> "hint"

type confidence =
  | High
  | Medium
  | Low

let confidence_to_string = function
  | High -> "high"
  | Medium -> "medium"
  | Low -> "low"

type fix_action =
  | Add_flag of flag
  | Remove_flag of flag
  | Reorder_libs of lib_ref list
  | Add_group of lib_ref list
  | Suggest_package of string
  | Suggest_recompile of { file : string; flags : string list }
  | Use_cxx_driver
  | Add_search_path of string

type fix = {
  description : string;
  confidence : confidence;
  action : fix_action;
}

type diagnostic = {
  severity : severity;
  code : string;
  message : string;
  evidence : string list;
  fixes : fix list;
}

(* --- Fix mode policy --- *)

type fix_mode =
  | Auto_fix
  | Suggest
  | Hard_fail

(* --- Invocation (pre-plan) --- *)

type invocation = {
  raw_args : string list;
  flags : flag list;
  inputs : input list;
  output : string option;
  link_mode : link_mode;
  search_paths : string list;
}

let empty_invocation =
  {
    raw_args = [];
    flags = [];
    inputs = [];
    output = None;
    link_mode = Executable;
    search_paths = [];
  }

(* --- LinkPlan (the core artifact) --- *)

type link_plan = {
  backend : backend;
  backend_path : string;
  triple : triple;
  link_mode : link_mode;
  output : string;
  inputs : input list;
  flags : flag list;
  search_paths : string list;
  resolved_libs : lib_resolved list;
  sysroot : string option;
  dynamic_linker : string option;
  fixes_applied : fix list;
  diagnostics : diagnostic list;
  raw_args : string list;
  normalized_args : string list;
  backend_args : string list;
}

(* --- Execution result --- *)

type exec_result = {
  plan : link_plan;
  exit_code : int;
  stdout : string;
  stderr : string;
  post_diagnostics : diagnostic list;
}

(* --- Errors --- *)

type error =
  | Parse_error of string
  | Normalize_error of string
  | Discovery_error of string
  | Resolve_error of { lib : string; searched : string list }
  | Symbol_error of string
  | Reorder_error of string
  | Plan_error of string
  | Exec_error of { exit_code : int; stderr : string }
  | Multiple of error list

let rec error_to_string = function
  | Parse_error s -> Printf.sprintf "parse error: %s" s
  | Normalize_error s -> Printf.sprintf "normalization error: %s" s
  | Discovery_error s -> Printf.sprintf "discovery error: %s" s
  | Resolve_error { lib; searched } ->
      Printf.sprintf "cannot find %s (searched: %s)" lib
        (String.concat ", " searched)
  | Symbol_error s -> Printf.sprintf "symbol error: %s" s
  | Reorder_error s -> Printf.sprintf "reorder error: %s" s
  | Plan_error s -> Printf.sprintf "plan error: %s" s
  | Exec_error { exit_code; stderr } ->
      Printf.sprintf "execution failed (exit %d): %s" exit_code stderr
  | Multiple errs ->
      errs |> List.map error_to_string |> String.concat "\n"
