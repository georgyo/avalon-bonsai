open! Core
open Types

(** Post-game achievement ("badge") detection (port of client/src/avalon-analysis.ts).
    {!create} returns [None] for games without an outcome (not yet completed) or with a
    canceled one (the detectors assume completed missions and would misfire on a canceled
    game's mostly pending ones); the ~40 individual detectors are private. *)

type t

type badge =
  { title : string
  ; body : string
  }

val create : game_data -> role_map:role String.Map.t -> t option
val get_badges : t -> badge list
