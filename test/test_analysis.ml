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
