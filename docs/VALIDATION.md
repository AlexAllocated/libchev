# Validation and releases

Before publishing a version:

1. Run the Lua suite in both orders under Lua 5.1 and the development interpreter.
2. Run Python vendor tests, parse every Lua file, and check whitespace.
3. Review owned/foreign boundaries, restriction failures, timer identities, detached fixtures, and diagnostic payload policy.
4. Commit the library, vendor that exact revision into each consumer, and verify manifests. Never edit an embedded copy.
5. Run each consumer's normal/reverse tests, TOC checks, and appropriate offline smoke profiles.
6. Publish a new immutable annotated tag. Never move an existing tag.

Automated coverage includes independent namespace copies, global-write traps for all runtime modules, finite primitive sanitization, history/counter/report bounds, generation fences, callback holes/errors/cleanup, queue replacement/reset/disabled behavior, numeric key precision, guarded report-window construction and callbacks, and all detached shared self-tests. Version 1.1.0 also covers shared filtering/search, dynamic owned stores, batching, headless versus presented tests, failure privacy, bounded newest-history exports, shared commands, console controls, popup paging, scrolling/tail state, and restriction changes across callbacks.

These checks are offline evidence. They do not prove Retail or Classic/Forever behavior. Live validation must separately exercise all three addons together, both load orders where practical, each diagnostics/copy command, test command, loading/reload/enable transitions, combat and restriction transitions, protected/forbidden nameplates, and each addon's unique behavior. Preserve saved variables. Record client build, addon revision, test counts, and observed errors/taint; do not infer support for unknown Forever mechanics.

An addon integration branch or pull request is not an addon release. Consumer version tags and deployment require their own authorization and validation.

## 1.1.1 console correction

User-reported Forever 1.60.1 build 70009/interface 16001 results for consumers of 1.1.0: QuestTogether 324/324 passed; PvPTogether 15/15 passed; NoPoizen 122/123 passed, with `CoreTests.lua:138` raising division by zero while constructing a NaN test fixture. Consumer fixes remove undefined arithmetic from client-loaded fixtures while retaining NaN rejection coverage offline. PvPTogether supplies the optional clock adapter for shared timestamp formatting.

The 1.1.1 window uses the same native texture templates and artwork referenced by the installed Retail and Forever FrameXML. All regions remain unnamed and independently guarded. Offline region simulations check every created region against denied ownership and restriction changes; they do not establish live appearance or taint safety. The new styling and corrected consumer suites still require a live rerun. Shared test presentation has one final summary, with bounded-history and fallback coverage.
