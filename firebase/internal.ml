open Js_of_ocaml

(* Shared plumbing for the binding modules. See the mli. NOTE: this library deliberately
   does not depend on Core — [Option]/[String]/[List] below are Stdlib's. *)

type any = Js.Unsafe.any

let str = Js.string
let inject = Js.Unsafe.inject

let is_nullish (v : any) : bool =
  (* [Opt.test] is a [!== null] check and [Optdef.test] a [!== undefined] check; combined
     they are exactly [x === undefined || x === null], with no per-call closure. *)
  let as_opt : any Js.Opt.t = Obj.magic v in
  let as_optdef : any Js.Optdef.t = Obj.magic v in
  not (Js.Opt.test as_opt && Js.Optdef.test as_optdef)
;;

let to_opt (v : any) : any option = if is_nullish v then None else Some v

let field_string_opt (o : any) (k : string) : string option =
  let v = Js.Unsafe.get o (str k) in
  if is_nullish v then None else Some (Js.to_string (Js.Unsafe.coerce v))
;;

let field_string ?(default = "") o k = Option.value (field_string_opt o k) ~default

(* [console.error(msg, ...)] — this library has no jsoo ppx, so no [##] syntax. *)
let console_error (msg : string) (vs : any array) : unit =
  ignore
    (Js.Unsafe.meth_call
       (Js.Unsafe.get Js.Unsafe.global (str "console"))
       "error"
       (Array.append [| inject (str msg) |] vs)
     : any)
;;

(* The merged exports of the modular SDK entry points, snapshotted from the embedded
   bundle's [globalThis.__fb] by {!on_ready}; [call] dispatches a free function by name. *)
let exports_ref : any option ref = ref None

let api () : any =
  match !exports_ref with
  | Some e -> e
  | None -> failwith "Firebase modules are not loaded; run inside Firebase.on_ready"
;;

let call (name : string) (args : any array) : any =
  Js.Unsafe.fun_call (Js.Unsafe.get (api ()) (str name)) args
;;

let promise_then (p : any) ~(on_ok : any -> unit) ~(on_err : any -> unit) : unit =
  (* [on_err] handles rejections of [p] itself. An exception raised *inside* [on_ok] (or
     [on_err]) rejects the derived promise instead, which would otherwise vanish as an
     unhandled rejection — chain a [catch] that at least logs it to the console. *)
  let derived =
    Js.Unsafe.meth_call
      p
      "then"
      [| inject (Js.wrap_callback on_ok); inject (Js.wrap_callback on_err) |]
  in
  ignore
    (Js.Unsafe.meth_call
       derived
       "catch"
       [| inject
            (Js.wrap_callback (fun (e : any) ->
               console_error "Exception in Firebase promise callback:" [| e |]))
       |]
     : any)
;;

(* The modular SDK is shipped as a vendored bundle (firebase/shim, built to
   firebase/vendor/firebase-shim.js) that is embedded into the page bundle via
   [(js_of_ocaml (javascript_files ...))] in [firebase/dune] — exactly like the
   bonsai_web_components bindings ship their JS. It runs at startup and exposes its named
   exports on [globalThis.__fb], so they are present synchronously with no gstatic CDN and
   no runtime dynamic [import()]. [on_ready] simply snapshots that global once and runs
   [f]; the asynchronous-load API shape is kept so callers (and [on_error]) are
   unaffected. *)
let on_ready ?(on_error = fun () -> ()) (f : unit -> unit) : unit =
  match !exports_ref with
  | Some _ -> f ()
  | None ->
    let g = Js.Unsafe.get Js.Unsafe.global (str "__fb") in
    if is_nullish g
    then (
      console_error
        "Firebase SDK bundle missing: globalThis.__fb is not set \
         (firebase/vendor/firebase-shim.js not embedded?)"
        [||];
      on_error ())
    else (
      exports_ref := Some g;
      f ())
;;
