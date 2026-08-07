(** Typed bindings to the Firebase v12 {e modular} JS SDK — one OCaml module per SDK entry
    point, mirroring the upstream API surface
    ({:https://firebase.google.com/docs/reference/js}):

    - {!App} — [firebase/app]: [initializeApp] and the {!App.t} handle.
    - {!Auth} — [firebase/auth]: the {!Auth.t} service handle, the sign-in/sign-out entry
      points, and {!Auth.User}.
    - {!Firestore} — [firebase/firestore]: the {!Firestore.t} service handle, document
      references, snapshots, and listeners.
    - {!Error} — [FirebaseError], the rejection value of a failed SDK promise.

    As upstream, there are no module-level singletons here: {!App.initialize_app} returns
    an {!App.t}, the per-service handles are derived from it ({!Auth.get_auth},
    {!Firestore.get_firestore}), and every call takes its handle as the first argument.
    The handle types are abstract and distinct, so the type checker rejects mixing them
    up, and JS objects are read only through the typed accessors — never via raw
    [Js.Unsafe] in callers.

    The SDK itself is a vendored bundle (built from [shim/] to [vendor/firebase-shim.js])
    embedded ahead of the OCaml code in the page bundle; it runs at startup and exposes
    its exports on [globalThis.__fb]. Wrap setup in {!on_ready}, which snapshots that
    global before running its callback. *)

module App = App
module Auth = Auth
module Error = Error
module Firestore = Firestore

(** Run [f] with the SDK available: the embedded bundle has already run by the time OCaml
    code executes, so this just snapshots [globalThis.__fb] and calls [f]. [on_error] runs
    if that global is missing (i.e. the bundle was not embedded or did not run — a build
    problem) so the caller can show an error instead of hanging. *)
val on_ready : ?on_error:(unit -> unit) -> (unit -> unit) -> unit
