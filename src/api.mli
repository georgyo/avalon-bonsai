open! Core

(** REST client (port of client/src/avalon-api-rest.ts). Each call fetches a fresh
    Firebase ID token from the given [auth] handle's current user, then POSTs JSON
    directly to [https://api.avalon.onl/api/<endpoint>] with it (no same-origin proxy;
    that host serves CORS headers, see the note in the implementation). [on_ok] receives
    the parsed JSON response; [on_err] receives an error message. *)

val login
  :  ?on_ok:(Ffi.any -> unit)
  -> ?on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> string option
  -> unit

val join_lobby
  :  on_ok:(Ffi.any -> unit)
  -> on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> name:string
  -> lobby:string
  -> unit

val create_lobby
  :  on_ok:(Ffi.any -> unit)
  -> on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> name:string
  -> unit

val leave_lobby
  :  ?on_ok:(Ffi.any -> unit)
  -> ?on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> lobby:string
  -> unit
  -> unit

val kick_player
  :  ?on_ok:(Ffi.any -> unit)
  -> ?on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> lobby:string
  -> name:string
  -> unit
  -> unit

val cancel_game
  :  ?on_ok:(Ffi.any -> unit)
  -> ?on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> lobby:string
  -> name:string
  -> unit
  -> unit

val vote_team
  :  ?on_ok:(Ffi.any -> unit)
  -> ?on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> lobby:string
  -> name:string
  -> mission:int
  -> proposal:int
  -> vote:bool
  -> unit
  -> unit

val start_game
  :  ?on_ok:(Ffi.any -> unit)
  -> ?on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> lobby:string
  -> player_list:string list
  -> roles:string list
  -> in_game_log:bool
  -> unit
  -> unit

val propose_team
  :  ?on_ok:(Ffi.any -> unit)
  -> ?on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> lobby:string
  -> name:string
  -> mission:int
  -> proposal:int
  -> team:string list
  -> unit
  -> unit

val do_mission
  :  ?on_ok:(Ffi.any -> unit)
  -> ?on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> lobby:string
  -> name:string
  -> mission:int
  -> proposal:int
  -> vote:bool
  -> unit
  -> unit

val assassinate
  :  ?on_ok:(Ffi.any -> unit)
  -> ?on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> lobby:string
  -> name:string
  -> target:string
  -> unit
  -> unit
