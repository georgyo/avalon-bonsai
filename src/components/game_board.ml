open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Avalon_core
module D = State.Derived
module N = Vdom.Node

(** The in-game board: stacks the mission track, the participants panel, and the action
    pane, and owns the shared team-selection state they read/write. *)

module Style =
  [%css
  stylesheet {|
  .game_board { width: 100%; }
  .game_section { padding: 8px 0; }
|}]

let game_board (local_ graph) =
  let selected, set_selected = Bonsai.state [] graph ~equal:(List.equal String.equal) in
  (* clear the team selection whenever the phase changes (original cleared on phase watch) *)
  let phase =
    let%arr m = State.value () in
    match D.game m with
    | Some g -> Game.phase g
    | None -> Types.Unknown_phase ""
  in
  let () =
    Bonsai.Edge.on_change
      phase
      ~equal:Types.equal_phase
      ~callback:
        (let%arr set_selected in
         fun _ -> set_selected [])
      graph
  in
  let missions = Missions.game_missions graph in
  let participants = Player_list.game_participants ~selected ~set_selected graph in
  let actions = Actions.action_pane ~selected graph in
  let%arr missions and participants and actions in
  {%html.jsx|
    <div *{[ Style.game_board ]}>
      <div *{[ Style.game_section ]}>%{missions}</div>
      <div *{[ Style.game_section ]}>%{participants}</div>
      <div *{[ Style.game_section ]}>%{actions}</div>
    </div>
  |}
;;
