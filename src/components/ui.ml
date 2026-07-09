open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Avalon_core
open Types
module N = Vdom.Node
module A = Vdom.Attr

(** Shared UI foundation: the generic "design system" used by every component — the small
    set of node-building helpers ([div]/[card]/[btn]/[fa]/[overlay]/[text_field]/...) plus
    the reusable layout, spacing, typography, button, card, tab and list-item style
    classes.

    Component-specific styling is co-located in each component module instead (e.g. the
    welcome heading in {!Login}, the mission tab colours in {!Missions}); only the
    generic, cross-component vocabulary lives here.

    A handful of class names are kept as literal (un-hashed) strings because the
    Playwright e2e suite and imperative DOM code select on them ([v-list], [v-list-item],
    [lobby-name], [bottom-sheet], the FontAwesome [fa-layers] helper, and the icon-font
    classes from [fa]/[mdi]); those live as plain CSS in [web/index.html]. *)

module Style =
  [%css
  stylesheet
    {|
  @keyframes spin { to { transform: rotate(360deg); } }

  .app { min-height: 100vh; background: #303f9f; }

  /* layout helpers */
  .container { max-width: 1100px; margin: 0 auto; padding: 16px; }
  .row { display: flex; flex-direction: row; gap: 8px; }
  .col { display: flex; flex-direction: column; }
  .col6 { display: flex; flex-direction: column; flex: 1 1 320px; }
  .wrap { flex-wrap: wrap; }
  .center { align-items: center; justify-content: center; text-align: center; }
  .center_v { align-items: center; }
  .start { align-items: flex-start; }
  .between { justify-content: space-between; align-items: center; }
  .fill { min-height: 70vh; }
  .spacer { flex: 1 1 auto; }
  .ga_2 { gap: 8px; }
  .pt_2 { padding-top: 8px; }
  .pt_6 { padding-top: 24px; }
  .pt_8 { padding-top: 32px; }
  .mt_4 { margin-top: 16px; }
  .mt_6 { margin-top: 24px; }
  .pa_4 { padding: 16px; }

  /* typography */
  .fw { font-weight: 600; }
  .thin { font-weight: 200; }
  .text_h4 { font-size: 1.8rem; font-weight: 500; }
  .text_h5 { font-size: 1.5rem; font-weight: 500; }
  .text_h6 { font-size: 1.15rem; font-weight: 500; }
  .caption { font-size: 0.8rem; }
  /* section header (overline) for labels sitting on the dark indigo page */
  .label { color: rgba(224,247,250,0.95); font-size: 0.8125rem; font-weight: 500; letter-spacing: 0.08em; text-transform: uppercase; }
  .subtitle { font-size: 1rem; }
  .upper { text-transform: uppercase; }

  /* cards */
  .card { background: #eceff1; border-radius: 8px; box-shadow: 0 2px 6px rgba(0,0,0,0.3); overflow: hidden; margin: 4px 0; }
  .card_title { padding: 12px 16px; font-size: 1.15rem; font-weight: 500; }
  .card_title h3 { margin: 0; font-size: 1.25rem; font-weight: 500; }
  .card_text { padding: 12px 16px; }
  .title_bar { background: #b3e5fc; display: flex; align-items: center; gap: 8px; }
  .info_card { background: #eceff1; }

  /* buttons */
  .btn {
    display: inline-flex; align-items: center; justify-content: center; gap: 6px;
    background: #e0e0e0; color: rgba(0,0,0,0.87); border: none; border-radius: 4px;
    padding: 8px 16px; min-width: 88px; font-size: 0.875rem; font-weight: 500; letter-spacing: 0.03em;
    font-family: inherit; cursor: pointer; text-transform: none; text-decoration: none;
    transition: background-color 0.15s, box-shadow 0.15s;
    box-shadow: 0 3px 1px -2px rgba(0,0,0,0.2), 0 2px 2px 0 rgba(0,0,0,0.14), 0 1px 5px 0 rgba(0,0,0,0.12);
  }
  /* hover fills only on devices with real hover: on touch, the :hover state sticks
     after a tap and leaves buttons looking permanently pressed */
  @media (hover: hover) {
    .btn:hover:not(:disabled) { background: #d0d0d0; }
    .primary:hover:not(:disabled) { background: #303f9f; }
    .success:hover:not(:disabled) { background: #1b5e20; }
    .danger:hover:not(:disabled) { background: #b71c1c; }
    .cta_on_dark:hover:not(:disabled) { background: #e8eaf6; }
    .outlined:hover:not(:disabled) { background: rgba(255,255,255,0.12); }
  }
  .btn:focus-visible { outline: 2px solid #90caf9; outline-offset: 2px; }
  .btn:active:not(:disabled) { box-shadow: none; }
  .btn:disabled { background: #e0e0e0; color: rgba(0,0,0,0.38); box-shadow: none; cursor: default; }
  .primary { background: #3949ab; color: #fff; }
  .primary:disabled { background: #9fa8da; color: rgba(255,255,255,0.8); }
  .success { background: #2e7d32; color: #fff; }
  .danger { background: #c62828; color: #fff; }
  /* the filled CTA for buttons sitting directly on the indigo page, where .primary's
     indigo would disappear into the background */
  .cta_on_dark { background: #fff; color: #303f9f; }
  .icon_btn { background: transparent; box-shadow: none; padding: 4px 6px; min-width: 0; }
  .icon_btn:disabled { background: transparent; }
  .outlined { background: transparent; border: 1px solid rgba(255,255,255,0.6); color: #fff; }
  .actions { justify-content: flex-end; gap: 8px; padding: 8px 16px; }

  /* tabs (Vuetify v-tabs look: text with an active underline indicator) */
  .tabs { display: flex; gap: 0; justify-content: center; border-bottom: 1px solid rgba(0,0,0,0.12); }
  .tab {
    flex: 1; background: transparent; box-shadow: none; border-radius: 0; min-width: 0;
    color: rgba(0,0,0,0.6); padding: 12px 16px; border-bottom: 2px solid transparent;
  }
  .tab:hover:not(:disabled) { background: rgba(0,0,0,0.04); }
  .tab_active { background: transparent; color: #3949ab; border-bottom-color: #3949ab; font-weight: 500; }
  /* variant for a tab strip sitting directly on the dark indigo page */
  .tab_dark { color: rgba(255,255,255,0.7); }
  .tab_dark:hover:not(:disabled) { background: rgba(255,255,255,0.08); }
  .tab_dark.tab_active { color: #90caf9; border-bottom-color: #90caf9; }

  /* list-item internals; the .v-list / .v-list-item rules themselves are global (index.html) */
  .li_prepend { display: flex; align-items: center; gap: 6px; min-width: 28px; }
  .li_mid { width: 36px; display: flex; align-items: center; justify-content: center; }
  .li_title { flex: 1 1 auto; min-width: 0; max-width: 100%; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .li_append { min-width: 28px; text-align: right; }
  /* wraps a row's checkbox + name in a <label> without disturbing the flex row layout */
  .li_label { display: contents; }

  /* text fields (Vuetify filled variant: grey fill, bottom rule, rounded top) */
  .text_field {
    width: 100%; padding: 12px 12px; border: none; border-bottom: 1px solid rgba(0,0,0,0.42);
    border-radius: 4px 4px 0 0; font-size: 1rem; font-family: inherit; color: rgba(0,0,0,0.87);
    background: rgba(0,0,0,0.06); margin-bottom: 8px;
  }
  /* focus keeps the 1px border and fakes the 2px rule with a shadow, so the layout never shifts */
  .text_field:focus { outline: none; border-bottom: 1px solid #3949ab; box-shadow: 0 1px 0 0 #3949ab; background: rgba(0,0,0,0.09); }
  .field_error { background: #ffebee; color: #c62828; padding: 4px 10px; border-radius: 4px; font-size: 0.85rem; margin-bottom: 8px; }

  /* welcome / hero card (login + the connection-error screen); wide enough that the
     "Avalon: The Resistance Online" lockup fits on one line on desktop */
  .welcome { padding: 40px 32px; text-align: center; background: #e0f7fa; max-width: 760px; margin: 24px auto; }

  /* dialog content card (rendered inside a toplayer modal — see [modal] below) */
  .overlay_card { background: #e0f7fa; border-radius: 8px; max-width: 460px; width: 100%; max-height: 90vh; overflow: auto; }
  /* toplayer modal container: center it in the top layer and dim the background, matching
     the look the hand-rolled overlay used to give. */
  .modal_box { position: fixed; inset: 0; margin: auto; width: fit-content; height: fit-content; max-width: calc(100vw - 32px); max-height: calc(100vh - 32px); border: none; background: transparent; padding: 0; overflow: visible; }
  .modal_box::backdrop { background: rgba(0,0,0,0.5); }

  /* FontAwesome layering; .fa-layers itself is global (index.html) — a centering grid,
     so the numeral needs no manual offset */
  .layers_text { font-size: 0.55em; font-weight: 700; color: #212121; }

  /* spinners (border-top picks up currentColor, so it reads on dark and light buttons alike) */
  .spinner { display: inline-block; border: 3px solid rgba(0,0,0,0.2); border-top-color: currentColor; border-radius: 50%; width: 18px; height: 18px; animation: spin 0.8s linear infinite; }
  .spinner_lg { display: inline-block; border: 8px solid rgba(0,0,0,0.2); border-top-color: yellow; border-radius: 50%; width: 120px; height: 120px; animation: spin 0.8s linear infinite; }

  @media (max-width: 599px) {
    .container { padding: 8px; }
    .welcome { padding: 20px 12px; }
    .li_prepend { min-width: 20px; }
    .li_mid { width: 26px; }
    .icon_btn { min-width: 40px; min-height: 40px; }
  }
|}]

(* ---- effect / formatting helpers ---- *)
let run (e : unit Effect.t) : unit = Effect.Expert.handle_non_dom_event_exn e
let eff f = Effect.of_thunk f
let textf fmt = Printf.ksprintf N.text fmt
let on_enter e = A.on_keyup (fun ev -> if ev##.keyCode = 13 then e else Effect.return ())

let swap_at (l : 'a list) i =
  match List.nth l i, List.nth l (i + 1) with
  | Some a, Some b ->
    List.mapi l ~f:(fun j x -> if j = i then b else if j = i + 1 then a else x)
  | _ -> l
;;

(* ---- building blocks, rendered with ppx_html + the Style module ---- *)
let div ?(attrs = []) children = {%html.jsx|<div *{attrs}>*{children}</div>|}
let spanc ?(attrs = []) children = {%html.jsx|<span *{attrs}>*{children}</span>|}

let card ?(attrs = []) children =
  {%html.jsx|<div *{Style.card :: attrs}>*{children}</div>|}
;;

let card_title ?(attrs = []) children =
  {%html.jsx|<div *{Style.card_title :: attrs}>*{children}</div>|}
;;

let card_text ?(attrs = []) children =
  {%html.jsx|<div *{Style.card_text :: attrs}>*{children}</div>|}
;;

let btn ?(attrs = []) ?(disabled = false) ?(loading = false) ~on_click children =
  let attrs =
    (Style.btn :: attrs) @ if disabled || loading then [ A.disabled' true ] else []
  in
  (* keep the label while loading (prepend the spinner) so the button doesn't collapse *)
  let children =
    if loading
    then {%html.jsx|<span *{[ Style.spinner ]}></span>|} :: children
    else children
  in
  {%html.jsx|<button *{attrs} on_click=%{fun _ -> on_click}>*{children}</button>|}
;;

let fa ?(color = "") kind name =
  let style =
    if String.is_empty color then [] else [ A.style (Css_gen.color (`Name color)) ]
  in
  N.create "i" ~attrs:(A.classes [ kind; name ] :: style) []
;;

let mdi name = N.create "i" ~attrs:[ A.classes [ "mdi"; "mdi-" ^ name ] ] []

let team_icon (t : team) =
  match t with
  | Good -> fa "fab" "fa-old-republic"
  | Evil -> fa ~color:"red" "fab" "fa-empire"
;;

(* FontAwesome icon stacking; [fa-layers] is kept as a literal class (it is the external
   library's hook, styled globally in index.html). *)
let fa_layers ?(attrs = []) children =
  {%html.jsx|<span *{A.class_ "fa-layers" :: attrs}>*{children}</span>|}
;;

(* A centered, dimmed, focus-trapped, Esc/click-outside-closable modal (toplayer), shown
   while [value] is [Some]. The modal is portaled into the browser's top layer, so this is
   a graph-level component returning [unit] rather than a node to splice into the tree.
   Closing (Esc, click-outside, or a [~close]-driven button) runs [on_close]; typically
   that clears the same [value] option you pass in. *)
let modal ?(box_attrs = [ Style.modal_box ]) value ~on_close ~content (local_ graph)
  : unit
  =
  let autoclose =
    Bonsai_web_toplayer.Autoclose.create
      ~close:on_close
      ~close_on_esc:(Bonsai.return true)
      graph
  in
  let (_ : unit Bonsai.t) =
    match%sub value with
    | Some v ->
      Bonsai_web_toplayer.Modal.always_open
        ~attrs:(Bonsai.return box_attrs)
        ~autoclose
        ~lock_body_scroll:(Bonsai.return true)
        ~content:(fun (local_ _graph) ->
          let%arr v and on_close in
          content v ~close:on_close)
        graph;
      Bonsai.return ()
    | None -> Bonsai.return ()
  in
  ()
;;

let text_field
  ?(attrs = [])
  ?(typ = "text")
  ?(placeholder = "")
  ?(extra = [])
  ~value
  ~on_input
  ()
  =
  let all =
    (Style.text_field :: attrs)
    @ [ A.type_ typ
      ; A.placeholder placeholder
      ; A.value_prop value
      ; A.on_input (fun _ s -> on_input s)
      ]
    @ extra
  in
  {%html.jsx|<input *{all} />|}
;;

(* inline error text (named [error_text] to leave the [field_error] class accessor free) *)
let error_text error =
  if String.is_empty error
  then N.none
  else {%html.jsx|<div *{[ Style.field_error ]}>#{error}</div>|}
;;

(* A styled, touch-capable hover tooltip (toplayer), replacing bare [title=] attributes:
   it renders a real positioned box that also works on tap, unlike the native browser
   title. *)
let tooltip_text (s : string) : Vdom.Attr.t =
  Bonsai_web_toplayer.tooltip ~show_delay:(Time_ns.Span.of_ms 200.) (N.text s)
;;

(* A Vuetify-style tab strip: one button per label, the [active]-index tab gets the
   underline indicator, and clicking tab [i] runs [on_select i]. [tab_attrs] are extra
   attributes added to every tab button (before the tab classes). *)
let tab_strip ?(tab_attrs = []) ~active ~on_select labels =
  let tab_btn idx label =
    btn
      ~attrs:
        (tab_attrs
         @ if idx = active then [ Style.tab; Style.tab_active ] else [ Style.tab ])
      ~on_click:(on_select idx)
      label
  in
  let tabs = List.mapi labels ~f:tab_btn in
  {%html.jsx|<div *{[ Style.tabs ]}>*{tabs}</div>|}
;;

(* mailto feedback link, styled as a button (port of the Vue "Email"/"Send feedback" btns) *)
let feedback_link label =
  {%html.jsx|<a *{[ Style.btn; Style.mt_4 ]} href="mailto:avalon@shamm.as" target="_blank">%{fa "fas" "fa-envelope-square"} #{label}</a>|}
;;

(* ---- shared style-class accessors re-exported for use across component modules ----
   (the clashing card/card_title/card_text/btn/text_field/overlay classes stay internal
   and are reached only through the helper functions above). *)
let app = Style.app
let container = Style.container
let row = Style.row
let col = Style.col
let col6 = Style.col6
let wrap = Style.wrap
let center = Style.center
let center_v = Style.center_v
let start = Style.start
let between = Style.between
let fill = Style.fill
let spacer = Style.spacer
let ga_2 = Style.ga_2
let pt_2 = Style.pt_2
let pt_6 = Style.pt_6
let pt_8 = Style.pt_8
let mt_4 = Style.mt_4
let mt_6 = Style.mt_6
let pa_4 = Style.pa_4
let fw = Style.fw
let thin = Style.thin
let text_h4 = Style.text_h4
let text_h5 = Style.text_h5
let text_h6 = Style.text_h6
let caption = Style.caption
let label = Style.label
let subtitle = Style.subtitle
let upper = Style.upper
let title_bar = Style.title_bar
let info_card = Style.info_card
let primary = Style.primary
let success = Style.success
let danger = Style.danger
let cta_on_dark = Style.cta_on_dark
let icon_btn = Style.icon_btn
let outlined = Style.outlined
let actions = Style.actions
let tabs = Style.tabs
let tab = Style.tab
let tab_active = Style.tab_active
let tab_dark = Style.tab_dark
let li_prepend = Style.li_prepend
let li_mid = Style.li_mid
let li_title = Style.li_title
let li_append = Style.li_append
let li_label = Style.li_label
let field_error = Style.field_error
let welcome = Style.welcome
let overlay_card = Style.overlay_card
let modal_box = Style.modal_box
let layers_text = Style.layers_text
let spinner = Style.spinner
let spinner_lg = Style.spinner_lg
