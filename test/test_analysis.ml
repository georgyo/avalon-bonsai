open! Core
open Avalon_core

let lines l = String.concat ~sep:"\n" l
let create_exn data ~role_map = Option.value_exn (Analysis.create data ~role_map)

(* A clean good win where evil was never placed on a mission. Locks in the badge engine:
   the exact set here matches what the live e2e game produced (Lockdown / Clean sweep / "I
   trust you guys"), plus the deductions that follow from the fixture's roles. *)
let%test_unit "badges for a clean good win" =
  let t = create_exn Fixtures.good_win ~role_map:Fixtures.role_map in
  let actual =
    lines
      (List.map (Analysis.get_badges t) ~f:(fun (b : Analysis.badge) ->
         sprintf "- %s: %s" b.title b.body))
  in
  [%test_result: string]
    actual
    ~expect:
      (lines
         [ "- Lockdown: No evil players went on any missions"
         ; "- Clean sweep: Good team dominated the game"
         ; "- I trust you guys: CARL proposed a team that did not include themselves"
         ; "- What a trusting bunch: First mission got approved within 1 try"
         ; "- Universal acclaim: Everyone voted for ALICE's proposal on mission 1"
         ; "- Put me in, coach!: DAVE did not go on a single mission"
         ; "- Cover blown: Morgana approved a team with Merlin"
         ; "- Yes-man: ALICE approved every single proposal"
         ; "- Ghost: DAVE was evil but never went on a single mission"
         ])
;;

let badge_lines t =
  lines
    (List.map (Analysis.get_badges t) ~f:(fun (b : Analysis.badge) ->
       sprintf "- %s: %s" b.title b.body))
;;

let find_body t title =
  match
    List.find (Analysis.get_badges t) ~f:(fun (b : Analysis.badge) ->
      String.equal b.title title)
  with
  | Some b -> b.body
  | None -> "<absent>"
;;

(* Guards the psychic_powers tie-break: ALICE and BOB both have two perfect proposals; the
   badge must name the earliest-seated (ALICE), not whichever a hashtable happens to
   yield. *)
let%test_unit "Actual Merlin tie-break is deterministic (earliest seat)" =
  let t = create_exn Fixtures.psychic_tie ~role_map:Fixtures.role_map in
  [%test_result: string]
    (find_body t "Actual Merlin")
    ~expect:"ALICE proposed 2 perfect teams and no bad teams"
;;

(* Guards the proposer_curse tie-break: ALICE and BOB each have three rejected proposals;
   the badge must name the one rejected first (ALICE), matching JS object-insertion order. *)
let%test_unit "Cursed proposer tie-break is deterministic (first rejected)" =
  let mission0 =
    { (List.hd_exn Fixtures.good_win.missions) with
      proposals =
        [ Fixtures.rejected "ALICE" [ "ALICE"; "BOB" ]
        ; Fixtures.rejected "BOB" [ "BOB"; "CARL" ]
        ; Fixtures.rejected "ALICE" [ "ALICE"; "CARL" ]
        ; Fixtures.rejected "BOB" [ "ALICE"; "BOB" ]
        ; Fixtures.rejected "ALICE" [ "BOB"; "CARL" ]
        ; Fixtures.rejected "BOB" [ "ALICE"; "CARL" ]
        ; Fixtures.approved "ALICE" [ "ALICE"; "BOB" ]
        ]
    }
  in
  let data =
    { Fixtures.good_win with
      missions = mission0 :: List.tl_exn Fixtures.good_win.missions
    }
  in
  let t = create_exn data ~role_map:Fixtures.role_map in
  [%test_result: string]
    (find_body t "Cursed proposer")
    ~expect:"ALICE had 3 proposals rejected"
;;

let analyze data = create_exn data ~role_map:Fixtures.role_map

(* A 5-player good win with the given missions (outcome / roles from [good_win]). *)
let five_with missions = analyze { Fixtures.good_win with missions }

(* [pos_neg pos neg title] renders the badge body for [title] in both games. *)
let pos_neg pos neg title = lines [ find_body pos title; find_body neg title ]

(* ----- universal_acclaim ----- *)

(* Positive: [Fixtures.approved] records votes from all 5 players. Negative: the same game
   with only 4-of-5 approval votes on every proposal must not award it. *)
let%test_unit "Universal acclaim: unanimous vs 4-of-5 approvals" =
  let team = [ "ALICE"; "BOB" ] in
  let mission ~proposals =
    Fixtures.make_mission ~state:Success ~size:2 ~team ~proposals ()
  in
  let pos = five_with [ mission ~proposals:[ Fixtures.approved "ALICE" team ] ] in
  let neg =
    five_with
      [ mission
          ~proposals:
            [ Fixtures.approved_by [ "ALICE"; "BOB"; "CARL"; "DAVE" ] "ALICE" team ]
      ]
  in
  [%test_result: string]
    (pos_neg pos neg "Universal acclaim")
    ~expect:(lines [ "Everyone voted for ALICE's proposal on mission 1"; "<absent>" ])
;;

(* ----- almost_lost ----- *)

(* Good win after two failed missions; on mission 3 the team got approved on the 4th
   proposal, so exactly one player was "behind" the last proposer. Positive: last proposer
   EVE (seat 4) — the seat index wraps around to ALICE (good), so good really was one
   rejection away from an evil hammer. Negative: last proposer CARL (seat 2) — the only
   player behind is DAVE (evil), so the badge must not fire. *)
let%test_unit "By the skin of our teeth: hammer counting wraps around the seats" =
  let fail_m team proposer =
    Fixtures.make_mission
      ~state:Fail
      ~num_fails:1
      ~size:(List.length team)
      ~team
      ~proposals:[ Fixtures.approved proposer team ]
      ()
  in
  let m3 ~proposals =
    Fixtures.make_mission ~state:Success ~size:2 ~team:[ "ALICE"; "BOB" ] ~proposals ()
  in
  let game m3_proposals =
    five_with
      [ fail_m [ "ALICE"; "DAVE" ] "BOB"
      ; fail_m [ "BOB"; "CARL"; "EVE" ] "CARL"
      ; m3 ~proposals:m3_proposals
      ; Fixtures.pending_mission ~size:3
      ; Fixtures.pending_mission ~size:3
      ]
  in
  let pos =
    game
      [ Fixtures.rejected "BOB" [ "BOB"; "DAVE" ]
      ; Fixtures.rejected "CARL" [ "CARL"; "DAVE" ]
      ; Fixtures.rejected "DAVE" [ "DAVE"; "EVE" ]
      ; Fixtures.approved "EVE" [ "ALICE"; "BOB" ]
      ]
  in
  let neg =
    game
      [ Fixtures.rejected "BOB" [ "BOB"; "DAVE" ]
      ; Fixtures.rejected "ALICE" [ "ALICE"; "CARL" ]
      ; Fixtures.rejected "EVE" [ "DAVE"; "EVE" ]
      ; Fixtures.approved "CARL" [ "ALICE"; "BOB" ]
      ]
  in
  [%test_result: string]
    (pos_neg pos neg "By the skin of our teeth")
    ~expect:
      (lines
         [ "Good came close to losing on mission 3 when evil team had hammer"
         ; "<absent>"
         ])
;;

(* ----- same_team ----- *)

(* Positive: the same pair proposed three times in a row (order within the team must not
   matter). Negative: a different team in between resets the streak. *)
let%test_unit "We made up our minds: streak of 3 identical teams, reset by a different \
               team"
  =
  let mission proposals =
    Fixtures.make_mission ~state:Success ~size:2 ~team:[ "ALICE"; "BOB" ] ~proposals ()
  in
  let pos =
    five_with
      [ mission
          [ Fixtures.rejected "ALICE" [ "ALICE"; "BOB" ]
          ; Fixtures.rejected "BOB" [ "BOB"; "ALICE" ]
          ; Fixtures.approved "CARL" [ "ALICE"; "BOB" ]
          ]
      ]
  in
  let neg =
    five_with
      [ mission
          [ Fixtures.rejected "ALICE" [ "ALICE"; "BOB" ]
          ; Fixtures.rejected "BOB" [ "ALICE"; "BOB" ]
          ; Fixtures.rejected "CARL" [ "ALICE"; "CARL" ]
          ; Fixtures.approved "DAVE" [ "ALICE"; "BOB" ]
          ]
      ]
  in
  [%test_result: string]
    (pos_neg pos neg "We made up our minds")
    ~expect:
      (lines [ "The team of ALICE and BOB got proposed 3 times in a row"; "<absent>" ])
;;

(* ----- flip_flopper ----- *)

(* Positive: the identical team gets rejected then approved within a mission; the first
   voter who newly approved (ALICE) is the flip-flopper. Negative: the approved team
   differs from the rejected one. *)
let%test_unit "Flip-flopper: rejected-then-approved identical team" =
  let mission proposals =
    Fixtures.make_mission ~state:Success ~size:2 ~team:[ "ALICE"; "BOB" ] ~proposals ()
  in
  let pos =
    five_with
      [ mission
          [ Fixtures.rejected "DAVE" [ "ALICE"; "BOB" ]
          ; Fixtures.approved "EVE" [ "ALICE"; "BOB" ]
          ]
      ]
  in
  let neg =
    five_with
      [ mission
          [ Fixtures.rejected "DAVE" [ "DAVE"; "EVE" ]
          ; Fixtures.approved "EVE" [ "ALICE"; "BOB" ]
          ]
      ]
  in
  [%test_result: string]
    (pos_neg pos neg "Flip-flopper")
    ~expect:
      (lines [ "ALICE rejected then approved the same team on mission 1"; "<absent>" ])
;;

(* ----- rejection_streak ----- *)

(* The streak accumulates ACROSS missions and only an approval resets it. Positive: 2
   rejections at the end of mission 1 plus 2 at the start of mission 2 = 4. Negative: 1 +
   2 = 3 stays under the threshold. *)
let%test_unit "Nobody likes anyone: rejection streak spans mission boundaries" =
  let game m1_proposals =
    five_with
      [ Fixtures.make_mission
          ~state:Fail
          ~num_fails:1
          ~size:2
          ~team:[ "BOB"; "DAVE" ]
          ~proposals:m1_proposals
          ()
      ; Fixtures.make_mission
          ~state:Success
          ~size:3
          ~team:[ "ALICE"; "BOB"; "CARL" ]
          ~proposals:
            [ Fixtures.rejected "DAVE" [ "DAVE"; "EVE"; "ALICE" ]
            ; Fixtures.rejected "EVE" [ "EVE"; "DAVE"; "BOB" ]
            ; Fixtures.approved "ALICE" [ "ALICE"; "BOB"; "CARL" ]
            ]
          ()
      ]
  in
  let pos =
    game
      [ Fixtures.approved "ALICE" [ "BOB"; "DAVE" ]
      ; Fixtures.rejected "BOB" [ "ALICE"; "BOB" ]
      ; Fixtures.rejected "CARL" [ "ALICE"; "CARL" ]
      ]
  in
  let neg =
    game
      [ Fixtures.approved "ALICE" [ "BOB"; "DAVE" ]
      ; Fixtures.rejected "CARL" [ "ALICE"; "CARL" ]
      ]
  in
  [%test_result: string]
    (pos_neg pos neg "Nobody likes anyone")
    ~expect:(lines [ "4 proposals were rejected in a row"; "<absent>" ])
;;

(* ----- perfect_coordination / failure_to_coordinate (need fails_required = 2) ----- *)

(* Same shape as [seven_two_fail] except mission 4 got THREE fail votes — one more than
   required — and mission 5 still completed. *)
let seven_overkill_fails : Types.game_data =
  let s ~size ~team ~proposer =
    Fixtures.make_mission
      ~state:Success
      ~size
      ~team
      ~proposals:[ Fixtures.approved_by team proposer team ]
      ()
  in
  Fixtures.seven_game
    ~outcome_state:Good_win
    ~missions:
      [ s ~size:2 ~team:[ "ALICE"; "BOB" ] ~proposer:"ALICE"
      ; s ~size:3 ~team:[ "ALICE"; "BOB"; "CARL" ] ~proposer:"BOB"
      ; s ~size:3 ~team:[ "ALICE"; "BOB"; "FRAN" ] ~proposer:"CARL"
      ; Fixtures.make_mission
          ~state:Fail
          ~fails_required:2
          ~num_fails:3
          ~size:4
          ~team:[ "DAVE"; "EVE"; "GREG"; "ALICE" ]
          ~proposals:
            [ Fixtures.approved_by
                [ "DAVE"; "EVE"; "GREG"; "ALICE" ]
                "DAVE"
                [ "DAVE"; "EVE"; "GREG"; "ALICE" ]
            ]
          ()
      ; s ~size:4 ~team:[ "ALICE"; "BOB"; "CARL"; "FRAN" ] ~proposer:"EVE"
      ]
;;

(* On the two-fail mission 4: exactly 2 fails from 3 evil = perfect coordination; 3 fails
   from 3 evil = over-failing, which is failure to coordinate instead (the next mission
   completed, so the game demonstrably went on). Each game is the other's negative. *)
let%test_unit "Same wavelength vs Failure to coordinate on the two-fail mission" =
  let exact = analyze Fixtures.seven_two_fail in
  let overkill = analyze seven_overkill_fails in
  [%test_result: string]
    (lines
       [ pos_neg exact overkill "Same wavelength"
       ; pos_neg overkill exact "Failure to coordinate"
       ])
    ~expect:
      (lines
         [ "DAVE, EVE and GREG had perfect coordination on mission 4"
         ; "<absent>"
         ; "DAVE, EVE and GREG had 3 failure votes on mission 4"
         ; "<absent>"
         ])
;;

(* ----- playing_the_long_con (gated on fails_required < 2) ----- *)

(* GREG (evil) rides along on a successful mission 4 without failing. If that mission only
   needs one fail, he was playing the long con; if it needs two, his single fail vote
   could never have flipped it, so no badge. *)
let%test_unit "Playing the long con is not awarded on a two-fail mission" =
  let game ~fails_required =
    let s ~size ~team ~proposer =
      Fixtures.make_mission
        ~state:Success
        ~size
        ~team
        ~proposals:[ Fixtures.approved_by team proposer team ]
        ()
    in
    Fixtures.seven_game
      ~outcome_state:Good_win
      ~missions:
        [ s ~size:2 ~team:[ "ALICE"; "BOB" ] ~proposer:"ALICE"
        ; s ~size:3 ~team:[ "ALICE"; "BOB"; "CARL" ] ~proposer:"BOB"
        ; s ~size:3 ~team:[ "ALICE"; "BOB"; "FRAN" ] ~proposer:"CARL"
        ; Fixtures.make_mission
            ~state:Success
            ~fails_required
            ~size:4
            ~team:[ "ALICE"; "BOB"; "CARL"; "GREG" ]
            ~proposals:
              [ Fixtures.approved_by
                  [ "ALICE"; "BOB"; "CARL"; "GREG" ]
                  "DAVE"
                  [ "ALICE"; "BOB"; "CARL"; "GREG" ]
              ]
            ()
        ; s ~size:4 ~team:[ "ALICE"; "BOB"; "CARL"; "FRAN" ] ~proposer:"EVE"
        ]
  in
  let pos = analyze (game ~fails_required:1) in
  let neg = analyze (game ~fails_required:2) in
  [%test_result: string]
    (pos_neg pos neg "Playing the long con")
    ~expect:(lines [ "GREG stayed undercover instead of failing mission 4"; "<absent>" ])
;;

(* ----- psychic_powers with a two-fail mission ----- *)

(* On the two-fail mission 4, BOB's approved team carries one evil player (GREG) — not
   enough to fail it, so it still counts as a perfect proposal and BOB reaches the
   two-good-proposals threshold. ALICE proposed two all-good teams earlier, but her
   rejected mission-4 team carried two evil players (>= fails_required), which counts as a
   bad proposal and disqualifies her; if that boundary were wrong (evil_count <=
   fails_required counting as good) she would win with three perfect teams instead. *)
let%test_unit "Actual Merlin: one evil on a two-fail mission is still a perfect team" =
  let t =
    analyze
      (Fixtures.seven_game
         ~outcome_state:Good_win
         ~missions:
           [ Fixtures.make_mission
               ~state:Success
               ~size:2
               ~team:[ "ALICE"; "BOB" ]
               ~proposals:
                 [ Fixtures.rejected "ALICE" [ "ALICE"; "CARL" ]
                 ; Fixtures.approved_by [ "ALICE"; "BOB" ] "BOB" [ "ALICE"; "BOB" ]
                 ]
               ()
           ; Fixtures.make_mission
               ~state:Success
               ~size:3
               ~team:[ "ALICE"; "BOB"; "CARL" ]
               ~proposals:
                 [ Fixtures.rejected "ALICE" [ "ALICE"; "BOB"; "FRAN" ]
                 ; Fixtures.approved_by
                     [ "ALICE"; "BOB"; "CARL" ]
                     "CARL"
                     [ "ALICE"; "BOB"; "CARL" ]
                 ]
               ()
           ; Fixtures.make_mission
               ~state:Success
               ~size:3
               ~team:[ "ALICE"; "BOB"; "FRAN" ]
               ~proposals:
                 [ Fixtures.approved_by
                     [ "ALICE"; "BOB"; "FRAN" ]
                     "DAVE"
                     [ "ALICE"; "BOB"; "FRAN" ]
                 ]
               ()
           ; Fixtures.make_mission
               ~state:Success
               ~fails_required:2
               ~size:4
               ~team:[ "ALICE"; "BOB"; "CARL"; "GREG" ]
               ~proposals:
                 [ Fixtures.rejected "ALICE" [ "ALICE"; "DAVE"; "EVE"; "BOB" ]
                 ; Fixtures.approved_by
                     [ "ALICE"; "BOB"; "CARL"; "GREG" ]
                     "BOB"
                     [ "ALICE"; "BOB"; "CARL"; "GREG" ]
                 ]
               ()
           ; Fixtures.make_mission
               ~state:Success
               ~size:4
               ~team:[ "ALICE"; "BOB"; "CARL"; "FRAN" ]
               ~proposals:
                 [ Fixtures.approved_by
                     [ "ALICE"; "BOB"; "CARL"; "FRAN" ]
                     "EVE"
                     [ "ALICE"; "BOB"; "CARL"; "FRAN" ]
                 ]
               ()
           ])
  in
  [%test_result: string]
    (find_body t "Actual Merlin")
    ~expect:"BOB proposed 2 perfect teams and no bad teams"
;;

(* ----- merlin_sends_evil_team / merlin_proposes_evil_team ----- *)

(* Merlin (ALICE) proposes, approves, and sends a team carrying visible evil (DAVE): both
   Merlin badges fire. *)
let%test_unit "Traitor Merlin and Advanced Merlin: Merlin sends a team with Morgana" =
  let team = [ "ALICE"; "DAVE" ] in
  let t =
    five_with
      [ Fixtures.make_mission
          ~state:Fail
          ~num_fails:1
          ~size:2
          ~team
          ~proposals:[ Fixtures.approved "ALICE" team ]
          ()
      ]
  in
  [%test_result: string]
    (lines [ find_body t "Traitor Merlin"; find_body t "Advanced Merlin" ])
    ~expect:
      (lines
         [ "Merlin sent an evil team with DAVE"
         ; "Merlin proposed and approved a team with DAVE"
         ])
;;

(* Merlin's evil proposal got REJECTED (but he voted for it himself): only the proposal
   badge fires, not the sent-a-team badge. *)
let%test_unit "Advanced Merlin without Traitor Merlin: the evil proposal was rejected" =
  let t =
    five_with
      [ Fixtures.make_mission
          ~state:Success
          ~size:2
          ~team:[ "ALICE"; "BOB" ]
          ~proposals:
            [ Fixtures.rejected_by [ "ALICE"; "DAVE" ] "ALICE" [ "ALICE"; "DAVE" ]
            ; Fixtures.approved "BOB" [ "ALICE"; "BOB" ]
            ]
          ()
      ]
  in
  [%test_result: string]
    (lines [ find_body t "Traitor Merlin"; find_body t "Advanced Merlin" ])
    ~expect:(lines [ "<absent>"; "Merlin proposed and approved a team with DAVE" ])
;;

(* Merlin cannot see Mordred, so a Merlin team whose ONLY evil member is Mordred (GREG)
   must award neither badge — even though Mordred went on to fail the mission. *)
let%test_unit "Merlin badges ignore Mordred, whom Merlin cannot see" =
  let team = [ "ALICE"; "GREG" ] in
  let t =
    analyze
      (Fixtures.seven_game
         ~outcome_state:Good_win
         ~missions:
           [ Fixtures.make_mission
               ~state:Fail
               ~num_fails:1
               ~size:2
               ~team
               ~proposals:[ Fixtures.approved_by Fixtures.seven_players "ALICE" team ]
               ()
           ; Fixtures.pending_mission ~size:3
           ; Fixtures.pending_mission ~size:3
           ; Fixtures.pending_mission ~size:4
           ; Fixtures.pending_mission ~size:4
           ])
  in
  [%test_result: string]
    (lines [ find_body t "Traitor Merlin"; find_body t "Advanced Merlin" ])
    ~expect:(lines [ "<absent>"; "<absent>" ])
;;

(* ----- hammer_time ----- *)

(* Positive: mission 1 approved only on the 5th (hammer) proposal. Negative: approved on
   the 4th. *)
let%test_unit "Hammer time: approval on the 5th proposal only" =
  let team = [ "ALICE"; "BOB" ] in
  let rejections =
    [ Fixtures.rejected "ALICE" [ "ALICE"; "CARL" ]
    ; Fixtures.rejected "BOB" [ "BOB"; "CARL" ]
    ; Fixtures.rejected "CARL" [ "CARL"; "DAVE" ]
    ; Fixtures.rejected "DAVE" [ "DAVE"; "EVE" ]
    ]
  in
  let game proposals =
    five_with [ Fixtures.make_mission ~state:Success ~size:2 ~team ~proposals () ]
  in
  let pos = game (rejections @ [ Fixtures.approved "EVE" team ]) in
  let neg = game (List.take rejections 3 @ [ Fixtures.approved "DAVE" team ]) in
  [%test_result: string]
    (pos_neg pos neg "Hammer time")
    ~expect:(lines [ "Mission 1 went to the 5th proposal (hammer)"; "<absent>" ])
;;

(* ----- lone_wolf ----- *)

(* Positive: DAVE is the only evil player on a failed mission. Negative: two evil players
   were aboard, so the single fail cannot be pinned on one of them. *)
let%test_unit "Lone wolf: single evil player fails a mission alone" =
  let fail_m team =
    five_with
      [ Fixtures.make_mission
          ~state:Fail
          ~num_fails:1
          ~size:2
          ~team
          ~proposals:[ Fixtures.approved "ALICE" team ]
          ()
      ]
  in
  let pos = fail_m [ "ALICE"; "DAVE" ] in
  let neg = fail_m [ "DAVE"; "EVE" ] in
  [%test_result: string]
    (pos_neg pos neg "Lone wolf")
    ~expect:(lines [ "DAVE single-handedly failed mission 1"; "<absent>" ])
;;

(* ----- one_man_army ----- *)

(* Positive: DAVE is the sole evil player on BOTH failed missions. Negative: the second
   failed mission also carried EVE, so no single player failed them all alone. *)
let%test_unit "One-man army: same lone evil player on every failed mission" =
  let fail_m team proposer =
    Fixtures.make_mission
      ~state:Fail
      ~num_fails:1
      ~size:(List.length team)
      ~team
      ~proposals:[ Fixtures.approved proposer team ]
      ()
  in
  let game second_team =
    five_with
      [ fail_m [ "BOB"; "DAVE" ] "BOB"
      ; fail_m second_team "CARL"
      ; Fixtures.success ~size:2 ~team:[ "ALICE"; "BOB" ] ~proposer:"DAVE"
      ; Fixtures.pending_mission ~size:3
      ; Fixtures.pending_mission ~size:3
      ]
  in
  let pos = game [ "ALICE"; "CARL"; "DAVE" ] in
  let neg = game [ "ALICE"; "DAVE"; "EVE" ] in
  [%test_result: string]
    (pos_neg pos neg "One-man army")
    ~expect:
      (lines [ "DAVE was the only evil player on every failed mission"; "<absent>" ])
;;

(* Locks in the badge set for an evil win by assassination — exercises the assassination,
   evil-side, and rejection detectors the good-win fixture never reaches. *)
let%test_unit "badges for an evil win by assassination" =
  let t = create_exn Fixtures.evil_win ~role_map:Fixtures.role_map in
  [%test_result: string]
    (badge_lines t)
    ~expect:
      (lines
         [ "- Look, ma, no hands: Evil team won despite not failing any missions"
         ; "- I trust you guys: CARL proposed a team that did not include themselves"
         ; "- What a trusting bunch: First mission got approved within 2 tries"
         ; "- Playing the long con: DAVE stayed undercover instead of failing mission 2"
         ; "- Universal acclaim: Everyone voted for ALICE's proposal on mission 1"
         ; "- Biding my time: DAVE was evil, but only went on successful missions"
         ; "- Put me in, coach!: EVE did not go on a single mission"
         ; "- Cover blown: Morgana approved a team with Merlin"
         ; "- Good luck, Percival: Merlin approved a team with Morgana"
         ; "- Got you fooled: Percival both proposed and approved teams with Morgana"
         ; "- Hard pass: DAVE's proposal on mission 1 was rejected by everyone"
         ; "- Ghost: EVE was evil but never went on a single mission"
         ; "- Dodged a bullet: Mission 2 succeeded despite DAVE being on the team"
         ; "- Bullseye: The assassin correctly identified and killed Merlin"
         ])
;;
