open Js_of_ocaml

(** Typed bindings to the Firebase v12 modular JS SDK. {!on_ready} loads the ESM build
    itself via a runtime dynamic [import()] (no bundler) before any call is made.

    The handle types below are abstract and distinct, modeled on the [@firebase/auth] and
    [@firebase/firestore] TypeScript definitions, so the type checker rejects mixing them
    up and callers read JS objects only through the typed accessors here. Wrap setup in
    {!on_ready} so it runs after the asynchronous dynamic import has completed. *)

(** [User] — an authenticated user. *)
type user

(** [DocumentReference] — a handle to a Firestore document location. *)
type document_reference

(** [DocumentSnapshot] — the contents of a document at a point in time. *)
type document_snapshot

(** [FirebaseError] — rejection value of a Firebase promise. *)
type error

(** [FirebaseOptions] passed to [initializeApp]. *)
type config =
  { api_key : string
  ; auth_domain : string
  ; database_url : string
  ; project_id : string
  ; storage_bucket : string
  ; messaging_sender_id : string
  ; app_id : string
  }

(** [ActionCodeSettings] for email-link sign-in. *)
type action_code_settings =
  { url : string
  ; handle_code_in_app : bool
  }

(** Run [f] once the modular SDK is loaded (immediately if already loaded). [on_error] runs
    if the dynamic import fails (e.g. the CDN is blocked or offline) so the caller can show a
    recoverable error instead of hanging. *)
val on_ready : ?on_error:(unit -> unit) -> (unit -> unit) -> unit

(** [initializeApp] the default app. Must run before any other call; do it in {!on_ready}. *)
val init : config -> unit

(* ---- auth ---- *)
val current_user : unit -> user option
val on_auth_state_changed : (user option -> unit) -> unit
val sign_in_anonymously : on_err:(error -> unit) -> unit
val sign_in_with_email_link : email:string -> link:string -> on_ok:(unit -> unit) -> on_err:(error -> unit) -> unit
val send_sign_in_link_to_email : email:string -> settings:action_code_settings -> on_ok:(unit -> unit) -> on_err:(error -> unit) -> unit
val sign_out : unit -> unit

(* ---- user ---- *)
val uid : user -> string
val email : user -> string option
val display_name : user -> string option
val get_id_token : user -> force_refresh:bool -> on_ok:(string -> unit) -> on_err:(error -> unit) -> unit

(* ---- firestore ---- *)

(** A document reference at the given path segments, e.g. [doc ["lobbies"; name]]. *)
val doc : string list -> document_reference

(** Subscribe to realtime updates; returns the unsubscribe thunk. *)
val on_snapshot : document_reference -> on_next:(document_snapshot -> unit) -> on_error:(error -> unit) -> unit -> unit

val get_doc : document_reference -> on_ok:(document_snapshot -> unit) -> on_err:(error -> unit) -> unit

(* ---- document snapshot ---- *)
val exists : document_snapshot -> bool

(** The document's data as a raw JS object (for {!Avalon.Parse}), or [None] if it doesn't exist. *)
val data : document_snapshot -> Js.Unsafe.any option

(* ---- error ---- *)
val error_message : error -> string
val error_code : error -> string
