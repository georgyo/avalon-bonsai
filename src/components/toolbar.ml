open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Avalon_core
open Types
open Ui
module D = State.Derived
module N = Vdom.Node
module A = Vdom.Attr

(** The top app bar: the lobby name, the view-role button (which opens a bottom sheet with
    the player's secret role or their stats), and the quit/logout button. *)

module Style =
  [%css
  stylesheet
    {|
  .toolbar { display: flex; align-items: center; gap: 8px; padding: 8px 16px; background: #1e88e5; color: #e0f7fa; }
  .toolbar_email { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 220px; }
  .quit_text { display: inline; }

  /* bottom sheet (view role); [.bottom-sheet] kept global (index.html) so the e2e suite can read the role text */
  .bottom_sheet_overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.4); z-index: 1000; display: flex; align-items: flex-end; }
  .sheet { border-radius: 0; box-shadow: none; margin: 0; }

  @media (max-width: 599px) {
    .toolbar_email { max-width: 150px; font-size: 0.85rem; }
    .quit_text { display: none; }
  }
|}]

(* ---- ViewRoleButton (private) ---- *)
let view_role_button (local_ graph) =
  let%arr m = State.value () in
  let sheet = m.show_role_sheet in
  let activator =
    btn
      ~attrs:[ Ui.outlined ]
      ~on_click:(eff (fun () -> State.set_show_role_sheet true))
      [ mdi "account"; N.span [ N.text (D.user_name m) ] ]
  in
  let sheet_node =
    if not sheet
    then N.none
    else (
      let body =
        if not (D.is_game_in_progress m)
        then
          card
            ~attrs:[ Style.sheet ]
            [ card_title
                [ {%html.jsx|<div *{[ Ui.fw; Ui.center ]}>When the game starts, you will see your role here.</div>|}
                ]
            ; card_text
                [ div
                    ~attrs:[ Ui.col; Ui.center ]
                    [ N.p [ N.text "Your Stats" ]
                    ; Stats.stats_display
                        (Option.bind m.user ~f:(fun u -> u.stats))
                        m.global_stats
                    ]
                ]
            ]
        else (
          match D.role m with
          | None -> N.none
          | Some rd ->
            card
              ~attrs:[ Style.sheet ]
              [ card_title
                  ~attrs:[ Ui.title_bar ]
                  [ team_icon rd.role.team
                  ; spanc ~attrs:[ Ui.text_h5 ] [ N.text rd.role.name ]
                  ]
              ; card_text
                  [ N.p [ textf "Your role is %s." rd.role.name ]
                  ; N.p [ textf "You are on the %s team." (team_to_string rd.role.team) ]
                  ; N.p [ N.text rd.role.description ]
                  ; (if rd.assassin
                     then
                       N.p
                         [ N.text
                             "You are also the ASSASSIN! It will be up to you to \
                              identify MERLIN if the good team succeeds 3 missions."
                         ]
                     else N.none)
                  ; (if List.is_empty rd.sees
                     then N.p [ N.text "You do not see anyone." ]
                     else N.p [ textf "You see %s." (Util.join_with_and rd.sees) ])
                  ]
              ])
      in
      {%html.jsx|
        <div *{[ Style.bottom_sheet_overlay ]} on_click=%{fun _ -> eff (fun () -> State.set_show_role_sheet false)}>
          <div class="bottom-sheet" on_click=%{fun _ -> Vdom.Effect.Stop_propagation}>%{body}</div>
        </div>
      |})
  in
  {%html.jsx|<div>%{activator}%{sheet_node}</div>|}
;;

(* ---- QuitButton (private) ---- *)
(* Spike: this dialog uses a toplayer [Modal] instead of the hand-rolled [Ui.overlay], so
   it gets focus-trapping, Esc-to-close, an inert background, and body-scroll lock for
   free. The modal is portaled into the top layer (it returns only [Controls], not a
   node), and its open state lives in toplayer rather than a local [Bonsai.state]. *)
let quit_button (local_ graph) =
  let controls =
    Bonsai_web_toplayer.Modal.create
      ~attrs:(Bonsai.return [ Ui.modal_box ])
      ~close_on_esc:(Bonsai.return true)
      ~lock_body_scroll:(Bonsai.return true)
      ~content:(fun ~close graph ->
        let%arr m = State.value ()
        and close in
        let in_game = D.is_game_in_progress m in
        let action_desc = if in_game then "Cancel Game" else "Leave Lobby" in
        let confirm =
          Effect.Many
            [ eff (fun () ->
                if in_game then State.cancel_game () else State.leave_lobby ())
            ; close
            ]
        in
        div
          ~attrs:[ Ui.overlay_card ]
          [ card_title ~attrs:[ Ui.title_bar ] [ N.h3 [ textf "%s?" action_desc ] ]
          ; card_text
              [ N.text
                  ((if in_game then "The current game will be canceled! " else "")
                   ^ "Are you sure you want to proceed?")
              ]
          ; div
              ~attrs:[ Ui.row; Ui.actions ]
              [ btn ~on_click:confirm [ N.text action_desc ]
              ; btn ~on_click:close [ N.text "Nevermind" ]
              ]
          ])
      graph
  in
  let%arr open_ = controls.open_ in
  let activator =
    btn
      ~on_click:open_
      [ mdi "exit-to-app"; spanc ~attrs:[ Style.quit_text ] [ N.text "Quit" ] ]
  in
  {%html.jsx|<div>%{activator}</div>|}
;;

(* ---- GameToolbar ---- *)
let game_toolbar (local_ graph) =
  let view_role = view_role_button graph in
  let quit = quit_button graph in
  let%arr m = State.value ()
  and view_role
  and quit in
  let lobby_named =
    match m.lobby with
    | Some l -> not (String.is_empty l.name)
    | None -> false
  in
  if lobby_named && Option.is_some m.user
  then (
    let lobby_label = Option.value_map m.lobby ~default:"" ~f:(fun l -> l.name) in
    {%html.jsx|
      <div *{[ Style.toolbar ]}>
        <div *{[ Ui.row; Ui.center_v ]}>%{mdi "map-marker"}<span *{[ A.class_ "lobby-name"; Ui.fw ]}>#{lobby_label}</span></div>
        <div *{[ Ui.spacer ]}></div>
        %{view_role}
        %{quit}
      </div>
    |})
  else (
    let email = Option.value (Option.bind m.user ~f:(fun u -> u.email)) ~default:"" in
    let logout =
      btn ~on_click:(eff State.logout) [ mdi "exit-to-app"; N.text "Logout" ]
    in
    {%html.jsx|
      <div *{[ Style.toolbar ]}>
        <span *{[ Style.toolbar_email ]}>#{email}</span>
        <div *{[ Ui.spacer ]}></div>
        %{logout}
      </div>
    |})
;;
