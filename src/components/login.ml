open! Core
open Bonsai_web
open Bonsai.Let_syntax
open Avalon_core
open Types
open Ui
module N = Vdom.Node

(** The login screen: email-link or anonymous sign-in. *)

module Style =
  [%css
  stylesheet
    {|
  .welcome_heading { font-size: 1.75rem; font-weight: 400; line-height: 1.3; }
  .alert_error { background: #ffcdd2; color: #b71c1c; padding: 10px 14px; border-radius: 6px; margin-bottom: 12px; }
  .login_form { width: 100%; max-width: 420px; margin: 0 auto; }

  @media (min-width: 600px) {
    .welcome_heading { font-size: 3rem; }
  }
|}]

let user_login (local_ graph) =
  let tab, set_tab = Bonsai.state "email" graph in
  let email, set_email = Bonsai.state "" graph in
  let error, set_error = Bonsai.state "" graph in
  let submitting, set_submitting = Bonsai.state false graph in
  let submitted, set_submitted = Bonsai.state false graph in
  let%arr m = State.value ()
  and tab
  and set_tab
  and email
  and set_email
  and error
  and set_error
  and submitting
  and set_submitting
  and submitted
  and set_submitted in
  let submit_email =
    eff (fun () ->
      run (set_submitting true);
      run (set_error "");
      Email_auth.submit_email_addr
        email
        ~on_ok:(fun () ->
          run (set_submitted true);
          run (set_submitting false))
        ~on_err:(fun e ->
          run (set_error e);
          run (set_submitting false)))
  in
  let anon =
    eff (fun () ->
      run (set_error "");
      State.sign_in_anonymously ~on_err:(fun e -> run (set_error e)) ())
  in
  let field_err = error_text error in
  let alert =
    match m.confirming_email_error with
    | Some e ->
      {%html.jsx|<div *{[ Style.alert_error ]}>%{textf "%s Please try logging in again." e}</div>|}
    | None -> N.none
  in
  let tab_button value lbl =
    btn
      ~attrs:(if String.equal tab value then [ Ui.tab; Ui.tab_active ] else [ Ui.tab ])
      ~on_click:(set_tab value)
      [ N.text lbl ]
  in
  let email_pane =
    if not submitted
    then
      div
        ~attrs:[ Ui.pa_4; Style.login_form ]
        [ text_field
            ~typ:"email"
            ~placeholder:"Email Address"
            ~value:email
            ~on_input:set_email
            ~extra:[ on_enter submit_email ]
            ()
        ; field_err
        ; btn ~loading:submitting ~on_click:submit_email [ N.text "Login" ]
        ]
    else
      div
        ~attrs:[ Ui.pa_4; Style.login_form ]
        [ card
            ~attrs:[ Ui.info_card ]
            [ card_text
                ~attrs:[ Ui.center ]
                [ N.p [ N.text "Check your email for the verification link" ] ]
            ]
        ; btn ~attrs:[ Ui.mt_4 ] ~on_click:(set_submitted false) [ N.text "Try Again" ]
        ]
  in
  let anon_pane =
    div ~attrs:[ Ui.pa_4 ] [ btn ~on_click:anon [ N.text "Login" ]; field_err ]
  in
  let heading =
    {%html.jsx|<span *{[ Style.welcome_heading ]}>Avalon: The Resistance <span *{[ Ui.thin ]}>Online</span></span>|}
  in
  let subtitle =
    {%html.jsx|<p *{[ Ui.mt_4 ]}><span *{[ Ui.subtitle ]}>A game of social deduction for 5 to 10 people, now on desktop and mobile.</span></p>|}
  in
  card
    ~attrs:[ Ui.welcome ]
    [ {%html.jsx|
        <div *{[ Ui.col; Ui.center ]}>
          %{alert}
          %{card_title [ heading; subtitle ]}
          <div *{[ Ui.tabs ]}>
            %{tab_button "email" "Email"}
            %{tab_button "anonymous" "Anonymous"}
          </div>
          %{if String.equal tab "email" then email_pane else anon_pane}
          %{feedback_link "Email"}
        </div>
      |}
    ]
;;
