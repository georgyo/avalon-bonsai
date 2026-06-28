open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Types
module M = State.Model
module D = State.Derived
module N = Vdom.Node
module A = Vdom.Attr

(** The view layer: a faithful port of the Vue/Vuetify components, rendered with plain
    Vdom + CSS (see web/style.css) and FontAwesome / MDI icon fonts loaded in index.html.
    Every game component guards on [D.game]/[D.role] being present, since Bonsai evaluates
    all sub-views regardless of which one is displayed. *)

let run (e : unit Effect.t) : unit = Effect.Expert.handle_non_dom_event_exn e
let eff f = Effect.of_thunk f
let textf fmt = Printf.ksprintf N.text fmt
let on_enter e = A.on_keyup (fun ev -> if ev##.keyCode = 13 then e else Effect.return ())

let swap_at (l : 'a list) i =
  match List.nth l i, List.nth l (i + 1) with
  | Some a, Some b -> List.mapi l ~f:(fun j x -> if j = i then b else if j = i + 1 then a else x)
  | _ -> l
;;

(* ---- Vuetify-ish building blocks ---- *)
let div ?(cls = []) children = N.div ~attrs:[ A.classes cls ] children
let spanc ?(cls = []) children = N.span ~attrs:[ A.classes cls ] children
let card ?(cls = []) children = N.div ~attrs:[ A.classes ("v-card" :: cls) ] children
let card_title ?(cls = []) children = N.div ~attrs:[ A.classes ("v-card-title" :: cls) ] children
let card_text ?(cls = []) children = N.div ~attrs:[ A.classes ("v-card-text" :: cls) ] children

let btn ?(cls = []) ?(disabled = false) ?(loading = false) ~on_click children =
  let attrs =
    [ A.classes ("v-btn" :: cls); A.on_click (fun _ -> on_click) ]
    @ (if disabled || loading then [ A.disabled' true ] else [])
  in
  N.button ~attrs (if loading then [ N.span ~attrs:[ A.class_ "spinner" ] [] ] else children)
;;

let fa ?(color = "") kind name =
  let style = if String.is_empty color then [] else [ A.style (Css_gen.color (`Name color)) ] in
  N.create "i" ~attrs:(A.classes [ kind; name ] :: style) []
;;

let mdi name = N.create "i" ~attrs:[ A.classes [ "mdi"; "mdi-" ^ name ] ] []
let team_icon (t : team) = match t with Good -> fa "fab" "fa-old-republic" | Evil -> fa ~color:"red" "fab" "fa-empire"

let overlay ?(fullscreen = false) ~on_close children =
  N.div
    ~attrs:[ A.classes [ "overlay" ]; A.on_click (fun _ -> on_close) ]
    [ N.div
        ~attrs:[ A.classes (if fullscreen then [ "overlay-card"; "fullscreen" ] else [ "overlay-card" ]); A.on_click (fun _ -> Effect.Many []) ]
        children
    ]
;;

let text_field ?(cls = []) ?(typ = "text") ?(placeholder = "") ?(extra = []) ~value ~on_input () =
  N.input
    ~attrs:
      ([ A.classes ("text-field" :: cls); A.type_ typ; A.placeholder placeholder
       ; A.value_prop value; A.on_input (fun _ s -> on_input s)
       ]
       @ extra)
    ()
;;

let field_error error = if String.is_empty error then N.none else N.div ~attrs:[ A.class_ "field-error" ] [ N.text error ]

(* ============================ StatsDisplay ============================ *)
let stats_display (stats : stats option) (global : stats option) =
  let s = Option.value stats ~default:empty_stats in
  let games = s.games and good = s.good and wins = s.wins and good_wins = s.good_wins in
  let evil = games - good in
  let evil_wins = wins - good_wins in
  let pct n d = if d > 0 then sprintf "%d%%" (Float.to_int (100. *. Float.of_int n /. Float.of_int d)) else "N/A" in
  let row label a b c = N.tr [ N.td ~attrs:[ A.class_ "fw" ] [ N.text label ]; N.td [ N.text a ]; N.td [ N.text b ]; N.td [ N.text c ] ] in
  let playtime =
    let secs = s.playtime_seconds in
    let hours = Float.of_int secs /. 60. /. 60. in
    if Float.(hours > 1.) then sprintf "%.1f hours" hours
    else if secs > 60 then sprintf "%d minutes" (secs / 60)
    else "Not enough"
  in
  let global_rows =
    match global with
    | Some g when g.games > 0 ->
      [ N.tr
          [ N.td ~attrs:[ A.class_ "fw" ] [ N.text "All Users" ]
          ; N.td [ N.text (pct g.good_wins g.games) ]
          ; N.td [ N.text (pct (g.games - g.good_wins) g.games) ]
          ; N.td []
          ]
      ]
    | _ -> []
  in
  div ~cls:[ "col"; "center"; "stats-wrap" ]
    [ N.table
        [ N.thead [ N.tr ~attrs:[ A.class_ "stats-header" ] [ N.td []; N.td [ N.text "Good" ]; N.td [ N.text "Evil" ]; N.td [ N.text "Total" ] ] ]
        ; N.tbody
            ([ row "Games" (Int.to_string good) (Int.to_string evil) (Int.to_string games)
             ; row "Wins" (Int.to_string good_wins) (Int.to_string evil_wins) (Int.to_string wins)
             ; row "Losses" (Int.to_string (good - good_wins)) (Int.to_string (evil - evil_wins)) (Int.to_string (games - wins))
             ; row "Win Rate" (pct good_wins good) (pct evil_wins evil) (pct wins games)
             ]
             @ global_rows)
        ]
    ; div ~cls:[ "pt-2" ] [ N.div [ textf "Total Playtime: %s" playtime ] ]
    ]
;;

(* ============================ RoleList (selectable, lobby) ============================ *)
let selectable_role_list (local_ graph) =
  let info, set_info = Bonsai.state_opt graph ~sexp_of_model:[%sexp_of: role] in
  let%arr m = State.value () and info = info and set_info = set_info in
  let allow = D.is_admin m in
  let selected = m.selected_roles in
  let item (role : role) =
    let is_sel = Set.mem selected role.name in
    let checkbox =
      if allow
      then N.input ~attrs:[ A.type_ "checkbox"; A.checked_prop is_sel; A.on_click (fun _ -> eff (fun () -> State.toggle_role ~name:role.name ~selected:(not is_sel))) ] ()
      else N.none
    in
    N.create "li" ~attrs:[ A.class_ "v-list-item" ]
      [ div ~cls:[ "li-prepend" ] [ checkbox; team_icon role.team ]
      ; div ~cls:[ "li-title" ] [ N.text role.name ]
      ; btn ~cls:[ "icon-btn" ] ~on_click:(set_info (Some role)) [ mdi "information" ]
      ]
  in
  N.div
    [ N.create "ul" ~attrs:[ A.class_ "v-list" ] (List.map Avalonlib.selectable_roles ~f:item)
    ; (match info with
       | None -> N.none
       | Some role ->
         overlay ~on_close:(set_info None)
           [ card_title ~cls:[ "title-bar" ] [ team_icon role.team; N.h3 [ N.text role.name ] ]; card_text [ N.text role.description ] ])
    ]
;;

(* static role display (in-game participants tab) *)
let role_list_view (roles : role list) =
  N.create "ul" ~attrs:[ A.class_ "v-list" ]
    (List.map roles ~f:(fun (role : role) ->
       N.create "li" ~attrs:[ A.class_ "v-list-item"; A.create "title" role.description ]
         [ div ~cls:[ "li-prepend" ] [ team_icon role.team ]; div ~cls:[ "li-title" ] [ N.text role.name ] ]))
;;

(* ============================ MissionSummaryTable ============================ *)
let mission_summary_table ~players ~(missions : mission list) ~(roles : role_assignment list option) ~(mission_votes : bool String.Map.t list option) =
  let proposals_of (m : mission) = List.filter m.proposals ~f:(fun p -> not (List.is_empty p.team)) in
  let cell_for player (proposal : proposal) =
    N.create "span" ~attrs:[ A.class_ "fa-layers" ]
      (List.filter_opt
         [ (if String.equal proposal.proposer player then Some (fa ~color:"gold" "fas" "fa-circle") else None)
         ; (if List.mem proposal.team player ~equal:String.equal then Some (fa ~color:"#629ec1" "far" "fa-circle") else None)
         ; (match proposal.state with
            | Pending -> None
            | _ -> Some (if List.mem proposal.votes player ~equal:String.equal then fa ~color:"green" "far" "fa-thumbs-up" else fa ~color:"#ed1515" "far" "fa-thumbs-down"))
         ])
  in
  let row player =
    let role_cell =
      match roles with
      | Some rs -> let r = List.find rs ~f:(fun r -> String.equal r.name player) in [ N.td ~attrs:[ A.class_ "role" ] [ N.text (Option.value_map r ~default:"" ~f:(fun r -> r.role)) ] ]
      | None -> []
    in
    let mission_cells =
      List.concat_mapi missions ~f:(fun midx m ->
        let prop_cells = List.map (proposals_of m) ~f:(fun p -> N.td [ cell_for player p ]) in
        let result_cell =
          match mission_votes with
          | Some mv ->
            if List.mem m.team player ~equal:String.equal
            then (
              let v = Option.bind (List.nth mv midx) ~f:(fun map -> Map.find map player) in
              [ N.td ~attrs:[ A.class_ "mission-result" ] [ (match v with Some true -> fa ~color:"green" "fas" "fa-check-circle" | _ -> fa ~color:"red" "fas" "fa-times-circle") ] ])
            else [ N.td ~attrs:[ A.class_ "mission-result" ] [] ]
          | None -> []
        in
        prop_cells @ result_cell)
    in
    N.tr ([ N.td ~attrs:[ A.class_ "player-name" ] [ spanc ~cls:[ "fw" ] [ N.text player ] ] ] @ role_cell @ mission_cells)
  in
  N.table ~attrs:[ A.class_ "summary-table" ] (List.map players ~f:row)
;;

(* ============================ GameAchievements ============================ *)
let achievements (g : Game.t) =
  match Game.outcome g with
  | Some o when not (equal_outcome_state o.state Canceled) ->
    let badges = Analysis.get_badges (Analysis.create g.data ~role_map:Avalonlib.role_map) in
    if List.is_empty badges
    then N.none
    else
      div ~cls:[ "pt-6" ]
        (div ~cls:[ "text-h4"; "center" ] [ N.text "Achievements" ]
         :: List.map badges ~f:(fun b ->
              div ~cls:[ "pt-2" ]
                [ card ~cls:[ "achievement" ]
                    [ card_title ~cls:[ "title-bar" ] [ fa ~color:"gold" "fas" "fa-trophy"; div ~cls:[ "text-h6" ] [ N.text b.title ] ]; card_text [ N.text b.body ] ]
                ]))
  | _ -> N.none
;;

(* ============================ UserLogin ============================ *)
let user_login (local_ graph) =
  let tab, set_tab = Bonsai.state "email" graph in
  let email, set_email = Bonsai.state "" graph in
  let error, set_error = Bonsai.state "" graph in
  let submitting, set_submitting = Bonsai.state false graph in
  let submitted, set_submitted = Bonsai.state false graph in
  let%arr m = State.value ()
  and tab = tab and set_tab = set_tab
  and email = email and set_email = set_email
  and error = error and set_error = set_error
  and submitting = submitting and set_submitting = set_submitting
  and submitted = submitted and set_submitted = set_submitted in
  let submit_email =
    eff (fun () ->
      run (set_submitting true);
      run (set_error "");
      State.submit_email_addr email
        ~on_ok:(fun () -> run (set_submitted true); run (set_submitting false))
        ~on_err:(fun e -> run (set_error e); run (set_submitting false)))
  in
  let anon = eff (fun () -> run (set_error ""); State.sign_in_anonymously ~on_err:(fun e -> run (set_error e)) ()) in
  card ~cls:[ "welcome" ]
    [ div ~cls:[ "col"; "center" ]
        [ (match m.confirming_email_error with
           | Some e -> N.div ~attrs:[ A.class_ "alert-error" ] [ textf "%s Please try logging in again." e ]
           | None -> N.none)
        ; div ~cls:[ "welcome-title" ]
            [ spanc ~cls:[ "welcome-heading" ] [ N.text "Avalon: The Resistance "; spanc ~cls:[ "thin" ] [ N.text "Online" ] ]
            ; N.p ~attrs:[ A.class_ "mt-4" ] [ spanc ~cls:[ "subtitle" ] [ N.text "A game of social deduction for 5 to 10 people, now on desktop and mobile." ] ]
            ]
        ; div ~cls:[ "tabs" ]
            [ btn ~cls:(if String.equal tab "email" then [ "tab"; "tab-active" ] else [ "tab" ]) ~on_click:(set_tab "email") [ N.text "Email" ]
            ; btn ~cls:(if String.equal tab "anonymous" then [ "tab"; "tab-active" ] else [ "tab" ]) ~on_click:(set_tab "anonymous") [ N.text "Anonymous" ]
            ]
        ; (if String.equal tab "email"
           then
             div ~cls:[ "pa-4"; "login-form" ]
               (if not submitted
                then
                  [ text_field ~typ:"email" ~placeholder:"Email Address" ~value:email ~on_input:(fun s -> set_email s) ~extra:[ on_enter submit_email ] ()
                  ; field_error error
                  ; btn ~loading:submitting ~on_click:submit_email [ N.text "Login" ]
                  ]
                else
                  [ card ~cls:[ "info-card" ] [ card_text ~cls:[ "center" ] [ N.p [ N.text "Check your email for the verification link" ] ] ]
                  ; btn ~cls:[ "mt-4" ] ~on_click:(set_submitted false) [ N.text "Try Again" ]
                  ])
           else div ~cls:[ "pa-4" ] [ btn ~on_click:anon [ N.text "Login" ]; field_error error ])
        ]
    ]
;;

(* ============================ LobbySelect ============================ *)
let lobby_select (local_ graph) =
  let name_default = Option.value_map (State.model ()).user ~default:"" ~f:(fun u -> u.name) in
  let name, set_name = Bonsai.state name_default graph in
  let lobby, set_lobby = Bonsai.state "" graph in
  let error, set_error = Bonsai.state "" graph in
  let show_lobby_input, set_show_lobby_input = Bonsai.state false graph in
  let creating, set_creating = Bonsai.state false graph in
  let joining, set_joining = Bonsai.state false graph in
  let%arr m = State.value ()
  and name = name and set_name = set_name
  and lobby = lobby and set_lobby = set_lobby
  and error = error and set_error = set_error
  and show_lobby_input = show_lobby_input and set_show_lobby_input = set_show_lobby_input
  and creating = creating and set_creating = set_creating
  and joining = joining and set_joining = set_joining in
  let do_create =
    eff (fun () ->
      run (set_creating true);
      State.create_lobby ~name ~on_ok:(fun () -> run (set_creating false)) ~on_err:(fun e -> run (set_error e); run (set_creating false)) ())
  in
  let do_join =
    eff (fun () ->
      run (set_joining true);
      State.join_lobby ~name ~lobby ~on_ok:(fun () -> run (set_joining false)) ~on_err:(fun e -> run (set_error e); run (set_joining false)) ())
  in
  N.div ~attrs:[ A.class_ "lobby-select" ]
    [ div ~cls:[ "col"; "center"; "lobby-inner" ]
        ((if not show_lobby_input
          then
            [ text_field ~cls:[ "upper" ] ~placeholder:"Your Name" ~value:name ~on_input:(fun s -> set_name (String.uppercase s)) ()
            ; field_error error
            ; div ~cls:[ "col"; "ga-2"; "lobby-buttons" ]
                [ btn ~disabled:(String.is_empty name) ~loading:creating ~on_click:do_create [ N.text "Create Lobby" ]
                ; btn ~disabled:(String.is_empty name || creating) ~on_click:(set_show_lobby_input true) [ N.text "Join Lobby" ]
                ]
            ]
          else
            [ text_field ~cls:[ "upper" ] ~placeholder:"Lobby" ~value:lobby ~on_input:(fun s -> set_lobby (String.uppercase s)) ~extra:[ on_enter do_join ] ()
            ; field_error error
            ; div ~cls:[ "col"; "ga-2"; "lobby-buttons" ]
                [ btn ~disabled:(String.is_empty lobby) ~loading:joining ~on_click:do_join [ N.text "Join Lobby" ]
                ; btn ~disabled:joining ~on_click:(set_show_lobby_input false) [ N.text "Cancel" ]
                ]
            ])
         @ [ div ~cls:[ "pt-8" ] []; stats_display (Option.bind m.user ~f:(fun u -> u.stats)) m.global_stats ])
    ]
;;

(* ============================ LobbyPlayerList ============================ *)
let lobby_player_list (local_ graph) =
  let kick_target, set_kick_target = Bonsai.state_opt graph ~sexp_of_model:[%sexp_of: string] in
  let%arr m = State.value () and kick_target = kick_target and set_kick_target = set_kick_target in
  let can_reorder = D.is_admin m && not (D.is_game_in_progress m) in
  let admin_name = Option.value_map (D.admin m) ~default:"" ~f:(fun a -> a.name) in
  let me = D.user_name m in
  let n = List.length m.player_list in
  let item idx player =
    let prepend_icon =
      if String.equal player admin_name then mdi "star"
      else if String.equal player me then mdi "account"
      else mdi "account-outline"
    in
    let reorder =
      if can_reorder
      then
        [ btn ~cls:[ "icon-btn" ] ~disabled:(idx = 0) ~on_click:(eff (fun () -> State.set_player_list (swap_at m.player_list (idx - 1)))) [ mdi "chevron-up" ]
        ; btn ~cls:[ "icon-btn" ] ~disabled:(idx = n - 1) ~on_click:(eff (fun () -> State.set_player_list (swap_at m.player_list idx))) [ mdi "chevron-down" ]
        ]
      else []
    in
    let kick_btn =
      if D.is_admin m && (not (String.equal player me)) && not (D.is_game_in_progress m)
      then [ btn ~cls:[ "icon-btn" ] ~on_click:(set_kick_target (Some player)) [ mdi "close" ] ]
      else []
    in
    N.create "li" ~attrs:[ A.class_ "v-list-item" ]
      ([ div ~cls:[ "li-prepend" ] (reorder @ [ prepend_icon ]); div ~cls:[ "li-title" ] [ N.text player ] ] @ kick_btn)
  in
  N.div
    [ N.create "ul" ~attrs:[ A.class_ "v-list" ] (List.mapi m.player_list ~f:item)
    ; (match kick_target with
       | None -> N.none
       | Some player ->
         overlay ~on_close:(set_kick_target None)
           [ card_title ~cls:[ "title-bar" ] [ N.h3 [ textf "Kick %s?" player ] ]
           ; card_text [ textf "Do you wish to kick %s from the lobby?" player ]
           ; div ~cls:[ "row"; "actions" ]
               [ btn ~on_click:(eff (fun () -> run (set_kick_target None); State.kick_player player)) [ textf "Kick %s" player ]; btn ~on_click:(set_kick_target None) [ N.text "Cancel" ] ]
           ])
    ]
;;

(* ============================ GameLobby ============================ *)
let game_lobby (local_ graph) =
  let starting, set_starting = Bonsai.state false graph in
  let in_game_log, set_in_game_log = Bonsai.state false graph in
  let players = lobby_player_list graph in
  let roles = selectable_role_list graph in
  let%arr m = State.value ()
  and starting = starting and set_starting = set_starting
  and in_game_log = in_game_log and set_in_game_log = set_in_game_log
  and players = players and roles = roles in
  let num_players = List.length m.player_list in
  let valid_team_size = num_players >= 5 && num_players <= 10 in
  let num_evil = Option.value (Avalonlib.get_num_evil_for_game_size num_players) ~default:0 in
  let lobby_name = Option.value_map m.lobby ~default:"" ~f:(fun l -> l.name) in
  let reason_not_start =
    if num_players < 5 then Some (sprintf "Need at least 5 players! Invite your friends to lobby %s" lobby_name)
    else if num_players > 10 then Some "Cannot start game with more than 10 players"
    else if not (D.is_admin m) then Some (sprintf "Waiting for %s to start game..." (Option.value_map (D.admin m) ~default:"" ~f:(fun a -> a.name)))
    else None
  in
  let start = eff (fun () -> run (set_starting true); State.start_game ~in_game_log ~on_ok:(fun () -> run (set_starting false)) ~on_err:(fun _ -> run (set_starting false)) ()) in
  div ~cls:[ "container" ]
    [ div ~cls:[ "row"; "wrap"; "start" ]
        [ div ~cls:[ "col6" ]
            [ N.p ~attrs:[ A.class_ "label" ] [ N.text "Players" ]
            ; players
            ; (if D.is_admin m && num_players > 2 then N.p ~attrs:[ A.class_ "caption" ] [ N.text "Use the arrows to set seating order" ] else N.none)
            ]
        ; (if valid_team_size then div ~cls:[ "col6" ] [ N.p ~attrs:[ A.class_ "label" ] [ N.text "Special Roles Available" ]; roles ] else N.none)
        ]
    ; (if valid_team_size
       then div ~cls:[ "row"; "center" ] [ N.p ~attrs:[ A.class_ "text-h6"; A.class_ "label" ] [ textf "%d players: %d good, %d evil" num_players (num_players - num_evil) num_evil ] ]
       else N.none)
    ; div ~cls:[ "row"; "center"; "pt-2" ]
        [ (match reason_not_start with
           | None -> btn ~loading:starting ~on_click:start [ mdi "play"; N.text "Start Game" ]
           | Some reason -> card ~cls:[ "info-card" ] [ card_text ~cls:[ "center" ] [ N.text reason ] ])
        ]
    ; N.label ~attrs:[ A.class_ "checkbox-row" ]
        [ N.input ~attrs:[ A.type_ "checkbox"; A.checked_prop in_game_log; A.on_click (fun _ -> set_in_game_log (not in_game_log)) ] (); N.text " In-game log" ]
    ]
;;

(* ============================ GameMissions ============================ *)
let game_missions (local_ graph) =
  let active, set_active = Bonsai.state 0 graph in
  let%arr m = State.value () and active = active and set_active = set_active in
  match D.game m with
  | None -> N.none
  | Some g ->
    let missions = Game.missions g in
    let is_future idx = idx > 0 && (match List.nth missions (idx - 1) with Some prev -> equal_mission_state prev.state M_pending | None -> false) in
    let tab idx (mission : mission) =
      let icon =
        match mission.state with
        | M_pending ->
          N.create "span" ~attrs:[ A.class_ "fa-layers" ]
            [ fa ~color:(if is_future idx then "gray" else "black") "far" "fa-circle"; spanc ~cls:[ "layers-text" ] [ N.text (Int.to_string mission.team_size) ] ]
        | Fail -> fa ~color:"red" "far" "fa-times-circle"
        | Success -> fa ~color:"green" "far" "fa-check-circle"
      in
      btn ~cls:(if active = idx then [ "tab"; "tab-active" ] else [ "tab" ]) ~on_click:(set_active idx) [ icon ]
    in
    let panel idx (mission : mission) =
      let cls = match mission.state with Fail -> "bg-fail" | Success -> "bg-success" | M_pending -> "bg-pending" in
      let header =
        let status =
          if idx = g.current_mission_idx && not (String.equal (Game.phase g) "ASSASSINATION") then "CURRENT"
          else (match mission.state with Success -> "SUCCESS" | Fail -> "FAIL" | M_pending -> "PENDING")
        in
        N.div [ textf "Mission %d: %s" (idx + 1) status; (if mission.num_fails > 0 then textf " (%d %s)" mission.num_fails (if mission.num_fails > 1 then "fails" else "fail") else N.none) ]
      in
      let detail =
        match mission.state with
        | M_pending -> N.div [ textf "Team Size: %d" mission.team_size; (if mission.fails_required > 1 then textf " (%d fails required)" mission.fails_required else N.none) ]
        | _ -> N.div [ textf "Team: %s" (Util.join_with_and mission.team) ]
      in
      let log = if (Game.data g).in_game_log then mission_summary_table ~players:(Game.players g) ~missions:[ mission ] ~roles:None ~mission_votes:None else N.none in
      card ~cls:[ cls; "mission-panel" ] [ card_text ~cls:[ "caption" ] [ header; detail; log ] ]
    in
    N.div
      [ div ~cls:[ "tabs" ] (List.mapi missions ~f:tab)
      ; (match List.nth missions active with Some mission -> panel active mission | None -> N.none)
      ]
;;

(* ============================ GamePlayerList ============================ *)
let game_player_list ~selected ~set_selected (local_ graph) =
  let%arr m = State.value () and selected = selected and set_selected = set_selected in
  match D.game m, D.role m with
  | Some g, role_doc ->
    let me = D.user_name m in
    let phase = Game.phase g in
    let assassin = Option.value_map role_doc ~default:false ~f:(fun r -> r.assassin) in
    let team_size = Option.value_map g.current_mission ~default:1 ~f:(fun mi -> mi.team_size) in
    let max_selected = if String.equal phase "TEAM_PROPOSAL" then team_size else 1 in
    let toggle name =
      let next =
        if List.mem selected name ~equal:String.equal then List.filter selected ~f:(fun x -> not (String.equal x name)) else selected @ [ name ]
      in
      let next = if List.length next > max_selected then List.drop next (List.length next - max_selected) else next in
      set_selected next
    in
    let enable_checkbox name =
      (String.equal phase "TEAM_PROPOSAL" && Option.value_map g.current_proposer ~default:false ~f:(String.equal me))
      || (String.equal phase "ASSASSINATION" && assassin && not (String.equal name me))
    in
    let selected_for_mission name =
      (String.equal phase "PROPOSAL_VOTE" || String.equal phase "MISSION_VOTE")
      && Option.value_map g.current_proposal ~default:false ~f:(fun p -> List.mem p.team name ~equal:String.equal)
    in
    let was_on_last name =
      match phase with
      | "TEAM_PROPOSAL" | "ASSASSINATION" -> Option.value_map (Game.last_proposal g) ~default:false ~f:(fun p -> List.mem p.team name ~equal:String.equal)
      | "PROPOSAL_VOTE" | "MISSION_VOTE" -> Option.value_map g.current_proposal ~default:false ~f:(fun p -> List.mem p.team name ~equal:String.equal)
      | _ -> false
    in
    let has_voted name = String.equal phase "PROPOSAL_VOTE" && Option.value_map g.current_proposal ~default:false ~f:(fun p -> List.mem p.votes name ~equal:String.equal) in
    let waiting name = String.equal phase "PROPOSAL_VOTE" && not (Option.value_map g.current_proposal ~default:false ~f:(fun p -> List.mem p.votes name ~equal:String.equal)) in
    let approved name =
      if String.equal phase "TEAM_PROPOSAL" || String.equal phase "ASSASSINATION" then Option.value_map (Game.last_proposal g) ~default:false ~f:(fun p -> List.mem p.votes name ~equal:String.equal)
      else if String.equal phase "MISSION_VOTE" then Option.value_map g.current_proposal ~default:false ~f:(fun p -> List.mem p.votes name ~equal:String.equal)
      else false
    in
    let rejected name =
      if String.equal phase "TEAM_PROPOSAL" || String.equal phase "ASSASSINATION" then Option.value_map (Game.last_proposal g) ~default:false ~f:(fun p -> not (List.mem p.votes name ~equal:String.equal))
      else if String.equal phase "MISSION_VOTE" then Option.value_map g.current_proposal ~default:false ~f:(fun p -> not (List.mem p.votes name ~equal:String.equal))
      else false
    in
    let crown_color = if g.current_proposal_idx < 4 then "#fcfc00" else "#cc0808" in
    let status_icons name =
      let icons =
        List.filter_opt
          [ (if was_on_last name then Some (fa ~color:"#629ec1" "far" "fa-circle") else None)
          ; (if waiting name then Some (fa ~color:"#4c4c4c" "fas" "fa-ellipsis-h")
             else if has_voted name then Some (fa ~color:"#4c4c4c" "fas" "fa-vote-yea")
             else if approved name then Some (fa ~color:"green" "far" "fa-thumbs-up")
             else if rejected name then Some (fa ~color:"#ed1515" "far" "fa-thumbs-down")
             else None)
          ]
      in
      if List.is_empty icons then N.none else N.create "span" ~attrs:[ A.class_ "fa-layers" ] icons
    in
    let item name =
      let checkbox =
        if enable_checkbox name then N.input ~attrs:[ A.type_ "checkbox"; A.checked_prop (List.mem selected name ~equal:String.equal); A.on_click (fun _ -> toggle name) ] ()
        else if selected_for_mission name then N.input ~attrs:[ A.type_ "checkbox"; A.checked_prop true; A.disabled' true ] ()
        else N.none
      in
      let marker =
        if Option.value_map g.current_proposer ~default:false ~f:(String.equal name)
        then N.create "span" ~attrs:[ A.class_ "fa-layers"; A.create "title" (sprintf "%s is proposing the next team" name) ] [ fa ~color:crown_color "fas" "fa-crown"; spanc ~cls:[ "layers-text" ] [ N.text (Int.to_string (g.current_proposal_idx + 1)) ] ]
        else if Option.value_map g.hammer ~default:false ~f:(String.equal name) then fa "fas" "fa-hammer"
        else N.none
      in
      N.create "li" ~attrs:[ A.class_ "v-list-item" ]
        [ div ~cls:[ "li-prepend" ] [ checkbox ]
        ; div ~cls:[ "li-mid" ] [ marker ]
        ; div ~cls:[ "li-title" ] [ N.text name ]
        ; div ~cls:[ "li-append" ] [ status_icons name ]
        ]
    in
    N.create "ul" ~attrs:[ A.class_ "v-list" ] (List.map (Game.players g) ~f:item)
  | None, _ -> N.none
;;

(* ============================ GameParticipants ============================ *)
let game_participants ~selected ~set_selected (local_ graph) =
  let tab, set_tab = Bonsai.state "players" graph in
  let players = game_player_list ~selected ~set_selected graph in
  let%arr m = State.value () and tab = tab and set_tab = set_tab and players = players in
  match D.game m with
  | None -> N.none
  | Some g ->
    let role_objs = List.filter_map (Game.roles g) ~f:(fun r -> Map.find Avalonlib.role_map r) in
    N.div
      [ div ~cls:[ "tabs" ]
          [ btn ~cls:(if String.equal tab "players" then [ "tab"; "tab-active" ] else [ "tab" ]) ~on_click:(set_tab "players") [ N.text "Players" ]
          ; btn ~cls:(if String.equal tab "roles" then [ "tab"; "tab-active" ] else [ "tab" ]) ~on_click:(set_tab "roles") [ N.text "Roles" ]
          ]
      ; (if String.equal tab "players" then players else role_list_view role_objs)
      ]
;;

(* ============================ Action panes ============================ *)
let team_proposal_action ~selected (local_ graph) =
  let proposing, set_proposing = Bonsai.state false graph in
  let%arr m = State.value () and selected = selected and proposing = proposing and set_proposing = set_proposing in
  match D.game m with
  | None -> N.none
  | Some g ->
    let me = D.user_name m in
    let team_size = Option.value_map g.current_mission ~default:0 ~f:(fun mi -> mi.team_size) in
    let valid = List.length selected = team_size in
    let propose = eff (fun () -> run (set_proposing true); State.propose_team selected ~on_err:(fun _ -> run (set_proposing false))) in
    card ~cls:[ "action" ]
      [ card_title ~cls:[ "action-title" ] [ textf "Team Proposal (%d/5)" (g.current_proposal_idx + 1) ]
      ; card_text
          [ (if Option.value_map g.current_proposer ~default:false ~f:(String.equal me)
             then div ~cls:[ "col"; "center" ] [ N.div ~attrs:[ A.class_ "center" ] [ textf "Propose a team of %d" team_size ]; btn ~disabled:(not valid) ~loading:proposing ~on_click:propose [ N.text "Propose Team" ] ]
             else div ~cls:[ "center" ] [ textf "Waiting for %s to propose a team of %d" (Option.value g.current_proposer ~default:"") team_size ])
          ]
      ]
;;

let team_vote_action (local_ graph) =
  let voted, set_voted = Bonsai.state_opt graph ~sexp_of_model:[%sexp_of: bool] in
  let%arr m = State.value () and voted = voted and set_voted = set_voted in
  match D.game m with
  | None -> N.none
  | Some g ->
    let me = D.user_name m in
    let already = Option.value_map g.current_proposal ~default:false ~f:(fun p -> List.mem p.votes me ~equal:String.equal) in
    let proposer_label = if Option.value_map g.current_proposer ~default:false ~f:(String.equal me) then "your" else Option.value g.current_proposer ~default:"" ^ "'s " in
    let team = Option.value_map g.current_proposal ~default:"" ~f:(fun p -> Util.join_with_and p.team) in
    let disabled v = already || (match voted with Some _ -> true | None -> false) && not (Option.value_map voted ~default:false ~f:(Bool.equal v)) in
    let vote v = eff (fun () -> State.vote_team v ~on_ok:(fun () -> run (set_voted (Some v)))) in
    let voted_yes = Option.value_map voted ~default:false ~f:Fn.id in
    let voted_no = Option.value_map voted ~default:false ~f:not in
    card ~cls:[ "action" ]
      [ card_title ~cls:[ "action-title" ] [ textf "Team Proposal Vote (%d/5)" (g.current_proposal_idx + 1) ]
      ; card_text
          [ N.div [ textf "Voting for %s team of %s" proposer_label team ]
          ; div ~cls:[ "row"; "between" ]
              [ btn ~disabled:(disabled true) ~on_click:(vote true) [ (if voted_yes then fa ~color:"green" "fas" "fa-vote-yea" else fa ~color:"green" "far" "fa-thumbs-up"); N.text " Approve" ]
              ; btn ~disabled:(disabled false) ~on_click:(vote false) [ (if voted_no then fa ~color:"red" "fas" "fa-vote-yea" else fa ~color:"red" "far" "fa-thumbs-down"); N.text " Reject" ]
              ]
          ]
      ]
;;

let mission_action (local_ graph) =
  let done_, set_done = Bonsai.state false graph in
  let error, set_error = Bonsai.state "" graph in
  (* reset the optimistic "already submitted" flag whenever the mission changes, so a vote
     on one mission doesn't suppress the buttons on the next *)
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
        (let%arr set_done = set_done in
         fun _ -> set_done false)
      graph
  in
  let%arr m = State.value () and done_ = done_ and set_done = set_done and error = error and set_error = set_error in
  match D.game m with
  | None -> N.none
  | Some g ->
    let me = D.user_name m in
    let on_team = Option.value_map g.current_proposal ~default:false ~f:(fun p -> List.mem p.team me ~equal:String.equal) in
    let already_voted = Option.value_map g.current_mission ~default:false ~f:(fun mi -> List.mem mi.team me ~equal:String.equal) in
    let needs_to_vote = on_team && not already_voted && not done_ in
    let still_waiting =
      match g.current_proposal, g.current_mission with
      | Some p, Some mi -> List.filter (Util.difference p.team mi.team) ~f:(fun n -> not (String.equal n me))
      | _ -> []
    in
    let vote v = eff (fun () -> run (set_done true); run (set_error ""); State.do_mission v ~on_err:(fun _ -> run (set_done false); run (set_error "Vote failed, please try again"))) in
    card ~cls:[ "action" ]
      [ card_title ~cls:[ "action-title" ] [ N.text "Mission in Progress" ]
      ; card_text
          [ (if needs_to_vote
             then
               N.div
                 [ (if String.is_empty error then N.none else N.div ~attrs:[ A.class_ "field-error center" ] [ N.text error ])
                 ; div ~cls:[ "row"; "between" ]
                     [ btn ~on_click:(vote true) [ fa ~color:"green" "fas" "fa-check-circle"; N.text " SUCCESS" ]; btn ~on_click:(vote false) [ fa ~color:"red" "fas" "fa-times-circle"; N.text " FAIL" ] ]
                 ]
             else N.div [ N.text (if List.length still_waiting > 0 then "Waiting for " ^ Util.join_with_and still_waiting else "Waiting for results...") ])
          ]
      ]
;;

let assassination_action ~selected (local_ graph) =
  let assassinating, set_assassinating = Bonsai.state false graph in
  let%arr m = State.value () and selected = selected and assassinating = assassinating and set_assassinating = set_assassinating in
  match D.game m, D.role m with
  | Some _, role_doc ->
    let me = D.user_name m in
    let assassin = Option.value_map role_doc ~default:false ~f:(fun r -> r.assassin) in
    let target = List.hd selected in
    let valid = List.length selected = 1 && Option.value_map target ~default:false ~f:(fun t -> not (String.equal t me)) in
    let label = if valid then "Assassinate " ^ Option.value target ~default:"" else "Select target" in
    let go = eff (fun () -> match target with Some t -> run (set_assassinating true); State.assassinate t ~on_err:(fun _ -> run (set_assassinating false)) | None -> ()) in
    card ~cls:[ "action" ]
      [ card_title ~cls:[ "action-title" ] [ N.text "Assassination Attempt" ]
      ; card_text [ (if assassin then N.div [ btn ~disabled:(not valid) ~loading:assassinating ~on_click:go [ N.text label ] ] else N.div [ N.text "Waiting for target selection" ]) ]
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

(* Only the active action component is instantiated (via [match%sub]); when the phase
   changes Bonsai resets the inactive branch's state, mirroring the original's v-if
   remount semantics (so e.g. a mission "already voted" flag doesn't leak across missions). *)
let action_pane ~selected (local_ graph) =
  let kind =
    let%arr m = State.value () in
    match D.game m with
    | None -> No_action
    | Some g ->
      (match Game.phase g with
       | "TEAM_PROPOSAL" -> Propose
       | "PROPOSAL_VOTE" -> Vote
       | "MISSION_VOTE" -> Mission
       | "ASSASSINATION" -> Assassinate
       | _ -> No_action)
  in
  match%sub kind with
  | Propose -> team_proposal_action ~selected graph
  | Vote -> team_vote_action graph
  | Mission -> mission_action graph
  | Assassinate -> assassination_action ~selected graph
  | No_action -> Bonsai.return N.none
;;

(* ============================ GameBoard ============================ *)
let game_board (local_ graph) =
  let selected, set_selected = Bonsai.state [] graph ~equal:(List.equal String.equal) in
  (* clear the team selection whenever the phase changes (original cleared on phase watch) *)
  let phase =
    let%arr m = State.value () in
    match D.game m with
    | Some g -> Game.phase g
    | None -> ""
  in
  let () =
    Bonsai.Edge.on_change
      phase
      ~equal:String.equal
      ~callback:
        (let%arr set_selected = set_selected in
         fun _ -> set_selected [])
      graph
  in
  let missions = game_missions graph in
  let participants = game_participants ~selected ~set_selected graph in
  let actions = action_pane ~selected graph in
  let%arr missions = missions and participants = participants and actions = actions in
  div ~cls:[ "game-board" ]
    [ div ~cls:[ "game-section" ] [ missions ]; div ~cls:[ "game-section" ] [ participants ]; div ~cls:[ "game-section" ] [ actions ] ]
;;

(* ============================ Toolbar ============================ *)
let view_role_button (local_ graph) =
  let%arr m = State.value () in
  let sheet = m.show_role_sheet in
  let activator = btn ~cls:[ "outlined" ] ~on_click:(eff (fun () -> State.set_show_role_sheet true)) [ mdi "account"; spanc ~cls:[ "role-btn-text" ] [ N.text (D.user_name m) ] ] in
  let sheet_node =
    if not sheet
    then N.none
    else (
      let body =
        if not (D.is_game_in_progress m)
        then card ~cls:[ "sheet" ] [ card_title [ N.div ~attrs:[ A.class_ "fw center" ] [ N.text "When the game starts, you will see your role here." ] ]; card_text [ div ~cls:[ "col"; "center" ] [ N.p [ N.text "Your Stats" ]; stats_display (Option.bind m.user ~f:(fun u -> u.stats)) m.global_stats ] ] ]
        else (
          match D.role m with
          | None -> N.none
          | Some rd ->
            card ~cls:[ "sheet" ]
              [ card_title ~cls:[ "title-bar" ] [ team_icon rd.role.team; spanc ~cls:[ "text-h5" ] [ N.text rd.role.name ] ]
              ; card_text
                  [ N.p [ textf "Your role is %s." rd.role.name ]
                  ; N.p [ textf "You are on the %s team." (team_to_string rd.role.team) ]
                  ; N.p [ N.text rd.role.description ]
                  ; (if rd.assassin then N.p [ N.text "You are also the ASSASSIN! It will be up to you to identify MERLIN if the good team succeeds 3 missions." ] else N.none)
                  ; (if List.is_empty rd.sees then N.p [ N.text "You do not see anyone." ] else N.p [ textf "You see %s." (Util.join_with_and rd.sees) ])
                  ]
              ])
      in
      N.div ~attrs:[ A.class_ "bottom-sheet-overlay"; A.on_click (fun _ -> eff (fun () -> State.set_show_role_sheet false)) ] [ N.div ~attrs:[ A.class_ "bottom-sheet"; A.on_click (fun _ -> Effect.Many []) ] [ body ] ])
  in
  N.div [ activator; sheet_node ]
;;

let quit_button (local_ graph) =
  let dialog, set_dialog = Bonsai.state false graph in
  let%arr m = State.value () and dialog = dialog and set_dialog = set_dialog in
  let in_game = D.is_game_in_progress m in
  let action_desc = if in_game then "Cancel Game" else "Leave Lobby" in
  let confirm = eff (fun () -> run (set_dialog false); if in_game then State.cancel_game () else State.leave_lobby ()) in
  N.div
    [ btn ~cls:[ "quit-btn" ] ~on_click:(set_dialog true) [ mdi "exit-to-app"; spanc ~cls:[ "quit-btn-text" ] [ N.text "Quit" ] ]
    ; (if not dialog then N.none
       else
         overlay ~on_close:(set_dialog false)
           [ card_title ~cls:[ "title-bar" ] [ N.h3 [ textf "%s?" action_desc ] ]
           ; card_text [ N.text ((if in_game then "The current game will be canceled! " else "") ^ "Are you sure you want to proceed?") ]
           ; div ~cls:[ "row"; "actions" ] [ btn ~on_click:confirm [ N.text action_desc ]; btn ~on_click:(set_dialog false) [ N.text "Nevermind" ] ]
           ])
    ]
;;

let game_toolbar (local_ graph) =
  let view_role = view_role_button graph in
  let quit = quit_button graph in
  let%arr m = State.value () and view_role = view_role and quit = quit in
  let lobby_named = match m.lobby with Some l -> not (String.is_empty l.name) | None -> false in
  if lobby_named && Option.is_some m.user
  then
    N.div ~attrs:[ A.class_ "toolbar" ]
      [ div ~cls:[ "row"; "center-v" ] [ mdi "map-marker"; spanc ~cls:[ "fw"; "lobby-name" ] [ N.text (Option.value_map m.lobby ~default:"" ~f:(fun l -> l.name)) ] ]
      ; div ~cls:[ "spacer" ] []
      ; view_role
      ; quit
      ]
  else
    N.div ~attrs:[ A.class_ "toolbar" ]
      [ spanc ~cls:[ "toolbar-email" ] [ N.text (Option.value (Option.bind m.user ~f:(fun u -> u.email)) ~default:"") ]
      ; div ~cls:[ "spacer" ] []
      ; btn ~on_click:(eff State.logout) [ mdi "exit-to-app"; N.text "Logout" ]
      ]
;;

(* ============================ Event modals ============================ *)
let modals (local_ graph) =
  let%arr m = State.value () in
  let close = eff (fun () -> State.set_modal No_modal) in
  match m.modal, D.game m with
  | M.Start_game, _ ->
    overlay ~on_close:Effect.(return ())
      [ card_title ~cls:[ "title-bar" ] [ N.h3 [ N.text "Game Started" ] ]
      ; card_text [ N.p [ N.text "A new game has started. When you are ready, view your secret role." ]; N.p [ N.text "You may also view your role anytime by clicking on your name in the toolbar." ] ]
      ; div ~cls:[ "row"; "actions" ] [ btn ~on_click:(eff (fun () -> State.set_modal No_modal; State.set_show_role_sheet true)) [ N.text "View Role" ] ]
      ]
  | M.Mission_result, Some g ->
    let idx = if g.current_mission_idx < 0 then List.length (Game.missions g) else g.current_mission_idx in
    (match List.nth (Game.missions g) (idx - 1) with
     | None -> N.none
     | Some mission ->
       overlay ~on_close:close
         [ card_title ~cls:[ "title-bar" ]
             [ (match mission.state with
                | Success -> N.div [ fa ~color:"green" "fas" "fa-check-circle"; N.text " Mission Succeeded!" ]
                | _ -> N.div [ fa ~color:"red" "fas" "fa-times-circle"; N.text " Mission Failed!" ])
             ]
         ; card_text [ textf "%s had %s failure %s" (Util.join_with_and mission.team) (if mission.num_fails > 0 then Int.to_string mission.num_fails else "no") (if mission.num_fails = 1 then "vote." else "votes.") ]
         ; div ~cls:[ "row"; "actions" ] [ btn ~on_click:close [ N.text "Close" ] ]
         ])
  | M.End_game, Some g ->
    (match Game.outcome g with
     | None -> N.none
     | Some o ->
       let title = match o.state with Good_win -> "Good wins!" | Evil_win -> "Evil wins!" | Canceled -> "Game Canceled" in
       let role_assignments = List.sort o.roles ~compare:(fun a b -> Int.compare (Avalonlib.role_index a.role) (Avalonlib.role_index b.role)) in
       let missions = List.filter (Game.missions g) ~f:(fun mi -> List.exists mi.proposals ~f:(fun p -> not (equal_proposal_state p.state Pending))) in
       overlay ~fullscreen:true ~on_close:close
         [ card_title ~cls:[ "endgame-title" ] [ spanc ~cls:[ "text-h4"; "fw" ] [ N.text title ] ]
         ; card_text
             [ div ~cls:[ "col"; "center" ]
                 [ N.div ~attrs:[ A.class_ "endgame-message fw" ] [ N.text o.message ]
                 ; (match o.assassinated with
                    | Some a -> N.p [ textf "%s was assassinated by %s" a (Option.value_map (List.find o.roles ~f:(fun r -> r.assassin)) ~default:"" ~f:(fun r -> r.name)) ]
                    | None -> N.none)
                 ; div ~cls:[ "endgame-table-wrap" ] [ mission_summary_table ~players:(Game.players g) ~missions ~roles:(Some role_assignments) ~mission_votes:(Some o.votes) ]
                 ; achievements g
                 ; btn ~cls:[ "mt-6"; "primary" ] ~on_click:close [ N.text "Close" ]
                 ]
             ]
         ])
  | _ -> N.none
;;

(* ============================ App ============================ *)
let app (local_ graph) =
  let login = user_login graph in
  let lobby_sel = lobby_select graph in
  let lobby = game_lobby graph in
  let board = game_board graph in
  let toolbar = game_toolbar graph in
  let modals = modals graph in
  let%arr m = State.value () and login = login and lobby_sel = lobby_sel and lobby = lobby and board = board and toolbar = toolbar and modals = modals in
  let content =
    if not (D.initialized m)
    then div ~cls:[ "container"; "center"; "fill" ] [ N.div ~attrs:[ A.class_ "spinner-lg" ] [] ]
    else if not (D.is_logged_in m)
    then div ~cls:[ "container"; "center" ] [ login ]
    else
      N.div
        [ toolbar
        ; div ~cls:[ "container" ]
            [ (if not (D.is_in_lobby m) then lobby_sel else if not (D.is_game_in_progress m) then lobby else board) ]
        ]
  in
  N.div ~attrs:[ A.class_ "app bg-indigo" ] [ modals; content ]
;;

let run_app () =
  State.init ();
  Bonsai_web.Start.start ~bind_to_element_with_id:"app" app
;;
