open Js_of_ocaml

(** Bindings to the [firebase/app] entry point of the modular Firebase JS SDK.

    Reference: {:https://firebase.google.com/docs/reference/js/app} *)

(** [FirebaseApp] — "holds the initialization information for a collection of services."
    Never constructed directly: created by {!initialize_app} and consumed by the
    per-service handle constructors ({!Auth.get_auth}, {!Firestore.get_firestore}).

    Reference: {:https://firebase.google.com/docs/reference/js/app.firebaseapp} *)
type t

(** [FirebaseOptions] — "Firebase configuration object. Contains a set of parameters
    required by services in order to successfully communicate with Firebase server APIs
    and to associate client data with your Firebase project and Firebase application.
    Typically this object is populated by the Firebase console at project setup." All
    fields upstream are optional; this app always supplies these seven.

    Reference: {:https://firebase.google.com/docs/reference/js/app.firebaseoptions} *)
type options =
  { api_key : string
  (** [apiKey] — "An encrypted string used when calling certain APIs that don't need to
      access private user data." Identifies the Firebase project; not a secret. *)
  ; auth_domain : string (** [authDomain] — "Auth domain for the project ID." *)
  ; database_url : string (** [databaseURL] — "Default Realtime Database URL." *)
  ; project_id : string
  (** [projectId] — "The unique identifier for the project across all of Firebase and
      Google Cloud." *)
  ; storage_bucket : string
  (** [storageBucket] — "The default Cloud Storage bucket name." *)
  ; messaging_sender_id : string
  (** [messagingSenderId] — "Unique numerical value used to identify each sender that can
      send Firebase Cloud Messaging messages to client apps." *)
  ; app_id : string (** [appId] — "Unique identifier for the app." *)
  }

(** [initializeApp(options)] — "Creates and initializes a FirebaseApp instance." Must run
    inside {!Firebase.on_ready}. Upstream's optional [name] argument is not exposed: this
    always initializes the default app.

    Reference: {:https://firebase.google.com/docs/reference/js/app#initializeapp} *)
val initialize_app : options -> t

(**/**)

(* Internal — for the sibling binding modules (Auth/Firestore), which pass the app handle
   back to the SDK's per-service constructors. *)
val to_any : t -> Js.Unsafe.any
