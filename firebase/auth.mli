(** Bindings to the [firebase/auth] entry point of the modular Firebase JS SDK. As
    upstream, every entry point takes the {!t} service handle (from {!get_auth}) as its
    first argument. Promise-returning functions take [on_ok]/[on_err] callbacks instead.

    Reference: {:https://firebase.google.com/docs/reference/js/auth} *)

(** [Auth] — "Interface representing Firebase Auth service." Obtained from {!get_auth}.

    Reference: {:https://firebase.google.com/docs/reference/js/auth.auth} *)
type t

(** [User] — "A user account."

    Reference: {:https://firebase.google.com/docs/reference/js/auth.user} *)
module User : sig
  type t

  (** [User.uid] — "The user's unique ID, scoped to the project." *)
  val uid : t -> string

  (** [User.email] — "The email of the user." [None] when the account has none (e.g.
      anonymous sign-in). *)
  val email : t -> string option

  (** [User.displayName] — "The display name of the user." *)
  val display_name : t -> string option

  (** [User.getIdToken(forceRefresh)] — "Returns a JSON Web Token (JWT) used to identify
      the user to a Firebase service. Returns the current token if it has not expired or
      if it will not expire in the next five minutes. Otherwise, this will refresh the
      token and return a new one." [force_refresh] forces a refresh regardless of token
      expiration.

      Reference: {:https://firebase.google.com/docs/reference/js/auth.user#usergetidtoken} *)
  val get_id_token
    :  t
    -> force_refresh:bool
    -> on_ok:(string -> unit)
    -> on_err:(Error.t -> unit)
    -> unit
end

(** [ActionCodeSettings] — "An interface that defines the required continue/state URL" for
    out-of-band email actions. The optional Android/iOS bundle-identifier fields are not
    exposed.

    - [url]: "Sets the link continue/state URL."
    - [handle_code_in_app]: "When set to true, the action code link will be sent as a
      Universal Link or Android App Link and will be opened by the app if installed."

    Reference: {:https://firebase.google.com/docs/reference/js/auth.actioncodesettings} *)
type action_code_settings =
  { url : string
  ; handle_code_in_app : bool
  }

(** [getAuth(app)] — "Returns the Auth instance associated with the provided FirebaseApp.
    If no instance exists, initializes an Auth instance with platform-specific default
    dependencies."

    In this app the vendored shim implements [getAuth] as
    [initializeAuth(app, { persistence; popupRedirectResolver: undefined })] — same
    caching, same signature — so the unused popup/redirect and reCAPTCHA machinery is
    tree-shaken out of the bundle (see [shim/entry.mjs]).

    References: {:https://firebase.google.com/docs/reference/js/auth#getauth} and
    {:https://firebase.google.com/docs/reference/js/auth#initializeauth} *)
val get_auth : App.t -> t

(** [Auth.currentUser] — "The currently signed-in user (or null)." *)
val current_user : t -> User.t option

(** [onAuthStateChanged(auth, nextOrObserver)] — "Adds an observer for changes to the
    user's sign-in state." Returns the [Unsubscribe] thunk that removes the observer.

    Reference: {:https://firebase.google.com/docs/reference/js/auth#onauthstatechanged} *)
val on_auth_state_changed : t -> (User.t option -> unit) -> unit -> unit

(** [signInAnonymously(auth)] — "Asynchronously signs in as an anonymous user. If there is
    already an anonymous user signed in, that user will be returned; otherwise, a new
    anonymous user identity will be created and returned." Success is observed via
    {!on_auth_state_changed}; only failure is reported here.

    Reference: {:https://firebase.google.com/docs/reference/js/auth#signinanonymously} *)
val sign_in_anonymously : t -> on_err:(Error.t -> unit) -> unit

(** [signInWithEmailLink(auth, email, emailLink)] — "Asynchronously signs in using an
    email and sign-in email link." "Fails with an error if the email address is invalid or
    OTP in email link expires."

    Reference: {:https://firebase.google.com/docs/reference/js/auth#signinwithemaillink} *)
val sign_in_with_email_link
  :  t
  -> email:string
  -> link:string
  -> on_ok:(unit -> unit)
  -> on_err:(Error.t -> unit)
  -> unit

(** [sendSignInLinkToEmail(auth, email, actionCodeSettings)] — "Sends a sign-in email link
    to the user with the specified email." "To complete sign in with the email link, call
    [signInWithEmailLink] with the email address and the email link supplied in the email
    sent to the user."

    Reference: {:https://firebase.google.com/docs/reference/js/auth#sendsigninlinktoemail} *)
val send_sign_in_link_to_email
  :  t
  -> email:string
  -> settings:action_code_settings
  -> on_ok:(unit -> unit)
  -> on_err:(Error.t -> unit)
  -> unit

(** [signOut(auth)] — "Signs out the current user." [on_error] runs if the underlying
    promise rejects (default logs the error to the console) — otherwise a failed logout
    would be invisible.

    Reference: {:https://firebase.google.com/docs/reference/js/auth#signout} *)
val sign_out : ?on_error:(Error.t -> unit) -> t -> unit
