open Js_of_ocaml

(** [FirebaseError] — the rejection value of a failed Firebase SDK promise. Upstream it
    extends the built-in [Error] with a service-scoped [code] (e.g.
    ["auth/invalid-email"]) and optional [customData].

    Reference: {:https://firebase.google.com/docs/reference/js/util.firebaseerror} *)

type t

(** "The error code for this error." Service-scoped, e.g. ["auth/invalid-email"] or
    ["permission-denied"]. The empty string when the rejection value has no [code] field
    (i.e. it was not a [FirebaseError]). *)
val code : t -> string

(** The error's [message] (inherited from the built-in [Error]). A rejection value need
    not be a [FirebaseError] — a plain string (or anything else) can be thrown/rejected
    too, and defaulting to [""] would show users empty toasts: this falls back from the
    [message] field to a [String()] coercion, and to ["unknown error"] as a last resort —
    never the empty string for a non-empty rejection. *)
val message : t -> string

(**/**)

(* Internal — for the sibling binding modules, which receive raw rejection values from
   [Internal.promise_then] and SDK error callbacks. *)
val of_any : Js.Unsafe.any -> t
