(** Plan serialization — JSON and shell script emission. *)

val json : Types.link_plan -> string
val shell : Types.link_plan -> string
val diagnostics_json : Types.diagnostic list -> string

val write_artifacts :
  dir:string ->
  Types.link_plan ->
  Types.diagnostic list ->
  (unit, [> `Msg of string ]) result
