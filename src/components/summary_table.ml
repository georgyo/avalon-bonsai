open! Core
open Bonsai_web
open Avalon_core
open Types
open Ui
module N = Vdom.Node

(** The per-player mission summary grid (one row per player, columns per proposal/result),
    shown in the in-game log and the end-game dialog. *)

module Style =
  [%css
  stylesheet
    {|
  .summary_table { border-collapse: collapse; font-size: 0.875rem; }
  .summary_table tr { height: 2.2em; }
  .summary_table td { width: 1.7em; padding: 0 4px; text-align: center; }
  .summary_table tr:nth-child(even) { background: #ffffff; }
  .summary_table tr:nth-child(odd) { background: #eceff1; }
  .player_name { border-left: 1px solid rgba(0,0,0,0.25); white-space: nowrap; text-align: left; max-width: 120px; overflow: hidden; text-overflow: ellipsis; }
  .role_cell { border-right: 1px solid rgba(0,0,0,0.25); white-space: nowrap; }
  .mission_result { border-right: 1px solid rgba(0,0,0,0.25); }
  /* allegiance tint on the reveal columns: the table communicates teams at a glance */
  .team_good { background: rgba(21,101,192,0.10); }
  .team_evil { background: rgba(198,40,40,0.12); }
|}]

let mission_summary_table
  ~players
  ~(missions : mission list)
  ~(roles : role_assignment list option)
  ~(mission_votes : bool String.Map.t list option)
  =
  let proposals_of (m : mission) =
    List.filter m.proposals ~f:(fun p -> not (List.is_empty p.team))
  in
  let cell_for player (proposal : proposal) =
    fa_layers
      (List.filter_opt
         [ (if String.equal proposal.proposer player
            then Some (fa ~color:"#f9a825" "fas" "fa-circle")
            else None)
         ; (if List.mem proposal.team player ~equal:String.equal
            then Some (fa ~color:"#629ec1" "far" "fa-circle")
            else None)
         ; (match proposal.state with
            | Pending -> None
            | _ ->
              Some
                (if List.mem proposal.votes player ~equal:String.equal
                 then fa ~color:"#2e7d32" "far" "fa-thumbs-up"
                 else fa ~color:"#c62828" "far" "fa-thumbs-down"))
         ])
  in
  let row player =
    let team_tint =
      match roles with
      | None -> []
      | Some rs ->
        (match
           List.find rs ~f:(fun r -> String.equal r.name player)
           |> Option.bind ~f:(fun r -> Map.find Avalonlib.role_map r.role)
         with
         | Some { team = Good; _ } -> [ Style.team_good ]
         | Some { team = Evil; _ } -> [ Style.team_evil ]
         | None -> [])
    in
    let role_cell =
      match roles with
      | Some rs ->
        let r = List.find rs ~f:(fun r -> String.equal r.name player) in
        [ N.td
            ~attrs:(Style.role_cell :: team_tint)
            [ N.text (Option.value_map r ~default:"" ~f:(fun r -> r.role)) ]
        ]
      | None -> []
    in
    let mission_cells =
      List.concat_mapi missions ~f:(fun midx m ->
        let prop_cells =
          List.map (proposals_of m) ~f:(fun p -> N.td [ cell_for player p ])
        in
        let result_cell =
          match mission_votes with
          | Some mv ->
            if List.mem m.team player ~equal:String.equal
            then (
              let v =
                Option.bind (List.nth mv midx) ~f:(fun map -> Map.find map player)
              in
              [ N.td
                  ~attrs:[ Style.mission_result ]
                  [ (match v with
                     | Some true -> fa ~color:"green" "fas" "fa-check-circle"
                     | _ -> fa ~color:"red" "fas" "fa-times-circle")
                  ]
              ])
            else [ N.td ~attrs:[ Style.mission_result ] [] ]
          | None -> []
        in
        prop_cells @ result_cell)
    in
    N.tr
      ([ N.td
           ~attrs:(Style.player_name :: team_tint)
           [ spanc ~attrs:[ Ui.fw ] [ N.text player ] ]
       ]
       @ role_cell
       @ mission_cells)
  in
  N.table ~attrs:[ Style.summary_table ] (List.map players ~f:row)
;;
