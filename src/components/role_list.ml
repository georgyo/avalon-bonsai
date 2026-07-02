open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Avalon_core
open Types
open Ui
module D = State.Derived
module N = Vdom.Node
module A = Vdom.Attr

(** Role lists: the admin-selectable list in the lobby, and the static read-only list
    shown on the in-game participants tab. Uses only the shared {!Ui} styling. *)

let selectable_role_list (local_ graph) =
  let info, set_info = Bonsai.state_opt graph ~sexp_of_model:[%sexp_of: role] in
  Ui.modal
    info
    ~on_close:
      (let%arr set_info in
       set_info None)
    ~content:(fun (role : role) ~close:_ ->
      div
        ~attrs:[ Ui.overlay_card ]
        [ card_title
            ~attrs:[ Ui.title_bar ]
            [ team_icon role.team; N.h3 [ N.text role.name ] ]
        ; card_text [ N.text role.description ]
        ])
    graph;
  let%arr m = State.value ()
  and set_info in
  let allow = D.is_admin m in
  let selected = m.selected_roles in
  let item (role : role) =
    let is_sel = Set.mem selected role.name in
    let checkbox =
      if allow
      then
        N.input
          ~attrs:
            [ A.type_ "checkbox"
            ; A.checked_prop is_sel
            ; A.on_click (fun _ ->
                eff (fun () -> State.toggle_role ~name:role.name ~selected:(not is_sel)))
            ]
          ()
      else N.none
    in
    let info_btn =
      btn
        ~attrs:[ Ui.icon_btn; A.create "aria-label" (sprintf "About %s" role.name) ]
        ~on_click:(set_info (Some role))
        [ mdi "information" ]
    in
    (* the checkbox and the role name live in one <label> (display: contents, so the flex
       row layout is untouched): clicking the name toggles the box, and screen readers
       announce the role's name for it *)
    {%html.jsx|
      <li class="v-list-item">
        <label *{[ Ui.li_label ]}>
          <div *{[ Ui.li_prepend ]}>%{checkbox}%{team_icon role.team}</div>
          <div *{[ Ui.li_title ]}>#{role.name}</div>
        </label>
        %{info_btn}
      </li>
    |}
  in
  let items = List.map Avalonlib.selectable_roles ~f:item in
  {%html.jsx|<div><ul class="v-list">*{items}</ul></div>|}
;;

(* static role display (in-game participants tab) *)
let role_list_view (roles : role list) =
  let item (role : role) =
    let attrs = [ A.class_ "v-list-item"; Ui.tooltip_text role.description ] in
    {%html.jsx|
      <li *{attrs}>
        <div *{[ Ui.li_prepend ]}>%{team_icon role.team}</div>
        <div *{[ Ui.li_title ]}>#{role.name}</div>
      </li>
    |}
  in
  let items = List.map roles ~f:item in
  {%html.jsx|<ul class="v-list">*{items}</ul>|}
;;
