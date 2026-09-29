# Optional consumer localization (1.2.3)

`NewDebugController(policy)`, `NewWelcomeController(policy)` and `OpenReportWindow(owner, text, policy)` accept an optional `policy.translate` callback. It is a plain function, called as `translate(sourceEnglishString)` without a self argument. For the debug controller it belongs on the controller policy, not `policy.ui`. Welcome forwards the same function into its owned feedback window.

The consumer owns this function, its lookup table and locale selection. It should be a pure lookup: do not perform UI operations or change restriction policy inside it. Return the translated string or the input for an unknown key. Missing callbacks, exceptions, inaccessible values and non-string results retain the source English. Explicit consumer window titles also pass through this lookup. Supply translation before creating the controller/window; changing language in already-created controls requires a new UI session.

`LibChev.Translate(policy, text)` implements the lookup. `LibChev.TranslateFormat(policy, sourceFormat, ...)` translates first, sanitizes primitive arguments and formats with `pcall`; an invalid translated format retries the original English format. Preserve Lua format placeholders and argument order, including leading spaces in the title suffix. Neither function invokes foreign table metamethods. A policy itself must be an addon-owned table.

`TestSummary(result, policy)` accepts the optional translation policy; its previous one-argument English behavior remains supported. Shared windows, welcome text, status/help text, report headings and test summaries use these helpers. Existing internal category keys, filter values, commands, links, URLs, diagnostic machine keys and raw log/failure content remain unchanged. Consumers translate their own domain strings and supplied client descriptions separately. API_VERSION remains 1.

## English source keys

The `%s %s` report title receives the addon name then the translated report title. The welcome format receives version, supported-client description, settings command, CurseForge label/link and GitHub label/link. The category and metrics formats receive the unchanged category identifier.

- `Addon`
- `Debug`
- `%s Debug`
- `Diagnostics`
- `%s %s`
- `Debug console unavailable; results follow in chat.`
- `[older events omitted]`
- `[diagnostics truncated]`
- `Report unavailable`
- `Recent events:`
- `%s in-game tests`
- `Addon-owned isolated checks; live-client behavior requires separate validation.`
- `Test summary: %d passed, %d failed (%d total).`
- `Select All`
- `Clear`
- `Reload UI`
- `Run Tests`
- `Log`
- `Search:`
- `Category: %s v`
- ` [%s] (%d/%d lines, %d chars)`
- `Search is fuzzy; use "quotes" for an exact phrase. Select All, then Ctrl+C to copy.`
- `Search is fuzzy; use "quotes" for an exact phrase. Scroll categories with the mouse wheel.`
- `Select All, then Ctrl+C to copy this report. Log returns to event history.`
- `Following newest events`
- `Scroll to the bottom to follow new events`
- `Report`
- `Close`
- `Select Link`
- `Select Report`
- `Press Ctrl+C to copy this address, then open it in your browser.`
- `Report selected: press Ctrl+C to copy. Use the mouse wheel to scroll.`
- `%s Feedback`
- `Feedback: %s`
- `unknown`
- `v%s loaded! Now supports %s. Type %s for settings. If you run into any issues, please leave feedback on %s or %s.`
