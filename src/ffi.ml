open! Core
open Js_of_ocaml

(** Low-level js_of_ocaml helpers for talking to the global (compat) Firebase SDK,
    [fetch], and for reading fields out of plain JS objects returned by Firestore. *)

type any = Js.Unsafe.any

let global : Js.Unsafe.any = Js.Unsafe.coerce Js.Unsafe.global
let inject = Js.Unsafe.inject
let str = Js.string

(* ---- null / undefined ---- *)

let is_nullish : any -> bool =
  let f = Js.Unsafe.js_expr "(function(x){return x===undefined||x===null;})" in
  fun v -> Js.to_bool (Js.Unsafe.fun_call f [| inject v |])
;;

(* ---- readers ---- *)

let get (obj : any) (key : string) : any = Js.Unsafe.get obj (str key)
let to_string (v : any) : string = Js.to_string (Js.Unsafe.coerce v)
let to_float (v : any) : float = Js.float_of_number (Js.Unsafe.coerce v)
let to_int (v : any) : int = Int.of_float (to_float v)
let to_bool (v : any) : bool = Js.to_bool (Js.Unsafe.coerce v)

let to_list (v : any) : any list =
  if is_nullish v
  then []
  else (
    let len = to_int (get v "length") in
    List.init len ~f:(fun i -> Js.Unsafe.get v i))
;;

let keys (obj : any) : string list =
  if is_nullish obj
  then []
  else (
    let arr = Js.Unsafe.fun_call (Js.Unsafe.js_expr "Object.keys") [| inject obj |] in
    List.map (to_list arr) ~f:to_string)
;;

let field_string ?(default = "") obj key =
  let v = get obj key in
  if is_nullish v then default else to_string v
;;

let field_string_opt obj key =
  let v = get obj key in
  if is_nullish v then None else Some (to_string v)
;;

let field_int ?(default = 0) obj key =
  let v = get obj key in
  if is_nullish v then default else to_int v
;;

let field_bool ?(default = false) obj key =
  let v = get obj key in
  if is_nullish v then default else to_bool v
;;

let field_str_list obj key = to_list (get obj key) |> List.map ~f:to_string

(* ---- builders (OCaml -> JS) ---- *)

let obj (fields : (string * any) list) : any =
  Js.Unsafe.obj (List.map fields ~f:(fun (k, v) -> k, v) |> Array.of_list)
;;

let null_value : any = Js.Unsafe.inject Js.null
let of_string s : any = inject (str s)
let of_bool b : any = inject (Js.bool b)
let of_int i : any = inject (Js.number_of_float (Int.to_float i))
let of_str_list (l : string list) : any = inject (Js.array (Array.of_list_map l ~f:str))

(* ---- promises ---- *)

let promise_then (p : any) ~(on_ok : any -> unit) ~(on_err : any -> unit) : unit =
  let _ : any =
    Js.Unsafe.meth_call
      p
      "then"
      [| inject (Js.wrap_callback on_ok); inject (Js.wrap_callback on_err) |]
  in
  ()
;;

(* ---- Firebase (compat global) ---- *)

let firebase () : any = get global "firebase"

let init_app (config : (string * any) list) : unit =
  let _ : any = Js.Unsafe.meth_call (firebase ()) "initializeApp" [| inject (obj config) |] in
  ()
;;

let auth () : any = Js.Unsafe.meth_call (firebase ()) "auth" [||]
let firestore () : any = Js.Unsafe.meth_call (firebase ()) "firestore" [||]
let current_user () : any = get (auth ()) "currentUser"

(* doc reference at db/lobbies/<name> (and nested) via collection/doc chaining *)
let doc (path : string list) : any =
  let db = firestore () in
  let rec go ref = function
    | [] -> ref
    | coll :: id :: rest ->
      let c = Js.Unsafe.meth_call ref "collection" [| inject (str coll) |] in
      let d = Js.Unsafe.meth_call c "doc" [| inject (str id) |] in
      go d rest
    | [ coll ] ->
      Js.Unsafe.meth_call ref "collection" [| inject (str coll) |]
  in
  go db path
;;

(** Subscribe with onSnapshot; returns the unsubscribe thunk. *)
let on_snapshot (doc_ref : any) ~(on_next : any -> unit) ~(on_error : any -> unit) : unit -> unit =
  let unsub : any =
    Js.Unsafe.meth_call
      doc_ref
      "onSnapshot"
      [| inject (Js.wrap_callback on_next); inject (Js.wrap_callback on_error) |]
  in
  fun () ->
    let _ : any = Js.Unsafe.fun_call unsub [||] in
    ()
;;

let get_doc (doc_ref : any) ~(on_ok : any -> unit) ~(on_err : any -> unit) : unit =
  promise_then (Js.Unsafe.meth_call doc_ref "get" [||]) ~on_ok ~on_err
;;

(* In the compat (namespaced) SDK, DocumentSnapshot.exists is a boolean property, not a
   method (unlike the modular SDK's exists()). *)
let snapshot_exists (snap : any) : bool = Js.to_bool (Js.Unsafe.coerce (get snap "exists"))

let snapshot_data (snap : any) : any = Js.Unsafe.meth_call snap "data" [||]

(* ---- window / location ---- *)

let window_origin () : string = to_string (Js.Unsafe.js_expr "window.location.origin")
let window_search () : string = to_string (Js.Unsafe.js_expr "window.location.search")
let window_href () : string = to_string (Js.Unsafe.js_expr "window.location.href")
let window_pathname () : string = to_string (Js.Unsafe.js_expr "window.location.pathname")

let set_document_title (title : string) : unit =
  Js.Unsafe.set (Js.Unsafe.js_expr "document") (str "title") (str title)
;;

let replace_state_to_pathname () : unit =
  let _ : any =
    Js.Unsafe.fun_call
      (Js.Unsafe.js_expr
         "(function(p){window.history.replaceState(null,'',p);})")
      [| inject (str (window_pathname ())) |]
  in
  ()
;;

let alert (msg : string) : unit =
  let _ : any = Js.Unsafe.fun_call (Js.Unsafe.js_expr "window.alert") [| inject (str msg) |] in
  ()
;;

let url_has_param (name : string) : bool =
  let f =
    Js.Unsafe.js_expr
      "(function(s,n){return new URLSearchParams(s).has(n);})"
  in
  Js.to_bool (Js.Unsafe.fun_call f [| inject (str (window_search ())); inject (str name) |])
;;

let url_get_param (name : string) : string option =
  let f =
    Js.Unsafe.js_expr "(function(s,n){return new URLSearchParams(s).get(n);})"
  in
  let v = Js.Unsafe.fun_call f [| inject (str (window_search ())); inject (str name) |] in
  if is_nullish v then None else Some (to_string v)
;;
