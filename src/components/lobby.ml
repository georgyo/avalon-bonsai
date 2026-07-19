open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Avalon_core
open Types
open Ui
module D = State.Derived
module N = Vdom.Node
module A = Vdom.Attr
module Dnd = Bonsai_web_drag_and_drop

(** The lobby screens: choosing/creating a lobby, and the pre-game lobby (player list,
    selectable roles, start controls). *)

module Style =
  [%css
  stylesheet
    {|
  .lobby_select { display: flex; justify-content: center; padding: 16px; }
  /* a light card surface: the shared filled text-field/stats styling assumes a light
     background and is unreadable directly on the indigo page */
  .lobby_inner { width: 100%; max-width: 440px; background: #e0f7fa; border-radius: 8px; padding: 24px 20px; box-shadow: 0 2px 6px rgba(0,0,0,0.3); }
  .lobby_buttons { width: 100%; }
  .lobby_buttons .btn { width: 100%; }
  .checkbox_row { display: flex; align-items: center; justify-content: center; gap: 6px; color: #e0f7fa; padding-top: 16px; }
  .hint_on_dark { color: rgba(255,255,255,0.65); }
  .on_dark { color: #e0f7fa; }
  /* the shareable lobby code: the one thing the host needs to read out / long-press */
  .lobby_code { font-size: 2rem; font-weight: 700; letter-spacing: 0.35em; text-align: center; background: #fff; border-radius: 8px; padding: 8px 8px 8px 16px; margin-top: 8px; user-select: all; }
  /* drag-to-reorder (toplayer/drag_and_drop) affordances */
  .drag_handle { cursor: grab; color: rgba(0,0,0,0.4); display: flex; align-items: center; }
  .drag_handle:active { cursor: grabbing; }
  .drag_ghost { background: #cfd8dc; border-radius: 4px; padding: 4px 12px; box-shadow: 0 3px 8px rgba(0,0,0,0.35); font-weight: 600; opacity: 0.95; }
|}]

(* Move [name] to sit at [target_idx] in the player order (used by drag-and-drop on_drop). *)
let reorder_to list ~name ~target_idx =
  let without = List.filter list ~f:(fun p -> not (String.equal p name)) in
  let idx = Int.max 0 (Int.min target_idx (List.length without)) in
  List.take without idx @ [ name ] @ List.drop without idx
;;

(* ---- LobbySelect ---- *)
let lobby_select (local_ graph) =
  let name, set_name = Bonsai.state "" graph in
  (* Pre-fill the name field from the signed-in user. Firebase auth resolves after the
     graph is built, so a one-shot read at build time would miss it: instead watch the
     user's name and seed the field when it becomes available, but only while the field is
     still empty (peeked at callback time) so user typing is never clobbered. *)
  let peek_name = Bonsai.peek name graph in
  let user_name =
    let%arr m = State.value () in
    Option.value_map m.user ~default:"" ~f:(fun u -> u.name)
  in
  let () =
    Bonsai.Edge.on_change
      user_name
      ~equal:String.equal
      ~callback:
        (let%arr set_name and peek_name in
         fun user_name ->
           if String.is_empty user_name
           then Effect.Ignore
           else (
             match%bind.Effect peek_name with
             | Bonsai.Computation_status.Active "" -> set_name user_name
             | Active _ | Inactive -> Effect.Ignore))
      graph
  in
  let lobby, set_lobby = Bonsai.state "" graph in
  let error, set_error = Bonsai.state "" graph in
  let show_lobby_input, set_show_lobby_input = Bonsai.state false graph in
  let creating, set_creating = Bonsai.state false graph in
  let joining, set_joining = Bonsai.state false graph in
  let%arr m = State.value ()
  and name
  and set_name
  and lobby
  and set_lobby
  and error
  and set_error
  and show_lobby_input
  and set_show_lobby_input
  and creating
  and set_creating
  and joining
  and set_joining in
  let do_create =
    eff (fun () ->
      run (set_error "");
      run (set_creating true);
      State.create_lobby
        ~name
        ~on_ok:(fun () -> run (set_creating false))
        ~on_err:(fun e ->
          run (set_error e);
          run (set_creating false))
        ())
  in
  let do_join =
    eff (fun () ->
      run (set_error "");
      run (set_joining true);
      State.join_lobby
        ~name
        ~lobby
        ~on_ok:(fun () -> run (set_joining false))
        ~on_err:(fun e ->
          run (set_error e);
          run (set_joining false))
        ())
  in
  let form =
    if not show_lobby_input
    then
      [ text_field
          ~attrs:[ Ui.upper ]
          ~placeholder:"Your Name"
          ~value:name
          ~on_input:(fun s -> set_name (String.uppercase s))
          ~extra:[ A.create "maxlength" "20" ]
          ()
      ; error_text error
      ; div
          ~attrs:[ Ui.col; Ui.ga_2; Style.lobby_buttons ]
          [ btn
              ~attrs:[ Ui.primary ]
              ~disabled:(String.is_empty name)
              ~loading:creating
              ~on_click:do_create
              [ N.text "Create Lobby" ]
          ; btn
              ~disabled:(String.is_empty name || creating)
              ~on_click:(Effect.Many [ set_error ""; set_show_lobby_input true ])
              [ N.text "Join Lobby" ]
          ]
      ]
    else
      [ text_field
          ~attrs:[ Ui.upper ]
          ~placeholder:"Lobby"
          ~value:lobby
          ~on_input:(fun s -> set_lobby (String.uppercase s))
          ~extra:[ on_enter do_join ]
          ()
      ; error_text error
      ; div
          ~attrs:[ Ui.col; Ui.ga_2; Style.lobby_buttons ]
          [ btn
              ~attrs:[ Ui.primary ]
              ~disabled:(String.is_empty lobby)
              ~loading:joining
              ~on_click:do_join
              [ N.text "Join Lobby" ]
          ; btn
              ~disabled:joining
              ~on_click:(Effect.Many [ set_error ""; set_show_lobby_input false ])
              [ N.text "Cancel" ]
          ]
      ]
  in
  let children =
    form
    @ [ div ~attrs:[ Ui.pt_8 ] []
      ; Stats.stats_display (Option.bind m.user ~f:(fun u -> u.stats)) m.global_stats
      ]
  in
  {%html|
    <div *{[ Style.lobby_select ]}>
      <div *{[ Ui.col; Ui.center; Style.lobby_inner ]}>*{children}</div>
    </div>
  |}
;;

(* ---- LobbyPlayerList (private) ---- *)
let lobby_player_list (local_ graph) =
  let kick_target, set_kick_target =
    Bonsai.state_opt graph ~sexp_of_model:[%sexp_of: string]
  in
  (* A drag-and-drop "universe": dragging a player's handle (source = player name) onto a
     row (drop target = that row's index) reorders the seating. The on_click ▲▼ arrows are
     kept as an accessible fallback. *)
  let dnd =
    Dnd.create
      ~source_id:(module String)
      ~target_id:(module Int)
      ~on_drop:
        (Bonsai.return (fun name target_idx ->
           eff (fun () ->
             State.set_player_list
               (reorder_to (State.model ()).player_list ~name ~target_idx))))
      graph
  in
  let ghost =
    Dnd.dragged_element dnd graph ~f:(fun name _graph ->
      let%arr name in
      {%html|<div *{[ Style.drag_ghost ]}>#{name}</div>|})
  in
  Ui.modal
    kick_target
    ~on_close:
      (let%arr set_kick_target in
       set_kick_target None)
    ~content:(fun player ~close ->
      div
        ~attrs:[ Ui.overlay_card ]
        [ card_title ~attrs:[ Ui.title_bar ] [ N.h3 [ textf "Kick %s?" player ] ]
        ; card_text [ textf "Do you wish to kick %s from the lobby?" player ]
        ; div
            ~attrs:[ Ui.row; Ui.actions ]
            [ btn
                ~on_click:
                  (Effect.Many [ eff (fun () -> State.kick_player player); close ])
                [ textf "Kick %s" player ]
            ; btn ~on_click:close [ N.text "Cancel" ]
            ]
        ])
    graph;
  let%arr m = State.value ()
  and set_kick_target
  and dnd
  and ghost in
  let can_reorder = D.is_admin m && not (D.is_game_in_progress m) in
  let admin_name = Option.value_map (D.admin m) ~default:"" ~f:(fun a -> a.name) in
  let me = D.user_name m in
  let n = List.length m.player_list in
  let item idx player =
    let prepend_icon =
      if String.equal player admin_name
      then mdi "star"
      else if String.equal player me
      then mdi "account"
      else mdi "account-outline"
    in
    let reorder =
      if can_reorder
      then
        [ spanc
            ~attrs:
              [ Style.drag_handle
              ; Dnd.source dnd ~id:player
              ; Ui.tooltip_text "Drag to reorder seating"
              ]
            [ mdi "drag-horizontal-variant" ]
        ; btn
            ~attrs:[ Ui.icon_btn; A.create "aria-label" (sprintf "Move %s up" player) ]
            ~disabled:(idx = 0)
            ~on_click:
              (eff (fun () -> State.set_player_list (swap_at m.player_list (idx - 1))))
            [ mdi "chevron-up" ]
        ; btn
            ~attrs:[ Ui.icon_btn; A.create "aria-label" (sprintf "Move %s down" player) ]
            ~disabled:(idx = n - 1)
            ~on_click:(eff (fun () -> State.set_player_list (swap_at m.player_list idx)))
            [ mdi "chevron-down" ]
        ]
      else []
    in
    let kick_btn =
      if D.is_admin m && (not (String.equal player me)) && not (D.is_game_in_progress m)
      then
        [ btn
            ~attrs:[ Ui.icon_btn; A.create "aria-label" (sprintf "Kick %s" player) ]
            ~on_click:(set_kick_target (Some player))
            [ mdi "close" ]
        ]
      else []
    in
    let prepend = div ~attrs:[ Ui.li_prepend ] (reorder @ [ prepend_icon ]) in
    let li_attrs = if can_reorder then [ Dnd.drop_target dnd ~id:idx ] else [] in
    {%html|
      <li class="v-list-item" *{li_attrs}>
        %{prepend}
        <div *{[ Ui.li_title ]}>#{player}</div>
        *{kick_btn}
      </li>
    |}
  in
  let items = List.mapi m.player_list ~f:item in
  {%html|
    <div *{[ Dnd.sentinel dnd ~name:"lobby-players" ]}>
      <ul class="v-list">*{items}</ul>
      %{ghost}
    </div>
  |}
;;

(* ---- GameLobby ---- *)
let game_lobby (local_ graph) =
  let starting, set_starting = Bonsai.state false graph in
  let in_game_log, set_in_game_log = Bonsai.state false graph in
  let players = lobby_player_list graph in
  let roles = Role_list.selectable_role_list graph in
  let%arr m = State.value ()
  and starting
  and set_starting
  and in_game_log
  and set_in_game_log
  and players
  and roles in
  let num_players = List.length m.player_list in
  let valid_team_size = num_players >= 5 && num_players <= 10 in
  let num_evil =
    Option.value (Avalonlib.get_num_evil_for_game_size num_players) ~default:0
  in
  let lobby_name = Option.value_map m.lobby ~default:"" ~f:(fun l -> l.name) in
  let reason_not_start =
    if num_players < 5
    then
      (* surface the lobby code as a big selectable block: it is the one thing the host
         has to share to fill the lobby *)
      Some
        (N.div
           [ N.text "Need at least 5 players! Invite your friends with the lobby code:"
           ; {%html|<div *{[ Style.lobby_code ]}>#{lobby_name}</div>|}
           ])
    else if num_players > 10
    then Some (N.text "Cannot start game with more than 10 players")
    else if not (D.is_admin m)
    then
      Some
        (textf
           "Waiting for %s to start game..."
           (Option.value_map (D.admin m) ~default:"" ~f:(fun a -> a.name)))
    else None
  in
  let start =
    eff (fun () ->
      run (set_starting true);
      State.start_game
        ~in_game_log
        ~on_ok:(fun () -> run (set_starting false))
        ~on_err:(fun e ->
          Toast.show e;
          run (set_starting false))
        ())
  in
  let seating_hint =
    if D.is_admin m && num_players > 2
    then
      {%html|<p *{[ Ui.caption; Style.hint_on_dark ]}>Use the arrows to set seating order</p>|}
    else N.none
  in
  let roles_col =
    if valid_team_size
    then
      {%html|<div *{[ Ui.col6 ]}><p *{[ Ui.label ]}>Special Roles Available</p>%{roles}</div>|}
    else N.none
  in
  let counts =
    if valid_team_size
    then
      {%html|<div *{[ Ui.row; Ui.center ]}><p *{[ Ui.text_h6; Style.on_dark ]}>%{textf "%d players: %d good, %d evil" num_players (num_players - num_evil) num_evil}</p></div>|}
    else N.none
  in
  let start_area =
    match reason_not_start with
    | None ->
      btn
        ~attrs:[ Ui.cta_on_dark ]
        ~loading:starting
        ~on_click:start
        [ mdi "play"; N.text "Start Game" ]
    | Some reason ->
      card ~attrs:[ Ui.info_card ] [ card_text ~attrs:[ Ui.center ] [ reason ] ]
  in
  let log_attrs =
    [ A.type_ "checkbox"
    ; A.checked_prop in_game_log
    ; A.on_click (fun _ -> set_in_game_log (not in_game_log))
    ]
  in
  {%html|
    <div *{[ Ui.container ]}>
      <div *{[ Ui.row; Ui.wrap; Ui.start ]}>
        <div *{[ Ui.col6 ]}>
          <p *{[ Ui.label ]}>Players</p>
          %{players}
          %{seating_hint}
        </div>
        %{roles_col}
      </div>
      %{counts}
      <div *{[ Ui.row; Ui.center; Ui.pt_2 ]}>%{start_area}</div>
      <label *{[ Style.checkbox_row ]}><input *{log_attrs} />#{" In-game log"}</label>
      <div *{[ Ui.col; Ui.center; Ui.pt_6 ]}>%{feedback_link "Send feedback"}</div>
    </div>
  |}
;;
