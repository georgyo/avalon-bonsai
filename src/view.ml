open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Avalon_core
open Types
module M = State.Model
module D = State.Derived
module N = Vdom.Node
module A = Vdom.Attr

(** The view layer: a faithful port of the Vue/Vuetify components, rendered with [ppx_html]
    markup + the scoped [ppx_css] {!Style} module (see [src/style.ml]) and FontAwesome / MDI
    icon fonts loaded in index.html. Every game component guards on [D.game]/[D.role] being
    present, since Bonsai evaluates all sub-views regardless of which one is displayed.

    A handful of class names are kept as literal (un-hashed) strings because the Playwright
    e2e suite and imperative DOM code select on them: [v-list], [v-list-item], [lobby-name],
    [bottom-sheet] (styled via [:global(...)] in {!Style}), plus the FontAwesome [fa-layers]
    layering helper and the icon-font classes emitted by [fa]/[mdi]. *)

let run (e : unit Effect.t) : unit = Effect.Expert.handle_non_dom_event_exn e
let eff f = Effect.of_thunk f
let textf fmt = Printf.ksprintf N.text fmt
let on_enter e = A.on_keyup (fun ev -> if ev##.keyCode = 13 then e else Effect.return ())

let swap_at (l : 'a list) i =
  match List.nth l i, List.nth l (i + 1) with
  | Some a, Some b -> List.mapi l ~f:(fun j x -> if j = i then b else if j = i + 1 then a else x)
  | _ -> l
;;

(* ---- building blocks, rendered with ppx_html + the Style module ---- *)
let div ?(attrs = []) children = {%html.jsx|<div *{attrs}>*{children}</div>|}
let spanc ?(attrs = []) children = {%html.jsx|<span *{attrs}>*{children}</span>|}
let card ?(attrs = []) children = {%html.jsx|<div *{Style.card :: attrs}>*{children}</div>|}
let card_title ?(attrs = []) children = {%html.jsx|<div *{Style.card_title :: attrs}>*{children}</div>|}
let card_text ?(attrs = []) children = {%html.jsx|<div *{Style.card_text :: attrs}>*{children}</div>|}

let btn ?(attrs = []) ?(disabled = false) ?(loading = false) ~on_click children =
  let attrs = (Style.btn :: attrs) @ (if disabled || loading then [ A.disabled' true ] else []) in
  let children = if loading then [ {%html.jsx|<span *{[ Style.spinner ]}></span>|} ] else children in
  {%html.jsx|<button *{attrs} on_click=%{fun _ -> on_click}>*{children}</button>|}
;;

let fa ?(color = "") kind name =
  let style = if String.is_empty color then [] else [ A.style (Css_gen.color (`Name color)) ] in
  N.create "i" ~attrs:(A.classes [ kind; name ] :: style) []
;;

let mdi name = N.create "i" ~attrs:[ A.classes [ "mdi"; "mdi-" ^ name ] ] []
let team_icon (t : team) = match t with Good -> fa "fab" "fa-old-republic" | Evil -> fa ~color:"red" "fab" "fa-empire"

(* FontAwesome icon stacking; [fa-layers] is kept as a literal class (it is the external
   library's hook, styled via :global in Style). *)
let fa_layers ?(attrs = []) children = {%html.jsx|<span *{A.class_ "fa-layers" :: attrs}>*{children}</span>|}

let overlay ?(fullscreen = false) ~on_close children =
  let inner = if fullscreen then [ Style.overlay_card; Style.fullscreen ] else [ Style.overlay_card ] in
  {%html.jsx|
    <div *{[ Style.overlay ]} on_click=%{fun _ -> on_close}>
      <div *{inner} on_click=%{fun _ -> Effect.Many []}>*{children}</div>
    </div>
  |}
;;

let text_field ?(attrs = []) ?(typ = "text") ?(placeholder = "") ?(extra = []) ~value ~on_input () =
  let all =
    (Style.text_field :: attrs)
    @ [ A.type_ typ; A.placeholder placeholder; A.value_prop value; A.on_input (fun _ s -> on_input s) ]
    @ extra
  in
  {%html.jsx|<input *{all} />|}
;;

let field_error error = if String.is_empty error then N.none else {%html.jsx|<div *{[ Style.field_error ]}>#{error}</div>|}

(* mailto feedback link, styled as a button (port of the Vue "Email"/"Send feedback" btns) *)
let feedback_link label =
  {%html.jsx|<a *{[ Style.btn; Style.mt_4 ]} href="mailto:avalon@shamm.as" target="_blank">%{fa "fas" "fa-envelope-square"} #{label}</a>|}
;;

(* ============================ StatsDisplay ============================ *)
let stats_display (stats : stats option) (global : stats option) =
  let s = Option.value stats ~default:empty_stats in
  let games = s.games and good = s.good and wins = s.wins and good_wins = s.good_wins in
  let evil = games - good in
  let evil_wins = wins - good_wins in
  let pct n d = if d > 0 then sprintf "%d%%" (Float.to_int (100. *. Float.of_int n /. Float.of_int d)) else "N/A" in
  let row label a b c =
    N.tr [ N.td ~attrs:[ Style.fw ] [ N.text label ]; N.td [ N.text a ]; N.td [ N.text b ]; N.td [ N.text c ] ]
  in
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
          [ N.td ~attrs:[ Style.fw ] [ N.text "All Users" ]
          ; N.td [ N.text (pct g.good_wins g.games) ]
          ; N.td [ N.text (pct (g.games - g.good_wins) g.games) ]
          ; N.td []
          ]
      ]
    | _ -> []
  in
  let table =
    N.table
      [ N.thead [ N.tr ~attrs:[ Style.stats_header ] [ N.td []; N.td [ N.text "Good" ]; N.td [ N.text "Evil" ]; N.td [ N.text "Total" ] ] ]
      ; N.tbody
          ([ row "Games" (Int.to_string good) (Int.to_string evil) (Int.to_string games)
           ; row "Wins" (Int.to_string good_wins) (Int.to_string evil_wins) (Int.to_string wins)
           ; row "Losses" (Int.to_string (good - good_wins)) (Int.to_string (evil - evil_wins)) (Int.to_string (games - wins))
           ; row "Win Rate" (pct good_wins good) (pct evil_wins evil) (pct wins games)
           ]
           @ global_rows)
      ]
  in
  {%html.jsx|
    <div *{[ Style.col; Style.center; Style.stats_wrap ]}>
      %{table}
      <div *{[ Style.pt_2 ]}><div>%{textf "Total Playtime: %s" playtime}</div></div>
    </div>
  |}
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
      then
        N.input
          ~attrs:[ A.type_ "checkbox"; A.checked_prop is_sel; A.on_click (fun _ -> eff (fun () -> State.toggle_role ~name:role.name ~selected:(not is_sel))) ]
          ()
      else N.none
    in
    let info_btn = btn ~attrs:[ Style.icon_btn ] ~on_click:(set_info (Some role)) [ mdi "information" ] in
    {%html.jsx|
      <li class="v-list-item">
        <div *{[ Style.li_prepend ]}>%{checkbox}%{team_icon role.team}</div>
        <div *{[ Style.li_title ]}>#{role.name}</div>
        %{info_btn}
      </li>
    |}
  in
  let dialog =
    match info with
    | None -> N.none
    | Some role ->
      overlay ~on_close:(set_info None)
        [ card_title ~attrs:[ Style.title_bar ] [ team_icon role.team; N.h3 [ N.text role.name ] ]; card_text [ N.text role.description ] ]
  in
  let items = List.map Avalonlib.selectable_roles ~f:item in
  {%html.jsx|<div><ul class="v-list">*{items}</ul>%{dialog}</div>|}
;;

(* static role display (in-game participants tab) *)
let role_list_view (roles : role list) =
  let item (role : role) =
    let attrs = [ A.class_ "v-list-item"; A.create "title" role.description ] in
    {%html.jsx|
      <li *{attrs}>
        <div *{[ Style.li_prepend ]}>%{team_icon role.team}</div>
        <div *{[ Style.li_title ]}>#{role.name}</div>
      </li>
    |}
  in
  let items = List.map roles ~f:item in
  {%html.jsx|<ul class="v-list">*{items}</ul>|}
;;

(* ============================ MissionSummaryTable ============================ *)
let mission_summary_table ~players ~(missions : mission list) ~(roles : role_assignment list option) ~(mission_votes : bool String.Map.t list option) =
  let proposals_of (m : mission) = List.filter m.proposals ~f:(fun p -> not (List.is_empty p.team)) in
  let cell_for player (proposal : proposal) =
    fa_layers
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
      | Some rs ->
        let r = List.find rs ~f:(fun r -> String.equal r.name player) in
        [ N.td ~attrs:[ Style.role_cell ] [ N.text (Option.value_map r ~default:"" ~f:(fun r -> r.role)) ] ]
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
              [ N.td ~attrs:[ Style.mission_result ] [ (match v with Some true -> fa ~color:"green" "fas" "fa-check-circle" | _ -> fa ~color:"red" "fas" "fa-times-circle") ] ])
            else [ N.td ~attrs:[ Style.mission_result ] [] ]
          | None -> []
        in
        prop_cells @ result_cell)
    in
    N.tr ([ N.td ~attrs:[ Style.player_name ] [ spanc ~attrs:[ Style.fw ] [ N.text player ] ] ] @ role_cell @ mission_cells)
  in
  N.table ~attrs:[ Style.summary_table ] (List.map players ~f:row)
;;

(* ============================ GameAchievements ============================ *)
let achievements (g : Game.t) =
  match Game.outcome g with
  | Some o when not (equal_outcome_state o.state Canceled) ->
    let badges = Analysis.get_badges (Analysis.create g.data ~role_map:Avalonlib.role_map) in
    if List.is_empty badges
    then N.none
    else (
      let badge (b : Analysis.badge) =
        {%html.jsx|
          <div *{[ Style.pt_2 ]}>
            %{card ~attrs:[ Style.achievement ]
                 [ card_title ~attrs:[ Style.title_bar ] [ fa ~color:"gold" "fas" "fa-trophy"; div ~attrs:[ Style.text_h6 ] [ N.text b.title ] ]
                 ; card_text [ N.text b.body ]
                 ]}
          </div>
        |}
      in
      let badge_nodes = List.map badges ~f:badge in
      {%html.jsx|
        <div *{[ Style.pt_6 ]}>
          <div *{[ Style.text_h4; Style.center ]}>Achievements</div>
          *{badge_nodes}
        </div>
      |})
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
  let field_err = if String.is_empty error then N.none else {%html.jsx|<div *{[ Style.field_error ]}>#{error}</div>|} in
  let alert =
    match m.confirming_email_error with
    | Some e -> {%html.jsx|<div *{[ Style.alert_error ]}>%{textf "%s Please try logging in again." e}</div>|}
    | None -> N.none
  in
  let tab_button value label =
    let attrs = if String.equal tab value then [ Style.btn; Style.tab; Style.tab_active ] else [ Style.btn; Style.tab ] in
    {%html.jsx|<button *{attrs} on_click=%{fun _ -> set_tab value}>#{label}</button>|}
  in
  let email_pane =
    if not submitted
    then (
      let input_attrs =
        [ Style.text_field; A.type_ "email"; A.placeholder "Email Address"; A.value_prop email
        ; A.on_input (fun _ s -> set_email s); on_enter submit_email
        ]
      in
      let login_attrs = Style.btn :: (if submitting then [ A.disabled' true ] else []) in
      let login_label = if submitting then {%html.jsx|<span *{[ Style.spinner ]}></span>|} else N.text "Login" in
      {%html.jsx|
        <div *{[ Style.pa_4; Style.login_form ]}>
          <input *{input_attrs} />
          %{field_err}
          <button *{login_attrs} on_click=%{fun _ -> submit_email}>%{login_label}</button>
        </div>
      |})
    else
      {%html.jsx|
        <div *{[ Style.pa_4; Style.login_form ]}>
          <div *{[ Style.card; Style.info_card ]}>
            <div *{[ Style.card_text; Style.center ]}><p>Check your email for the verification link</p></div>
          </div>
          <button *{[ Style.btn; Style.mt_4 ]} on_click=%{fun _ -> set_submitted false}>Try Again</button>
        </div>
      |}
  in
  let anon_pane =
    {%html.jsx|
      <div *{[ Style.pa_4 ]}>
        <button *{[ Style.btn ]} on_click=%{fun _ -> anon}>Login</button>
        %{field_err}
      </div>
    |}
  in
  {%html.jsx|
    <div *{[ Style.card; Style.welcome ]}>
      <div *{[ Style.col; Style.center ]}>
        %{alert}
        <div *{[ Style.card_title ]}>
          <span *{[ Style.welcome_heading ]}>Avalon: The Resistance <span *{[ Style.thin ]}>Online</span></span>
          <p *{[ Style.mt_4 ]}><span *{[ Style.subtitle ]}>A game of social deduction for 5 to 10 people, now on desktop and mobile.</span></p>
        </div>
        <div *{[ Style.tabs ]}>
          %{tab_button "email" "Email"}
          %{tab_button "anonymous" "Anonymous"}
        </div>
        %{if String.equal tab "email" then email_pane else anon_pane}
        %{feedback_link "Email"}
      </div>
    </div>
  |}
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
  let form =
    if not show_lobby_input
    then
      [ text_field ~attrs:[ Style.upper ] ~placeholder:"Your Name" ~value:name ~on_input:(fun s -> set_name (String.uppercase s)) ()
      ; field_error error
      ; div ~attrs:[ Style.col; Style.ga_2; Style.lobby_buttons ]
          [ btn ~disabled:(String.is_empty name) ~loading:creating ~on_click:do_create [ N.text "Create Lobby" ]
          ; btn ~disabled:(String.is_empty name || creating) ~on_click:(set_show_lobby_input true) [ N.text "Join Lobby" ]
          ]
      ]
    else
      [ text_field ~attrs:[ Style.upper ] ~placeholder:"Lobby" ~value:lobby ~on_input:(fun s -> set_lobby (String.uppercase s)) ~extra:[ on_enter do_join ] ()
      ; field_error error
      ; div ~attrs:[ Style.col; Style.ga_2; Style.lobby_buttons ]
          [ btn ~disabled:(String.is_empty lobby) ~loading:joining ~on_click:do_join [ N.text "Join Lobby" ]
          ; btn ~disabled:joining ~on_click:(set_show_lobby_input false) [ N.text "Cancel" ]
          ]
      ]
  in
  let children = form @ [ div ~attrs:[ Style.pt_8 ] []; stats_display (Option.bind m.user ~f:(fun u -> u.stats)) m.global_stats ] in
  {%html.jsx|
    <div *{[ Style.lobby_select ]}>
      <div *{[ Style.col; Style.center; Style.lobby_inner ]}>*{children}</div>
    </div>
  |}
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
        [ btn ~attrs:[ Style.icon_btn ] ~disabled:(idx = 0) ~on_click:(eff (fun () -> State.set_player_list (swap_at m.player_list (idx - 1)))) [ mdi "chevron-up" ]
        ; btn ~attrs:[ Style.icon_btn ] ~disabled:(idx = n - 1) ~on_click:(eff (fun () -> State.set_player_list (swap_at m.player_list idx))) [ mdi "chevron-down" ]
        ]
      else []
    in
    let kick_btn =
      if D.is_admin m && (not (String.equal player me)) && not (D.is_game_in_progress m)
      then [ btn ~attrs:[ Style.icon_btn ] ~on_click:(set_kick_target (Some player)) [ mdi "close" ] ]
      else []
    in
    let prepend = div ~attrs:[ Style.li_prepend ] (reorder @ [ prepend_icon ]) in
    {%html.jsx|
      <li class="v-list-item">
        %{prepend}
        <div *{[ Style.li_title ]}>#{player}</div>
        *{kick_btn}
      </li>
    |}
  in
  let items = List.mapi m.player_list ~f:item in
  let dialog =
    match kick_target with
    | None -> N.none
    | Some player ->
      overlay ~on_close:(set_kick_target None)
        [ card_title ~attrs:[ Style.title_bar ] [ N.h3 [ textf "Kick %s?" player ] ]
        ; card_text [ textf "Do you wish to kick %s from the lobby?" player ]
        ; div ~attrs:[ Style.row; Style.actions ]
            [ btn ~on_click:(eff (fun () -> run (set_kick_target None); State.kick_player player)) [ textf "Kick %s" player ]; btn ~on_click:(set_kick_target None) [ N.text "Cancel" ] ]
        ]
  in
  {%html.jsx|<div><ul class="v-list">*{items}</ul>%{dialog}</div>|}
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
  let seating_hint = if D.is_admin m && num_players > 2 then {%html.jsx|<p *{[ Style.caption ]}>Use the arrows to set seating order</p>|} else N.none in
  let roles_col = if valid_team_size then {%html.jsx|<div *{[ Style.col6 ]}><p *{[ Style.label ]}>Special Roles Available</p>%{roles}</div>|} else N.none in
  let counts =
    if valid_team_size
    then {%html.jsx|<div *{[ Style.row; Style.center ]}><p *{[ Style.text_h6; Style.label ]}>%{textf "%d players: %d good, %d evil" num_players (num_players - num_evil) num_evil}</p></div>|}
    else N.none
  in
  let start_area =
    match reason_not_start with
    | None -> btn ~loading:starting ~on_click:start [ mdi "play"; N.text "Start Game" ]
    | Some reason -> card ~attrs:[ Style.info_card ] [ card_text ~attrs:[ Style.center ] [ N.text reason ] ]
  in
  let log_attrs = [ A.type_ "checkbox"; A.checked_prop in_game_log; A.on_click (fun _ -> set_in_game_log (not in_game_log)) ] in
  {%html.jsx|
    <div *{[ Style.container ]}>
      <div *{[ Style.row; Style.wrap; Style.start ]}>
        <div *{[ Style.col6 ]}>
          <p *{[ Style.label ]}>Players</p>
          %{players}
          %{seating_hint}
        </div>
        %{roles_col}
      </div>
      %{counts}
      <div *{[ Style.row; Style.center; Style.pt_2 ]}>%{start_area}</div>
      <label *{[ Style.checkbox_row ]}><input *{log_attrs} />#{" In-game log"}</label>
      <div *{[ Style.col; Style.pt_6 ]}>%{feedback_link "Send feedback"}</div>
    </div>
  |}
;;

(* ============================ GameMissions ============================ *)
let game_missions (local_ graph) =
  let active, set_active = Bonsai.state 0 graph in
  (* follow the current mission as the game progresses (original watched currentMissionIdx) *)
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
        (let%arr set_active = set_active in
         fun i -> if i >= 0 && i < 5 then set_active i else Effect.return ())
      graph
  in
  let%arr m = State.value () and active = active and set_active = set_active in
  match D.game m with
  | None -> N.none
  | Some g ->
    let missions = Game.missions g in
    let is_future idx = idx > 0 && (match List.nth missions (idx - 1) with Some prev -> equal_mission_state prev.state M_pending | None -> false) in
    let tab idx (mission : mission) =
      let base =
        match mission.state with
        | M_pending ->
          [ fa ~color:(if is_future idx then "gray" else "black") "far" "fa-circle"; spanc ~attrs:[ Style.layers_text ] [ N.text (Int.to_string mission.team_size) ] ]
        | Fail -> [ fa ~color:"red" "far" "fa-times-circle" ]
        | Success -> [ fa ~color:"green" "far" "fa-check-circle" ]
      in
      (* A red dot marks a mission that needs two fails (the 4th in 7+ player games). *)
      let dot = if mission.fails_required > 1 then [ spanc ~attrs:[ Style.fails_dot ] [ fa ~color:"red" "fas" "fa-circle" ] ] else [] in
      let icon = fa_layers (base @ dot) in
      btn ~attrs:(Style.tab_mission :: (if active = idx then [ Style.tab; Style.tab_active ] else [ Style.tab ])) ~on_click:(set_active idx) [ icon ]
    in
    let panel idx (mission : mission) =
      let bg = match mission.state with Fail -> Style.bg_fail | Success -> Style.bg_success | M_pending -> Style.bg_pending in
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
      card ~attrs:[ bg; Style.mission_panel ] [ card_text ~attrs:[ Style.caption ] [ header; detail; log ] ]
    in
    let tabs = List.mapi missions ~f:tab in
    let panel_node = match List.nth missions active with Some mission -> panel active mission | None -> N.none in
    {%html.jsx|<div><div *{[ Style.tabs ]}>*{tabs}</div>%{panel_node}</div>|}
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
      (* Mirror Vue's tooltipText so the otherwise-cryptic status icons are explained on hover. *)
      let states =
        List.filter_opt
          [ (if was_on_last name then Some "was on the last proposed team" else None)
          ; (if waiting name then Some "is currently voting on the proposal"
             else if has_voted name then Some "has submitted a vote for the proposed team"
             else if approved name then Some "approved the last team"
             else if rejected name then Some "rejected the last team"
             else None)
          ]
      in
      if List.is_empty icons
      then N.none
      else fa_layers ~attrs:[ A.create "title" (sprintf "%s %s" name (Util.join_with_and states)) ] icons
    in
    let item name =
      let checkbox =
        if enable_checkbox name then N.input ~attrs:[ A.type_ "checkbox"; A.checked_prop (List.mem selected name ~equal:String.equal); A.on_click (fun _ -> toggle name) ] ()
        else if selected_for_mission name then N.input ~attrs:[ A.type_ "checkbox"; A.checked_prop true; A.disabled' true ] ()
        else N.none
      in
      let marker =
        if Option.value_map g.current_proposer ~default:false ~f:(String.equal name)
        then
          fa_layers
            ~attrs:[ A.create "title" (sprintf "%s is proposing the next team" name) ]
            [ fa ~color:crown_color "fas" "fa-crown"; spanc ~attrs:[ Style.layers_text ] [ N.text (Int.to_string (g.current_proposal_idx + 1)) ] ]
        else if Option.value_map g.hammer ~default:false ~f:(String.equal name) then fa "fas" "fa-hammer"
        else N.none
      in
      {%html.jsx|
        <li class="v-list-item">
          <div *{[ Style.li_prepend ]}>%{checkbox}</div>
          <div *{[ Style.li_mid ]}>%{marker}</div>
          <div *{[ Style.li_title ]}>#{name}</div>
          <div *{[ Style.li_append ]}>%{status_icons name}</div>
        </li>
      |}
    in
    let items = List.map (Game.players g) ~f:item in
    {%html.jsx|<ul class="v-list">*{items}</ul>|}
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
    let tab_attrs value = if String.equal tab value then [ Style.tab; Style.tab_active ] else [ Style.tab ] in
    let body = if String.equal tab "players" then players else role_list_view role_objs in
    {%html.jsx|
      <div>
        <div *{[ Style.tabs ]}>
          <button *{Style.btn :: tab_attrs "players"} on_click=%{fun _ -> set_tab "players"}>Players</button>
          <button *{Style.btn :: tab_attrs "roles"} on_click=%{fun _ -> set_tab "roles"}>Roles</button>
        </div>
        %{body}
      </div>
    |}
;;

(* ============================ Action panes ============================ *)

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
      (let%arr reset = reset in
       fun _ -> reset)
    graph
;;

let team_proposal_action ~selected (local_ graph) =
  let proposing, set_proposing = Bonsai.state false graph in
  let () =
    on_proposal_change
      graph
      ~reset:
        (let%arr set_proposing = set_proposing in
         set_proposing false)
  in
  let%arr m = State.value () and selected = selected and proposing = proposing and set_proposing = set_proposing in
  match D.game m with
  | None -> N.none
  | Some g ->
    let me = D.user_name m in
    let team_size = Option.value_map g.current_mission ~default:0 ~f:(fun mi -> mi.team_size) in
    let valid = List.length selected = team_size in
    let propose = eff (fun () -> run (set_proposing true); State.propose_team selected ~on_err:(fun _ -> run (set_proposing false))) in
    let body =
      if Option.value_map g.current_proposer ~default:false ~f:(String.equal me)
      then
        div ~attrs:[ Style.col; Style.center ]
          [ {%html.jsx|<div *{[ Style.center ]}>%{textf "Propose a team of %d" team_size}</div>|}
          ; btn ~disabled:(not valid) ~loading:proposing ~on_click:propose [ N.text "Propose Team" ]
          ]
      else {%html.jsx|<div *{[ Style.center ]}>%{textf "Waiting for %s to propose a team of %d" (Option.value g.current_proposer ~default:"") team_size}</div>|}
    in
    card ~attrs:[ Style.action ]
      [ card_title ~attrs:[ Style.action_title ] [ textf "Team Proposal (%d/5)" (g.current_proposal_idx + 1) ]; card_text [ body ] ]
;;

let team_vote_action (local_ graph) =
  let voted, set_voted = Bonsai.state_opt graph ~sexp_of_model:[%sexp_of: bool] in
  let () =
    on_proposal_change
      graph
      ~reset:
        (let%arr set_voted = set_voted in
         set_voted None)
  in
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
    let buttons =
      div ~attrs:[ Style.row; Style.between ]
        [ btn ~disabled:(disabled true) ~on_click:(vote true) [ (if voted_yes then fa ~color:"green" "fas" "fa-vote-yea" else fa ~color:"green" "far" "fa-thumbs-up"); N.text " Approve" ]
        ; btn ~disabled:(disabled false) ~on_click:(vote false) [ (if voted_no then fa ~color:"red" "fas" "fa-vote-yea" else fa ~color:"red" "far" "fa-thumbs-down"); N.text " Reject" ]
        ]
    in
    card ~attrs:[ Style.action ]
      [ card_title ~attrs:[ Style.action_title ] [ textf "Team Proposal Vote (%d/5)" (g.current_proposal_idx + 1) ]
      ; card_text [ N.div [ textf "Voting for %s team of %s" proposer_label team ]; buttons ]
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
    let body =
      if needs_to_vote
      then
        N.div
          [ (if String.is_empty error then N.none else {%html.jsx|<div *{[ Style.field_error; Style.center ]}>#{error}</div>|})
          ; div ~attrs:[ Style.row; Style.between ]
              [ btn ~on_click:(vote true) [ fa ~color:"green" "fas" "fa-check-circle"; N.text " SUCCESS" ]; btn ~on_click:(vote false) [ fa ~color:"red" "fas" "fa-times-circle"; N.text " FAIL" ] ]
          ]
      else N.div [ N.text (if List.length still_waiting > 0 then "Waiting for " ^ Util.join_with_and still_waiting else "Waiting for results...") ]
    in
    card ~attrs:[ Style.action ] [ card_title ~attrs:[ Style.action_title ] [ N.text "Mission in Progress" ]; card_text [ body ] ]
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
    let body =
      if assassin then N.div [ btn ~disabled:(not valid) ~loading:assassinating ~on_click:go [ N.text label ] ]
      else N.div [ N.text "Waiting for target selection" ]
    in
    card ~attrs:[ Style.action ] [ card_title ~attrs:[ Style.action_title ] [ N.text "Assassination Attempt" ]; card_text [ body ] ]
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
  {%html.jsx|
    <div *{[ Style.game_board ]}>
      <div *{[ Style.game_section ]}>%{missions}</div>
      <div *{[ Style.game_section ]}>%{participants}</div>
      <div *{[ Style.game_section ]}>%{actions}</div>
    </div>
  |}
;;

(* ============================ Toolbar ============================ *)
let view_role_button (local_ graph) =
  let%arr m = State.value () in
  let sheet = m.show_role_sheet in
  let activator = btn ~attrs:[ Style.outlined ] ~on_click:(eff (fun () -> State.set_show_role_sheet true)) [ mdi "account"; N.span [ N.text (D.user_name m) ] ] in
  let sheet_node =
    if not sheet
    then N.none
    else (
      let body =
        if not (D.is_game_in_progress m)
        then
          card ~attrs:[ Style.sheet ]
            [ card_title [ {%html.jsx|<div *{[ Style.fw; Style.center ]}>When the game starts, you will see your role here.</div>|} ]
            ; card_text [ div ~attrs:[ Style.col; Style.center ] [ N.p [ N.text "Your Stats" ]; stats_display (Option.bind m.user ~f:(fun u -> u.stats)) m.global_stats ] ]
            ]
        else (
          match D.role m with
          | None -> N.none
          | Some rd ->
            card ~attrs:[ Style.sheet ]
              [ card_title ~attrs:[ Style.title_bar ] [ team_icon rd.role.team; spanc ~attrs:[ Style.text_h5 ] [ N.text rd.role.name ] ]
              ; card_text
                  [ N.p [ textf "Your role is %s." rd.role.name ]
                  ; N.p [ textf "You are on the %s team." (team_to_string rd.role.team) ]
                  ; N.p [ N.text rd.role.description ]
                  ; (if rd.assassin then N.p [ N.text "You are also the ASSASSIN! It will be up to you to identify MERLIN if the good team succeeds 3 missions." ] else N.none)
                  ; (if List.is_empty rd.sees then N.p [ N.text "You do not see anyone." ] else N.p [ textf "You see %s." (Util.join_with_and rd.sees) ])
                  ]
              ])
      in
      {%html.jsx|
        <div *{[ Style.bottom_sheet_overlay ]} on_click=%{fun _ -> eff (fun () -> State.set_show_role_sheet false)}>
          <div class="bottom-sheet" on_click=%{fun _ -> Effect.Many []}>%{body}</div>
        </div>
      |})
  in
  {%html.jsx|<div>%{activator}%{sheet_node}</div>|}
;;

let quit_button (local_ graph) =
  let dialog, set_dialog = Bonsai.state false graph in
  let%arr m = State.value () and dialog = dialog and set_dialog = set_dialog in
  let in_game = D.is_game_in_progress m in
  let action_desc = if in_game then "Cancel Game" else "Leave Lobby" in
  let confirm = eff (fun () -> run (set_dialog false); if in_game then State.cancel_game () else State.leave_lobby ()) in
  let activator = btn ~on_click:(set_dialog true) [ mdi "exit-to-app"; spanc ~attrs:[ Style.quit_text ] [ N.text "Quit" ] ] in
  let dialog_node =
    if not dialog
    then N.none
    else
      overlay ~on_close:(set_dialog false)
        [ card_title ~attrs:[ Style.title_bar ] [ N.h3 [ textf "%s?" action_desc ] ]
        ; card_text [ N.text ((if in_game then "The current game will be canceled! " else "") ^ "Are you sure you want to proceed?") ]
        ; div ~attrs:[ Style.row; Style.actions ] [ btn ~on_click:confirm [ N.text action_desc ]; btn ~on_click:(set_dialog false) [ N.text "Nevermind" ] ]
        ]
  in
  {%html.jsx|<div>%{activator}%{dialog_node}</div>|}
;;

let game_toolbar (local_ graph) =
  let view_role = view_role_button graph in
  let quit = quit_button graph in
  let%arr m = State.value () and view_role = view_role and quit = quit in
  let lobby_named = match m.lobby with Some l -> not (String.is_empty l.name) | None -> false in
  if lobby_named && Option.is_some m.user
  then (
    let lobby_label = Option.value_map m.lobby ~default:"" ~f:(fun l -> l.name) in
    {%html.jsx|
      <div *{[ Style.toolbar ]}>
        <div *{[ Style.row; Style.center_v ]}>%{mdi "map-marker"}<span *{[ A.class_ "lobby-name"; Style.fw ]}>#{lobby_label}</span></div>
        <div *{[ Style.spacer ]}></div>
        %{view_role}
        %{quit}
      </div>
    |})
  else (
    let email = Option.value (Option.bind m.user ~f:(fun u -> u.email)) ~default:"" in
    let logout = btn ~on_click:(eff State.logout) [ mdi "exit-to-app"; N.text "Logout" ] in
    {%html.jsx|
      <div *{[ Style.toolbar ]}>
        <span *{[ Style.toolbar_email ]}>#{email}</span>
        <div *{[ Style.spacer ]}></div>
        %{logout}
      </div>
    |})
;;

(* ============================ Event modals ============================ *)
let modals (local_ graph) =
  let%arr m = State.value () in
  let close = eff (fun () -> State.set_modal No_modal) in
  match m.modal, D.game m with
  | M.Start_game, _ ->
    overlay ~on_close:Effect.(return ())
      [ card_title ~attrs:[ Style.title_bar ] [ N.h3 [ N.text "Game Started" ] ]
      ; card_text [ N.p [ N.text "A new game has started. When you are ready, view your secret role." ]; N.p [ N.text "You may also view your role anytime by clicking on your name in the toolbar." ] ]
      ; div ~attrs:[ Style.row; Style.actions ] [ btn ~on_click:(eff (fun () -> State.set_modal No_modal; State.set_show_role_sheet true)) [ N.text "View Role" ] ]
      ]
  | M.Mission_result, Some g ->
    let idx = if g.current_mission_idx < 0 then List.length (Game.missions g) else g.current_mission_idx in
    (match List.nth (Game.missions g) (idx - 1) with
     | None -> N.none
     | Some mission ->
       let title =
         match mission.state with
         | Success -> N.div [ fa ~color:"green" "fas" "fa-check-circle"; N.text " Mission Succeeded!" ]
         | _ -> N.div [ fa ~color:"red" "fas" "fa-times-circle"; N.text " Mission Failed!" ]
       in
       overlay ~on_close:close
         [ card_title ~attrs:[ Style.title_bar ] [ title ]
         ; card_text [ textf "%s had %s failure %s" (Util.join_with_and mission.team) (if mission.num_fails > 0 then Int.to_string mission.num_fails else "no") (if mission.num_fails = 1 then "vote." else "votes.") ]
         ; div ~attrs:[ Style.row; Style.actions ] [ btn ~on_click:close [ N.text "Close" ] ]
         ])
  | M.End_game, Some g ->
    (match Game.outcome g with
     | None -> N.none
     | Some o ->
       let title = match o.state with Good_win -> "Good wins!" | Evil_win -> "Evil wins!" | Canceled -> "Game Canceled" in
       let role_assignments = List.sort o.roles ~compare:(fun a b -> Int.compare (Avalonlib.role_index a.role) (Avalonlib.role_index b.role)) in
       let missions = List.filter (Game.missions g) ~f:(fun mi -> List.exists mi.proposals ~f:(fun p -> not (equal_proposal_state p.state Pending))) in
       let assassinated =
         match o.assassinated with
         | Some a -> N.p [ textf "%s was assassinated by %s" a (Option.value_map (List.find o.roles ~f:(fun r -> r.assassin)) ~default:"" ~f:(fun r -> r.name)) ]
         | None -> N.none
       in
       let body =
         div ~attrs:[ Style.col; Style.center ]
           [ {%html.jsx|<div *{[ Style.endgame_message; Style.fw ]}>#{o.message}</div>|}
           ; assassinated
           ; div ~attrs:[ Style.endgame_table_wrap ] [ mission_summary_table ~players:(Game.players g) ~missions ~roles:(Some role_assignments) ~mission_votes:(Some o.votes) ]
           ; achievements g
           ; btn ~attrs:[ Style.mt_6; Style.primary ] ~on_click:close [ N.text "Close" ]
           ]
       in
       overlay ~fullscreen:true ~on_close:close
         [ card_title ~attrs:[ Style.endgame_title ] [ spanc ~attrs:[ Style.text_h4; Style.fw ] [ N.text title ] ]; card_text [ body ] ])
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
    match m.connection_error with
    | Some msg ->
      div
        ~attrs:[ Style.container; Style.center; Style.fill ]
        [ card ~attrs:[ Style.welcome ]
            [ card_title [ N.text "Connection problem" ]
            ; card_text [ N.text msg ]
            ; div ~attrs:[ Style.actions ] [ btn ~on_click:(eff (fun () -> Ffi.reload_page ())) [ N.text "Reload" ] ]
            ]
        ]
    | None ->
    if not (D.initialized m)
    then div ~attrs:[ Style.container; Style.center; Style.fill ] [ {%html.jsx|<div *{[ Style.spinner_lg ]}></div>|} ]
    else if not (D.is_logged_in m)
    then div ~attrs:[ Style.container; Style.center ] [ login ]
    else (
      let main = if not (D.is_in_lobby m) then lobby_sel else if not (D.is_game_in_progress m) then lobby else board in
      {%html.jsx|<div>%{toolbar}<div *{[ Style.container ]}>%{main}</div></div>|})
  in
  {%html.jsx|<div *{[ Style.app ]}>%{modals}%{content}</div>|}
;;

let run_app () =
  State.init ();
  Bonsai_web.Start.start ~bind_to_element_with_id:"app" app
;;
