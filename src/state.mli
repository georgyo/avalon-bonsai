open! Core
open Avalon_core
open Types

(** The application store: an immutable {!Model.t} snapshot in a single
    [Bonsai.Expert.Var], updated imperatively by the Firebase listeners, plus the
    derived predicates and the UI-invoked actions. Internals (the Var, the Firebase
    subscription bookkeeping, the transition logic) are private. *)

module Model : sig
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
end

(** Derived predicates (port of the AvalonGame getters). *)
module Derived : sig
  open Model

  val user_name : t -> string
  val is_in_lobby : t -> bool
  val initialized : t -> bool
  val is_logged_in : t -> bool
  val admin : t -> Types.admin option
  val is_admin : t -> bool
  val game : t -> Game.t option
  val role : t -> role_doc option
  val is_game_in_progress : t -> bool
end

(** The current model snapshot. *)
val model : unit -> Model.t

(** The model as a Bonsai value driving the UI. *)
val value : unit -> Model.t Bonsai.t

(** Wire up Firebase auth + initial listeners. Call once at startup. *)
val init : unit -> unit

(* actions invoked by the UI; [on_ok]/[on_err] default to no-ops *)
val create_lobby : ?on_ok:(unit -> unit) -> ?on_err:(string -> unit) -> name:string -> unit -> unit
val join_lobby : ?on_ok:(unit -> unit) -> ?on_err:(string -> unit) -> name:string -> lobby:string -> unit -> unit
val leave_lobby : unit -> unit
val kick_player : ?on_ok:(unit -> unit) -> ?on_err:(string -> unit) -> string -> unit
val cancel_game : ?on_ok:(unit -> unit) -> ?on_err:(string -> unit) -> unit -> unit
val vote_team : ?on_ok:(unit -> unit) -> ?on_err:(string -> unit) -> bool -> unit
val start_game : ?on_ok:(unit -> unit) -> ?on_err:(string -> unit) -> in_game_log:bool -> unit -> unit
val propose_team : ?on_ok:(unit -> unit) -> ?on_err:(string -> unit) -> string list -> unit
val do_mission : ?on_ok:(unit -> unit) -> ?on_err:(string -> unit) -> bool -> unit
val assassinate : ?on_ok:(unit -> unit) -> ?on_err:(string -> unit) -> string -> unit
val logout : unit -> unit
val sign_in_anonymously : ?on_err:(string -> unit) -> unit -> unit
val submit_email_addr : ?on_ok:(unit -> unit) -> ?on_err:(string -> unit) -> string -> unit
val toggle_role : name:string -> selected:bool -> unit
val set_modal : Model.modal -> unit
val set_show_role_sheet : bool -> unit
val set_player_list : string list -> unit
