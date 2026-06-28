open! Core
open Js_of_ocaml

(** REST client, port of client/src/avalon-api-rest.ts. Each call fetches a fresh
    Firebase ID token, then POSTs JSON to /api/<endpoint> with the X-Avalon-Auth header. *)

let post
  ~(endpoint : string)
  ~(data : (string * Ffi.any) list)
  ~(on_ok : Ffi.any -> unit)
  ~(on_err : string -> unit)
  : unit
  =
  let user = Ffi.current_user () in
  if Ffi.is_nullish user
  then on_err "Not signed in"
  else
    Ffi.promise_then
      (Js.Unsafe.meth_call user "getIdToken" [| Ffi.of_bool false |])
      ~on_err:(fun _ -> on_err "Could not get auth token")
      ~on_ok:(fun id_token ->
        let url = "/api/" ^ endpoint in
        let headers =
          Ffi.obj
            [ "Content-Type", Ffi.of_string "application/json"
            ; "X-Avalon-Auth", id_token
            ]
        in
        let body =
          Js.Unsafe.fun_call
            (Js.Unsafe.js_expr "JSON.stringify")
            [| Ffi.inject (Ffi.obj data) |]
        in
        let opts =
          Ffi.obj
            [ "method", Ffi.of_string "POST"
            ; "headers", Ffi.inject headers
            ; "body", Ffi.inject body
            ]
        in
        let fetch_p =
          Js.Unsafe.fun_call
            (Js.Unsafe.js_expr "fetch")
            [| Ffi.of_string url; Ffi.inject opts |]
        in
        Ffi.promise_then
          fetch_p
          ~on_err:(fun _ -> on_err "Network error")
          ~on_ok:(fun resp ->
            let ok = Ffi.to_bool (Ffi.get resp "ok") in
            Ffi.promise_then
              (Js.Unsafe.meth_call resp "json" [||])
              ~on_err:(fun _ ->
                if ok then on_ok (Js.Unsafe.js_expr "({})") else on_err "Request failed")
              ~on_ok:(fun json ->
                if ok
                then on_ok json
                else (
                  let msg =
                    match Ffi.field_string_opt json "message" with
                    | Some m -> m
                    | None -> Ffi.field_string resp "statusText"
                  in
                  on_err msg))))
;;

let ignore_ok _ = ()
let ignore_err _ = ()

let login ?(on_ok = ignore_ok) ?(on_err = ignore_err) (email : string option) =
  let email_value = match email with Some e -> Ffi.of_string e | None -> Ffi.null_value in
  post ~endpoint:"login" ~data:[ "email", email_value ] ~on_ok ~on_err
;;

let join_lobby ~on_ok ~on_err ~name ~lobby =
  post
    ~endpoint:"joinLobby"
    ~data:[ "name", Ffi.of_string name; "lobby", Ffi.of_string lobby ]
    ~on_ok
    ~on_err
;;

let create_lobby ~on_ok ~on_err ~name =
  post ~endpoint:"createLobby" ~data:[ "name", Ffi.of_string name ] ~on_ok ~on_err
;;

let leave_lobby ?(on_ok = ignore_ok) ?(on_err = ignore_err) ~lobby () =
  post ~endpoint:"leaveLobby" ~data:[ "lobby", Ffi.of_string lobby ] ~on_ok ~on_err
;;

let kick_player ?(on_ok = ignore_ok) ?(on_err = ignore_err) ~lobby ~name () =
  post
    ~endpoint:"kickPlayer"
    ~data:[ "lobby", Ffi.of_string lobby; "name", Ffi.of_string name ]
    ~on_ok
    ~on_err
;;

let cancel_game ?(on_ok = ignore_ok) ?(on_err = ignore_err) ~lobby ~name () =
  post
    ~endpoint:"cancelGame"
    ~data:[ "lobby", Ffi.of_string lobby; "name", Ffi.of_string name ]
    ~on_ok
    ~on_err
;;

let vote_team ?(on_ok = ignore_ok) ?(on_err = ignore_err) ~lobby ~name ~mission ~proposal ~vote () =
  post
    ~endpoint:"voteTeam"
    ~data:
      [ "lobby", Ffi.of_string lobby
      ; "name", Ffi.of_string name
      ; "mission", Ffi.of_int mission
      ; "proposal", Ffi.of_int proposal
      ; "vote", Ffi.of_bool vote
      ]
    ~on_ok
    ~on_err
;;

let start_game ?(on_ok = ignore_ok) ?(on_err = ignore_err) ~lobby ~player_list ~roles ~in_game_log () =
  post
    ~endpoint:"startGame"
    ~data:
      [ "lobby", Ffi.of_string lobby
      ; "playerList", Ffi.of_str_list player_list
      ; "roles", Ffi.of_str_list roles
      ; "options", Ffi.obj [ "inGameLog", Ffi.of_bool in_game_log ]
      ]
    ~on_ok
    ~on_err
;;

let propose_team ?(on_ok = ignore_ok) ?(on_err = ignore_err) ~lobby ~name ~mission ~proposal ~team () =
  post
    ~endpoint:"proposeTeam"
    ~data:
      [ "lobby", Ffi.of_string lobby
      ; "name", Ffi.of_string name
      ; "mission", Ffi.of_int mission
      ; "proposal", Ffi.of_int proposal
      ; "team", Ffi.of_str_list team
      ]
    ~on_ok
    ~on_err
;;

let do_mission ?(on_ok = ignore_ok) ?(on_err = ignore_err) ~lobby ~name ~mission ~proposal ~vote () =
  post
    ~endpoint:"doMission"
    ~data:
      [ "lobby", Ffi.of_string lobby
      ; "name", Ffi.of_string name
      ; "mission", Ffi.of_int mission
      ; "proposal", Ffi.of_int proposal
      ; "vote", Ffi.of_bool vote
      ]
    ~on_ok
    ~on_err
;;

let assassinate ?(on_ok = ignore_ok) ?(on_err = ignore_err) ~lobby ~name ~target () =
  post
    ~endpoint:"assassinate"
    ~data:
      [ "lobby", Ffi.of_string lobby
      ; "name", Ffi.of_string name
      ; "target", Ffi.of_string target
      ]
    ~on_ok
    ~on_err
;;
