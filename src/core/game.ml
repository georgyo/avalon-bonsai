open! Core
open Types

(** Derived game state, ported from the [Game] class in client/src/avalon.ts. Pure:
    computed from {!Types.game_data} plus the role map. *)

type t =
  { data : game_data
  ; role_map : role String.Map.t
  ; num_players : int
  ; current_mission_idx : int
  ; current_mission : mission option
  ; current_proposal_idx : int
  ; current_proposal : proposal option
  ; current_proposer : string option
  ; hammer : string option
  }

(* convenience re-exports of the underlying game_data fields *)
let data t = t.data
let state t = t.data.state
let phase t = t.data.phase
let players t = t.data.players
let roles t = t.data.roles
let missions t = t.data.missions
let outcome t = t.data.outcome

let create (data : game_data) ~role_map : t =
  match data.state with
  | Init ->
    { data
    ; role_map
    ; num_players = 0
    ; current_mission_idx = -1
    ; current_mission = None
    ; current_proposal_idx = -1
    ; current_proposal = None
    ; current_proposer = None
    ; hammer = None
    }
  | _ ->
    let missions = data.missions in
    let num_players = List.length data.players in
    let current_mission_idx =
      match List.findi missions ~f:(fun _ m -> equal_mission_state m.state M_pending) with
      | Some (i, _) -> i
      | None -> -1
    in
    if current_mission_idx < 0
    then
      { data
      ; role_map
      ; num_players
      ; current_mission_idx
      ; current_mission = None
      ; current_proposal_idx = -1
      ; current_proposal = None
      ; current_proposer = None
      ; hammer = None
      }
    else (
      let current_mission = List.nth_exn missions current_mission_idx in
      let proposals = current_mission.proposals in
      let pending_idx =
        match
          List.findi proposals ~f:(fun _ p -> equal_proposal_state p.state Pending)
        with
        | Some (i, _) -> i
        | None -> List.length proposals - 1
      in
      let current_proposal = List.nth proposals pending_idx in
      let current_proposer = Option.map current_proposal ~f:(fun p -> p.proposer) in
      let hammer =
        match current_proposal, current_proposer with
        | Some _, Some proposer ->
          (* No hammer in the degenerate cases: an empty player list (the modulo below
             would raise) or a proposer who is not in the player list (index -1 would
             yield a plausible-looking but wrong hammer). *)
          (match List.findi data.players ~f:(fun _ p -> String.equal p proposer) with
           | None -> None
           | Some (proposer_idx, _) ->
             let hammer_idx = (proposer_idx + (4 - pending_idx)) % num_players in
             List.nth data.players hammer_idx)
        | _ -> None
      in
      { data
      ; role_map
      ; num_players
      ; current_mission_idx
      ; current_mission = Some current_mission
      ; current_proposal_idx = pending_idx
      ; current_proposal
      ; current_proposer
      ; hammer
      })
;;

(** [lastProposal] getter from the original. *)
let last_proposal (t : t) : proposal option =
  if t.current_proposal_idx > 0
  then
    Option.bind (List.nth t.data.missions t.current_mission_idx) ~f:(fun m ->
      List.nth m.proposals (t.current_proposal_idx - 1))
  else if t.current_mission_idx <= 0
  then None
  else
    Option.bind
      (List.nth t.data.missions (t.current_mission_idx - 1))
      ~f:(fun m ->
        List.find m.proposals ~f:(fun p -> equal_proposal_state p.state Approved))
;;

let get_num_team (t : t) (team : team) : int =
  List.count t.data.roles ~f:(fun r ->
    match Map.find t.role_map r with
    | Some role -> equal_team role.team team
    | None -> false)
;;

let num_evil t = get_num_team t Evil
let num_good t = get_num_team t Good
