(** Static library reordering via dependency analysis. *)

val libs : string list -> (string list * Types.fix list, Types.error) result
