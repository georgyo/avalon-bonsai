open! Core
open Bonsai_web
open Avalon_core
open Types
open Ui
module N = Vdom.Node

(** Win/loss statistics table (shown on the lobby-select screen and the view-role sheet). *)

module Style =
  [%css
  stylesheet
    {|
  .stats_wrap table { border-collapse: collapse; }
  .stats_wrap td { text-align: right; padding: 2px 12px; }
  .stats_header { border-bottom: 2px solid; }
  .stats_header td { font-weight: 500; color: rgba(0,0,0,0.6); }
|}]

let stats_display (stats : stats option) (global : stats option) =
  let s = Option.value stats ~default:empty_stats in
  let games = s.games
  and good = s.good
  and wins = s.wins
  and good_wins = s.good_wins in
  let evil = games - good in
  let evil_wins = wins - good_wins in
  let pct n d =
    if d > 0
    then sprintf "%d%%" (Float.to_int (100. *. Float.of_int n /. Float.of_int d))
    else "\u{2014}"
  in
  let row label a b c =
    N.tr
      [ N.td ~attrs:[ Ui.fw ] [ N.text label ]
      ; N.td [ N.text a ]
      ; N.td [ N.text b ]
      ; N.td [ N.text c ]
      ]
  in
  let playtime =
    let secs = s.playtime_seconds in
    let hours = Float.of_int secs /. 60. /. 60. in
    if Float.(hours > 1.)
    then sprintf "%.1f hours" hours
    else if secs > 60
    then sprintf "%d minutes" (secs / 60)
    else "Less than a minute"
  in
  let global_rows =
    match global with
    | Some g when g.games > 0 ->
      [ N.tr
          [ N.td ~attrs:[ Ui.fw ] [ N.text "All Users" ]
          ; N.td [ N.text (pct g.good_wins g.games) ]
          ; N.td [ N.text (pct (g.games - g.good_wins) g.games) ]
          ; N.td []
          ]
      ]
    | _ -> []
  in
  let table =
    N.table
      [ N.thead
          [ N.tr
              ~attrs:[ Style.stats_header ]
              [ N.td []
              ; N.td [ N.text "Good" ]
              ; N.td [ N.text "Evil" ]
              ; N.td [ N.text "Total" ]
              ]
          ]
      ; N.tbody
          ([ row "Games" (Int.to_string good) (Int.to_string evil) (Int.to_string games)
           ; row
               "Wins"
               (Int.to_string good_wins)
               (Int.to_string evil_wins)
               (Int.to_string wins)
           ; row
               "Losses"
               (Int.to_string (good - good_wins))
               (Int.to_string (evil - evil_wins))
               (Int.to_string (games - wins))
           ; row "Win Rate" (pct good_wins good) (pct evil_wins evil) (pct wins games)
           ]
           @ global_rows)
      ]
  in
  {%html.jsx|
    <div *{[ Ui.col; Ui.center; Style.stats_wrap ]}>
      %{table}
      <div *{[ Ui.pt_2 ]}><div>%{textf "Total Playtime: %s" playtime}</div></div>
    </div>
  |}
;;
