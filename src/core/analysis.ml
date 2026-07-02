open! Core
open Types
open Util

(** Port of client/src/avalon-analysis.ts: post-game achievement ("badge") detection.
    [create] returns [None] for games without an outcome. *)

type badge =
  { title : string
  ; body : string
  }

type mission_ex =
  { m : mission
  ; evil_on_team : string list
  }

type t =
  { game : game_data
  ; outcome : game_outcome
  ; roles_by_name : role_assignment String.Map.t
  ; names_by_role : string String.Map.t
  ; evil_players : string list
  ; evil_set : String.Set.t
  ; good_players : string list
  ; missions : mission_ex list
  ; completed_missions : mission_ex list
  }

let str_eq = String.equal
let mem l x = List.mem l x ~equal:String.equal

let team_eq a b =
  List.equal
    String.equal
    (List.sort a ~compare:String.compare)
    (List.sort b ~compare:String.compare)
;;

let tail = function
  | [] -> []
  | _ :: t -> t
;;

let initial l =
  match List.rev l with
  | [] -> []
  | _ :: t -> List.rev t
;;

let create (game : game_data) ~(role_map : role String.Map.t) : t option =
  match game.outcome with
  | None -> None
  | Some outcome ->
    let team_of_role role =
      match Map.find role_map role with
      | Some r -> Some r.team
      | None -> None
    in
    let roles_by_name =
      String.Map.of_alist_reduce
        (List.map outcome.roles ~f:(fun ra -> ra.name, ra))
        ~f:(fun _ b -> b)
    in
    (* invert(mapValues(rolesByName, r => r.role)); later entries win (lossy). *)
    let names_by_role =
      List.fold outcome.roles ~init:String.Map.empty ~f:(fun acc ra ->
        Map.set acc ~key:ra.role ~data:ra.name)
    in
    let evil_players =
      List.filter_map outcome.roles ~f:(fun ra ->
        match team_of_role ra.role with
        | Some Evil -> Some ra.name
        | _ -> None)
    in
    let good_players =
      List.filter_map outcome.roles ~f:(fun ra ->
        match team_of_role ra.role with
        | Some Good -> Some ra.name
        | _ -> None)
    in
    let evil_set = String.Set.of_list evil_players in
    let missions =
      List.map game.missions ~f:(fun m ->
        { m; evil_on_team = List.filter m.team ~f:(fun n -> Set.mem evil_set n) })
    in
    let completed_missions =
      List.filter missions ~f:(fun me -> not (equal_mission_state me.m.state M_pending))
    in
    Some
      { game
      ; outcome
      ; roles_by_name
      ; names_by_role
      ; evil_players
      ; evil_set
      ; good_players
      ; missions
      ; completed_missions
      }
;;

let name_of_role t role = Map.find t.names_by_role role
let is_evil t n = Set.mem t.evil_set n

let role_proposes_role t proposer_role role_proposed =
  match name_of_role t proposer_role, name_of_role t role_proposed with
  | Some pn, Some rn ->
    List.exists t.missions ~f:(fun me ->
      List.exists me.m.proposals ~f:(fun p -> str_eq p.proposer pn && mem p.team rn))
  | _ -> false
;;

let role_approves_role t approver_role role_proposed =
  match name_of_role t approver_role, name_of_role t role_proposed with
  | Some an, Some rn ->
    List.exists t.missions ~f:(fun me ->
      List.existsi me.m.proposals ~f:(fun idx p ->
        idx <> 4 && mem p.team rn && mem p.votes an))
  | _ -> false
;;

let role_trusts_role t source_role dest_role ~gen =
  let proposed = role_proposes_role t source_role dest_role in
  let approved = role_approves_role t source_role dest_role in
  if proposed || approved
  then (
    let msg =
      if proposed && approved
      then "both proposed and approved teams"
      else if proposed
      then "proposed a team"
      else "approved a team"
    in
    Some (gen msg))
  else None
;;

(* ----- individual badges ----- *)

let merlin_sends_evil_team t =
  match name_of_role t "MERLIN" with
  | None -> None
  | Some merlin ->
    List.find_map t.missions ~f:(fun me ->
      (* Deliberate divergence from the original JS, which counts Mordred here but
         excludes him in the sibling merlin_proposes_evil_team badge. Merlin cannot see
         Mordred (see avalonlib.ml), so he must not count as evil Merlin knowingly sent. *)
      let visible_evil =
        List.filter me.evil_on_team ~f:(fun pl ->
          match Map.find t.roles_by_name pl with
          | Some ra -> not (str_eq ra.role "MORDRED")
          | None -> true)
      in
      match
        List.find me.m.proposals ~f:(fun p -> equal_proposal_state p.state Approved)
      with
      | Some ap
        when str_eq merlin ap.proposer && List.length visible_evil >= me.m.fails_required
        ->
        Some
          { title = "Traitor Merlin"
          ; body = sprintf "Merlin sent an evil team with %s" (join_with_and visible_evil)
          }
      | _ -> None)
;;

let merlin_proposes_evil_team t =
  match name_of_role t "MERLIN" with
  | None -> None
  | Some merlin ->
    List.find_map t.missions ~f:(fun me ->
      List.find_map me.m.proposals ~f:(fun p ->
        let evil_on_proposal =
          List.filter p.team ~f:(fun pl ->
            is_evil t pl
            &&
            match Map.find t.roles_by_name pl with
            | Some ra -> not (str_eq ra.role "MORDRED")
            | None -> true)
        in
        if str_eq p.proposer merlin
           && mem p.votes merlin
           && List.length evil_on_proposal >= me.m.fails_required
        then
          Some
            { title = "Advanced Merlin"
            ; body =
                sprintf
                  "Merlin proposed and approved a team with %s"
                  (join_with_and evil_on_proposal)
            }
        else None))
;;

let running_scared t =
  List.find_mapi t.missions ~f:(fun idx me ->
    if List.length me.evil_on_team > 1 && me.m.num_fails = 0
    then
      Some
        { title = "No, you do it"
        ; body =
            sprintf
              "%s went on mission %d together and nobody failed"
              (join_with_and me.evil_on_team)
              (idx + 1)
        }
    else None)
;;

let failure_to_coordinate t =
  let n = List.length t.missions in
  List.find_mapi t.missions ~f:(fun idx me ->
    let next_not_pending =
      match List.nth t.missions (idx + 1) with
      | Some next -> not (equal_mission_state next.m.state M_pending)
      | None -> false
    in
    if me.m.num_fails > me.m.fails_required && idx < n - 1 && next_not_pending
    then
      Some
        { title = "Failure to coordinate"
        ; body =
            sprintf
              "%s had %d failure votes on mission %d"
              (join_with_and me.evil_on_team)
              me.m.num_fails
              (idx + 1)
        }
    else None)
;;

let perfect_coordination t =
  List.find_mapi t.missions ~f:(fun idx me ->
    if List.length me.evil_on_team > me.m.num_fails
       && me.m.num_fails = me.m.fails_required
    then
      Some
        { title = "Same wavelength"
        ; body =
            sprintf
              "%s had perfect coordination on mission %d"
              (join_with_and me.evil_on_team)
              (idx + 1)
        }
    else None)
;;

let forces_of_evil t =
  if List.length t.evil_players <= 2
  then None
  else
    List.find_mapi t.missions ~f:(fun idx me ->
      if List.length me.evil_on_team = List.length t.evil_players
      then
        Some
          { title = "With our powers combined"
          ; body = sprintf "All evil players went on mission %d together" (idx + 1)
          }
      else None)
;;

let no_evil_players_on_missions t =
  if List.for_all (tail t.missions) ~f:(fun me -> List.is_empty me.evil_on_team)
  then (
    let suffix =
      match List.hd t.missions with
      | Some m0 when not (List.is_empty m0.evil_on_team) -> " after mission 1"
      | _ -> ""
    in
    Some { title = "Lockdown"; body = "No evil players went on any missions" ^ suffix })
  else None
;;

let clean_sweep t =
  match List.nth t.missions 0, List.nth t.missions 1, List.nth t.missions 2 with
  | Some m0, Some m1, Some m2
    when equal_mission_state m0.m.state m1.m.state
         && equal_mission_state m1.m.state m2.m.state ->
    if equal_mission_state m0.m.state Fail
    then
      Some { title = "Nasty, brutish, and short"; body = "Evil team dominated the game" }
    else if equal_outcome_state t.outcome.state Evil_win
    then
      Some
        { title = "Look, ma, no hands"
        ; body = "Evil team won despite not failing any missions"
        }
    else Some { title = "Clean sweep"; body = "Good team dominated the game" }
  | _ -> None
;;

let trust_you t =
  List.find_map t.missions ~f:(fun me ->
    List.find_map me.m.proposals ~f:(fun p ->
      if (not (List.is_empty p.team)) && not (mem p.team p.proposer)
      then
        Some
          { title = "I trust you guys"
          ; body = sprintf "%s proposed a team that did not include themselves" p.proposer
          }
      else None))
;;

let trusting_bunch t =
  match List.nth t.missions 0 with
  | None -> None
  | Some m0 ->
    let approved_idx =
      match
        List.findi m0.m.proposals ~f:(fun _ p -> equal_proposal_state p.state Approved)
      with
      | Some (i, _) -> i
      | None -> -1
    in
    if approved_idx >= 0 && approved_idx < 4
    then
      Some
        { title = "What a trusting bunch"
        ; body =
            sprintf
              "First mission got approved within %d %s"
              (approved_idx + 1)
              (if approved_idx = 0 then "try" else "tries")
        }
    else None
;;

let playing_the_long_con t =
  List.find_mapi (tail t.missions) ~f:(fun idx me ->
    if List.length me.evil_on_team = 1 && me.m.fails_required < 2 && me.m.num_fails = 0
    then
      Some
        { title = "Playing the long con"
        ; body =
            sprintf
              "%s stayed undercover instead of failing mission %d"
              (List.hd_exn me.evil_on_team)
              (idx + 2)
        }
    else None)
;;

let universal_acclaim t =
  (* Deliberate divergence from the original JS, which only scanned all but the last
     proposal of each mission. A unanimous proposal is always the approved, last one (the
     server appends a new proposal only after a rejection), so the JS badge was dead code.
     Scan ALL proposals instead. *)
  let num_players = List.length t.game.players in
  List.find_mapi t.missions ~f:(fun idx me ->
    List.find_map me.m.proposals ~f:(fun p ->
      if List.length p.votes = num_players
      then
        Some
          { title = "Universal acclaim"
          ; body =
              sprintf "Everyone voted for %s's proposal on mission %d" p.proposer (idx + 1)
          }
      else None))
;;

let still_waiting t =
  let good, bad =
    List.fold t.missions ~init:([], []) ~f:(fun (g, b) me ->
      match me.m.state with
      | Success -> g @ me.evil_on_team, b
      | Fail -> g, b @ me.evil_on_team
      | M_pending -> g, b)
  in
  match difference good bad with
  | candidate :: _ ->
    Some
      { title = "Biding my time"
      ; body = sprintf "%s was evil, but only went on successful missions" candidate
      }
  | [] -> None
;;

let assassination_analysis t =
  match t.outcome.assassinated with
  | None -> None
  | Some target ->
    if is_evil t target
    then Some { title = "Stabbed in the back"; body = "Evil player got assassinated" }
    else (
      match Map.find t.roles_by_name target with
      | Some ra when str_eq ra.role "PERCIVAL" ->
        Some { title = "Taking a bullet for you"; body = "Percival got assassinated" }
      | _ -> None)
;;

let reversal_of_fortune t =
  match
    ( List.nth t.missions 0
    , List.nth t.missions 1
    , List.nth t.missions 2
    , List.nth t.missions 3
    , List.nth t.missions 4 )
  with
  | Some m0, Some m1, Some m2, Some m3, Some m4
    when equal_mission_state m0.m.state m1.m.state
         && (not (equal_mission_state m1.m.state m2.m.state))
         && equal_mission_state m2.m.state m3.m.state
         && equal_mission_state m3.m.state m4.m.state ->
    if equal_mission_state m0.m.state Fail && equal_outcome_state t.outcome.state Good_win
    then
      Some
        { title = "Reversal of fortune"
        ; body = "Good won the game despite losing first two missions"
        }
    else if equal_mission_state m0.m.state Success
    then
      Some
        { title = "Stunning comeback"
        ; body = "Evil won the game despite losing first two missions"
        }
    else None
  | _ -> None
;;

let same_team t =
  let proposals = List.concat_map t.missions ~f:(fun me -> me.m.proposals) in
  let last_team = ref [] in
  let count = ref 0 in
  With_return.with_return (fun { return } ->
    List.iter proposals ~f:(fun p ->
      if team_eq !last_team p.team
      then incr count
      else (
        if !count >= 3 then return ();
        last_team := p.team;
        count := 1)));
  if !count >= 3
  then
    Some
      { title = "We made up our minds"
      ; body =
          sprintf
            "The team of %s got proposed %d times in a row"
            (join_with_and !last_team)
            !count
      }
  else None
;;

let player_doesnt_go_on_missions t =
  let completed = t.completed_missions in
  if List.is_empty completed
  then None
  else (
    let players =
      List.fold (initial completed) ~init:t.game.players ~f:(fun acc me ->
        difference acc me.m.team)
    in
    match players with
    | [] -> None
    | player :: _ ->
      let last = List.last_exn completed in
      if mem last.m.team player
      then
        Some
          { title = "Here to save the day"
          ; body = sprintf "%s did not go on any mission except the last one" player
          }
      else
        Some
          { title = "Put me in, coach!"
          ; body = sprintf "%s did not go on a single mission" player
          })
;;

let almost_lost t =
  if not (equal_outcome_state t.outcome.state Good_win)
  then None
  else (
    let players = Array.of_list t.game.players in
    let nplayers = Array.length players in
    let player_index name =
      Array.findi players ~f:(fun _ p -> str_eq p name)
      |> Option.map ~f:fst
      |> Option.value ~default:(-1)
    in
    let num_fails = ref 0 in
    List.find_mapi t.missions ~f:(fun idx me ->
      let result =
        match List.last me.m.proposals with
        | Some last_p when !num_fails = 2 && List.length me.m.proposals < 5 ->
          let num_behind = 5 - List.length me.m.proposals in
          let proposer = ref last_p.proposer in
          let players_behind = ref [] in
          for _ = 0 to num_behind - 1 do
            let pidx = player_index !proposer in
            proposer := players.((pidx + 1) % nplayers);
            players_behind := !proposer :: !players_behind
          done;
          if not (List.for_all !players_behind ~f:(fun p -> is_evil t p))
          then
            Some
              { title = "By the skin of our teeth"
              ; body =
                  sprintf
                    "Good came close to losing on mission %d when evil team had hammer"
                    (idx + 1)
              }
          else None
        | Some _ | None -> None
      in
      if equal_mission_state me.m.state Fail then incr num_fails;
      result))
;;

let psychic_powers t =
  let players = String.Table.create () in
  List.iter t.game.players ~f:(fun name ->
    Hashtbl.set players ~key:name ~data:{ name; good_proposals = 0; bad_proposals = 0 });
  List.iter t.missions ~f:(fun me ->
    List.iter me.m.proposals ~f:(fun p ->
      match Hashtbl.find players p.proposer with
      | None -> ()
      | Some ps ->
        let evil_count = List.count p.team ~f:(fun n -> is_evil t n) in
        if evil_count < me.m.fails_required
        then ps.good_proposals <- ps.good_proposals + 1
        else ps.bad_proposals <- ps.bad_proposals + 1));
  (* Match the JS: iterate in player (seat) order and use a stable sort, so ties resolve
     to the earliest-seated player as Object.values(keyBy(...)).sort() does. *)
  let perfect =
    List.filter_map t.game.players ~f:(Hashtbl.find players)
    |> List.filter ~f:(fun p -> p.bad_proposals = 0 && p.good_proposals >= 2)
    |> List.stable_sort ~compare:(fun a b ->
      Int.compare b.good_proposals a.good_proposals)
  in
  match perfect with
  | top :: _ ->
    Some
      { title = "Actual Merlin"
      ; body =
          sprintf
            "%s proposed %d perfect teams and no bad teams"
            top.name
            top.good_proposals
      }
  | [] -> None
;;

let morgana_trusts_merlin t =
  role_trusts_role t "MORGANA" "MERLIN" ~gen:(fun msg ->
    { title = "Cover blown"; body = sprintf "Morgana %s with Merlin" msg })
;;

let merlin_trusts_morgana t =
  role_trusts_role t "MERLIN" "MORGANA" ~gen:(fun msg ->
    { title = "Good luck, Percival"; body = sprintf "Merlin %s with Morgana" msg })
;;

let percival_trusts_morgana t =
  role_trusts_role t "PERCIVAL" "MORGANA" ~gen:(fun msg ->
    { title = "Got you fooled"; body = sprintf "Percival %s with Morgana" msg })
;;

let unanimous_rejection t =
  List.find_mapi t.missions ~f:(fun idx me ->
    List.find_map me.m.proposals ~f:(fun p ->
      if equal_proposal_state p.state Rejected && List.is_empty p.votes
      then
        Some
          { title = "Hard pass"
          ; body =
              sprintf
                "%s's proposal on mission %d was rejected by everyone"
                p.proposer
                (idx + 1)
          }
      else None))
;;

let lone_wolf t =
  List.find_mapi t.missions ~f:(fun idx me ->
    if List.length me.evil_on_team = 1
       && me.m.num_fails = 1
       && equal_mission_state me.m.state Fail
    then
      Some
        { title = "Lone wolf"
        ; body =
            sprintf
              "%s single-handedly failed mission %d"
              (List.hd_exn me.evil_on_team)
              (idx + 1)
        }
    else None)
;;

let hammer_time t =
  List.find_mapi t.missions ~f:(fun idx me ->
    match List.length me.m.proposals, List.nth me.m.proposals 4 with
    | 5, Some p4 when equal_proposal_state p4.state Approved ->
      Some
        { title = "Hammer time"
        ; body = sprintf "Mission %d went to the 5th proposal (hammer)" (idx + 1)
        }
    | _ -> None)
;;

let oberon_gambit t =
  match name_of_role t "OBERON" with
  | None -> None
  | Some oberon ->
    List.find_mapi t.missions ~f:(fun idx me ->
      if mem me.evil_on_team oberon
         && List.exists me.evil_on_team ~f:(fun p -> not (str_eq p oberon))
      then
        Some
          { title = "Oberon's gambit"
          ; body =
              sprintf
                "Oberon went on mission %d with evil allies who couldn't see them"
                (idx + 1)
          }
      else None)
;;

let evil_everywhere t =
  let completed = t.completed_missions in
  if List.length completed >= 3
     && List.for_all completed ~f:(fun me -> not (List.is_empty me.evil_on_team))
  then
    Some
      { title = "Omnipresent evil"; body = "Every mission had at least one evil player" }
  else None
;;

let loyal_to_a_fault t =
  let non_hammer =
    List.concat_map t.missions ~f:(fun me ->
      List.filteri me.m.proposals ~f:(fun idx p ->
        idx < 4 && not (equal_proposal_state p.state Pending)))
  in
  if List.length non_hammer < 3
  then None
  else
    List.find_map t.game.players ~f:(fun player ->
      if List.for_all non_hammer ~f:(fun p -> mem p.votes player)
      then
        Some
          { title = "Yes-man"; body = sprintf "%s approved every single proposal" player }
      else None)
;;

let contrarian t =
  let approved_non_hammer =
    List.concat_map t.missions ~f:(fun me ->
      List.filteri me.m.proposals ~f:(fun idx p ->
        idx < 4 && equal_proposal_state p.state Approved))
  in
  if List.length approved_non_hammer < 2
  then None
  else
    List.find_map t.game.players ~f:(fun player ->
      if List.for_all approved_non_hammer ~f:(fun p -> not (mem p.votes player))
      then
        Some
          { title = "Contrarian"
          ; body = sprintf "%s rejected every proposal that got approved" player
          }
      else None)
;;

let one_man_army t =
  let failed =
    List.filter t.missions ~f:(fun me -> equal_mission_state me.m.state Fail)
  in
  if List.length failed < 2
  then None
  else (
    let first = List.hd_exn failed in
    let evil_on_all =
      List.filter first.evil_on_team ~f:(fun p ->
        List.for_all failed ~f:(fun me -> mem me.evil_on_team p))
    in
    if List.length evil_on_all = 1
       && List.for_all failed ~f:(fun me -> List.length me.evil_on_team = 1)
    then
      Some
        { title = "One-man army"
        ; body =
            sprintf
              "%s was the only evil player on every failed mission"
              (List.hd_exn evil_on_all)
        }
    else None)
;;

let evil_ghost t =
  let completed = t.completed_missions in
  if List.length completed < 3
  then None
  else
    List.find_map t.evil_players ~f:(fun player ->
      if List.for_all completed ~f:(fun me -> not (mem me.m.team player))
      then
        Some
          { title = "Ghost"
          ; body = sprintf "%s was evil but never went on a single mission" player
          }
      else None)
;;

let trojan_horse t =
  List.find_mapi t.missions ~f:(fun idx me ->
    let e = List.length me.evil_on_team in
    let total = List.length me.m.team in
    if e > 0 && e * 2 > total
    then
      Some
        { title = "Trojan horse"
        ; body =
            sprintf "Mission %d had a majority evil team (%d of %d)" (idx + 1) e total
        }
    else None)
;;

let close_call t =
  List.find_mapi t.missions ~f:(fun idx me ->
    if equal_mission_state me.m.state Success
       && (not (List.is_empty me.evil_on_team))
       && me.m.num_fails = 0
    then
      Some
        { title = "Dodged a bullet"
        ; body =
            sprintf
              "Mission %d succeeded despite %s being on the team"
              (idx + 1)
              (join_with_and me.evil_on_team)
        }
    else None)
;;

let rejection_streak t =
  let max_streak = ref 0 in
  let streak = ref 0 in
  List.iter t.missions ~f:(fun me ->
    List.iter me.m.proposals ~f:(fun p ->
      match p.state with
      | Rejected ->
        incr streak;
        max_streak := Int.max !max_streak !streak
      | Approved -> streak := 0
      | Pending -> ()));
  if !max_streak >= 4
  then
    Some
      { title = "Nobody likes anyone"
      ; body = sprintf "%d proposals were rejected in a row" !max_streak
      }
  else None
;;

let big_team_betrayal t =
  let completed = t.completed_missions in
  if List.length completed < 3
  then None
  else (
    let max_team_size =
      List.fold completed ~init:0 ~f:(fun acc me -> Int.max acc me.m.team_size)
    in
    match
      List.findi t.missions ~f:(fun _ me ->
        me.m.team_size = max_team_size && equal_mission_state me.m.state Fail)
    with
    | Some (idx, me) ->
      Some
        { title = "Et tu, Brute?"
        ; body =
            sprintf
              "The largest mission (%d players) on mission %d was failed"
              me.m.team_size
              (idx + 1)
        }
    | None -> None)
;;

let proposer_curse t =
  let counts = String.Table.create () in
  (* Preserve first-rejection encounter order (JS object insertion order) so a stable sort
     resolves ties to the proposer who was rejected first, matching Object.entries(...). *)
  let order = Queue.create () in
  List.iter t.missions ~f:(fun me ->
    List.iter me.m.proposals ~f:(fun p ->
      if equal_proposal_state p.state Rejected
      then (
        if not (Hashtbl.mem counts p.proposer) then Queue.enqueue order p.proposer;
        Hashtbl.update counts p.proposer ~f:(function
          | None -> 1
          | Some n -> n + 1))));
  let sorted =
    Queue.to_list order
    |> List.map ~f:(fun player -> player, Hashtbl.find_exn counts player)
    |> List.stable_sort ~compare:(fun (_, a) (_, b) -> Int.compare b a)
  in
  match sorted with
  | (player, count) :: _ when count >= 3 ->
    Some
      { title = "Cursed proposer"
      ; body = sprintf "%s had %d proposals rejected" player count
      }
  | _ -> None
;;

let last_stand t =
  let states = List.map t.missions ~f:(fun me -> me.m.state) in
  match List.nth states 4 with
  | Some M_pending | None -> None
  | Some _ ->
    let first4 = List.take states 4 in
    let successes = List.count first4 ~f:(equal_mission_state Success) in
    let fails = List.count first4 ~f:(equal_mission_state Fail) in
    if successes = 2 && fails = 2
    then
      Some
        { title = "Last stand"; body = "The score was 2-2 going into the final mission" }
    else None
;;

let perfect_assassin t =
  match t.outcome.assassinated with
  | Some target when equal_outcome_state t.outcome.state Evil_win ->
    (match Map.find t.roles_by_name target with
     | Some ra when str_eq ra.role "MERLIN" ->
       Some
         { title = "Bullseye"
         ; body = "The assassin correctly identified and killed Merlin"
         }
     | _ -> None)
  | _ -> None
;;

let oberon_saboteur t =
  match name_of_role t "OBERON" with
  | None -> None
  | Some oberon ->
    List.find_mapi t.missions ~f:(fun idx me ->
      if equal_mission_state me.m.state Fail
         && mem me.evil_on_team oberon
         && List.length me.evil_on_team > 1
      then
        Some
          { title = "Who did that?"
          ; body =
              sprintf
                "Oberon failed mission %d alongside evil allies who didn't know they \
                 were there"
                (idx + 1)
          }
      else None)
;;

let all_aboard t =
  let completed = t.completed_missions in
  if List.length completed < 3
  then None
  else (
    let on_missions =
      List.concat_map completed ~f:(fun me -> me.m.team) |> String.Set.of_list
    in
    if Set.length on_missions = List.length t.game.players
    then Some { title = "All aboard"; body = "Every player went on at least one mission" }
    else None)
;;

let flip_flopper t =
  List.find_mapi t.missions ~f:(fun mission_idx me ->
    let n = List.length me.m.proposals in
    With_return.with_return (fun { return } ->
      for i = 1 to n - 1 do
        let current = List.nth_exn me.m.proposals i in
        for j = 0 to i - 1 do
          let previous = List.nth_exn me.m.proposals j in
          if equal_proposal_state previous.state Rejected
             && equal_proposal_state current.state Approved
             && team_eq current.team previous.team
          then (
            let flippers =
              List.filter current.votes ~f:(fun v -> not (mem previous.votes v))
            in
            match flippers with
            | flipper :: _ ->
              return
                (Some
                   { title = "Flip-flopper"
                   ; body =
                       sprintf
                         "%s rejected then approved the same team on mission %d"
                         flipper
                         (mission_idx + 1)
                   })
            | [] -> ())
        done
      done;
      None))
;;

(* Order matches the JS object literal, since [getBadges] uses [Object.values]. *)
let all_badges : (t -> badge option) list =
  [ merlin_sends_evil_team
  ; merlin_proposes_evil_team
  ; running_scared
  ; failure_to_coordinate
  ; perfect_coordination
  ; forces_of_evil
  ; no_evil_players_on_missions
  ; clean_sweep
  ; trust_you
  ; trusting_bunch
  ; playing_the_long_con
  ; universal_acclaim
  ; still_waiting
  ; assassination_analysis
  ; reversal_of_fortune
  ; same_team
  ; player_doesnt_go_on_missions
  ; almost_lost
  ; psychic_powers
  ; morgana_trusts_merlin
  ; merlin_trusts_morgana
  ; percival_trusts_morgana
  ; unanimous_rejection
  ; lone_wolf
  ; hammer_time
  ; oberon_gambit
  ; evil_everywhere
  ; loyal_to_a_fault
  ; contrarian
  ; one_man_army
  ; evil_ghost
  ; trojan_horse
  ; close_call
  ; rejection_streak
  ; big_team_betrayal
  ; proposer_curse
  ; last_stand
  ; perfect_assassin
  ; oberon_saboteur
  ; all_aboard
  ; flip_flopper
  ]
;;

let get_badges (t : t) : badge list = List.filter_map all_badges ~f:(fun f -> f t)
