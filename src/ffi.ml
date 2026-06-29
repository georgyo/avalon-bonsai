open! Core
open Js_of_ocaml

(** Low-level js_of_ocaml helpers for [fetch], promises, the window/location, and for
    reading fields out of plain JS objects returned by Firestore. The Firebase SDK
    bindings themselves live in the {!Firebase} library. *)

type any = Js.Unsafe.any

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
  else List.map (Array.to_list (Js.to_array (Js.object_keys (Js.Unsafe.coerce obj)))) ~f:Js.to_string
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

(* The Fetch API has no typed binding in js_of_ocaml, so confine the one raw [fetch] call
   here. [on_ok] receives the (untyped) Response. *)
let fetch ?opts (url : string) ~(on_ok : any -> unit) ~(on_err : any -> unit) : unit =
  let args =
    match opts with
    | Some (o : any) -> [| inject (str url); inject o |]
    | None -> [| inject (str url) |]
  in
  promise_then (Js.Unsafe.fun_call (Js.Unsafe.js_expr "fetch") args) ~on_ok ~on_err
;;

(* ---- window / location / url (typed js_of_ocaml DOM bindings) ---- *)

let window = Dom_html.window
let location = window##.location

let window_origin () : string = Js.to_string location##.origin
let window_href () : string = Js.to_string location##.href
let window_pathname () : string = Js.to_string location##.pathname
let set_document_title (title : string) : unit = window##.document##.title := str title

let replace_state_to_pathname () : unit =
  window##.history##replaceState Js.null (str "") (Js.some (str (window_pathname ())))
;;

let alert (msg : string) : unit = window##alert (str msg)
let reload_page () : unit = ignore (Js.Unsafe.meth_call location "reload" [||] : any)

(* GET arguments of the current URL, decoded — [Url.Current.arguments] replaces a manual
   URLSearchParams construction. *)
let url_has_param (name : string) : bool = List.Assoc.mem Url.Current.arguments name ~equal:String.equal
let url_get_param (name : string) : string option = List.Assoc.find Url.Current.arguments name ~equal:String.equal
