open Js_of_ocaml

let str = Internal.str
let inject = Internal.inject

type t = Internal.any

module User = struct
  type t = Internal.any

  let uid (u : t) : string = Internal.field_string u "uid"
  let email (u : t) : string option = Internal.field_string_opt u "email"
  let display_name (u : t) : string option = Internal.field_string_opt u "displayName"

  let get_id_token
    (u : t)
    ~(force_refresh : bool)
    ~(on_ok : string -> unit)
    ~(on_err : Error.t -> unit)
    : unit
    =
    Internal.promise_then
      (Js.Unsafe.meth_call u "getIdToken" [| inject (Js.bool force_refresh) |])
      ~on_ok:(fun token -> on_ok (Js.to_string (Js.Unsafe.coerce token)))
      ~on_err:(fun e -> on_err (Error.of_any e))
  ;;
end

type action_code_settings =
  { url : string
  ; handle_code_in_app : bool
  }

let get_auth (app : App.t) : t = Internal.call "getAuth" [| inject (App.to_any app) |]

let current_user (auth : t) : User.t option =
  Internal.to_opt (Js.Unsafe.get auth (str "currentUser"))
;;

let on_auth_state_changed (auth : t) (cb : User.t option -> unit) : unit -> unit =
  let wrapped = Js.wrap_callback (fun (u : Internal.any) -> cb (Internal.to_opt u)) in
  let unsub = Internal.call "onAuthStateChanged" [| inject auth; inject wrapped |] in
  fun () -> ignore (Js.Unsafe.fun_call unsub [||] : Internal.any)
;;

let sign_in_anonymously (auth : t) ~(on_err : Error.t -> unit) : unit =
  Internal.promise_then
    (Internal.call "signInAnonymously" [| inject auth |])
    ~on_ok:(fun _ -> ())
    ~on_err:(fun e -> on_err (Error.of_any e))
;;

let sign_in_with_email_link
  (auth : t)
  ~(email : string)
  ~(link : string)
  ~(on_ok : unit -> unit)
  ~(on_err : Error.t -> unit)
  : unit
  =
  Internal.promise_then
    (Internal.call
       "signInWithEmailLink"
       [| inject auth; inject (str email); inject (str link) |])
    ~on_ok:(fun _ -> on_ok ())
    ~on_err:(fun e -> on_err (Error.of_any e))
;;

let send_sign_in_link_to_email
  (auth : t)
  ~(email : string)
  ~(settings : action_code_settings)
  ~(on_ok : unit -> unit)
  ~(on_err : Error.t -> unit)
  : unit
  =
  let s =
    Js.Unsafe.obj
      [| "url", inject (str settings.url)
       ; "handleCodeInApp", inject (Js.bool settings.handle_code_in_app)
      |]
  in
  Internal.promise_then
    (Internal.call
       "sendSignInLinkToEmail"
       [| inject auth; inject (str email); inject s |])
    ~on_ok:(fun _ -> on_ok ())
    ~on_err:(fun e -> on_err (Error.of_any e))
;;

let sign_out
  ?(on_error =
    fun (e : Error.t) ->
      Internal.console_error ("Firebase signOut failed: " ^ Error.message e) [||])
  (auth : t)
  : unit
  =
  Internal.promise_then
    (Internal.call "signOut" [| inject auth |])
    ~on_ok:(fun _ -> ())
    ~on_err:(fun e -> on_error (Error.of_any e))
;;
