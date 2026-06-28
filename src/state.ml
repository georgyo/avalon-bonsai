open! Core
open Js_of_ocaml
open Bonsai_web
open Types

(** The reactive store. [Model.t] is an immutable snapshot held in a {!Bonsai.Var};
    Firebase listeners and UI actions push new snapshots into it. This replaces the Vue
    [AvalonGame] + [LobbySubscription] + [GameConfig] objects and the mitt EventBus. *)

let firebase_config : (string * Ffi.any) list =
  [ "apiKey", Ffi.of_string "AIzaSyCwhCvO8NbTusBaHmHHnNT7yC0_11UL2RI"
  ; "authDomain", Ffi.of_string "georgyo-avalon.firebaseapp.com"
  ; "databaseURL", Ffi.of_string "https://georgyo-avalon-default-rtdb.firebaseio.com"
  ; "projectId", Ffi.of_string "georgyo-avalon"
  ; "storageBucket", Ffi.of_string "georgyo-avalon.appspot.com"
  ; "messagingSenderId", Ffi.of_string "1000859874531"
  ; "appId", Ffi.of_string "1:1000859874531:web:789f785c58c574bff181d6"
  ]
;;

module Model = struct
  type modal =
    | No_modal
    | Start_game
    | Mission_result
    | End_game
  [@@deriving equal]

  type lobby =
    { name : string
    ; connected : bool
    ; data : lobby_data option
    ; role : role_doc option
    ; game : Game.t option
    }

  type t =
    { auth_initialized : bool
    ; confirming_email_error : string option
    ; user : user_data option
    ; lobby : lobby option
    ; global_stats : stats option
    ; player_list : string list
    ; selected_roles : String.Set.t
    ; modal : modal
    ; show_role_sheet : bool
    }

  let default_selected_roles =
    String.Set.of_list
      (List.filter_map Avalonlib.roles ~f:(fun r ->
         if r.default_selected then Some r.name else None))
  ;;

  let initial =
    { auth_initialized = false
    ; confirming_email_error = None
    ; user = None
    ; lobby = None
    ; global_stats = None
    ; player_list = []
    ; selected_roles = default_selected_roles
    ; modal = No_modal
    ; show_role_sheet = false
    }
  ;;
end

(* ---- derived predicates (port of the AvalonGame getters) ---- *)
module Derived = struct
  open Model

  let user_name (m : t) = Option.value_map m.user ~default:"" ~f:(fun u -> u.name)

  let is_in_lobby (m : t) =
    match m.user, m.lobby with
    | Some u, Some l -> Option.is_some u.lobby && l.connected
    | _ -> false
  ;;

  let initialized (m : t) =
    if not m.auth_initialized
    then false
    else (
      match m.user with
      | None -> true
      | Some u -> Option.is_none u.lobby || is_in_lobby m)
  ;;

  let is_logged_in (m : t) = initialized m && Option.is_some m.user

  let admin (m : t) : Types.admin option =
    Option.bind m.lobby ~f:(fun l -> Option.map l.data ~f:(fun d -> d.admin))
  ;;

  let is_admin (m : t) =
    is_in_lobby m
    &&
    match admin m, m.user with
    | Some a, Some u -> String.equal a.uid u.uid
    | _ -> false
  ;;

  let game (m : t) : Game.t option = Option.bind m.lobby ~f:(fun l -> l.game)
  let role (m : t) : role_doc option = Option.bind m.lobby ~f:(fun l -> l.role)

  let is_game_in_progress (m : t) =
    is_in_lobby m
    &&
    match game m, role m with
    | Some g, Some _ -> equal_game_state (Game.state g) Active
    | _ -> false
  ;;

  let selected_role_list (m : t) =
    List.filter_map Avalonlib.roles ~f:(fun r ->
      if Set.mem m.selected_roles r.name then Some r.name else None)
  ;;
end

(* ---- the Var and basic accessors ---- *)
module Var = Bonsai.Expert.Var

let var = Var.create Model.initial
let model () = Var.get var
let value () = Var.value var
let set m = Var.set var m
let update ~f = Var.update var ~f
let update_lobby ~f = update ~f:(fun m -> { m with Model.lobby = Option.map m.lobby ~f })

(* ---- subscription bookkeeping ---- *)
let user_doc_unsub : (unit -> unit) option ref = ref None
let lobby_unsubs : (unit -> unit) list ref = ref []

let lobby_name () =
  match (model ()).lobby with
  | Some l -> l.name
  | None -> ""
;;

let user_name_str () = Derived.user_name (model ())

let cur_game () : Game.t option = Derived.game (model ())

(* ---- player list / role config (port of GameConfig) ---- *)
let update_player_list ~(users : (string * lobby_user) list) ~notify (m : Model.t) : Model.t =
  let name_list = List.map users ~f:(fun (_, u) -> u.name) in
  if List.is_empty m.player_list
  then { m with player_list = name_list }
  else (
    let removed = Util.difference m.player_list name_list in
    let new_players = Util.difference name_list m.player_list in
    if notify
    then (
      List.iter removed ~f:(fun r -> Toast.show (r ^ " left the lobby"));
      List.iter new_players ~f:(fun p -> Toast.show (p ^ " joined the lobby")));
    { m with player_list = Util.difference m.player_list removed @ new_players })
;;

let update_roles ~roles (m : Model.t) : Model.t =
  { m with selected_roles = String.Set.of_list roles }
;;

(* ---- lobby subscription lifecycle ---- *)
let stop_lobby () =
  List.iter !lobby_unsubs ~f:(fun u -> u ());
  lobby_unsubs := []
;;

let unsubscribe_from_lobby () =
  stop_lobby ();
  update ~f:(fun m -> { m with lobby = None })
;;

let role_doc_updated snap =
  let rd =
    if Ffi.snapshot_exists snap then Parse.role_doc (Ffi.snapshot_data snap) else None
  in
  update_lobby ~f:(fun l -> { l with role = rd })
;;

let lobby_doc_updated snap =
  let m = model () in
  match m.lobby with
  | None -> ()
  | Some lob ->
    if not (Ffi.snapshot_exists snap)
    then unsubscribe_from_lobby ()
    else (
      let new_data = Parse.lobby_data (Ffi.snapshot_data snap) in
      let game = Game.create new_data.game ~role_map:Avalonlib.role_map in
      let old_data = lob.data in
      let base =
        { m with Model.lobby = Some { lob with data = Some new_data; game = Some game } }
      in
      let connected_case (m : Model.t) =
        let m =
          { m with Model.lobby = Option.map m.lobby ~f:(fun l -> { l with connected = true }) }
        in
        let m = update_player_list ~users:new_data.users ~notify:false m in
        let m =
          if List.is_empty new_data.game.roles
          then m
          else update_roles ~roles:new_data.game.roles m
        in
        Ffi.set_document_title (sprintf "Avalon - %s - %s" lob.name (Derived.user_name m));
        m
      in
      let final =
        match old_data with
        | None -> connected_case base
        | Some old when not (String.equal old.name new_data.name) -> connected_case base
        | Some old ->
          let m = ref base in
          if not (String.equal old.admin.uid new_data.admin.uid)
          then (
            let is_admin =
              match (!m).user with
              | Some u -> String.equal u.uid new_data.admin.uid
              | None -> false
            in
            Toast.show
              (if is_admin
               then "You are now lobby administrator"
               else sprintf "%s became lobby administrator" new_data.admin.name));
          let old_keys = List.map old.users ~f:fst in
          let new_keys = String.Set.of_list (List.map new_data.users ~f:fst) in
          let users_changed =
            List.length old.users <> List.length new_data.users
            || not (List.for_all old_keys ~f:(Set.mem new_keys))
          in
          if users_changed
          then m := update_player_list ~users:new_data.users ~notify:true !m;
          if not (equal_game_state old.game.state new_data.game.state)
          then
            if equal_game_state new_data.game.state Active
            then (
              m := update_roles ~roles:new_data.game.roles !m;
              m := { !m with modal = Start_game })
            else m := { !m with modal = End_game; show_role_sheet = false }
          else if not (String.equal old.game.phase new_data.game.phase)
          then (
            let phase = new_data.game.phase in
            if String.equal phase "TEAM_PROPOSAL"
            then
              if game.current_proposal_idx > 0
              then (
                match Game.last_proposal game with
                | Some p -> Toast.show (sprintf "%s's team rejected" p.proposer)
                | None -> ())
              else m := { !m with modal = Mission_result }
            else if String.equal phase "ASSASSINATION"
            then m := { !m with modal = Mission_result }
            else if String.equal phase "MISSION_VOTE"
            then (
              match game.current_proposal with
              | Some p -> Toast.show (sprintf "%s's team approved" p.proposer)
              | None -> ())
            else if String.equal phase "PROPOSAL_VOTE"
            then (
              match game.current_proposal with
              | Some p -> Toast.show (sprintf "%s has proposed a team" p.proposer)
              | None -> ()));
          !m
      in
      set final)
;;

let subscribe_to_lobby name =
  let m = model () in
  match m.lobby with
  | Some _ -> ()
  | None ->
    let uid = Option.value_map m.user ~default:"" ~f:(fun u -> u.uid) in
    set { m with lobby = Some { name; connected = false; data = None; role = None; game = None } };
    let u1 =
      Ffi.on_snapshot (Ffi.doc [ "lobbies"; name ]) ~on_next:lobby_doc_updated ~on_error:(fun _ -> ())
    in
    let u2 =
      Ffi.on_snapshot
        (Ffi.doc [ "lobbies"; name; "roles"; uid ])
        ~on_next:role_doc_updated
        ~on_error:(fun _ -> ())
    in
    lobby_unsubs := [ u1; u2 ]
;;

(* ---- user doc + auth ---- *)
let user_doc_updated snap =
  update ~f:(fun m -> { m with auth_initialized = true });
  if not (Ffi.snapshot_exists snap)
  then (
    let au = Ffi.current_user () in
    if not (Ffi.is_nullish au)
    then (
      let uid = Ffi.field_string au "uid" in
      let name =
        Option.value (Ffi.field_string_opt au "displayName") ~default:"Anonymous"
      in
      let email = Ffi.field_string_opt au "email" in
      update ~f:(fun m ->
        { m with user = Some { uid; name; email; lobby = None; stats = None } })))
  else (
    let u = Parse.user_data (Ffi.snapshot_data snap) in
    update ~f:(fun m -> { m with user = Some u });
    let m = model () in
    match u.lobby, m.lobby with
    | None, Some lob ->
      let old = lob.name in
      unsubscribe_from_lobby ();
      Toast.show (sprintf "You've been disconnected from %s" old)
    | Some lobby_name, None -> subscribe_to_lobby lobby_name
    | _ -> ())
;;

let on_auth_state_changed user =
  if Ffi.is_nullish user
  then (
    (match Ffi.url_get_param "confirmEmail" with
     | Some email ->
       let p =
         Js.Unsafe.meth_call
           (Ffi.auth ())
           "signInWithEmailLink"
           [| Ffi.of_string email; Ffi.of_string (Ffi.window_href ()) |]
       in
       Ffi.promise_then
         p
         ~on_ok:(fun _ ->
           update ~f:(fun m -> { m with confirming_email_error = None });
           Ffi.replace_state_to_pathname ())
         ~on_err:(fun e ->
           update ~f:(fun m ->
             { m with
               confirming_email_error = Some (Ffi.field_string e "message")
             ; auth_initialized = true
             });
           Ffi.replace_state_to_pathname ())
     | None -> update ~f:(fun m -> { m with auth_initialized = true }));
    (match !user_doc_unsub with
     | Some u ->
       u ();
       user_doc_unsub := None
     | None -> ());
    update ~f:(fun m -> { m with user = None }))
  else (
    (* Call login unconditionally (even for anonymous users with no email) so the server
       creates the user doc; otherwise createLobby fails with "No such user". *)
    Api.login (Ffi.field_string_opt user "email");
    let unsub =
      Ffi.on_snapshot
        (Ffi.doc [ "users"; Ffi.field_string user "uid" ])
        ~on_next:user_doc_updated
        ~on_error:(fun _ -> ())
    in
    user_doc_unsub := Some unsub;
    Ffi.get_doc
      (Ffi.doc [ "stats"; "global" ])
      ~on_ok:(fun snap ->
        let d = Ffi.snapshot_data snap in
        if not (Ffi.is_nullish d)
        then update ~f:(fun m -> { m with global_stats = Some (Parse.stats d) }))
      ~on_err:(fun _ -> ());
    Ffi.replace_state_to_pathname ())
;;

let init () =
  Ffi.init_app firebase_config;
  if Ffi.url_has_param "purchaseSuccess"
  then Ffi.alert "Thank you. Your support means a lot."
  else if Ffi.url_has_param "purchaseCanceled"
  then Ffi.alert "Maybe next time?";
  let cb = Js.wrap_callback (fun user -> on_auth_state_changed user) in
  let _ : Ffi.any =
    Js.Unsafe.meth_call (Ffi.auth ()) "onAuthStateChanged" [| Ffi.inject cb |]
  in
  ()
;;

(* ---- actions invoked by the UI ---- *)
let noop_ok () = ()
let noop_err (_ : string) = ()

let create_lobby ?(on_ok = noop_ok) ?(on_err = noop_err) ~name () =
  Api.create_lobby
    ~name
    ~on_ok:(fun json ->
      subscribe_to_lobby (Ffi.field_string json "lobby");
      on_ok ())
    ~on_err
;;

let join_lobby ?(on_ok = noop_ok) ?(on_err = noop_err) ~name ~lobby () =
  Api.join_lobby
    ~name
    ~lobby
    ~on_ok:(fun json ->
      subscribe_to_lobby (Ffi.field_string json "lobby");
      on_ok ())
    ~on_err
;;

let leave_lobby () =
  Api.leave_lobby ~lobby:(lobby_name ()) ~on_ok:(fun _ -> unsubscribe_from_lobby ()) ()
;;

let kick_player ?(on_ok = noop_ok) ?(on_err = noop_err) name =
  Api.kick_player
    ~lobby:(lobby_name ())
    ~name
    ~on_ok:(fun _ -> on_ok ())
    ~on_err
    ()
;;

let cancel_game ?(on_ok = noop_ok) ?(on_err = noop_err) () =
  Api.cancel_game
    ~lobby:(lobby_name ())
    ~name:(user_name_str ())
    ~on_ok:(fun _ -> on_ok ())
    ~on_err
    ()
;;

let vote_team ?(on_ok = noop_ok) ?(on_err = noop_err) vote =
  match cur_game () with
  | None -> ()
  | Some g ->
    Api.vote_team
      ~lobby:(lobby_name ())
      ~name:(user_name_str ())
      ~mission:g.current_mission_idx
      ~proposal:g.current_proposal_idx
      ~vote
      ~on_ok:(fun _ -> on_ok ())
      ~on_err
      ()
;;

let start_game ?(on_ok = noop_ok) ?(on_err = noop_err) ~in_game_log () =
  let m = model () in
  Api.start_game
    ~lobby:(lobby_name ())
    ~player_list:m.player_list
    ~roles:(Derived.selected_role_list m)
    ~in_game_log
    ~on_ok:(fun _ -> on_ok ())
    ~on_err
    ()
;;

let propose_team ?(on_ok = noop_ok) ?(on_err = noop_err) team =
  match cur_game () with
  | None -> ()
  | Some g ->
    Api.propose_team
      ~lobby:(lobby_name ())
      ~name:(user_name_str ())
      ~mission:g.current_mission_idx
      ~proposal:g.current_proposal_idx
      ~team
      ~on_ok:(fun _ -> on_ok ())
      ~on_err
      ()
;;

let do_mission ?(on_ok = noop_ok) ?(on_err = noop_err) vote =
  match cur_game () with
  | None -> ()
  | Some g ->
    Api.do_mission
      ~lobby:(lobby_name ())
      ~name:(user_name_str ())
      ~mission:g.current_mission_idx
      ~proposal:g.current_proposal_idx
      ~vote
      ~on_ok:(fun _ -> on_ok ())
      ~on_err
      ()
;;

let assassinate ?(on_ok = noop_ok) ?(on_err = noop_err) target =
  Api.assassinate
    ~lobby:(lobby_name ())
    ~name:(user_name_str ())
    ~target
    ~on_ok:(fun _ -> on_ok ())
    ~on_err
    ()
;;

let logout () =
  let _ : Ffi.any = Js.Unsafe.meth_call (Ffi.auth ()) "signOut" [||] in
  ()
;;

let sign_in_anonymously ?(on_err = noop_err) () =
  Ffi.promise_then
    (Js.Unsafe.meth_call (Ffi.auth ()) "signInAnonymously" [||])
    ~on_ok:(fun _ -> ())
    ~on_err:(fun e -> on_err (Ffi.field_string e "message"))
;;

let email_regex_ok email =
  let f =
    Js.Unsafe.js_expr "(function(e){return /^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(e);})"
  in
  Js.to_bool (Js.Unsafe.fun_call f [| Ffi.of_string email |])
;;

let whitelist = [ "gmail.com"; "yahoo.com"; "outlook.com"; "hotmail.com"; "live.com" ]

let send_sign_in_link ~email ~on_ok ~on_err =
  let hostname = Ffi.window_origin () ^ "/" in
  let url =
    Js.to_string
      (Js.Unsafe.fun_call
         (Js.Unsafe.js_expr "encodeURI")
         [| Ffi.of_string (hostname ^ "?confirmEmail=" ^ email) |])
  in
  let settings = Ffi.obj [ "url", Ffi.of_string url; "handleCodeInApp", Ffi.of_bool true ] in
  Ffi.promise_then
    (Js.Unsafe.meth_call
       (Ffi.auth ())
       "sendSignInLinkToEmail"
       [| Ffi.of_string email; Ffi.inject settings |])
    ~on_ok:(fun _ -> on_ok ())
    ~on_err:(fun e -> on_err (Ffi.field_string e "message"))
;;

let submit_email_addr ?(on_ok = noop_ok) ?(on_err = noop_err) email =
  if not (email_regex_ok email)
  then on_err "Not a valid email address"
  else (
    let domain =
      match String.split email ~on:'@' with
      | _ :: d :: _ -> d
      | _ -> ""
    in
    let proceed () = send_sign_in_link ~email ~on_ok ~on_err in
    if List.mem whitelist domain ~equal:String.equal
    then proceed ()
    else (
      let p =
        Js.Unsafe.fun_call
          (Js.Unsafe.js_expr "fetch")
          [| Ffi.of_string ("https://api.mailcheck.ai/domain/" ^ domain) |]
      in
      Ffi.promise_then
        p
        ~on_err:(fun _ -> on_err "Cannot verify email. Try again later")
        ~on_ok:(fun resp ->
          Ffi.promise_then
            (Js.Unsafe.meth_call resp "json" [||])
            ~on_err:(fun _ -> on_err "Cannot verify email. Try again later")
            ~on_ok:(fun data ->
              let mx = Ffi.field_bool data "mx" in
              let disposable = Ffi.field_bool data "disposable" in
              if mx && not disposable
              then proceed ()
              else on_err "This email address appears to be invalid or disposable"))))
;;

(* ---- UI-only state setters ---- *)
let set_player_list list = update ~f:(fun m -> { m with player_list = list })

let toggle_role ~name ~selected =
  update ~f:(fun m ->
    let selected_roles =
      if selected then Set.add m.selected_roles name else Set.remove m.selected_roles name
    in
    { m with selected_roles })
;;

let set_modal modal = update ~f:(fun m -> { m with modal })
let set_show_role_sheet b = update ~f:(fun m -> { m with show_role_sheet = b })
