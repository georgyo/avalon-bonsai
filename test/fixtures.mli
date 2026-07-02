open! Core
open Avalon_core
open Types

(** Hand-built game_data fixtures for the pure-logic tests. *)

val role_map : role String.Map.t
val players : string list
val role_names : string list
val roles_assignment : role_assignment list

(* proposal / mission builders *)
val approved : string -> string list -> proposal
val pending : string -> proposal
val rejected : string -> string list -> proposal

(* [approved_by votes proposer team] / [rejected_by votes proposer team] *)
val approved_by : string list -> string -> string list -> proposal
val rejected_by : string list -> string -> string list -> proposal
val all_true : string list -> bool String.Map.t
val success : size:int -> team:string list -> proposer:string -> mission
val pending_mission : size:int -> mission

val make_mission
  :  ?fails_required:int
  -> ?num_fails:int
  -> state:mission_state
  -> size:int
  -> team:string list
  -> proposals:proposal list
  -> unit
  -> mission

(* completed / in-progress games *)
val good_win : game_data
val evil_win : game_data
val psychic_tie : game_data
val mid_game : game_data

(* 7-player fixtures: 3 evil (DAVE=MORGANA, EVE=ASSASSIN, GREG=MORDRED), mission 4
   requires two fails *)
val seven_players : string list
val seven_roles_assignment : role_assignment list
val seven_role_names : string list
val seven_game : missions:mission list -> outcome_state:outcome_state -> game_data
val seven_two_fail : game_data
