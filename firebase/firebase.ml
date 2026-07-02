open! Core
open Js_of_ocaml

(** Typed bindings to the Firebase v12 *modular* JS SDK.

    The handle types ({!user}, {!document_reference}, {!document_snapshot}, {!error}) are
    abstract and distinct, modeled on the [@firebase/auth] and [@firebase/firestore]
    TypeScript definitions, so the OCaml type system enforces that e.g. a snapshot can't
    be passed where a reference is expected, and JS objects are read only through the
    typed accessors below — never via raw [Js.Unsafe] in callers.

    The modular SDK is shipped as a vendored, esbuild-bundled artifact (see [shim/]) that
    is embedded into the page bundle via [(js_of_ocaml (javascript_files ...))] and
    exposes its exports on [globalThis.__fb] — present synchronously, no gstatic CDN, no
    dynamic [import()]. Wrap setup in {!on_ready}, which snapshots that global once before
    running its callback. *)

type any = Js.Unsafe.any
type user = any
type document_reference = any
type document_snapshot = any
type error = any

type config =
  { api_key : string
  ; auth_domain : string
  ; database_url : string
  ; project_id : string
  ; storage_bucket : string
  ; messaging_sender_id : string
  ; app_id : string
  }

type action_code_settings =
  { url : string
  ; handle_code_in_app : bool
  }

let str = Js.string
let inject = Js.Unsafe.inject

let is_nullish (v : any) : bool =
  (* [Opt.test] is a [!== null] check and [Optdef.test] a [!== undefined] check; combined
     they are exactly [x === undefined || x === null], with no per-call closure. *)
  let as_opt : any Js.Opt.t = Obj.magic v in
  let as_optdef : any Js.Optdef.t = Obj.magic v in
  not (Js.Opt.test as_opt && Js.Optdef.test as_optdef)
;;

let field_string_opt (o : any) (k : string) : string option =
  let v = Js.Unsafe.get o (str k) in
  if is_nullish v then None else Some (Js.to_string (Js.Unsafe.coerce v))
;;

let field_string ?(default = "") o k = Option.value (field_string_opt o k) ~default
let to_opt (v : any) : any option = if is_nullish v then None else Some v

(* [console.error(msg, v)] — this library has no jsoo ppx, so no [##] syntax. *)
let console_error (msg : string) (v : any) : unit =
  ignore
    (Js.Unsafe.meth_call
       (Js.Unsafe.get Js.Unsafe.global (str "console"))
       "error"
       [| inject (str msg); inject v |]
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

let promise_then (p : any) ~(on_ok : any -> unit) ~(on_err : error -> unit) : unit =
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
               console_error "Exception in Firebase promise callback:" e))
       |]
     : any)
;;

(* ---- app (cached default app; auth/firestore handles derived lazily) ---- *)

let app_ref : any option ref = ref None

let app () : any =
  match !app_ref with
  | Some a -> a
  | None -> failwith "Firebase.init has not been called"
;;

let init (c : config) : unit =
  let cfg =
    Js.Unsafe.obj
      [| "apiKey", inject (str c.api_key)
       ; "authDomain", inject (str c.auth_domain)
       ; "databaseURL", inject (str c.database_url)
       ; "projectId", inject (str c.project_id)
       ; "storageBucket", inject (str c.storage_bucket)
       ; "messagingSenderId", inject (str c.messaging_sender_id)
       ; "appId", inject (str c.app_id)
      |]
  in
  app_ref := Some (call "initializeApp" [| inject cfg |])
;;

let auth () : any = call "getAuth" [| inject (app ()) |]
let firestore () : any = call "getFirestore" [| inject (app ()) |]

(* ---- auth ---- *)

let current_user () : user option = to_opt (Js.Unsafe.get (auth ()) (str "currentUser"))

let on_auth_state_changed (cb : user option -> unit) : unit -> unit =
  let wrapped = Js.wrap_callback (fun (u : any) -> cb (to_opt u)) in
  let unsub = call "onAuthStateChanged" [| inject (auth ()); inject wrapped |] in
  fun () -> ignore (Js.Unsafe.fun_call unsub [||] : any)
;;

let sign_in_anonymously ~(on_err : error -> unit) : unit =
  promise_then
    (call "signInAnonymously" [| inject (auth ()) |])
    ~on_ok:(fun _ -> ())
    ~on_err
;;

let sign_in_with_email_link
  ~(email : string)
  ~(link : string)
  ~(on_ok : unit -> unit)
  ~(on_err : error -> unit)
  : unit
  =
  promise_then
    (call
       "signInWithEmailLink"
       [| inject (auth ()); inject (str email); inject (str link) |])
    ~on_ok:(fun _ -> on_ok ())
    ~on_err
;;

let send_sign_in_link_to_email
  ~(email : string)
  ~(settings : action_code_settings)
  ~(on_ok : unit -> unit)
  ~(on_err : error -> unit)
  : unit
  =
  let s =
    Js.Unsafe.obj
      [| "url", inject (str settings.url)
       ; "handleCodeInApp", inject (Js.bool settings.handle_code_in_app)
      |]
  in
  promise_then
    (call "sendSignInLinkToEmail" [| inject (auth ()); inject (str email); inject s |])
    ~on_ok:(fun _ -> on_ok ())
    ~on_err
;;

let sign_out
  ?(on_error = fun (e : error) -> console_error "Firebase signOut failed:" e)
  ()
  : unit
  =
  promise_then
    (call "signOut" [| inject (auth ()) |])
    ~on_ok:(fun _ -> ())
    ~on_err:on_error
;;

(* ---- user accessors ---- *)

let uid (u : user) : string = field_string u "uid"
let email (u : user) : string option = field_string_opt u "email"
let display_name (u : user) : string option = field_string_opt u "displayName"

let get_id_token
  (u : user)
  ~(force_refresh : bool)
  ~(on_ok : string -> unit)
  ~(on_err : error -> unit)
  : unit
  =
  promise_then
    (Js.Unsafe.meth_call u "getIdToken" [| inject (Js.bool force_refresh) |])
    ~on_ok:(fun token -> on_ok (Js.to_string (Js.Unsafe.coerce token)))
    ~on_err
;;

(* ---- firestore ---- *)

(* Modular [doc(db, ...pathSegments)] replaces compat's collection/doc chaining. *)
let doc (path : string list) : document_reference =
  call
    "doc"
    (Array.of_list (inject (firestore ()) :: List.map path ~f:(fun s -> inject (str s))))
;;

let on_snapshot
  (ref : document_reference)
  ~(on_next : document_snapshot -> unit)
  ~(on_error : error -> unit)
  : unit -> unit
  =
  let unsub =
    call
      "onSnapshot"
      [| inject ref
       ; inject (Js.wrap_callback on_next)
       ; inject (Js.wrap_callback on_error)
      |]
  in
  fun () -> ignore (Js.Unsafe.fun_call unsub [||] : any)
;;

let get_doc
  (ref : document_reference)
  ~(on_ok : document_snapshot -> unit)
  ~(on_err : error -> unit)
  : unit
  =
  promise_then (call "getDoc" [| inject ref |]) ~on_ok ~on_err
;;

(* ---- document snapshot ---- *)

(* Modular SDK: [exists()] is a METHOD (compat exposed [exists] as a property); [data()]
   returns DocumentData | undefined. *)
let exists (snap : document_snapshot) : bool =
  Js.to_bool (Js.Unsafe.coerce (Js.Unsafe.meth_call snap "exists" [||]))
;;

let data (snap : document_snapshot) : any option =
  to_opt (Js.Unsafe.meth_call snap "data" [||])
;;

(* ---- error ---- *)

(* A rejection value need not be a FirebaseError — a plain string (or anything else) can
   be thrown/rejected too, and defaulting to "" would show users empty toasts. Fall back
   from the [message] field to a [String()] coercion, and finally to a fixed text. *)
let error_message (e : error) : string =
  if is_nullish e
  then "unknown error"
  else (
    match field_string_opt e "message" with
    | Some m -> m
    | None ->
      let coerced =
        Js.Unsafe.fun_call (Js.Unsafe.get Js.Unsafe.global (str "String")) [| inject e |]
      in
      let s = Js.to_string (Js.Unsafe.coerce coerced) in
      if String.is_empty s then "unknown error" else s)
;;

let error_code (e : error) : string = field_string e "code"

(* ---- readiness ---- *)

(* The modular SDK is shipped as a vendored bundle (firebase/shim, built to
   firebase/vendor/firebase-shim.js) that is embedded into the page bundle via
   [(js_of_ocaml (javascript_files ...))] in [firebase/dune] — exactly like the
   bonsai_web_components bindings ship their JS. It runs at startup and exposes its named
   exports on [globalThis.__fb], so they are present synchronously with no gstatic CDN and
   no runtime dynamic [import()]. [on_ready] simply snapshots that global once and runs
   [f]; the asynchronous-load API shape is kept so callers (and {!on_error}) are
   unaffected. *)
let on_ready ?(on_error = fun () -> ()) (f : unit -> unit) : unit =
  match !exports_ref with
  | Some _ -> f ()
  | None ->
    let g = Js.Unsafe.get Js.Unsafe.global (str "__fb") in
    if is_nullish g
    then (
      ignore
        (Js.Unsafe.fun_call
           (Js.Unsafe.js_expr
              "(function(){console.error('Firebase SDK bundle missing: globalThis.__fb \
               is not set (firebase/vendor/firebase-shim.js not embedded?)');})")
           [||]
         : any);
      on_error ())
    else (
      exports_ref := Some g;
      f ())
;;
