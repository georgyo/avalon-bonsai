open! Core
open Bonsai_web
open Avalon_core
open Types

(** Shared UI foundation: generic node-building helpers and the cross-component style
    vocabulary. Component-specific styling lives in each component module instead. *)

(* ---- effect / formatting helpers ---- *)
val run : unit Effect.t -> unit
val eff : (unit -> unit) -> unit Effect.t
val textf : ('a, unit, string, Vdom.Node.t) format4 -> 'a
val on_enter : unit Effect.t -> Vdom.Attr.t
val swap_at : 'a list -> int -> 'a list

(* ---- node builders ---- *)
val div : ?attrs:Vdom.Attr.t list -> Vdom.Node.t list -> Vdom.Node.t
val spanc : ?attrs:Vdom.Attr.t list -> Vdom.Node.t list -> Vdom.Node.t
val card : ?attrs:Vdom.Attr.t list -> Vdom.Node.t list -> Vdom.Node.t
val card_title : ?attrs:Vdom.Attr.t list -> Vdom.Node.t list -> Vdom.Node.t
val card_text : ?attrs:Vdom.Attr.t list -> Vdom.Node.t list -> Vdom.Node.t

val btn
  :  ?attrs:Vdom.Attr.t list
  -> ?disabled:bool
  -> ?loading:bool
  -> on_click:unit Effect.t
  -> Vdom.Node.t list
  -> Vdom.Node.t

val fa : ?color:string -> string -> string -> Vdom.Node.t
val mdi : string -> Vdom.Node.t
val team_icon : team -> Vdom.Node.t
val fa_layers : ?attrs:Vdom.Attr.t list -> Vdom.Node.t list -> Vdom.Node.t
(** A centered, dimmed, focus-trapped, Esc/click-outside-closable modal (toplayer), shown
    while [value] is [Some]. Portaled into the browser's top layer, so it returns [unit]
    rather than a node to splice into the tree; closing runs [on_close] (which typically
    clears the same [value] option). [content] receives the [Some] payload and a [~close]
    effect for its own buttons. [box_attrs] styles the top-layer container itself
    (defaults to the centered [modal_box]; pass something else for e.g. a bottom
    sheet). *)
val modal
  :  ?box_attrs:Vdom.Attr.t list
  -> 'a option Bonsai.t
  -> on_close:unit Effect.t Bonsai.t
  -> content:('a -> close:unit Effect.t -> Vdom.Node.t)
  -> local_ Bonsai.graph
  -> unit

val text_field
  :  ?attrs:Vdom.Attr.t list
  -> ?typ:string
  -> ?placeholder:string
  -> ?extra:Vdom.Attr.t list
  -> value:string
  -> on_input:(string -> unit Effect.t)
  -> unit
  -> Vdom.Node.t

val error_text : string -> Vdom.Node.t

(** A styled, touch-capable hover tooltip attribute (toplayer), for use in place of a bare
    [title=] attribute. *)
val tooltip_text : string -> Vdom.Attr.t

(** A Vuetify-style tab strip: one button per label, the [active]-index tab gets the
    underline indicator, and clicking tab [i] runs [on_select i]. [tab_attrs] are extra
    attributes added to every tab button (before the tab classes). *)
val tab_strip
  :  ?tab_attrs:Vdom.Attr.t list
  -> active:int
  -> on_select:(int -> unit Effect.t)
  -> Vdom.Node.t list list
  -> Vdom.Node.t

val feedback_link : string -> Vdom.Node.t

(* ---- shared style-class accessors ---- *)
val app : Vdom.Attr.t
val container : Vdom.Attr.t
val row : Vdom.Attr.t
val col : Vdom.Attr.t
val col6 : Vdom.Attr.t
val wrap : Vdom.Attr.t
val center : Vdom.Attr.t
val center_v : Vdom.Attr.t
val start : Vdom.Attr.t
val between : Vdom.Attr.t
val fill : Vdom.Attr.t
val spacer : Vdom.Attr.t
val ga_2 : Vdom.Attr.t
val pt_2 : Vdom.Attr.t
val pt_6 : Vdom.Attr.t
val pt_8 : Vdom.Attr.t
val mt_4 : Vdom.Attr.t
val mt_6 : Vdom.Attr.t
val pa_4 : Vdom.Attr.t
val fw : Vdom.Attr.t
val thin : Vdom.Attr.t
val text_h4 : Vdom.Attr.t
val text_h5 : Vdom.Attr.t
val text_h6 : Vdom.Attr.t
val caption : Vdom.Attr.t
val label : Vdom.Attr.t
val subtitle : Vdom.Attr.t
val upper : Vdom.Attr.t
val title_bar : Vdom.Attr.t
val info_card : Vdom.Attr.t
val primary : Vdom.Attr.t
val success : Vdom.Attr.t
val danger : Vdom.Attr.t
val cta_on_dark : Vdom.Attr.t
val icon_btn : Vdom.Attr.t
val outlined : Vdom.Attr.t
val actions : Vdom.Attr.t
val tabs : Vdom.Attr.t
val tab : Vdom.Attr.t
val tab_active : Vdom.Attr.t
val tab_dark : Vdom.Attr.t
val li_prepend : Vdom.Attr.t
val li_mid : Vdom.Attr.t
val li_title : Vdom.Attr.t
val li_append : Vdom.Attr.t
val li_label : Vdom.Attr.t
val field_error : Vdom.Attr.t
val welcome : Vdom.Attr.t
val overlay_card : Vdom.Attr.t
val modal_box : Vdom.Attr.t
val layers_text : Vdom.Attr.t
val spinner : Vdom.Attr.t
val spinner_lg : Vdom.Attr.t
