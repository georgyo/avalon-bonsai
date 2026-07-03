open! Core

(** Email-link ("passwordless") sign-in: validate the address shape, screen obviously
    invalid/disposable domains via mailcheck.ai, then have Firebase email a sign-in link.
    This flow talks only to Firebase auth and the network — it has no dependency on the
    application model. *)

val submit_email_addr
  :  ?on_ok:(unit -> unit)
  -> ?on_err:(string -> unit)
  -> auth:Firebase.Auth.t
  -> string
  -> unit
