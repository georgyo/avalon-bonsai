open! Core
open Avalon_core
open Types

(** Hand-built game_data fixtures for the pure-logic tests. The 5-player layout mirrors
    the e2e games: ALICE=MERLIN, BOB=PERCIVAL, CARL=LOYAL FOLLOWER (good); DAVE=MORGANA,
    EVE=ASSASSIN (evil). *)

let role_map = Avalonlib.role_map
let players = [ "ALICE"; "BOB"; "CARL"; "DAVE"; "EVE" ]

let roles_assignment : role_assignment list =
  [ { name = "ALICE"; role = "MERLIN"; assassin = false }
  ; { name = "BOB"; role = "PERCIVAL"; assassin = false }
  ; { name = "CARL"; role = "LOYAL FOLLOWER"; assassin = false }
  ; { name = "DAVE"; role = "MORGANA"; assassin = false }
  ; { name = "EVE"; role = "ASSASSIN"; assassin = true }
  ]
;;

let role_names = [ "MERLIN"; "PERCIVAL"; "LOYAL FOLLOWER"; "MORGANA"; "ASSASSIN" ]

let approved (proposer : string) (team : string list) : proposal =
  { proposer; team; votes = players; state = Approved }
;;

let pending (proposer : string) : proposal =
  { proposer; team = []; votes = []; state = Pending }
;;

let rejected (proposer : string) (team : string list) : proposal =
  { proposer; team; votes = []; state = Rejected }
;;

(* like [approved]/[rejected] but with explicit approval votes, for games whose player
   list is not the 5-player [players] (or for rejected proposals that still had voters). *)
let approved_by (votes : string list) (proposer : string) (team : string list) : proposal =
  { proposer; team; votes; state = Approved }
;;

let rejected_by (votes : string list) (proposer : string) (team : string list) : proposal =
  { proposer; team; votes; state = Rejected }
;;

let all_true (team : string list) : bool String.Map.t =
  String.Map.of_alist_exn (List.map team ~f:(fun n -> n, true))
;;

let success ~size ~team ~proposer : mission =
  { state = Success
  ; team
  ; team_size = size
  ; fails_required = 1
  ; num_fails = 0
  ; proposals = [ approved proposer team ]
  }
;;

let pending_mission ~size : mission =
  { state = M_pending
  ; team = []
  ; team_size = size
  ; fails_required = 1
  ; num_fails = 0
  ; proposals = []
  }
;;

let make_mission ?(fails_required = 1) ?(num_fails = 0) ~state ~size ~team ~proposals ()
  : mission
  =
  { state; team; team_size = size; fails_required; num_fails; proposals }
;;

(* A completed good win in which evil was never sent on a mission (good teams only). *)
let good_win : game_data =
  let mission_votes =
    let all_true team = String.Map.of_alist_exn (List.map team ~f:(fun n -> n, true)) in
    [ all_true [ "ALICE"; "BOB" ]
    ; all_true [ "ALICE"; "BOB"; "CARL" ]
    ; all_true [ "ALICE"; "BOB" ]
    ]
  in
  { state = Game_ended
  ; (* GOOD_WIN is an outcome state, not a phase; the real end-of-game phase for a lobby
       with an assassin is ASSASSINATION (server/types.ts). *)
    phase = Assassination
  ; players
  ; roles = role_names
  ; missions =
      [ success ~size:2 ~team:[ "ALICE"; "BOB" ] ~proposer:"ALICE"
      ; success ~size:3 ~team:[ "ALICE"; "BOB"; "CARL" ] ~proposer:"BOB"
      ; success ~size:2 ~team:[ "ALICE"; "BOB" ] ~proposer:"CARL"
      ; pending_mission ~size:3
      ; pending_mission ~size:3
      ]
  ; outcome =
      Some
        { state = Good_win
        ; message = "Good wins!"
        ; assassinated = None
        ; roles = roles_assignment
        ; votes = mission_votes
        }
  ; in_game_log = false
  }
;;

(* A completed EVIL win by assassination: good ran 3 successful missions (evil rode along
   without failing), then the assassin (EVE) correctly killed Merlin (ALICE). Includes a
   couple of rejected proposals so rejection/curse detectors have data. *)
let evil_win : game_data =
  let m1 : mission =
    { state = Success
    ; team = [ "ALICE"; "BOB" ]
    ; team_size = 2
    ; fails_required = 1
    ; num_fails = 0
    ; proposals =
        [ rejected "DAVE" [ "DAVE"; "EVE" ]; approved "ALICE" [ "ALICE"; "BOB" ] ]
    }
  in
  let m2 = success ~size:3 ~team:[ "BOB"; "CARL"; "DAVE" ] ~proposer:"BOB" in
  let m3 : mission =
    { state = Success
    ; team = [ "ALICE"; "DAVE" ]
    ; team_size = 2
    ; fails_required = 1
    ; num_fails = 0
    ; proposals =
        [ rejected "EVE" [ "DAVE"; "EVE" ]; approved "CARL" [ "ALICE"; "DAVE" ] ]
    }
  in
  { state = Game_ended
  ; phase = Assassination
  ; players
  ; roles = role_names
  ; missions = [ m1; m2; m3; pending_mission ~size:3; pending_mission ~size:3 ]
  ; outcome =
      Some
        { state = Evil_win
        ; message = "Evil wins!"
        ; assassinated = Some "ALICE"
        ; roles = roles_assignment
        ; votes =
            [ all_true [ "ALICE"; "BOB" ]
            ; all_true [ "BOB"; "CARL"; "DAVE" ]
            ; all_true [ "ALICE"; "DAVE" ]
            ]
        }
  ; in_game_log = false
  }
;;

(* A completed good win contrived so two proposers (ALICE, BOB) each have exactly two
   "perfect" (all-good) proposals and no bad ones — a TIE. The "Actual Merlin" badge must
   deterministically name the earliest-seated of the two (ALICE). Guards the
   psychic_powers tie-break. *)
let psychic_tie : game_data =
  let m ~proposals : mission =
    { state = Success
    ; team = [ "ALICE"; "BOB" ]
    ; team_size = 2
    ; fails_required = 1
    ; num_fails = 0
    ; proposals
    }
  in
  { state = Game_ended
  ; phase = Assassination
  ; players
  ; roles = role_names
  ; missions =
      [ m
          ~proposals:
            [ rejected "ALICE" [ "ALICE"; "CARL" ]; approved "ALICE" [ "ALICE"; "BOB" ] ]
      ; m
          ~proposals:
            [ rejected "BOB" [ "BOB"; "CARL" ]; approved "BOB" [ "ALICE"; "BOB" ] ]
      ; m ~proposals:[ approved "CARL" [ "ALICE"; "BOB" ] ]
      ; pending_mission ~size:3
      ; pending_mission ~size:3
      ]
  ; outcome =
      Some
        { state = Good_win
        ; message = "Good wins!"
        ; assassinated = None
        ; roles = roles_assignment
        ; votes =
            [ all_true [ "ALICE"; "BOB" ]
            ; all_true [ "ALICE"; "BOB" ]
            ; all_true [ "ALICE"; "BOB" ]
            ]
        }
  ; in_game_log = false
  }
;;

(* ----- 7-player fixtures (3 evil, mission 4 requires TWO fails) ----- *)

let seven_players = [ "ALICE"; "BOB"; "CARL"; "DAVE"; "EVE"; "FRAN"; "GREG" ]

let seven_roles_assignment : role_assignment list =
  [ { name = "ALICE"; role = "MERLIN"; assassin = false }
  ; { name = "BOB"; role = "PERCIVAL"; assassin = false }
  ; { name = "CARL"; role = "LOYAL FOLLOWER"; assassin = false }
  ; { name = "DAVE"; role = "MORGANA"; assassin = false }
  ; { name = "EVE"; role = "ASSASSIN"; assassin = true }
  ; { name = "FRAN"; role = "LOYAL FOLLOWER"; assassin = false }
  ; { name = "GREG"; role = "MORDRED"; assassin = false }
  ]
;;

let seven_role_names =
  [ "MERLIN"
  ; "PERCIVAL"
  ; "LOYAL FOLLOWER"
  ; "MORGANA"
  ; "ASSASSIN"
  ; "LOYAL FOLLOWER"
  ; "MORDRED"
  ]
;;

(* A completed 7-player game with the given missions; badge detectors only read
   [outcome.state], [outcome.roles], and [outcome.assassinated], so [votes] stays empty. *)
let seven_game ~(missions : mission list) ~(outcome_state : outcome_state) : game_data =
  { state = Game_ended
  ; phase = Assassination
  ; players = seven_players
  ; roles = seven_role_names
  ; missions
  ; outcome =
      Some
        { state = outcome_state
        ; message = "Game over"
        ; assassinated = None
        ; roles = seven_roles_assignment
        ; votes = []
        }
  ; in_game_log = false
  }
;;

(* 7-player mission ladder (sizes 2,3,3,4,4) where mission 4 requires TWO fails. Good wins
   3-2. On mission 4 all three evil players (DAVE, EVE, GREG) went together and produced
   exactly the two required fails — perfect coordination, not over-failing. *)
let seven_two_fail : game_data =
  let m1 =
    make_mission
      ~state:Success
      ~size:2
      ~team:[ "ALICE"; "BOB" ]
      ~proposals:
        [ approved_by [ "ALICE"; "BOB"; "CARL"; "DAVE" ] "ALICE" [ "ALICE"; "BOB" ] ]
      ()
  in
  let m2 =
    make_mission
      ~state:Fail
      ~num_fails:1
      ~size:3
      ~team:[ "BOB"; "CARL"; "DAVE" ]
      ~proposals:
        [ approved_by [ "BOB"; "CARL"; "DAVE"; "EVE" ] "BOB" [ "BOB"; "CARL"; "DAVE" ] ]
      ()
  in
  let m3 =
    make_mission
      ~state:Success
      ~size:3
      ~team:[ "ALICE"; "BOB"; "FRAN" ]
      ~proposals:
        [ approved_by [ "ALICE"; "BOB"; "CARL"; "FRAN" ] "CARL" [ "ALICE"; "BOB"; "FRAN" ]
        ]
      ()
  in
  let m4 =
    make_mission
      ~state:Fail
      ~fails_required:2
      ~num_fails:2
      ~size:4
      ~team:[ "ALICE"; "DAVE"; "EVE"; "GREG" ]
      ~proposals:
        [ approved_by
            [ "DAVE"; "EVE"; "GREG"; "ALICE" ]
            "DAVE"
            [ "ALICE"; "DAVE"; "EVE"; "GREG" ]
        ]
      ()
  in
  let m5 =
    make_mission
      ~state:Success
      ~size:4
      ~team:[ "ALICE"; "BOB"; "CARL"; "FRAN" ]
      ~proposals:
        [ approved_by
            [ "ALICE"; "BOB"; "CARL"; "FRAN" ]
            "EVE"
            [ "ALICE"; "BOB"; "CARL"; "FRAN" ]
        ]
      ()
  in
  seven_game ~missions:[ m1; m2; m3; m4; m5 ] ~outcome_state:Good_win
;;

(* An in-progress game: mission 1, first proposal pending, proposed by ALICE. *)
let mid_game : game_data =
  { state = Active
  ; (* TEAM_SELECTION was never a real token; the proposal phase is TEAM_PROPOSAL. *)
    phase = Team_proposal
  ; players
  ; roles = role_names
  ; missions =
      ({ state = M_pending
       ; team = []
       ; team_size = 2
       ; fails_required = 1
       ; num_fails = 0
       ; proposals = [ pending "ALICE" ]
       }
       : mission)
      :: List.map [ 3; 2; 3; 3 ] ~f:(fun size -> pending_mission ~size)
  ; outcome = None
  ; in_game_log = false
  }
;;
