open! Core
open Avalon_core

let lines l = String.concat ~sep:"\n" l

let%test_unit "init game derives no current mission" =
  let g =
    Game.create
      { Fixtures.good_win with state = Init; outcome = None }
      ~role_map:Fixtures.role_map
  in
  let actual =
    sprintf
      "num_players=%d mission_idx=%d proposal_idx=%d proposer=%s"
      g.num_players
      g.current_mission_idx
      g.current_proposal_idx
      (Option.value g.current_proposer ~default:"-")
  in
  [%test_result: string]
    actual
    ~expect:"num_players=0 mission_idx=-1 proposal_idx=-1 proposer=-"
;;

let%test_unit "mid game derives current proposer, hammer, and team balance" =
  let g = Game.create Fixtures.mid_game ~role_map:Fixtures.role_map in
  let actual =
    lines
      [ sprintf
          "num_players=%d mission_idx=%d proposal_idx=%d"
          g.num_players
          g.current_mission_idx
          g.current_proposal_idx
      ; sprintf
          "proposer=%s hammer=%s"
          (Option.value g.current_proposer ~default:"-")
          (Option.value g.hammer ~default:"-")
      ; sprintf "num_good=%d num_evil=%d" (Game.num_good g) (Game.num_evil g)
      ]
  in
  [%test_result: string]
    actual
    ~expect:
      (lines
         [ "num_players=5 mission_idx=0 proposal_idx=0"
         ; "proposer=ALICE hammer=EVE"
         ; "num_good=3 num_evil=2"
         ])
;;

let last_proposer g =
  match Game.last_proposal g with
  | Some p -> p.proposer
  | None -> "-"
;;

let%test_unit "last_proposal: a re-proposal within a mission returns the prior proposal" =
  let m0 : Types.mission =
    { state = M_pending
    ; team = []
    ; team_size = 2
    ; fails_required = 1
    ; num_fails = 0
    ; proposals = [ Fixtures.rejected "ALICE" [ "ALICE"; "BOB" ]; Fixtures.pending "BOB" ]
    }
  in
  let g =
    Game.create
      { Fixtures.mid_game with missions = m0 :: List.tl_exn Fixtures.mid_game.missions }
      ~role_map:Fixtures.role_map
  in
  [%test_result: string]
    (sprintf
       "idx=%d proposer=%s last=%s"
       g.current_proposal_idx
       (Option.value g.current_proposer ~default:"-")
       (last_proposer g))
    ~expect:"idx=1 proposer=BOB last=ALICE"
;;

let%test_unit "last_proposal: first proposal of mission 2 returns mission 1's approved \
               team"
  =
  let m0 = Fixtures.success ~size:2 ~team:[ "ALICE"; "BOB" ] ~proposer:"ALICE" in
  let m1 : Types.mission =
    { state = M_pending
    ; team = []
    ; team_size = 3
    ; fails_required = 1
    ; num_fails = 0
    ; proposals = [ Fixtures.pending "BOB" ]
    }
  in
  let g =
    Game.create
      { Fixtures.mid_game with
        missions = m0 :: m1 :: List.drop Fixtures.mid_game.missions 2
      }
      ~role_map:Fixtures.role_map
  in
  [%test_result: string]
    (sprintf "mission_idx=%d last=%s" g.current_mission_idx (last_proposer g))
    ~expect:"mission_idx=1 last=ALICE"
;;

let%test_unit "hammer index wraps around the player list" =
  (* EVE (seat 4) proposes the first proposal of mission 0: hammer = (4 + (4-0)) mod 5 = 3
     = DAVE *)
  let m0 : Types.mission =
    { state = M_pending
    ; team = []
    ; team_size = 2
    ; fails_required = 1
    ; num_fails = 0
    ; proposals = [ Fixtures.pending "EVE" ]
    }
  in
  let g =
    Game.create
      { Fixtures.mid_game with missions = m0 :: List.tl_exn Fixtures.mid_game.missions }
      ~role_map:Fixtures.role_map
  in
  [%test_result: string]
    (sprintf
       "proposer=%s hammer=%s"
       (Option.value g.current_proposer ~default:"-")
       (Option.value g.hammer ~default:"-"))
    ~expect:"proposer=EVE hammer=DAVE"
;;

(* MISSION_VOTE situation: the current mission has NO Pending proposal (its last proposal
   was approved and the team is out voting). The current proposal must fall back to the
   last one, and the hammer is still derived from it. *)
let%test_unit "no pending proposal (MISSION_VOTE) falls back to the last proposal" =
  let m0 : Types.mission =
    { state = M_pending
    ; team = [ "ALICE"; "BOB" ]
    ; team_size = 2
    ; fails_required = 1
    ; num_fails = 0
    ; proposals =
        [ Fixtures.rejected "ALICE" [ "ALICE"; "CARL" ]
        ; Fixtures.approved "BOB" [ "ALICE"; "BOB" ]
        ]
    }
  in
  let g =
    Game.create
      { Fixtures.mid_game with
        phase = Mission_vote
      ; missions = m0 :: List.tl_exn Fixtures.mid_game.missions
      }
      ~role_map:Fixtures.role_map
  in
  [%test_result: string]
    (sprintf
       "idx=%d proposer=%s hammer=%s"
       g.current_proposal_idx
       (Option.value g.current_proposer ~default:"-")
       (Option.value g.hammer ~default:"-"))
    ~expect:"idx=1 proposer=BOB hammer=EVE"
;;

let%test_unit "degenerate: empty player list yields no hammer and no crash" =
  let g =
    Game.create { Fixtures.mid_game with players = [] } ~role_map:Fixtures.role_map
  in
  [%test_result: string]
    (sprintf
       "num_players=%d proposer=%s hammer=%s"
       g.num_players
       (Option.value g.current_proposer ~default:"-")
       (Option.value g.hammer ~default:"-"))
    ~expect:"num_players=0 proposer=ALICE hammer=-"
;;

let%test_unit "degenerate: proposer not in the player list yields no hammer and no crash" =
  let m0 : Types.mission =
    { state = M_pending
    ; team = []
    ; team_size = 2
    ; fails_required = 1
    ; num_fails = 0
    ; proposals = [ Fixtures.pending "ZED" ]
    }
  in
  let g =
    Game.create
      { Fixtures.mid_game with missions = m0 :: List.tl_exn Fixtures.mid_game.missions }
      ~role_map:Fixtures.role_map
  in
  [%test_result: string]
    (sprintf
       "proposer=%s hammer=%s"
       (Option.value g.current_proposer ~default:"-")
       (Option.value g.hammer ~default:"-"))
    ~expect:"proposer=ZED hammer=-"
;;

let%test_unit "all missions resolved derives no current mission/proposer/hammer" =
  let s ~proposer team = Fixtures.success ~size:(List.length team) ~team ~proposer in
  let f proposer team : Types.mission =
    { state = Fail
    ; team
    ; team_size = List.length team
    ; fails_required = 1
    ; num_fails = 1
    ; proposals = [ Fixtures.approved proposer team ]
    }
  in
  let g =
    Game.create
      { Fixtures.good_win with
        state = Game_ended
      ; missions =
          [ s ~proposer:"ALICE" [ "ALICE"; "BOB" ]
          ; f "BOB" [ "ALICE"; "DAVE"; "EVE" ]
          ; s ~proposer:"CARL" [ "ALICE"; "BOB" ]
          ; f "DAVE" [ "DAVE"; "EVE"; "CARL" ]
          ; s ~proposer:"EVE" [ "ALICE"; "BOB" ]
          ]
      }
      ~role_map:Fixtures.role_map
  in
  [%test_result: string]
    (sprintf
       "num_players=%d mission_idx=%d proposer=%s hammer=%s"
       g.num_players
       g.current_mission_idx
       (Option.value g.current_proposer ~default:"-")
       (Option.value g.hammer ~default:"-"))
    ~expect:"num_players=5 mission_idx=-1 proposer=- hammer=-"
;;
