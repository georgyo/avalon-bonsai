open Js_of_ocaml

(** Shared plumbing for the per-entry-point binding modules ({!App}, {!Auth},
    {!Firestore}, {!Error}): the [globalThis.__fb] exports snapshot, free-function
    dispatch, promise helpers, and raw JS value accessors. This module is not re-exported
    by {!Firebase}, so it is invisible outside this library. *)

type any = Js.Unsafe.any

val str : string -> Js.js_string Js.t
val inject : 'a -> any

(** [x === undefined || x === null]. *)
val is_nullish : any -> bool

(** [None] iff {!is_nullish}. *)
val to_opt : any -> any option

(** Read a string-valued field, [None] when absent/nullish. *)
val field_string_opt : any -> string -> string option

val field_string : ?default:string -> any -> string -> string

(** [console.error(msg, ...args)]. *)
val console_error : string -> any array -> unit

(** Call the named free function from the snapshotted SDK exports. Raises if {!on_ready}
    has not snapshotted [globalThis.__fb] yet. *)
val call : string -> any array -> any

(** [promise_then p ~on_ok ~on_err]: [on_err] handles rejections of [p] itself; an
    exception raised inside [on_ok] (or [on_err]) rejects the derived promise instead,
    which would otherwise vanish as an unhandled rejection — a chained [catch] logs it to
    the console. *)
val promise_then : any -> on_ok:(any -> unit) -> on_err:(any -> unit) -> unit

(** See {!Firebase.on_ready} (re-exported there). *)
val on_ready : ?on_error:(unit -> unit) -> (unit -> unit) -> unit
