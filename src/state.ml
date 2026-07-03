open! Core
open Js_of_ocaml
open Bonsai_web
open Avalon_core
open Types

(** The reactive store. [Model.t] is an immutable snapshot held in a {!Bonsai.Var};
    Firebase listeners and UI actions push new snapshots into it. This replaces the Vue
    [AvalonGame] + [LobbySubscription] + [GameConfig] objects and the mitt EventBus. *)

module Auth = Firebase.Auth
module Firestore = Firebase.Firestore
module Snapshot = Firebase.Firestore.Document_snapshot

let firebase_config : Firebase.App.options =
  { api_key = "AIzaSyCwhCvO8NbTusBaHmHHnNT7yC0_11UL2RI"
  ; auth_domain = "georgyo-avalon.firebaseapp.com"
  ; database_url = "https://georgyo-avalon-default-rtdb.firebaseio.com"
  ; project_id = "georgyo-avalon"
  ; storage_bucket = "georgyo-avalon.appspot.com"
  ; messaging_sender_id = "1000859874531"
  ; app_id = "1:1000859874531:web:789f785c58c574bff181d6"
  }
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
    ; connection_error : string option
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
    ; connection_error = None
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

(* ---- the Firebase service handles ---- *)

(* Mirroring the modular SDK, the bindings hold no global state: [init] initializes the
   app and derives the Auth/Firestore handles once, and everything below threads them into
   each call explicitly. *)
let services : (Auth.t * Firestore.t) option ref = ref None

let auth () =
  match !services with
  | Some (auth, _) -> auth
  | None -> failwith "Firebase services are not initialized (State.init has not run)"
;;

let firestore () =
  match !services with
  | Some (_, db) -> db
  | None -> failwith "Firebase services are not initialized (State.init has not run)"
;;

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
let update_player_list ~(users : (string * lobby_user) list) ~notify (m : Model.t)
  : Model.t
  =
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
  (* Also reset lobby-scoped transient state so a later join starts clean: a surviving
     [player_list] would make [update_player_list] merge the new lobby's roster against
     the old lobby's order, and that order is what [start_game] sends as seating. *)
  update ~f:(fun m ->
    { m with
      lobby = None
    ; player_list = []
    ; selected_roles = Model.default_selected_roles
    ; modal = Model.No_modal
    ; show_role_sheet = false
    })
;;

(* Exception barrier for Firebase snapshot/get callbacks: the Parse functions can raise on
   type-malformed remote data, and an exception escaping into the Firebase observer kills
   the listener silently. Log it and tell the user instead. *)
let on_callback_exn exn =
  Console.console##error (Js.string (Exn.to_string exn));
  Toast.show "Received malformed data from the server"
;;

let role_doc_updated snap =
  try
    let rd =
      match Snapshot.data snap with
      | Some d -> Parse.role_doc d
      | None -> None
    in
    update_lobby ~f:(fun l -> { l with role = rd })
  with
  | exn -> on_callback_exn exn
;;

let lobby_doc_updated snap =
  try
    let m = model () in
    match m.lobby with
    | None -> ()
    | Some lob ->
      (match Snapshot.data snap with
       | None -> unsubscribe_from_lobby () (* lobby deleted *)
       | Some snap_data ->
         let new_data = Parse.lobby_data snap_data in
         let game = Game.create new_data.game ~role_map:Avalonlib.role_map in
         let old_data = lob.data in
         let base =
           { m with
             Model.lobby = Some { lob with data = Some new_data; game = Some game }
           }
         in
         let connected_case (m : Model.t) =
           let m =
             { m with
               Model.lobby = Option.map m.lobby ~f:(fun l -> { l with connected = true })
             }
           in
           let m = update_player_list ~users:new_data.users ~notify:false m in
           let m =
             if List.is_empty new_data.game.roles
             then m
             else update_roles ~roles:new_data.game.roles m
           in
           Ffi.set_document_title
             (sprintf "Avalon - %s - %s" lob.name (Derived.user_name m));
           m
         in
         let final =
           match old_data with
           | None -> connected_case base
           | Some old when not (String.equal old.name new_data.name) ->
             connected_case base
           | Some old ->
             let m = ref base in
             if not (String.equal old.admin.uid new_data.admin.uid)
             then (
               let is_admin =
                 match !m.user with
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
             else if not (equal_phase old.game.phase new_data.game.phase)
             then (
               match new_data.game.phase with
               | Team_proposal ->
                 if game.current_proposal_idx > 0
                 then (
                   match Game.last_proposal game with
                   | Some p -> Toast.show (sprintf "%s's team rejected" p.proposer)
                   | None -> ())
                 else m := { !m with modal = Mission_result }
               | Assassination -> m := { !m with modal = Mission_result }
               | Mission_vote ->
                 (match game.current_proposal with
                  | Some p -> Toast.show (sprintf "%s's team approved" p.proposer)
                  | None -> ())
               | Proposal_vote ->
                 (match game.current_proposal with
                  | Some p -> Toast.show (sprintf "%s has proposed a team" p.proposer)
                  | None -> ())
               | Unknown_phase _ -> ());
             !m
         in
         set final)
  with
  | exn -> on_callback_exn exn
;;

let subscribe_to_lobby name =
  let m = model () in
  match m.lobby with
  | Some _ -> ()
  | None ->
    set
      { m with
        lobby = Some { name; connected = false; data = None; role = None; game = None }
      };
    let u1 =
      Firestore.on_snapshot
        (Firestore.doc (firestore ()) [ "lobbies"; name ])
        ~on_next:lobby_doc_updated
          (* Snapshot-listener errors are terminal: the listener will never fire again, so
             a transient toast would leave a UI that looks live but never updates. Surface
             the same persistent reload screen as a Firebase-load failure. *)
        ~on_error:(fun _ ->
          update ~f:(fun m ->
            { m with
              connection_error = Some "Lost connection to the lobby. Please reload."
            }))
    in
    (* The role doc lives at lobbies/<name>/roles/<uid>. With no signed-in user (or an
       empty uid) there is no such doc, and an empty path segment makes Firestore's [doc]
       throw synchronously — so only register the role listener when a non-empty uid
       exists. *)
    let role_unsubs =
      match m.user with
      | Some u when not (String.is_empty u.uid) ->
        [ Firestore.on_snapshot
            (Firestore.doc (firestore ()) [ "lobbies"; name; "roles"; u.uid ])
            ~on_next:role_doc_updated
            ~on_error:(fun _ -> ())
        ]
      | Some _ | None -> []
    in
    lobby_unsubs := u1 :: role_unsubs
;;

(* ---- user doc + auth ---- *)

(* A minimal user_data built straight from the auth record, used before/instead of the
   Firestore user doc (e.g. the doc doesn't exist yet, or its listener errored). *)
let synthetic_user () : user_data option =
  Option.map
    (Auth.current_user (auth ()))
    ~f:(fun au ->
      { uid = Auth.User.uid au
      ; name = Option.value (Auth.User.display_name au) ~default:"Anonymous"
      ; email = Auth.User.email au
      ; lobby = None
      ; stats = None
      })
;;

let user_doc_updated snap =
  try
    update ~f:(fun m -> { m with auth_initialized = true });
    match Snapshot.data snap with
    | None -> update ~f:(fun m -> { m with user = synthetic_user () })
    | Some d ->
      let u = Parse.user_data d in
      update ~f:(fun m -> { m with user = Some u });
      let m = model () in
      (match u.lobby, m.lobby with
       | None, Some lob ->
         let old = lob.name in
         unsubscribe_from_lobby ();
         Toast.show (sprintf "You've been disconnected from %s" old)
       | Some lobby_name, None -> subscribe_to_lobby lobby_name
       | Some lobby_name, Some lob when not (String.equal lob.name lobby_name) ->
         (* Another session moved this user to a different lobby: drop the old
            subscription and follow. *)
         unsubscribe_from_lobby ();
         subscribe_to_lobby lobby_name
       | _ -> ())
  with
  | exn -> on_callback_exn exn
;;

let on_auth_state_changed (user : Auth.User.t option) =
  match user with
  | None ->
    (match Ffi.url_get_param "confirmEmail" with
     | Some email ->
       Auth.sign_in_with_email_link
         (auth ())
         ~email
         ~link:(Ffi.window_href ())
         ~on_ok:(fun () ->
           update ~f:(fun m -> { m with confirming_email_error = None });
           Ffi.replace_state_to_pathname ())
         ~on_err:(fun e ->
           update ~f:(fun m ->
             { m with
               confirming_email_error = Some (Firebase.Error.message e)
             ; auth_initialized = true
             });
           Ffi.replace_state_to_pathname ())
     | None -> update ~f:(fun m -> { m with auth_initialized = true }));
    (match !user_doc_unsub with
     | Some u ->
       u ();
       user_doc_unsub := None
     | None -> ());
    (* Tear down lobby listeners too: they must not keep running unauthenticated, and
       [subscribe_to_lobby] refuses to resubscribe on a later re-login while [m.lobby] is
       still [Some]. *)
    unsubscribe_from_lobby ();
    update ~f:(fun m -> { m with user = None })
  | Some user ->
    (* Call login unconditionally (even for anonymous users with no email) so the server
       creates the user doc; otherwise createLobby fails with "No such user". *)
    Api.login ~auth:(auth ()) (Auth.User.email user) ~on_err:(fun _ ->
      Toast.show "Couldn't reach the game server. Some actions may fail — try reloading.");
    let unsub =
      Firestore.on_snapshot
        (Firestore.doc (firestore ()) [ "users"; Auth.User.uid user ])
        ~on_next:user_doc_updated
          (* Don't hang on a listener error: fall back to a minimal user from auth so the
             UI still renders (login -> lobby-select) instead of spinning forever. *)
        ~on_error:(fun _ ->
          update ~f:(fun m ->
            { m with auth_initialized = true; user = synthetic_user () });
          Toast.show "Couldn't sync your profile. Try reloading.")
    in
    user_doc_unsub := Some unsub;
    Firestore.get_doc
      (Firestore.doc (firestore ()) [ "stats"; "global" ])
      ~on_ok:(fun snap ->
        try
          match Snapshot.data snap with
          | Some d -> update ~f:(fun m -> { m with global_stats = Some (Parse.stats d) })
          | None -> ()
        with
        | exn -> on_callback_exn exn)
      ~on_err:(fun _ -> ());
    Ffi.replace_state_to_pathname ()
;;

let init () =
  (* The Firebase SDK is a vendored bundle embedded ahead of the OCaml code in the page
     bundle; [on_ready] just snapshots [globalThis.__fb] before running the setup. *)
  Firebase.on_ready
    ~on_error:(fun () ->
      update ~f:(fun m ->
        { m with
          connection_error =
            Some
              "Firebase failed to initialize (the embedded Firebase bundle did not run). \
               Try a hard reload; if it persists this is a build problem."
        }))
    (fun () ->
      let app = Firebase.App.initialize_app firebase_config in
      services := Some (Auth.get_auth app, Firestore.get_firestore app);
      if Ffi.url_has_param "purchaseSuccess"
      then Ffi.alert "Thank you. Your support means a lot."
      else if Ffi.url_has_param "purchaseCanceled"
      then Ffi.alert "Maybe next time?";
      ignore
        (Auth.on_auth_state_changed (auth ()) (fun user -> on_auth_state_changed user)
         : unit -> unit))
;;

(* ---- actions invoked by the UI ---- *)
let noop_ok () = ()
let noop_err (_ : string) = ()

(* Default error handler for fire-and-observe actions whose callers don't show an inline
   error: surface the failure as a toast rather than silently dropping it. *)
let toast_err (msg : string) = Toast.show msg

(* A 2xx response whose body isn't the expected JSON (Api hands us an empty object when
   the body fails to parse) has no usable "lobby" field; subscribing with the resulting
   empty string would make the Firestore [doc] call throw. Treat it as an error instead. *)
let subscribe_from_response json ~on_ok ~on_err =
  let lobby = Ffi.field_string json "lobby" in
  if String.is_empty lobby
  then on_err "Unexpected response from the game server"
  else (
    subscribe_to_lobby lobby;
    on_ok ())
;;

let create_lobby ?(on_ok = noop_ok) ?(on_err = toast_err) ~name () =
  Api.create_lobby
    ~auth:(auth ())
    ~name
    ~on_ok:(fun json -> subscribe_from_response json ~on_ok ~on_err)
    ~on_err
;;

let join_lobby ?(on_ok = noop_ok) ?(on_err = toast_err) ~name ~lobby () =
  Api.join_lobby
    ~auth:(auth ())
    ~name
    ~lobby
    ~on_ok:(fun json -> subscribe_from_response json ~on_ok ~on_err)
    ~on_err
;;

let leave_lobby () =
  Api.leave_lobby
    ~auth:(auth ())
    ~lobby:(lobby_name ())
    ~on_ok:(fun _ -> unsubscribe_from_lobby ())
    ~on_err:(fun msg -> Toast.show msg)
    ()
;;

let kick_player ?(on_ok = noop_ok) ?(on_err = toast_err) name =
  Api.kick_player
    ~auth:(auth ())
    ~lobby:(lobby_name ())
    ~name
    ~on_ok:(fun _ -> on_ok ())
    ~on_err
    ()
;;

let cancel_game ?(on_ok = noop_ok) ?(on_err = toast_err) () =
  Api.cancel_game
    ~auth:(auth ())
    ~lobby:(lobby_name ())
    ~name:(user_name_str ())
    ~on_ok:(fun _ -> on_ok ())
    ~on_err
    ()
;;

(* The in-game actions (vote_team / propose_team / do_mission) all target the current
   game's mission and proposal indices in the current lobby; [with_game] extracts those
   and applies [f]. When there is no current game — e.g. a stale click racing the game-end
   snapshot — the action is deliberately a silent no-op: there is nothing valid to send
   and nothing useful to tell the user. *)
let with_game f =
  match cur_game () with
  | None -> ()
  | Some g ->
    f
      ~lobby:(lobby_name ())
      ~name:(user_name_str ())
      ~mission:g.current_mission_idx
      ~proposal:g.current_proposal_idx
      ()
;;

let vote_team ?(on_ok = noop_ok) ?(on_err = toast_err) vote =
  with_game (Api.vote_team ~auth:(auth ()) ~vote ~on_ok:(fun _ -> on_ok ()) ~on_err)
;;

let start_game ?(on_ok = noop_ok) ?(on_err = toast_err) ~in_game_log () =
  let m = model () in
  Api.start_game
    ~auth:(auth ())
    ~lobby:(lobby_name ())
    ~player_list:m.player_list
    ~roles:(Derived.selected_role_list m)
    ~in_game_log
    ~on_ok:(fun _ -> on_ok ())
    ~on_err
    ()
;;

let propose_team ?(on_ok = noop_ok) ?(on_err = toast_err) team =
  with_game (Api.propose_team ~auth:(auth ()) ~team ~on_ok:(fun _ -> on_ok ()) ~on_err)
;;

let do_mission ?(on_ok = noop_ok) ?(on_err = toast_err) vote =
  with_game (Api.do_mission ~auth:(auth ()) ~vote ~on_ok:(fun _ -> on_ok ()) ~on_err)
;;

let assassinate ?(on_ok = noop_ok) ?(on_err = toast_err) target =
  Api.assassinate
    ~auth:(auth ())
    ~lobby:(lobby_name ())
    ~name:(user_name_str ())
    ~target
    ~on_ok:(fun _ -> on_ok ())
    ~on_err
    ()
;;

let logout () =
  Auth.sign_out
    ~on_error:(fun e -> Toast.show ("Logout failed: " ^ Firebase.Error.message e))
    (auth ())
;;

let sign_in_anonymously ?(on_err = noop_err) () =
  Auth.sign_in_anonymously (auth ()) ~on_err:(fun e -> on_err (Firebase.Error.message e))
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
