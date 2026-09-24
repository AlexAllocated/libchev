# API version 1

Load `libchev.lua` first, then `Debug.lua` and `DebugWindow.lua` for the common console, then optional `ReportWindow.lua` and `SelfTests.lua`, with the same addon loader namespace. Capture `namespace.LibChev` locally. All arguments described as owned below must be private addon values; passing a foreign table is outside the contract.

## Primitives, logs, and reports

- `CanAccess(value)` gates available client accessibility/secret queries. Failed or nonboolean queries deny access. Absent queries support older clients; this is not a restriction-policy decision.
- `Text(value, fallback)` accepts accessible primitive values; other types get a type marker or owned string fallback. It never invokes foreign `__tostring`.
- `Number(value)` returns accessible finite numbers; other inputs return nil.
- `Category(value, fallback)` normalizes an accessible string to a bounded uppercase identifier.
- `NewLog()` returns an owned dense history. `AppendLog(store, text, category, elapsed, limits)` records a monotonic sequence and drops oldest entries to honor line/character bounds. Limits: `maxLines`, `maxChars`, `maxEntry`. `FormatEntry(entry)` formats an owned entry.
- `NewCounters()`, `Count(store, reason, maxReasons, maxCount)`, `CounterSnapshot(store)` provide bounded reasons/counts and sorted detached snapshots. Reasons are owned static identifiers, never names, GUIDs, or arbitrary API text. Sampling policy belongs to the consumer.
- `NewReport(maxChars)` returns `Add(label, value)` and `Text()` methods, bounded by total characters. `DiagnosticReport(addon, version, environment)` adds common addon/library/client headers.
- `ReadEnvironment(api)` calls owned `GetBuildInfo` and `GetLocale` adapters and sanitizes only their primitive results. Pass an owned adapter table, not a Blizzard API table.

## Callback and lifetime utilities

`GuardCall(callback, onError, ...)` preserves argument/result nil holes and returns the `xpcall` success flag and results. Errors are sanitized and bounded; an available `debugstack` is appended. It never installs an error handler. Consumers whose diagnostics prohibit error payloads should discard detail and record a static reason in `onError`.

`WeakKeys()` returns an owned weak-key table. `Advance(owner, key)` advances an owned generation. `Fence(owner, keys, callback)` snapshots multiple generation fields and silently rejects stale invocations; its key list is copied. Consumers advance generations at their own lifecycle boundaries.

## Deferred work

`NewWorkState()` creates private `entries` and `generations` tables. `WorkKey(workClass, key)` uses an owned nonempty string class and an owned nil/string/boolean/finite-number key. Other key types are rejected. Numeric keys preserve double precision; separator and primitive-type collisions are avoided.

The owned policy contains:

| Field | Contract |
| --- | --- |
| `getState()` | Return current owned work store. Replace the store to invalidate old callbacks. |
| `enabled()` | Return true only when background work is enabled. |
| `blocked(workClass)` | Return true for restricted, unknown, or failed restriction checks. |
| `invoke(class, key, reason, callback)` | Perform domain checks and contain callback errors, commonly with `GuardCall`. |
| `delay(seconds, callback)` | Optional injected scheduler. |
| `defaultDelay(workClass)` | Optional finite delay. |
| `allowImmediateWhenDisabled` | Explicit opt-in for immediate user actions only; never enables parked/background work. Use a separate policy for that work class. |

Adapters are trusted, synchronous policy functions: they must not throw or mutate the work store during a query. The library does not guess engine safety or retry indefinitely.

`ScheduleWork(policy, class, key, callback, delay, reason)` replaces prior work for the same key. A callback runs only while both the original store and original entry remain current, enabled, and unblocked. Blocked work parks until the consumer flushes it. Completed entries remove generation bookkeeping.

`RunOrDeferWork(...)` invokes immediately when allowed, otherwise parks work and returns false. An immediate invocation supersedes pending work for that key. `FlushWork(policy, reason)` snapshots pending entries, skips replaced/consumed entries, and stops if the store or enabled state changes. Queue capacity and flush triggers belong to consumers; this is not an unbounded input ingestion API.

## Diagnostic copy window

`OpenReportWindow(owner, text, policy)` uses `owner.diagnosticsWindow` for a single unnamed owned window. Reserve this field for the library. Its policy supplies `restricted()`, `canMutate(region)`, `createFrame(...)`, `parent`, and `title`. Policy callbacks must remain valid for the lifetime of the window and reflect current restrictions.

A restriction answer must be exactly false, and mutation permission exactly true; failures/unknown answers deny. Guards run before initializing every child and during callbacks after opening. Only the parent reference is passed to frame creation; it is never modified. Text is bounded to 32,768 characters, selected for copying, and scrollable. The function returns false when denied; the consumer chooses its fallback. The window may remain visible while restrictions prevent mutation or closing.

## Tests

`RunTests(cases, options)` accepts an owned array of `{name, run}` records (`fn` is also accepted). It snapshots registration, runs optional `setup(case)` and `run(callback, fixture)`, and always attempts `teardown(fixture, case)`, including failed setup/body. Options also include `reverse` and `onFailure(failure)`. Teardown must tolerate a nil fixture. Results contain `total`, `passed`, `failed`, and detached `failures`. `AssertEqual` and `TestSummary` standardize assertions and reporting.

`SelfTests()` returns fresh private cases. Consumers can register them alongside safe addon checks. Engine mocks, global replacement, live addon state resets, and offline library tests are forbidden in in-game loaders.

## Shared debug console

Version 1.1.0 adds `NewDebugController` and one guarded console view used by all three consumers. See [the complete controller contract](DEBUG_CONTRACT.md). The older `OpenReportWindow` remains available for standalone bounded copy windows; it is no longer the addon debug console. Shared tests include three extra controller checks when `Debug.lua` is loaded (13 pure checks total).
