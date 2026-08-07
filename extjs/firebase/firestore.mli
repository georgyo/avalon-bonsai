open Js_of_ocaml

(** Bindings to the [firebase/firestore] entry point of the modular Firebase JS SDK. As
    upstream, every entry point takes the relevant handle as its first argument: the {!t}
    service handle (from {!get_firestore}) for {!doc}, and a {!Document_reference.t} for
    {!on_snapshot} / {!get_doc}. Promise-returning functions take [on_ok]/[on_err]
    callbacks instead.

    Reference: {:https://firebase.google.com/docs/reference/js/firestore_} *)

(** [Firestore] — "The Cloud Firestore service interface. Do not call this constructor
    directly. Instead, use getFirestore()" ({!get_firestore} here).

    Reference: {:https://firebase.google.com/docs/reference/js/firestore_.firestore} *)
type t

(** [DocumentReference] — "A DocumentReference refers to a document location in a
    Firestore database and can be used to write, read, or listen to the location. The
    document at the referenced location may or may not exist."

    Reference:
    {:https://firebase.google.com/docs/reference/js/firestore_.documentreference} *)
module Document_reference : sig
  type t
end

(** [DocumentSnapshot] — "A DocumentSnapshot contains data read from a document in your
    Firestore database." "For a DocumentSnapshot that points to a non-existing document,
    any data access will return 'undefined'. You can use the exists() method to explicitly
    verify a document's existence."

    Reference:
    {:https://firebase.google.com/docs/reference/js/firestore_.documentsnapshot} *)
module Document_snapshot : sig
  type t

  (** [DocumentSnapshot.exists()] — "Returns whether or not the data exists. True if the
      document exists." (A method in the modular SDK; compat exposed it as a property.) *)
  val exists : t -> bool

  (** [DocumentSnapshot.data()] — "Retrieves all fields in the document as an Object.
      Returns undefined if the document doesn't exist." Here the fields come back as one
      raw JS object (for the avalon [Parse] module), or [None] if the document doesn't
      exist. *)
  val data : t -> Js.Unsafe.any option
end

(** [getFirestore(app)] — "Returns the existing default Firestore instance that is
    associated with the provided FirebaseApp. If no instance exists, initializes a new
    instance with default settings." *)
val get_firestore : App.t -> t

(** [doc(firestore, path, ...pathSegments)] — "Gets a DocumentReference instance that
    refers to the document at the specified absolute path", given here as a segment list,
    e.g. [doc db ["lobbies"; name]]. Throws (synchronously) "if the final path has an odd
    number of segments and does not point to a document"; an empty segment also throws. *)
val doc : t -> string list -> Document_reference.t

(** [onSnapshot(reference, onNext, onError)] — "Attaches a listener for DocumentSnapshot
    events", returning "an unsubscribe function that can be called to cancel the snapshot
    listener." [on_error] is "called if the listen fails or is cancelled. No further
    callbacks will occur" — i.e. a listener error is terminal, so callers should treat it
    as a lost subscription, not a transient fault. *)
val on_snapshot
  :  Document_reference.t
  -> on_next:(Document_snapshot.t -> unit)
  -> on_error:(Error.t -> unit)
  -> unit
  -> unit

(** [getDoc(reference)] — "Reads the document referred to by this DocumentReference."
    "getDoc() attempts to provide up-to-date data when possible by waiting for data from
    the server, but it may return cached data or fail if you are offline and the server
    cannot be reached." *)
val get_doc
  :  Document_reference.t
  -> on_ok:(Document_snapshot.t -> unit)
  -> on_err:(Error.t -> unit)
  -> unit
