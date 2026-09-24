# Shared debug controller (1.1.0 integration contract)

Load libchev.lua, Debug.lua, DebugWindow.lua, ReportWindow.lua, SelfTests.lua, then consumer code. `LibChev.NewDebugController(policy)` returns an addon-owned controller. The library owns logs/filtering/search/batching/test presentation/command dispatch/console creation and controls. Consumer adapters supply only private data and domain policies.

Owned policy fields:
- `addonName`, optional `title` (default addonName + ` Debug`).
- `getLog()` returns a private `{entries,chars,sequence,dropped}` store dynamically; `commitLog(store)` optionally synchronizes legacy consumer field aliases after mutations. Omit both to use an internal private store.
- `limits` is an AppendLog limits table; `clock()` optionally returns elapsed time.
- `getFilters()` returns category,search; `setFilters(category,search)` persists owned settings. Omit both for session-only filters.
- `getTests()` returns private cases; `testOptions(reverse)` optionally returns LibChev.RunTests options (QT supplies run=WithIsolatedState). The controller supplies reverse order and owns presentation.
- `beforeTests()` optionally returns a token; `afterTests(token)` restores consumer-specific isolation flags even after failures. No presentation/logging inside these hooks.
- `getVersion()` and `getEnvironment()` return sanitized version and owned environment primitives for the standard shared header.
- `buildReport(...)` returns a bounded diagnostic string containing addon-specific state (no generic event history); library owns newest-history composition, total32768 character budget, and presentation.
- `print(text)` is chat fallback; `reload()` is an optional Reload UI adapter.
- `failureDetails` explicitly permits bounded sanitized failure details. Default false (required for PvPTogether); case names/summaries still shown.
- `ui={restricted,canMutate,createFrame,parent}` matches the existing report window ownership/restriction contract.
- `onWindow(frame)` optionally maintains a consumer alias after console creation. Never attach to a Blizzard frame.

Methods:
- `Append(text,category,elapsed)`, `Appendf(category,format,...)`, `AppendState(category,label,value)`, `ClearLog()`, `Clear()` (also reset filters), `RemoveCategory(category)`, `BeginBatch()`, `EndBatch()`.
- `GetCategory()`, `SetCategory(category)`, `GetSearch()`, `SetSearch(text)`, `GetCategories()`, `HasCategory(category)`.
- `EntryText(entry)`, `Matches(entry,category,search)`, `GetEntries(category,search)`, `GetText(category,search)`, `GetMetrics(category,search)` -> shown,chars,total. Omitted filters use current settings.
- `GetRecentText(maxChars)`, `BuildDiagnosticExport(...)`, `Refresh()`, `ShowLog()`, `ShowReport(text,title)`, `ShowDiagnostics(...)`, `IsShowingAll()`.
- `RunTests(reverse,present)` -> success,passed,failed,result. Default present=false is headless and does not mutate live log/UI. present=true replaces TEST history, clears search, selects TEST unless a visible ALL log view is already open, and opens the same console. Suite execution always uses shared RunTests; addon-specific test isolation hooks remain consumer-owned.
- `HandleCommand(command,...)` handles `test`, `runtests`, `debug`, `dump`, `dump clear`, `dump CATEGORY`, `diagnostics`, `diag`. Returns handled,success; callers dispatch domain commands separately. Pass optional domain report arguments to diagnostics.

Window/controller fields used by the shared view are owned: `window`, `mode` (log/report), `reportText`, `reportTitle`, `title`, `tailPinned`, `forceTail`. UI implementation is exclusively DebugWindow.lua: same controls, layout, category/search/tail/copy/test/diagnostic behavior for every consumer. Keep test-runner and fixtures headless by default. Consumer methods may be thin compatibility forwards; delete duplicate generic mechanics/UI.

`LibChev.FormatSafe(format,...)` and `LibChev.StateText(label,value)` expose the same safe primitive formatting for compatibility adapters; no foreign object coercion. Internal batches restore their previous depth after a failed policy callback. Presentation failures retain a chat test-summary fallback and never leave the runner locked.
