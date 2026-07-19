open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Avalon_core
open Types
open Ui
module M = State.Model
module D = State.Derived
module N = Vdom.Node

(** Full-screen event dialogs driven by the model's [modal] field: game-started, a mission
    result, and the end-game summary (with the mission grid and achievements). *)

module Style =
  [%css
  stylesheet
    {|
  .endgame_title { background: #b3e5fc; text-align: center; justify-content: center; }
  .endgame_message { font-size: 1.25rem; text-align: center; }
  .endgame_table_wrap { overflow-x: auto; width: 100%; }
  .endgame_table_wrap table { margin: 0 auto; }
  /* the end-game modal is much wider than the small confirmation dialogs
     (dvh, not vh: iOS Safari's vh ignores the collapsing URL bar) */
  .endgame_card { background: #e0f7fa; border-radius: 8px; max-width: 900px; width: calc(100vw - 32px); max-height: calc(100vh - 48px); max-height: calc(100dvh - 48px); overflow: auto; padding-bottom: 8px; }
  /* outcome-tinted dialog title bars (defined after endgame_title so they win the cascade) */
  .title_success { display: flex; align-items: center; gap: 8px; background: #c8e6c9; color: #1b5e20; }
  .title_fail { display: flex; align-items: center; gap: 8px; background: #ffcdd2; color: #b71c1c; }
|}]

let start_node ~close:_ =
  div
    ~attrs:[ Ui.overlay_card ]
    [ card_title ~attrs:[ Ui.title_bar ] [ N.h3 [ N.text "Game Started" ] ]
    ; card_text
        [ N.p
            [ N.text "A new game has started. When you are ready, view your secret role."
            ]
        ; N.p
            [ N.text
                "You may also view your role anytime by clicking on your name in the \
                 toolbar."
            ]
        ]
    ; div
        ~attrs:[ Ui.row; Ui.actions ]
        [ btn
            ~attrs:[ Ui.primary ]
            ~on_click:
              (eff (fun () ->
                 State.set_modal No_modal;
                 State.set_show_role_sheet true))
            [ N.text "View Role" ]
        ]
    ]
;;

(* Defensive fallback for a dialog whose data is missing: without a body, the toplayer
   modal would still dim the page but show an invisible box with no way to close it. *)
let fallback_node ~title ~message ~close =
  div
    ~attrs:[ Ui.overlay_card ]
    [ card_title ~attrs:[ Ui.title_bar ] [ N.h3 [ N.text title ] ]
    ; card_text [ N.p [ N.text message ] ]
    ; div
        ~attrs:[ Ui.row; Ui.actions ]
        [ btn ~attrs:[ Ui.primary ] ~on_click:close [ N.text "Close" ] ]
    ]
;;

let mission_node (g : Game.t) ~close =
  let idx =
    if g.current_mission_idx < 0
    then List.length (Game.missions g)
    else g.current_mission_idx
  in
  match List.nth (Game.missions g) (idx - 1) with
  | None ->
    fallback_node
      ~title:"Mission Result"
      ~message:"No mission result is available yet."
      ~close
  | Some mission ->
    let title, title_tint =
      match mission.state with
      | Success ->
        ( N.div
            [ fa ~color:"#2e7d32" "fas" "fa-check-circle"; N.text " Mission Succeeded!" ]
        , Style.title_success )
      | _ ->
        ( N.div [ fa ~color:"#c62828" "fas" "fa-times-circle"; N.text " Mission Failed!" ]
        , Style.title_fail )
    in
    div
      ~attrs:[ Ui.overlay_card ]
      [ card_title ~attrs:[ title_tint ] [ title ]
      ; card_text
          [ textf
              "%s had %s failure %s"
              (Util.join_with_and mission.team)
              (if mission.num_fails > 0 then Int.to_string mission.num_fails else "no")
              (if mission.num_fails = 1 then "vote." else "votes.")
          ]
      ; div
          ~attrs:[ Ui.row; Ui.actions ]
          [ btn ~attrs:[ Ui.primary ] ~on_click:close [ N.text "Close" ] ]
      ]
;;

let end_node (g : Game.t) ~close =
  match Game.outcome g with
  | None -> N.none
  | Some o ->
    let title, title_tint =
      match o.state with
      | Good_win -> "Good wins!", [ Style.title_success ]
      | Evil_win -> "Evil wins!", [ Style.title_fail ]
      | Canceled -> "Game Canceled", []
    in
    let role_assignments =
      List.sort o.roles ~compare:(fun a b ->
        Int.compare (Avalonlib.role_index a.role) (Avalonlib.role_index b.role))
    in
    let missions =
      List.filter (Game.missions g) ~f:(fun mi ->
        List.exists mi.proposals ~f:(fun p -> not (equal_proposal_state p.state Pending)))
    in
    let assassinated =
      match o.assassinated with
      | Some a ->
        N.p
          [ textf
              "%s was assassinated by %s"
              a
              (Option.value_map
                 (List.find o.roles ~f:(fun r -> r.assassin))
                 ~default:""
                 ~f:(fun r -> r.name))
          ]
      | None -> N.none
    in
    let body =
      div
        ~attrs:[ Ui.col; Ui.center ]
        [ {%html|<div *{[ Style.endgame_message; Ui.fw ]}>#{o.message}</div>|}
        ; assassinated
        ; div
            ~attrs:[ Style.endgame_table_wrap ]
            [ Summary_table.mission_summary_table
                ~players:(Game.players g)
                ~missions
                ~roles:(Some role_assignments)
                ~mission_votes:(Some o.votes)
            ]
        ; Achievements.achievements g
        ; btn ~attrs:[ Ui.mt_6; Ui.primary ] ~on_click:close [ N.text "Close" ]
        ]
    in
    div
      ~attrs:[ Style.endgame_card ]
      [ card_title
          ~attrs:(Style.endgame_title :: title_tint)
          [ spanc ~attrs:[ Ui.text_h4; Ui.fw ] [ N.text title ] ]
      ; card_text [ body ]
      ]
;;

(* The event modals are driven by the model's [modal] field rather than a trigger button,
   so we map it to an option and let {!Ui.modal} portal the matching dialog into the top
   layer. *)
let modals (local_ graph) : unit =
  (* pair the tag with the live model so the dialog's content re-renders as the model
     changes, rather than freezing a snapshot taken when the modal opened *)
  let tag_and_model =
    let%arr m = State.value () in
    match m.modal with
    | M.Start_game -> Some (`Start, m)
    | M.Mission_result -> Some (`Mission, m)
    | M.End_game -> Some (`End, m)
    | M.No_modal -> None
  in
  Ui.modal
    tag_and_model
    ~on_close:(Bonsai.return (eff (fun () -> State.set_modal No_modal)))
    ~content:(fun (which, m) ~close ->
      match which, D.game m with
      | `Start, _ -> start_node ~close
      | `Mission, Some g -> mission_node g ~close
      | `End, Some g -> end_node g ~close
      | (`Mission | `End), None ->
        fallback_node
          ~title:"Game Unavailable"
          ~message:"The game data for this dialog is no longer available."
          ~close)
    graph
;;
