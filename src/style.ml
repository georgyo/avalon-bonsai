open! Bonsai_web

(** Scoped, co-located component styles via ppx_css. Class accessors are [Style.foo :
    Vdom.Attr.t] with auto-hashed names; the stylesheet is injected at runtime. Genuinely
    global rules (page reset/font, the imperative toast, and the stable [.v-list] /
    [.lobby-name] / [.bottom-sheet] / [.fa-layers] hooks the e2e and DOM code select on) live
    as plain CSS in [web/index.html] instead — ppx_css's [:global()] escape emits a literal
    [:global(...)] selector that browsers drop. *)

include
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
  .pt_4 { padding-top: 16px; }
  .pt_6 { padding-top: 24px; }
  .pt_8 { padding-top: 32px; }
  .mt_4 { margin-top: 16px; }
  .mt_6 { margin-top: 24px; }
  .pa_4 { padding: 16px; }
  .fw { font-weight: 600; }
  .thin { font-weight: 200; }
  .text_h4 { font-size: 1.8rem; font-weight: 500; }
  .text_h5 { font-size: 1.5rem; font-weight: 500; }
  .text_h6 { font-size: 1.15rem; font-weight: 500; }
  .caption { font-size: 0.8rem; }
  .label { color: #e0f7fa; }
  .subtitle { font-size: 1rem; }

  /* cards */
  .card { background: #cfd8dc; border-radius: 8px; box-shadow: 0 2px 6px rgba(0,0,0,0.3); overflow: hidden; margin: 4px 0; }
  .card_title { padding: 12px 16px; font-size: 1.15rem; font-weight: 500; }
  .card_text { padding: 12px 16px; }
  .title_bar { background: #80deea; display: flex; align-items: center; gap: 8px; }
  .info_card { background: #b0bec5; }

  /* buttons */
  .btn {
    display: inline-flex; align-items: center; justify-content: center; gap: 6px;
    background: #e0e0e0; color: rgba(0,0,0,0.87); border: none; border-radius: 4px;
    padding: 8px 16px; font-size: 0.875rem; font-weight: 500; letter-spacing: 0.03em;
    font-family: inherit; cursor: pointer; text-transform: none;
    box-shadow: 0 3px 1px -2px rgba(0,0,0,0.2), 0 2px 2px 0 rgba(0,0,0,0.14), 0 1px 5px 0 rgba(0,0,0,0.12);
  }
  .btn:hover:not(:disabled) { background: #d0d0d0; }
  .btn:disabled { opacity: 0.5; cursor: default; }
  .primary { background: #3949ab; color: #fff; }
  .icon_btn { background: transparent; box-shadow: none; padding: 4px 6px; }
  .outlined { background: transparent; border: 1px solid rgba(255,255,255,0.6); color: #fff; }
  .actions { justify-content: flex-end; gap: 8px; padding: 8px 16px; }

  /* tabs (Vuetify v-tabs look: text with an active underline indicator) */
  .tabs { display: flex; gap: 0; justify-content: center; border-bottom: 1px solid rgba(0,0,0,0.12); }
  .tab {
    flex: 1; background: transparent; box-shadow: none; border-radius: 0;
    color: rgba(0,0,0,0.6); padding: 12px 16px; border-bottom: 2px solid transparent;
  }
  .tab:hover:not(:disabled) { background: rgba(0,0,0,0.04); }
  .tab_active { background: transparent; color: #1976d2; border-bottom-color: #1976d2; font-weight: 500; }
  /* mission tabs keep a light-blue fill (Vuetify bg-light-blue-lighten-4) under the indicator */
  .tab_mission { background: #b3e5fc; border-radius: 0; }

  /* list-item internals; the .v-list / .v-list-item rules themselves are global (index.html) */
  .li_prepend { display: flex; align-items: center; gap: 6px; min-width: 28px; }
  .li_mid { width: 36px; display: flex; align-items: center; justify-content: center; }
  .li_title { flex: 1 1 auto; }
  .li_append { min-width: 28px; text-align: right; }

  /* text fields (Vuetify filled variant: grey fill, bottom rule, rounded top) */
  .text_field {
    width: 100%; padding: 12px 12px; border: none; border-bottom: 1px solid rgba(0,0,0,0.42);
    border-radius: 4px 4px 0 0; font-size: 1rem; font-family: inherit; color: rgba(0,0,0,0.87);
    background: rgba(0,0,0,0.06); margin-bottom: 8px;
  }
  .text_field:focus { outline: none; border-bottom: 2px solid #1976d2; background: rgba(0,0,0,0.09); }
  .upper { text-transform: uppercase; }
  .field_error { color: #c62828; font-size: 0.85rem; margin-bottom: 8px; }
  .alert_error { background: #ffcdd2; color: #b71c1c; padding: 10px 14px; border-radius: 6px; margin-bottom: 12px; }
  .checkbox_row { display: flex; align-items: center; gap: 6px; color: #e0f7fa; padding-top: 16px; }

  /* welcome / login */
  .welcome { padding: 30px 24px; text-align: center; background: #e0f7fa; max-width: 600px; margin: 24px auto; }
  .welcome_heading { font-size: 3rem; font-weight: 400; line-height: 1.3; }
  .login_form { width: 100%; max-width: 420px; margin: 0 auto; }
  .lobby_select { display: flex; justify-content: center; padding: 16px; }
  .lobby_inner { width: 100%; max-width: 440px; }
  .lobby_buttons { width: 100%; }
  .lobby_buttons .btn { width: 100%; }

  /* toolbar */
  .toolbar { display: flex; align-items: center; gap: 8px; padding: 8px 16px; background: #1e88e5; color: #e0f7fa; }
  .toolbar_email { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 220px; }
  .ellipsis { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  /* game board */
  .game_board { width: 100%; }
  .game_section { padding: 8px 0; }
  .action { width: 100%; }
  .action_title { background: #b3e5fc; }
  .mission_panel { margin-top: 4px; }
  .bg_fail { background: #ffcdd2; }
  .bg_success { background: #c8e6c9; }
  .bg_pending { background: #cfd8dc; }

  /* FontAwesome layering; .fa-layers itself is global (index.html) */
  .layers_text { font-size: 0.55em; top: 35%; font-weight: 700; }

  /* summary table */
  .summary_table { border-collapse: collapse; }
  .summary_table tr { height: 2.2em; }
  .summary_table td { width: 1.7em; padding: 0 4px; text-align: center; }
  .summary_table tr:nth-child(even) { background: gainsboro; }
  .summary_table tr:nth-child(odd) { background: bisque; }
  .player_name { border-left: 2px solid; white-space: nowrap; text-align: left; max-width: 120px; overflow: hidden; text-overflow: ellipsis; }
  .role_cell { border-right: 2px solid; white-space: nowrap; }
  .mission_result { border-right: 2px solid; }

  /* stats */
  .stats_wrap table { border-collapse: collapse; }
  .stats_wrap td { text-align: right; padding: 2px 12px; }
  .stats_header { border-bottom: 2px solid; }

  /* overlays / dialogs */
  .overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 1000; padding: 16px; }
  .overlay_card { background: #e0f7fa; border-radius: 8px; max-width: 460px; width: 100%; max-height: 90vh; overflow: auto; }
  .fullscreen { max-width: 100%; width: 100%; height: 100%; max-height: 100%; border-radius: 0; }
  .endgame_title { background: #80deea; text-align: center; justify-content: center; }
  .endgame_message { font-size: 1.25rem; text-align: center; }
  .endgame_table_wrap { overflow-x: auto; width: 100%; }
  .achievement { max-width: 900px; }

  /* bottom sheet (view role); [.bottom-sheet] kept global so the e2e suite can read the role text */
  .bottom_sheet_overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.4); z-index: 1000; display: flex; align-items: flex-end; }
  /* .bottom-sheet itself is global (index.html) so the e2e suite can read the role text */
  .sheet { border-radius: 0; box-shadow: none; margin: 0; }

  /* spinners */
  .spinner { display: inline-block; border: 3px solid rgba(0,0,0,0.2); border-top-color: #3949ab; border-radius: 50%; width: 18px; height: 18px; animation: spin 0.8s linear infinite; }
  .spinner_lg { display: inline-block; border: 8px solid rgba(0,0,0,0.2); border-top-color: yellow; border-radius: 50%; width: 120px; height: 120px; animation: spin 0.8s linear infinite; }
|}]
