open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Ui
module D = State.Derived
module N = Vdom.Node

(** The application root: picks which screen to show (login / lobby-select / lobby / game)
    from {!State}, mounts the toolbar and event modals, and starts the Bonsai app.

    The screens themselves live in their own component modules — {!Login}, {!Lobby},
    {!Game_board}, {!Toolbar}, {!Modals} — built from the shared helpers and style
    vocabulary in {!Ui}. *)

let app (local_ graph) =
  let login = Login.user_login graph in
  let lobby_sel = Lobby.lobby_select graph in
  let lobby = Lobby.game_lobby graph in
  let board = Game_board.game_board graph in
  let toolbar = Toolbar.game_toolbar graph in
  (* registers the event modals (start/mission-result/end-game) into the top layer *)
  Modals.modals graph;
  let%arr m = State.value ()
  and login
  and lobby_sel
  and lobby
  and board
  and toolbar in
  let content =
    match m.connection_error with
    | Some msg ->
      div
        ~attrs:[ Ui.container; Ui.center; Ui.fill ]
        [ card
            ~attrs:[ Ui.welcome ]
            [ card_title [ N.text "Connection problem" ]
            ; card_text [ N.text msg ]
            ; div
                ~attrs:[ Ui.actions ]
                [ btn ~on_click:(eff (fun () -> Ffi.reload_page ())) [ N.text "Reload" ] ]
            ]
        ]
    | None ->
      if not (D.initialized m)
      then
        div
          ~attrs:[ Ui.container; Ui.center; Ui.fill ]
          [ {%html|<div *{[ Ui.spinner_lg ]}></div>|} ]
      else if not (D.is_logged_in m)
      then div ~attrs:[ Ui.container; Ui.center ] [ login ]
      else (
        let main =
          if not (D.is_in_lobby m)
          then lobby_sel
          else if not (D.is_game_in_progress m)
          then lobby
          else board
        in
        {%html|<div>%{toolbar}<div *{[ Ui.container ]}>%{main}</div></div>|})
  in
  {%html|<div *{[ Ui.app ]}>%{content}</div>|}
;;

let run_app () =
  State.init ();
  Bonsai_web.Start.start ~bind_to_element_with_id:"app" app
;;
