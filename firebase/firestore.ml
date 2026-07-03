open Js_of_ocaml

let str = Internal.str
let inject = Internal.inject

type t = Internal.any

module Document_reference = struct
  type t = Internal.any
end

module Document_snapshot = struct
  type t = Internal.any

  (* Modular SDK: [exists()] is a METHOD (compat exposed [exists] as a property); [data()]
     returns DocumentData | undefined. *)
  let exists (snap : t) : bool =
    Js.to_bool (Js.Unsafe.coerce (Js.Unsafe.meth_call snap "exists" [||]))
  ;;

  let data (snap : t) : Js.Unsafe.any option =
    Internal.to_opt (Js.Unsafe.meth_call snap "data" [||])
  ;;
end

let get_firestore (app : App.t) : t =
  Internal.call "getFirestore" [| inject (App.to_any app) |]
;;

(* Modular [doc(db, ...pathSegments)] replaces compat's collection/doc chaining. *)
let doc (db : t) (path : string list) : Document_reference.t =
  Internal.call
    "doc"
    (Array.of_list (inject db :: List.map (fun s -> inject (str s)) path))
;;

let on_snapshot
  (ref : Document_reference.t)
  ~(on_next : Document_snapshot.t -> unit)
  ~(on_error : Error.t -> unit)
  : unit -> unit
  =
  let unsub =
    Internal.call
      "onSnapshot"
      [| inject ref
       ; inject (Js.wrap_callback on_next)
       ; inject (Js.wrap_callback (fun (e : Internal.any) -> on_error (Error.of_any e)))
      |]
  in
  fun () -> ignore (Js.Unsafe.fun_call unsub [||] : Internal.any)
;;

let get_doc
  (ref : Document_reference.t)
  ~(on_ok : Document_snapshot.t -> unit)
  ~(on_err : Error.t -> unit)
  : unit
  =
  Internal.promise_then
    (Internal.call "getDoc" [| inject ref |])
    ~on_ok
    ~on_err:(fun e -> on_err (Error.of_any e))
;;
