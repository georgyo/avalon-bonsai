open! Core
open Js_of_ocaml

(** Email-link ("passwordless") sign-in. See the mli. *)

let noop_ok () = ()
let noop_err (_ : string) = ()
let email_regexp = Regexp.regexp "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$"
let email_regex_ok email = Option.is_some (Regexp.string_match email_regexp email 0)
let whitelist = [ "gmail.com"; "yahoo.com"; "outlook.com"; "hotmail.com"; "live.com" ]

let send_sign_in_link ~email ~on_ok ~on_err =
  let hostname = Ffi.window_origin () ^ "/" in
  (* Percent-encode only the email value: [encodeURI] leaves [+] alone, and the URL param
     decoder on the return trip turns [+] into a space, breaking addresses like
     alice+x@gmail.com. *)
  let encoded_email = Js.to_string (Js.encodeURIComponent (Js.string email)) in
  let url = hostname ^ "?confirmEmail=" ^ encoded_email in
  let settings = { Firebase.url; handle_code_in_app = true } in
  Firebase.send_sign_in_link_to_email ~email ~settings ~on_ok ~on_err:(fun e ->
    on_err (Firebase.error_message e))
;;

let submit_email_addr ?(on_ok = noop_ok) ?(on_err = noop_err) email =
  if not (email_regex_ok email)
  then on_err "Not a valid email address"
  else (
    let domain =
      match String.split email ~on:'@' with
      | _ :: d :: _ -> d
      | _ -> ""
    in
    let proceed () = send_sign_in_link ~email ~on_ok ~on_err in
    if List.mem whitelist domain ~equal:String.equal
    then proceed ()
    else
      (* The mailcheck.ai screen is best-effort: Firebase's emailed link is the real
         verification, so an outage (or schema change) at this third-party API must not
         lock custom-domain users out of email sign-in. FAIL OPEN — any fetch or parse
         failure proceeds with sending the link — and block only when mailcheck positively
         reports the domain as invalid (no MX) or disposable. *)
      Ffi.fetch
        ("https://api.mailcheck.ai/domain/" ^ domain)
        ~on_err:(fun _ -> proceed ())
        ~on_ok:(fun resp ->
          Ffi.promise_then
            (Js.Unsafe.meth_call resp "json" [||])
            ~on_err:(fun _ -> proceed ())
            ~on_ok:(fun data ->
              let mx = Ffi.field_bool ~default:true data "mx" in
              let disposable = Ffi.field_bool ~default:false data "disposable" in
              if mx && not disposable
              then proceed ()
              else on_err "This email address appears to be invalid or disposable")))
;;
