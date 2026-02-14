(** Error diagnosis and fix suggestions. *)

val errors : Types.exec_result -> Types.exec_result
val auto_fixable : Types.exec_result -> Types.diagnostic list
