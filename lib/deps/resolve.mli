(** Library and path resolution. *)

val libs :
  Types.invocation ->
  (Types.lib_resolved list * string list, Types.error) result
