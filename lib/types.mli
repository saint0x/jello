(** Core types for the jello linker driver.
    All phases, flags, diagnostics, and plans are modeled here. *)

(** {1 Architecture} *)

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

val arch_to_string : arch -> string
val arch_of_string : string -> arch option

(** {1 Operating System} *)

type os = Linux | Darwin | FreeBSD | Windows | Bare

val os_to_string : os -> string
val os_of_string : string -> os option

(** {1 ABI / Environment} *)

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

val env_to_string : env -> string
val env_of_string : string -> env option

(** {1 Target Triple} *)

type triple = {
  arch : arch;
  vendor : string option;
  os : os;
  env : env option;
}

val triple_to_string : triple -> string

(** {1 Link Mode} *)

type link_mode = Executable | Shared | Static | Pie | Relocatable

val link_mode_to_string : link_mode -> string

(** {1 Linker Backend} *)

type backend = Mold | Lld | Gold | Bfd | System

val backend_to_string : backend -> string
val backend_of_string : string -> backend option

(** {1 Library References} *)

type lib_ref = Named of string | Path of string | Framework of string

val lib_ref_to_string : lib_ref -> string

type lib_kind = Static_lib | Shared_lib

type lib_resolved = {
  reference : lib_ref;
  path : string;
  kind : lib_kind;
  detected_arch : arch option;
}

(** {1 Inputs} *)

type input =
  | Object of string
  | Archive of string
  | Shared_object of string
  | Linker_script of string
  | Response_file of string
  | Lib of lib_ref
  | Raw_input of string

val input_path : input -> string

(** {1 Flags} *)

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

(** {1 Symbols} *)

type symbol_kind =
  | Sym_text
  | Sym_data
  | Sym_bss
  | Sym_rodata
  | Sym_undefined
  | Sym_weak
  | Sym_common
  | Sym_other

type symbol_scope = Scope_global | Scope_local

type symbol = {
  name : string;
  kind : symbol_kind;
  scope : symbol_scope;
}

(** {1 Diagnostics} *)

type severity = Sev_error | Sev_warning | Sev_info | Sev_hint

val severity_to_string : severity -> string

type confidence = High | Medium | Low

val confidence_to_string : confidence -> string

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

(** {1 Fix Mode} *)

type fix_mode = Auto_fix | Suggest | Hard_fail

val fix_mode_of_string : string -> fix_mode option
val fix_mode_to_string : fix_mode -> string

(** {1 Invocation} *)

type invocation = {
  raw_args : string list;
  flags : flag list;
  inputs : input list;
  output : string option;
  link_mode : link_mode;
  search_paths : string list;
}

val empty_invocation : invocation

(** {1 LinkPlan} *)

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
  backend_args : string list;
}

(** {1 Execution Result} *)

type exec_result = {
  plan : link_plan;
  exit_code : int;
  stdout : string;
  stderr : string;
  post_diagnostics : diagnostic list;
}

(** {1 Errors} *)

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

val error_to_string : error -> string
