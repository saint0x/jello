(** LinkPlan construction. *)

val preferred_linker : Types.flag list -> string option

val build :
  inv:Types.invocation ->
  triple:Types.triple ->
  backend:Types.backend ->
  backend_path:string ->
  resolved_libs:Types.lib_resolved list ->
  search_paths:string list ->
  fixes:Types.fix list ->
  (Types.link_plan, Types.error) result
