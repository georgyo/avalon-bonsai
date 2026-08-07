open Js_of_ocaml

type t = Internal.any

type options =
  { api_key : string
  ; auth_domain : string
  ; database_url : string
  ; project_id : string
  ; storage_bucket : string
  ; messaging_sender_id : string
  ; app_id : string
  }

let to_any (app : t) : Js.Unsafe.any = app

let initialize_app (o : options) : t =
  let str = Internal.str
  and inject = Internal.inject in
  let cfg =
    Js.Unsafe.obj
      [| "apiKey", inject (str o.api_key)
       ; "authDomain", inject (str o.auth_domain)
       ; "databaseURL", inject (str o.database_url)
       ; "projectId", inject (str o.project_id)
       ; "storageBucket", inject (str o.storage_bucket)
       ; "messagingSenderId", inject (str o.messaging_sender_id)
       ; "appId", inject (str o.app_id)
      |]
  in
  Internal.call "initializeApp" [| inject cfg |]
;;
