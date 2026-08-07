open Js_of_ocaml

type t = Internal.any

let of_any (e : Js.Unsafe.any) : t = e

(* A rejection value need not be a FirebaseError — a plain string (or anything else) can
   be thrown/rejected too, and defaulting to "" would show users empty toasts. Fall back
   from the [message] field to a [String()] coercion, and finally to a fixed text. *)
let message (e : t) : string =
  if Internal.is_nullish e
  then "unknown error"
  else (
    match Internal.field_string_opt e "message" with
    | Some m -> m
    | None ->
      let coerced =
        Js.Unsafe.fun_call
          (Js.Unsafe.get Js.Unsafe.global (Internal.str "String"))
          [| Internal.inject e |]
      in
      let s = Js.to_string (Js.Unsafe.coerce coerced) in
      if String.length s = 0 then "unknown error" else s)
;;

let code (e : t) : string = Internal.field_string e "code"
