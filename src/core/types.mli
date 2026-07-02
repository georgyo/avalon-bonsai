open! Core

(** The shared game data model (ported from client/src/types.ts and common/avalonlib.ts).
    These types are the common vocabulary used across the whole project, so the interface
    re-exports them with their generated [sexp]/[equal]/[compare] functions. *)

type team =
  | Good
  | Evil
[@@deriving sexp, equal, compare]

val team_to_string : team -> string

type role =
  { name : string
  ; team : team
  ; sees : string list
  ; description : string
  ; selectable : bool
  ; filler : bool
  ; default_selected : bool
  ; assassination_priority : int option
  }
[@@deriving sexp, equal, compare, fields ~getters]

type proposal_state =
  | Pending
  | Approved
  | Rejected
[@@deriving sexp, equal, compare]

val proposal_state_of_string : string -> proposal_state

type proposal =
  { proposer : string
  ; team : string list
  ; votes : string list
  ; state : proposal_state
  }
[@@deriving sexp, equal, compare]

type mission_state =
  | M_pending
  | Success
  | Fail
[@@deriving sexp, equal, compare]

val mission_state_of_string : string -> mission_state

type mission =
  { state : mission_state
  ; team : string list
  ; team_size : int
  ; fails_required : int
  ; num_fails : int
  ; proposals : proposal list
  }
[@@deriving sexp, equal, compare]

type role_assignment =
  { name : string
  ; role : string
  ; assassin : bool
  }
[@@deriving sexp, equal, compare]

type outcome_state =
  | Good_win
  | Evil_win
  | Canceled
[@@deriving sexp, equal, compare]

val outcome_state_of_string : string -> outcome_state

type game_outcome =
  { state : outcome_state
  ; message : string
  ; assassinated : string option
  ; roles : role_assignment list
  ; votes : bool String.Map.t list
  }
[@@deriving sexp, equal, compare]

type game_state =
  | Init
  | Active
  | Game_ended
[@@deriving sexp, equal, compare]

val game_state_of_string : string -> game_state

(** The in-game phase (server/types.ts: [game.phase]). [Unknown_phase] carries the raw
    string of any unexpected token (including the empty/absent phase before a game
    starts). *)
type phase =
  | Team_proposal
  | Proposal_vote
  | Mission_vote
  | Assassination
  | Unknown_phase of string
[@@deriving sexp, equal, compare]

val phase_of_string : string -> phase

type game_data =
  { state : game_state
  ; phase : phase
  ; players : string list
  ; roles : string list
  ; missions : mission list
  ; outcome : game_outcome option
  ; in_game_log : bool
  }
[@@deriving sexp, equal, compare]

type lobby_user =
  { name : string
  ; uid : string option
  }
[@@deriving sexp, equal, compare]

type admin =
  { uid : string
  ; name : string
  }
[@@deriving sexp, equal, compare]

type lobby_data =
  { name : string
  ; admin : admin
  ; users : (string * lobby_user) list
  ; game : game_data
  }
[@@deriving sexp, equal, compare]

type stats =
  { games : int
  ; good : int
  ; wins : int
  ; good_wins : int
  ; playtime_seconds : int
  }
[@@deriving sexp, equal, compare]

val empty_stats : stats

type user_data =
  { uid : string
  ; name : string
  ; email : string option
  ; lobby : string option
  ; stats : stats option
  }
[@@deriving sexp, equal, compare]

type role_doc =
  { role : role
  ; sees : string list
  ; assassin : bool
  }
[@@deriving sexp, equal, compare]

type proposer_stats =
  { name : string
  ; mutable good_proposals : int
  ; mutable bad_proposals : int
  }
