open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Avalon_core
open Types
open Ui
module D = State.Derived
module N = Vdom.Node

(** The phase-dependent action pane (propose a team / vote on a proposal / vote on a
    mission / assassinate). Only the active phase's component is instantiated via
    [match%sub]; the individual panes are private and dispatched through {!action_pane}. *)

module Style =
  [%css
  stylesheet {|
  .action { width: 100%; }
  .action_title { background: #b3e5fc; }
|}]

(* Fire [reset] whenever the active (mission, proposal) changes, to clear optimistic
   per-proposal local state. match%sub does not reset inactive-branch state in this Bonsai
   version, so without this a vote/proposal on one round leaks into the next. *)
let on_proposal_change (local_ graph) ~reset =
  let key =
    let%arr m = State.value () in
    match D.game m with
    | Some g -> g.current_mission_idx, g.current_proposal_idx
    | None -> -1, -1
  in
  Bonsai.Edge.on_change
    key
    ~equal:[%equal: int * int]
    ~callback:
      (let%arr reset in
       fun _ -> reset)
    graph
;;

let team_proposal_action ~selected (local_ graph) =
  let proposing, set_proposing = Bonsai.state false graph in
  let () =
    on_proposal_change
      graph
      ~reset:
        (let%arr set_proposing in
         set_proposing false)
  in
  let%arr m = State.value ()
  and selected
  and proposing
  and set_proposing in
  match D.game m with
  | None -> N.none
  | Some g ->
    let me = D.user_name m in
    let team_size =
      Option.value_map g.current_mission ~default:0 ~f:(fun mi -> mi.team_size)
    in
    let valid = List.length selected = team_size in
    let propose =
      eff (fun () ->
        run (set_proposing true);
        State.propose_team selected ~on_err:(fun _ -> run (set_proposing false)))
    in
    let body =
      if Option.value_map g.current_proposer ~default:false ~f:(String.equal me)
      then
        div
          ~attrs:[ Ui.col; Ui.center ]
          [ {%html.jsx|<div *{[ Ui.center ]}>%{textf "Propose a team of %d" team_size}</div>|}
          ; btn
              ~disabled:(not valid)
              ~loading:proposing
              ~on_click:propose
              [ N.text "Propose Team" ]
          ]
      else
        {%html.jsx|<div *{[ Ui.center ]}>%{textf "Waiting for %s to propose a team of %d" (Option.value g.current_proposer ~default:"") team_size}</div>|}
    in
    card
      ~attrs:[ Style.action ]
      [ card_title
          ~attrs:[ Style.action_title ]
          [ textf "Team Proposal (%d/5)" (g.current_proposal_idx + 1) ]
      ; card_text [ body ]
      ]
;;

let team_vote_action (local_ graph) =
  let voted, set_voted = Bonsai.state_opt graph ~sexp_of_model:[%sexp_of: bool] in
  let () =
    on_proposal_change
      graph
      ~reset:
        (let%arr set_voted in
         set_voted None)
  in
  let%arr m = State.value ()
  and voted
  and set_voted in
  match D.game m with
  | None -> N.none
  | Some g ->
    let me = D.user_name m in
    let already =
      Option.value_map g.current_proposal ~default:false ~f:(fun p ->
        List.mem p.votes me ~equal:String.equal)
    in
    let proposer_label =
      if Option.value_map g.current_proposer ~default:false ~f:(String.equal me)
      then "your"
      else Option.value g.current_proposer ~default:"" ^ "'s"
    in
    let team =
      Option.value_map g.current_proposal ~default:"" ~f:(fun p ->
        Util.join_with_and p.team)
    in
    (* disable both buttons once an optimistic vote is in flight (until server state
       catches up), so a double-click can't submit the vote twice *)
    let disabled = already || Option.is_some voted in
    let vote v =
      eff (fun () ->
        (* set the flag optimistically at click time so both buttons disable immediately;
           a failed vote re-enables them *)
        run (set_voted (Some v));
        State.vote_team v ~on_err:(fun _ -> run (set_voted None)))
    in
    let voted_yes = Option.value_map voted ~default:false ~f:Fn.id in
    let voted_no = Option.value_map voted ~default:false ~f:not in
    let buttons =
      div
        ~attrs:[ Ui.row; Ui.between ]
        [ btn
            ~disabled
            ~on_click:(vote true)
            [ (if voted_yes
               then fa ~color:"green" "fas" "fa-vote-yea"
               else fa ~color:"green" "far" "fa-thumbs-up")
            ; N.text " Approve"
            ]
        ; btn
            ~disabled
            ~on_click:(vote false)
            [ (if voted_no
               then fa ~color:"red" "fas" "fa-vote-yea"
               else fa ~color:"red" "far" "fa-thumbs-down")
            ; N.text " Reject"
            ]
        ]
    in
    card
      ~attrs:[ Style.action ]
      [ card_title
          ~attrs:[ Style.action_title ]
          [ textf "Team Proposal Vote (%d/5)" (g.current_proposal_idx + 1) ]
      ; card_text
          [ N.div [ textf "Voting for %s team of %s" proposer_label team ]; buttons ]
      ]
;;

let mission_action (local_ graph) =
  let done_, set_done = Bonsai.state false graph in
  let error, set_error = Bonsai.state "" graph in
  (* reset the optimistic "already submitted" flag and any stale error banner whenever the
     mission changes, so a vote (or failure) on one mission doesn't leak into the next *)
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
        (let%arr set_done and set_error in
         fun _ -> Effect.Many [ set_done false; set_error "" ])
      graph
  in
  let%arr m = State.value ()
  and done_
  and set_done
  and error
  and set_error in
  match D.game m with
  | None -> N.none
  | Some g ->
    let me = D.user_name m in
    let on_team =
      Option.value_map g.current_proposal ~default:false ~f:(fun p ->
        List.mem p.team me ~equal:String.equal)
    in
    let already_voted =
      Option.value_map g.current_mission ~default:false ~f:(fun mi ->
        List.mem mi.team me ~equal:String.equal)
    in
    let needs_to_vote = on_team && (not already_voted) && not done_ in
    let still_waiting =
      match g.current_proposal, g.current_mission with
      | Some p, Some mi ->
        List.filter (Util.difference p.team mi.team) ~f:(fun n -> not (String.equal n me))
      | _ -> []
    in
    let vote v =
      eff (fun () ->
        run (set_done true);
        run (set_error "");
        State.do_mission v ~on_err:(fun _ ->
          run (set_done false);
          run (set_error "Vote failed, please try again")))
    in
    let body =
      if needs_to_vote
      then
        N.div
          [ (if String.is_empty error
             then N.none
             else {%html.jsx|<div *{[ Ui.field_error; Ui.center ]}>#{error}</div>|})
          ; div
              ~attrs:[ Ui.row; Ui.between ]
              [ btn
                  ~on_click:(vote true)
                  [ fa ~color:"green" "fas" "fa-check-circle"; N.text " SUCCESS" ]
              ; btn
                  ~on_click:(vote false)
                  [ fa ~color:"red" "fas" "fa-times-circle"; N.text " FAIL" ]
              ]
          ]
      else
        N.div
          [ N.text
              (if List.length still_waiting > 0
               then "Waiting for " ^ Util.join_with_and still_waiting
               else "Waiting for results...")
          ]
    in
    card
      ~attrs:[ Style.action ]
      [ card_title ~attrs:[ Style.action_title ] [ N.text "Mission in Progress" ]
      ; card_text [ body ]
      ]
;;

let assassination_action ~selected (local_ graph) =
  let assassinating, set_assassinating = Bonsai.state false graph in
  let () =
    on_proposal_change
      graph
      ~reset:
        (let%arr set_assassinating in
         set_assassinating false)
  in
  let%arr m = State.value ()
  and selected
  and assassinating
  and set_assassinating in
  match D.game m, D.role m with
  | Some _, role_doc ->
    let me = D.user_name m in
    let assassin = Option.value_map role_doc ~default:false ~f:(fun r -> r.assassin) in
    let target = List.hd selected in
    let valid =
      List.length selected = 1
      && Option.value_map target ~default:false ~f:(fun t -> not (String.equal t me))
    in
    let label =
      if valid then "Assassinate " ^ Option.value target ~default:"" else "Select target"
    in
    let go =
      eff (fun () ->
        match target with
        | Some t ->
          run (set_assassinating true);
          State.assassinate t ~on_err:(fun _ -> run (set_assassinating false))
        | None -> ())
    in
    let body =
      if assassin
      then
        N.div
          [ btn ~disabled:(not valid) ~loading:assassinating ~on_click:go [ N.text label ]
          ]
      else N.div [ N.text "Waiting for target selection" ]
    in
    card
      ~attrs:[ Style.action ]
      [ card_title ~attrs:[ Style.action_title ] [ N.text "Assassination Attempt" ]
      ; card_text [ body ]
      ]
  | None, _ -> N.none
;;

type action_kind =
  | Propose
  | Vote
  | Mission
  | Assassinate
  | No_action
[@@deriving sexp, equal]

(* Only the active action component is instantiated (via [match%sub]). Note that match%sub
   does NOT reset the inactive branch's state in this Bonsai version, so each pane
   explicitly resets its own optimistic flags via [on_proposal_change] (or an equivalent
   on-change hook) to avoid state leaking across rounds and games. *)
let action_pane ~selected (local_ graph) =
  let kind =
    let%arr m = State.value () in
    match D.game m with
    | None -> No_action
    | Some g ->
      (match Game.phase g with
       | Team_proposal -> Propose
       | Proposal_vote -> Vote
       | Mission_vote -> Mission
       | Assassination -> Assassinate
       | Unknown_phase _ -> No_action)
  in
  match%sub kind with
  | Propose -> team_proposal_action ~selected graph
  | Vote -> team_vote_action graph
  | Mission -> mission_action graph
  | Assassinate -> assassination_action ~selected graph
  | No_action -> Bonsai.return N.none
;;
