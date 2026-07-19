open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Avalon_core
open Types
open Ui
module D = State.Derived
module N = Vdom.Node
module A = Vdom.Attr

(** The in-game participants panel: the live player list (with proposer crown, hammer, and
    per-player vote-status icons) and a tab toggle to the role list. Uses only shared
    {!Ui} styling. *)

(* ---- GamePlayerList (private) ---- *)
let game_player_list ~selected ~set_selected (local_ graph) =
  let%arr m = State.value ()
  and selected
  and set_selected in
  match D.game m, D.role m with
  | Some g, role_doc ->
    let me = D.user_name m in
    let phase = Game.phase g in
    let assassin = Option.value_map role_doc ~default:false ~f:(fun r -> r.assassin) in
    let team_size =
      Option.value_map g.current_mission ~default:1 ~f:(fun mi -> mi.team_size)
    in
    let max_selected =
      match phase with
      | Team_proposal -> team_size
      | _ -> 1
    in
    let toggle name =
      let next =
        if List.mem selected name ~equal:String.equal
        then List.filter selected ~f:(fun x -> not (String.equal x name))
        else selected @ [ name ]
      in
      let next =
        if List.length next > max_selected
        then List.drop next (List.length next - max_selected)
        else next
      in
      set_selected next
    in
    let enable_checkbox name =
      match phase with
      | Team_proposal ->
        Option.value_map g.current_proposer ~default:false ~f:(String.equal me)
      | Assassination -> assassin && not (String.equal name me)
      | _ -> false
    in
    let selected_for_mission name =
      (match phase with
       | Proposal_vote | Mission_vote -> true
       | _ -> false)
      && Option.value_map g.current_proposal ~default:false ~f:(fun p ->
        List.mem p.team name ~equal:String.equal)
    in
    let was_on_last name =
      match phase with
      | Team_proposal | Assassination ->
        Option.value_map (Game.last_proposal g) ~default:false ~f:(fun p ->
          List.mem p.team name ~equal:String.equal)
      | Proposal_vote | Mission_vote ->
        Option.value_map g.current_proposal ~default:false ~f:(fun p ->
          List.mem p.team name ~equal:String.equal)
      | Unknown_phase _ -> false
    in
    let has_voted name =
      equal_phase phase Proposal_vote
      && Option.value_map g.current_proposal ~default:false ~f:(fun p ->
        List.mem p.votes name ~equal:String.equal)
    in
    let waiting name =
      equal_phase phase Proposal_vote
      && not
           (Option.value_map g.current_proposal ~default:false ~f:(fun p ->
              List.mem p.votes name ~equal:String.equal))
    in
    let approved name =
      match phase with
      | Team_proposal | Assassination ->
        Option.value_map (Game.last_proposal g) ~default:false ~f:(fun p ->
          List.mem p.votes name ~equal:String.equal)
      | Mission_vote ->
        Option.value_map g.current_proposal ~default:false ~f:(fun p ->
          List.mem p.votes name ~equal:String.equal)
      | _ -> false
    in
    let rejected name =
      match phase with
      | Team_proposal | Assassination ->
        Option.value_map (Game.last_proposal g) ~default:false ~f:(fun p ->
          not (List.mem p.votes name ~equal:String.equal))
      | Mission_vote ->
        Option.value_map g.current_proposal ~default:false ~f:(fun p ->
          not (List.mem p.votes name ~equal:String.equal))
      | _ -> false
    in
    (* amber-gold reads on the light list where pure yellow #fcfc00 vanished *)
    let crown_color = if g.current_proposal_idx < 4 then "#f9a825" else "#cc0808" in
    let status_icons name =
      let icons =
        List.filter_opt
          [ (if was_on_last name
             then Some (fa ~color:"#629ec1" "far" "fa-circle")
             else None)
          ; (if waiting name
             then Some (fa ~color:"#4c4c4c" "fas" "fa-ellipsis-h")
             else if has_voted name
             then Some (fa ~color:"#4c4c4c" "fas" "fa-vote-yea")
             else if approved name
             then Some (fa ~color:"#2e7d32" "far" "fa-thumbs-up")
             else if rejected name
             then Some (fa ~color:"#c62828" "far" "fa-thumbs-down")
             else None)
          ]
      in
      (* Mirror Vue's tooltipText so the otherwise-cryptic status icons are explained on
         hover. *)
      let states =
        List.filter_opt
          [ (if was_on_last name then Some "was on the last proposed team" else None)
          ; (if waiting name
             then Some "is currently voting on the proposal"
             else if has_voted name
             then Some "has submitted a vote for the proposed team"
             else if approved name
             then Some "approved the last team"
             else if rejected name
             then Some "rejected the last team"
             else None)
          ]
      in
      if List.is_empty icons
      then N.none
      else
        fa_layers
          ~attrs:[ Ui.tooltip_text (sprintf "%s %s" name (Util.join_with_and states)) ]
          icons
    in
    let item name =
      let checkbox =
        if enable_checkbox name
        then
          N.input
            ~attrs:
              [ A.type_ "checkbox"
              ; A.checked_prop (List.mem selected name ~equal:String.equal)
              ; A.on_click (fun _ -> toggle name)
              ]
            ()
        else if selected_for_mission name
        then
          N.input ~attrs:[ A.type_ "checkbox"; A.checked_prop true; A.disabled' true ] ()
        else N.none
      in
      let marker =
        if Option.value_map g.current_proposer ~default:false ~f:(String.equal name)
        then
          fa_layers
            ~attrs:[ Ui.tooltip_text (sprintf "%s is proposing the next team" name) ]
            [ fa ~color:crown_color "fas" "fa-crown"
            ; spanc
                ~attrs:[ Ui.layers_text ]
                [ N.text (Int.to_string (g.current_proposal_idx + 1)) ]
            ]
        else if Option.value_map g.hammer ~default:false ~f:(String.equal name)
        then fa "fas" "fa-hammer"
        else N.none
      in
      (* the checkbox and the name live in one <label> (display: contents, so the flex row
         layout is untouched): clicking the name toggles the box, and screen readers
         announce the player's name for it *)
      {%html|
        <li class="v-list-item">
          <label *{[ Ui.li_label ]}>
            <div *{[ Ui.li_prepend ]}>%{checkbox}</div>
            <div *{[ Ui.li_mid ]}>%{marker}</div>
            <div *{[ Ui.li_title ]}>#{name}</div>
          </label>
          <div *{[ Ui.li_append ]}>%{status_icons name}</div>
        </li>
      |}
    in
    let items = List.map (Game.players g) ~f:item in
    {%html|<ul class="v-list">*{items}</ul>|}
  | None, _ -> N.none
;;

(* ---- GameParticipants ---- *)
let game_participants ~selected ~set_selected (local_ graph) =
  let tab, set_tab = Bonsai.state "players" graph in
  let players = game_player_list ~selected ~set_selected graph in
  let%arr m = State.value ()
  and tab
  and set_tab
  and players in
  match D.game m with
  | None -> N.none
  | Some g ->
    let role_objs =
      List.filter_map (Game.roles g) ~f:(fun r -> Map.find Avalonlib.role_map r)
    in
    let body =
      if String.equal tab "players" then players else Role_list.role_list_view role_objs
    in
    let strip =
      (* this strip sits directly on the indigo page, not on a light card *)
      tab_strip
        ~tab_attrs:[ Ui.tab_dark ]
        ~active:(if String.equal tab "players" then 0 else 1)
        ~on_select:(fun i -> set_tab (if i = 0 then "players" else "roles"))
        [ [ N.text "Players" ]; [ N.text "Roles" ] ]
    in
    {%html|
      <div>
        %{strip}
        %{body}
      </div>
    |}
;;
