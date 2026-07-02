open Js_of_ocaml

(** Typed bindings to the Firebase v12 modular JS SDK. The SDK is a vendored bundle (built
    from [shim/] to [vendor/firebase-shim.js]) embedded ahead of the OCaml code in the
    page bundle; it runs at startup and exposes its exports on [globalThis.__fb].

    The handle types below are abstract and distinct, modeled on the [@firebase/auth] and
    [@firebase/firestore] TypeScript definitions, so the type checker rejects mixing them
    up and callers read JS objects only through the typed accessors here. Wrap setup in
    {!on_ready}, which snapshots [globalThis.__fb] before running its callback. *)

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

(** Run [f] with the SDK available: the embedded bundle has already run by the time OCaml
    code executes, so this just snapshots [globalThis.__fb] and calls [f]. [on_error] runs
    if that global is missing (i.e. the bundle was not embedded or did not run — a build
    problem) so the caller can show an error instead of hanging. *)
val on_ready : ?on_error:(unit -> unit) -> (unit -> unit) -> unit

(** [initializeApp] the default app. Must run before any other call; do it in {!on_ready}. *)
val init : config -> unit

(* ---- auth ---- *)
val current_user : unit -> user option
val on_auth_state_changed : (user option -> unit) -> unit
val sign_in_anonymously : on_err:(error -> unit) -> unit

val sign_in_with_email_link
  :  email:string
  -> link:string
  -> on_ok:(unit -> unit)
  -> on_err:(error -> unit)
  -> unit

val send_sign_in_link_to_email
  :  email:string
  -> settings:action_code_settings
  -> on_ok:(unit -> unit)
  -> on_err:(error -> unit)
  -> unit

val sign_out : unit -> unit

(* ---- user ---- *)
val uid : user -> string
val email : user -> string option
val display_name : user -> string option

val get_id_token
  :  user
  -> force_refresh:bool
  -> on_ok:(string -> unit)
  -> on_err:(error -> unit)
  -> unit

(* ---- firestore ---- *)

(** A document reference at the given path segments, e.g. [doc ["lobbies"; name]]. *)
val doc : string list -> document_reference

(** Subscribe to realtime updates; returns the unsubscribe thunk. *)
val on_snapshot
  :  document_reference
  -> on_next:(document_snapshot -> unit)
  -> on_error:(error -> unit)
  -> unit
  -> unit

val get_doc
  :  document_reference
  -> on_ok:(document_snapshot -> unit)
  -> on_err:(error -> unit)
  -> unit

(* ---- document snapshot ---- *)
val exists : document_snapshot -> bool

(** The document's data as a raw JS object (for the avalon [Parse] module), or [None] if
    it doesn't exist. *)
val data : document_snapshot -> Js.Unsafe.any option

(* ---- error ---- *)
val error_message : error -> string
val error_code : error -> string
