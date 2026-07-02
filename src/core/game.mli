open! Core
open Types

(** Derived game state computed from {!Types.game_data} plus the role map (port of the
    [Game] class in client/src/avalon.ts). *)

type t =
  { data : game_data
  ; role_map : role String.Map.t
  ; num_players : int
  ; current_mission_idx : int
  ; current_mission : mission option
  ; current_proposal_idx : int
  ; current_proposal : proposal option
  ; current_proposer : string option
  ; hammer : string option
  }

val create : game_data -> role_map:role String.Map.t -> t
val data : t -> game_data
val state : t -> game_state
val phase : t -> phase
val players : t -> string list
val roles : t -> string list
val missions : t -> mission list
val outcome : t -> game_outcome option
val last_proposal : t -> proposal option
val get_num_team : t -> team -> int
val num_evil : t -> int
val num_good : t -> int
