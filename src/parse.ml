open! Core
open Avalon_core
open Types

(** Parsers from raw Firestore JS objects ([Ffi.any]) into the OCaml domain model. *)

let proposal (v : Ffi.any) : proposal =
  { proposer = Ffi.field_string v "proposer"
  ; team = Ffi.field_str_list v "team"
  ; votes = Ffi.field_str_list v "votes"
  ; state = proposal_state_of_string (Ffi.field_string v "state")
  }
;;

let mission (v : Ffi.any) : mission =
  { state = mission_state_of_string (Ffi.field_string v "state")
  ; team = Ffi.field_str_list v "team"
  ; team_size = Ffi.field_int v "teamSize"
  ; fails_required = Ffi.field_int v "failsRequired"
  ; num_fails = Ffi.field_int v "numFails"
  ; proposals = Ffi.to_list (Ffi.get v "proposals") |> List.map ~f:proposal
  }
;;

let role_assignment (v : Ffi.any) : role_assignment =
  { name = Ffi.field_string v "name"
  ; role = Ffi.field_string v "role"
  ; assassin = Ffi.field_bool v "assassin"
  }
;;

(* a votes element is a JS object: { playerName: bool, ... } *)
let vote_map (v : Ffi.any) : bool String.Map.t =
  Ffi.keys v
  |> List.map ~f:(fun k -> k, Ffi.to_bool (Ffi.get v k))
  |> String.Map.of_alist_reduce ~f:(fun _ b -> b)
;;

let outcome (v : Ffi.any) : game_outcome =
  { state = outcome_state_of_string (Ffi.field_string v "state")
  ; message = Ffi.field_string v "message"
  ; assassinated = Ffi.field_string_opt v "assassinated"
  ; roles = Ffi.to_list (Ffi.get v "roles") |> List.map ~f:role_assignment
  ; votes = Ffi.to_list (Ffi.get v "votes") |> List.map ~f:vote_map
  }
;;

let game_data (v : Ffi.any) : game_data =
  let outcome_v = Ffi.get v "outcome" in
  let options_v = Ffi.get v "options" in
  { state = game_state_of_string (Ffi.field_string v "state")
  ; phase = phase_of_string (Ffi.field_string v "phase")
  ; players = Ffi.field_str_list v "players"
  ; roles =
      (if Ffi.is_nullish (Ffi.get v "roles") then [] else Ffi.field_str_list v "roles")
  ; missions = Ffi.to_list (Ffi.get v "missions") |> List.map ~f:mission
  ; outcome = (if Ffi.is_nullish outcome_v then None else Some (outcome outcome_v))
  ; in_game_log =
      (if Ffi.is_nullish options_v then false else Ffi.field_bool options_v "inGameLog")
  }
;;

let lobby_user (v : Ffi.any) : lobby_user =
  { name = Ffi.field_string v "name"; uid = Ffi.field_string_opt v "uid" }
;;

let admin (v : Ffi.any) : admin =
  { uid = Ffi.field_string v "uid"; name = Ffi.field_string v "name" }
;;

let lobby_data (v : Ffi.any) : lobby_data =
  let users_v = Ffi.get v "users" in
  let users =
    Ffi.keys users_v |> List.map ~f:(fun k -> k, lobby_user (Ffi.get users_v k))
  in
  { name = Ffi.field_string v "name"
  ; admin = admin (Ffi.get v "admin")
  ; users
  ; game = game_data (Ffi.get v "game")
  }
;;

let stats (v : Ffi.any) : stats =
  { games = Ffi.field_int v "games"
  ; good = Ffi.field_int v "good"
  ; wins = Ffi.field_int v "wins"
  ; good_wins = Ffi.field_int v "good_wins"
  ; playtime_seconds = Ffi.field_int v "playtimeSeconds"
  }
;;

let user_data (v : Ffi.any) : user_data =
  let stats_v = Ffi.get v "stats" in
  { uid = Ffi.field_string v "uid"
  ; name = Ffi.field_string v "name"
  ; email = Ffi.field_string_opt v "email"
  ; lobby = Ffi.field_string_opt v "lobby"
  ; stats = (if Ffi.is_nullish stats_v then None else Some (stats stats_v))
  }
;;

(* RoleDoc: raw [{ role: string; sees?: string[]; assassin?: bool }] with role name
   resolved to a full Role via the role map. *)
let role_doc (v : Ffi.any) : role_doc option =
  if Ffi.is_nullish v
  then None
  else (
    let role_name = Ffi.field_string v "role" in
    match Map.find Avalonlib.role_map role_name with
    | None -> None
    | Some role ->
      Some
        { role
        ; sees =
            (if Ffi.is_nullish (Ffi.get v "sees") then [] else Ffi.field_str_list v "sees")
        ; assassin = Ffi.field_bool v "assassin"
        })
;;
