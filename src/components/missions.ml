open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Avalon_core
open Types
open Ui
module D = State.Derived
module N = Vdom.Node

(** The mission track: a tab strip of the five missions and the detail panel for the
    selected one. *)

module Style =
  [%css
  stylesheet
    {|
  /* mission tabs keep a light-blue fill (Vuetify bg-light-blue-lighten-4) under the indicator */
  .tab_mission { background: #b3e5fc; border-radius: 0; }
  .mission_panel { margin-top: 4px; }
  .bg_fail { background: #ffcdd2; }
  .bg_success { background: #c8e6c9; }
  .bg_pending { background: #cfd8dc; }
  /* small red "needs two fails" dot in the upper-right of a mission icon */
  .fails_dot { font-size: 0.5em; color: red; left: auto; right: 6%; top: 4%; width: auto; }
|}]

let game_missions (local_ graph) =
  let active, set_active = Bonsai.state 0 graph in
  (* follow the current mission as the game progresses (original watched
     currentMissionIdx) *)
  let midx =
    let%arr m = State.value () in
    match D.game m with
    | Some g -> g.current_mission_idx
    | None -> -1
  in
  let () =
    Bonsai.Edge.on_change
      midx
      ~equal:Int.equal
      ~callback:
        (let%arr set_active in
         fun i -> if i >= 0 && i < 5 then set_active i else Effect.return ())
      graph
  in
  let%arr m = State.value ()
  and active
  and set_active in
  match D.game m with
  | None -> N.none
  | Some g ->
    let missions = Game.missions g in
    let is_future idx =
      idx > 0
      &&
      match List.nth missions (idx - 1) with
      | Some prev -> equal_mission_state prev.state M_pending
      | None -> false
    in
    let tab_icon idx (mission : mission) =
      let base =
        match mission.state with
        | M_pending ->
          [ fa ~color:(if is_future idx then "gray" else "black") "far" "fa-circle"
          ; spanc ~attrs:[ Ui.layers_text ] [ N.text (Int.to_string mission.team_size) ]
          ]
        | Fail -> [ fa ~color:"red" "far" "fa-times-circle" ]
        | Success -> [ fa ~color:"green" "far" "fa-check-circle" ]
      in
      (* A red dot marks a mission that needs two fails (the 4th in 7+ player games). *)
      let dot =
        if mission.fails_required > 1
        then [ spanc ~attrs:[ Style.fails_dot ] [ fa ~color:"red" "fas" "fa-circle" ] ]
        else []
      in
      fa_layers (base @ dot)
    in
    let panel idx (mission : mission) =
      let bg =
        match mission.state with
        | Fail -> Style.bg_fail
        | Success -> Style.bg_success
        | M_pending -> Style.bg_pending
      in
      let header =
        let status =
          if idx = g.current_mission_idx && not (equal_phase (Game.phase g) Assassination)
          then "CURRENT"
          else (
            match mission.state with
            | Success -> "SUCCESS"
            | Fail -> "FAIL"
            | M_pending -> "PENDING")
        in
        N.div
          [ textf "Mission %d: %s" (idx + 1) status
          ; (if mission.num_fails > 0
             then
               textf
                 " (%d %s)"
                 mission.num_fails
                 (if mission.num_fails > 1 then "fails" else "fail")
             else N.none)
          ]
      in
      let detail =
        match mission.state with
        | M_pending ->
          N.div
            [ textf "Team Size: %d" mission.team_size
            ; (if mission.fails_required > 1
               then textf " (%d fails required)" mission.fails_required
               else N.none)
            ]
        | _ -> N.div [ textf "Team: %s" (Util.join_with_and mission.team) ]
      in
      let log =
        if (Game.data g).in_game_log
        then
          Summary_table.mission_summary_table
            ~players:(Game.players g)
            ~missions:[ mission ]
            ~roles:None
            ~mission_votes:None
        else N.none
      in
      card
        ~attrs:[ bg; Style.mission_panel ]
        [ card_text ~attrs:[ Ui.caption ] [ header; detail; log ] ]
    in
    let strip =
      tab_strip
        ~tab_attrs:[ Style.tab_mission ]
        ~active
        ~on_select:set_active
        (List.mapi missions ~f:(fun idx mission -> [ tab_icon idx mission ]))
    in
    let panel_node =
      match List.nth missions active with
      | Some mission -> panel active mission
      | None -> N.none
    in
    {%html.jsx|<div>%{strip}%{panel_node}</div>|}
;;
