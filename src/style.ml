open! Bonsai_web

(** Scoped, co-located styles via ppx_css. Class accessors are [Style.foo : Vdom.Attr.t]
    with auto-hashed names; the stylesheet is injected into the page at runtime. Global
    element rules, the imperative toast classes (see {!Toast}), and the FontAwesome/MDI
    layering helpers use [:global(...)] so they keep stable names. *)

include
  [%css
  stylesheet
    {|
  :global(html), :global(body) { margin: 0; padding: 0; height: 100%; }
  :global(body) {
    font-family: Roboto, "Helvetica Neue", Arial, sans-serif;
    background: #1a237e; color: #1a1a1a;
  }
  :global(*) { box-sizing: border-box; }

  /* imperative toast (created in toast.ml) */
  :global(#toast-container) {
    position: fixed; top: 12px; left: 50%; transform: translateX(-50%);
    display: flex; flex-direction: column; gap: 8px; z-index: 2000; align-items: center;
  }
  :global(.toast) {
    background: #323232; color: #fff; padding: 10px 18px; border-radius: 6px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.4); font-size: 0.95rem;
  }

  @keyframes spin { to { transform: rotate(360deg); } }

  .app { min-height: 100vh; background: #1a237e; }

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
    background: #e0e0e0; color: #1a1a1a; border: none; border-radius: 6px;
    padding: 8px 16px; font-size: 0.95rem; cursor: pointer; text-transform: none;
    box-shadow: 0 1px 3px rgba(0,0,0,0.25);
  }
  .btn:hover:not(:disabled) { background: #d0d0d0; }
  .btn:disabled { opacity: 0.5; cursor: default; }
  .primary { background: #3949ab; color: #fff; }
  .icon_btn { background: transparent; box-shadow: none; padding: 4px 6px; }
  .outlined { background: transparent; border: 1px solid rgba(255,255,255,0.6); color: #fff; }
  .actions { justify-content: flex-end; gap: 8px; padding: 8px 16px; }

  /* tabs */
  .tabs { display: flex; gap: 2px; }
  .tab { flex: 1; background: #b3e5fc; border-radius: 0; box-shadow: none; }
  .tab_active { background: #4fc3f7; font-weight: 600; }

  /* lists ([v-list]/[v-list-item] kept global so the e2e suite + DOM queries can select them) */
  :global(.v-list) { list-style: none; margin: 0; padding: 4px; background: #cfd8dc; border-radius: 6px; }
  :global(.v-list-item) { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border-bottom: 1px solid rgba(0,0,0,0.06); }
  :global(.v-list-item):last-child { border-bottom: none; }
  .li_prepend { display: flex; align-items: center; gap: 6px; min-width: 28px; }
  .li_mid { width: 36px; display: flex; align-items: center; justify-content: center; }
  .li_title { flex: 1 1 auto; }
  .li_append { min-width: 28px; text-align: right; }

  /* text fields */
  .text_field {
    width: 100%; padding: 10px 12px; border: 1px solid #90a4ae; border-radius: 6px;
    font-size: 1rem; background: #fff; margin-bottom: 8px;
  }
  .upper { text-transform: uppercase; }
  .field_error { color: #c62828; font-size: 0.85rem; margin-bottom: 8px; }
  .alert_error { background: #ffcdd2; color: #b71c1c; padding: 10px 14px; border-radius: 6px; margin-bottom: 12px; }
  .checkbox_row { display: flex; align-items: center; gap: 6px; color: #e0f7fa; padding-top: 16px; }

  /* welcome / login */
  .welcome { padding: 24px; text-align: center; background: #e0f7fa; max-width: 520px; margin: 24px auto; }
  .welcome_heading { font-size: 2rem; font-weight: 400; }
  .login_form { width: 100%; max-width: 420px; margin: 0 auto; }
  .lobby_select { display: flex; justify-content: center; padding: 16px; }
  .lobby_inner { width: 100%; max-width: 440px; }
  .lobby_buttons { width: 100%; }
  .lobby_buttons .btn { width: 100%; }

  /* toolbar */
  .toolbar { display: flex; align-items: center; gap: 8px; padding: 8px 16px; background: #1e88e5; color: #e0f7fa; }
  :global(.lobby-name) { font-weight: 700; }
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

  /* FontAwesome layering */
  :global(.fa-layers) { position: relative; display: inline-block; width: 1.4em; height: 1.4em; vertical-align: middle; }
  :global(.fa-layers) > * { position: absolute; left: 0; top: 0; width: 100%; text-align: center; }
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
  :global(.bottom-sheet) { width: 100%; background: #e0f7fa; border-radius: 12px 12px 0 0; max-height: 80vh; overflow: auto; }
  .sheet { border-radius: 0; box-shadow: none; margin: 0; }

  /* spinners */
  .spinner { display: inline-block; border: 3px solid rgba(0,0,0,0.2); border-top-color: #3949ab; border-radius: 50%; width: 18px; height: 18px; animation: spin 0.8s linear infinite; }
  .spinner_lg { display: inline-block; border: 8px solid rgba(0,0,0,0.2); border-top-color: yellow; border-radius: 50%; width: 120px; height: 120px; animation: spin 0.8s linear infinite; }
|}]
