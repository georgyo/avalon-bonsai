(* The umbrella module: re-export the per-entry-point binding modules (see the mli). As
   the library's main module, anything not re-exported here — [Internal], the shared
   plumbing — is invisible outside the library. *)

module App = App
module Auth = Auth
module Error = Error
module Firestore = Firestore

let on_ready = Internal.on_ready
