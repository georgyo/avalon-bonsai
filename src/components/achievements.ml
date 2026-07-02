open! Core
open Bonsai_web
open Avalon_core
open Types
open Ui
module N = Vdom.Node

(** End-game achievement badges, derived from {!Avalon_core.Analysis}. *)

module Style = [%css stylesheet {|
  .achievement { max-width: 900px; }
|}]

let achievements (g : Game.t) =
  match Game.outcome g with
  | Some o when not (equal_outcome_state o.state Canceled) ->
    let badges =
      match Analysis.create g.data ~role_map:Avalonlib.role_map with
      | Some analysis -> Analysis.get_badges analysis
      | None -> []
    in
    if List.is_empty badges
    then N.none
    else (
      let badge (b : Analysis.badge) =
        {%html.jsx|
          <div *{[ Ui.pt_2 ]}>
            %{card ~attrs:[ Style.achievement ]
                 [ card_title ~attrs:[ Ui.title_bar ] [ fa ~color:"gold" "fas" "fa-trophy"; div ~attrs:[ Ui.text_h6 ] [ N.text b.title ] ]
                 ; card_text [ N.text b.body ]
                 ]}
          </div>
        |}
      in
      let badge_nodes = List.map badges ~f:badge in
      {%html.jsx|
        <div *{[ Ui.pt_6 ]}>
          <div *{[ Ui.text_h4; Ui.center ]}>Achievements</div>
          *{badge_nodes}
        </div>
      |})
  | _ -> N.none
;;
