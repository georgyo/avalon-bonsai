open! Core

(** Game data model, ported from client/src/types.ts and common/avalonlib.ts. All values
    are immutable; "selected" role state lives in {!State.Model}, not on the role records. *)

type team =
  | Good
  | Evil
[@@deriving sexp, equal, compare]

let team_to_string = function
  | Good -> "good"
  | Evil -> "evil"
;;

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

let proposal_state_of_string = function
  | "APPROVED" -> Approved
  | "REJECTED" -> Rejected
  | _ -> Pending
;;

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

let mission_state_of_string = function
  | "SUCCESS" -> Success
  | "FAIL" -> Fail
  | _ -> M_pending
;;

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

let outcome_state_of_string = function
  | "GOOD_WIN" -> Good_win
  | "EVIL_WIN" -> Evil_win
  | _ -> Canceled
;;

type game_outcome =
  { state : outcome_state
  ; message : string
  ; assassinated : string option
  ; roles : role_assignment list
  ; (* one entry per mission: player name -> success/fail vote *)
    votes : bool String.Map.t list
  }
[@@deriving sexp, equal, compare]

type game_state =
  | Init
  | Active
  | Game_ended
[@@deriving sexp, equal, compare]

let game_state_of_string = function
  | "ACTIVE" -> Active
  | "ENDED" -> Game_ended
  | _ -> Init
;;

(* The in-game phase, from server/types.ts: game.phase is one of these four tokens.
   [Unknown_phase] preserves the raw string for anything unexpected (including the
   empty/absent phase before a game starts). *)
type phase =
  | Team_proposal
  | Proposal_vote
  | Mission_vote
  | Assassination
  | Unknown_phase of string
[@@deriving sexp, equal, compare]

let phase_of_string = function
  | "TEAM_PROPOSAL" -> Team_proposal
  | "PROPOSAL_VOTE" -> Proposal_vote
  | "MISSION_VOTE" -> Mission_vote
  | "ASSASSINATION" -> Assassination
  | s -> Unknown_phase s
;;

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
  ; (* preserves Firestore key order *)
    users : (string * lobby_user) list
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

let empty_stats = { games = 0; good = 0; wins = 0; good_wins = 0; playtime_seconds = 0 }

type user_data =
  { uid : string
  ; name : string
  ; email : string option
  ; lobby : string option
  ; stats : stats option
  }
[@@deriving sexp, equal, compare]

(* The role doc stored per-uid in Firestore, with the role name resolved to a full
   {!role}. [sees] and [assassin] come straight from the doc. *)
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
