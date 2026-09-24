# libchev

Private, embedded Lua utilities for World of Warcraft addons. Each addon loads its own copy into its loader namespace. There is no global registry, shared mutable state, or runtime replacement of another addon's library.

libchev provides bounded structured logs, capped counters, diagnostic reports and a copy window, callback error containment, generation fences, deferred work with injected policies, and a fixture-based test runner. Quest, poison, nameplate, secure-boundary, and lifecycle decisions belong to consumers.

## Embed an immutable revision

From a libchev checkout:

```sh
python3 scripts/vendor.py /path/to/YourAddon --ref v1.1.0
python3 scripts/vendor.py /path/to/YourAddon --check
```

For a verified provisional `Libs/LibTogether` embed, add `--migrate-legacy` to compare its bytes with its exact historical Git revision before migration. Edited or unverified legacy copies are preserved and refused.

The vendor tool records the exact Git revision and SHA-256 of every embedded file. It refuses changed files and unsafe destinations. Commit the generated manifest with the consumer. Tags are immutable; fixes receive new versions.

Place these entries before your own modules in the addon's TOC:

```text
Libs\libchev\libchev.lua
Libs\libchev\Debug.lua
Libs\libchev\DebugWindow.lua
Libs\libchev\ReportWindow.lua
Libs\libchev\SelfTests.lua
Core.lua
```

```lua
local _, namespace = ...
local LibChev = assert(namespace.LibChev)
local log = LibChev.NewLog()
LibChev.AppendLog(log, "Addon initialized", "CORE")
```

The core exports `VERSION = "1.1.0"` and `API_VERSION = 1`. Optional modules extend only that same private object. Never load the library via a separate addon or publish the object in a global registry. Different embedded versions may coexist in either addon load order.

## One debug interface across addons

`NewDebugController` owns the shared log/search/category model, test execution and results, diagnostic exports, command dispatch, and one console implementation. Every addon gets the same draggable, resizable UI with copy, clear, reload, run tests, diagnostics, category selection, fuzzy/quoted search, and scroll-to-latest behavior. Adapters supply owned stores/settings, isolated tests, domain diagnostics, and restriction policies. The library never chooses quest, nameplate, or poison behavior.

Call `controller:HandleCommand(command, ...)` for debug commands and `controller:Append(text, category)` for events. Programmatic `RunTests(reverse)` remains headless; user commands and the Run Tests button explicitly present results. See the [shared debug contract](docs/DEBUG_CONTRACT.md) for every adapter field and method.

## Ownership and safety

All stores, configuration tables, keys, fixtures, adapters, and callbacks must belong to the calling addon. Foreign values may enter primitive sanitizers (`CanAccess`, `Text`, `Number`, `Category`); no foreign table traversal, recursive dump, or `__tostring` is supported. `CanMutateOwnedRegion` applies only to a region the addon created and owns; it does not establish ownership.

The library never patches Blizzard globals, frames, mixins, shared API tables, or global error handlers. `pcall` and `GuardCall` contain errors; they are not taint barriers. Consumers supply fail-closed restriction checks and decide when observed data or engine operations are safe.

See [API contracts](docs/API.md) and [validation and release checklist](docs/VALIDATION.md).

## Tests

```sh
lua tests/test.lua
lua tests/test.lua . reverse
python3 -m unittest discover -s tests -p 'test_*.py'
find . -name '*.lua' -exec luac -p {} \;
git diff --check
```

Lua 5.1 is supported. CI checks 5.1 and 5.2. `tests/` contains offline engine simulations and must never appear in an addon TOC. `SelfTests.lua` supplies detached pure checks suitable for a consumer's in-game runner; it creates no frames, timers, hooks, saved variables, or live-state mutations.

Offline success does not establish Retail or Classic/Forever runtime safety. Live client validation is tracked separately.

MIT licensed.
