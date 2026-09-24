# Validation and releases

Before publishing a version:

1. Run the Lua suite in both orders under Lua 5.1 and the development interpreter.
2. Run Python vendor tests, parse every Lua file, and check whitespace.
3. Review owned/foreign boundaries, restriction failures, timer identities, detached fixtures, and diagnostic payload policy.
4. Commit the library, vendor that exact revision into each consumer, and verify manifests. Never edit an embedded copy.
5. Run each consumer's normal/reverse tests, TOC checks, and appropriate offline smoke profiles.
6. Publish a new immutable annotated tag. Never move an existing tag.

Initial 1.0.0 automated coverage includes independent namespace copies, global-write traps for all runtime modules, finite primitive sanitization, history/counter/report bounds, generation fences, callback holes/errors/cleanup, queue replacement/reset/disabled behavior, numeric key precision, guarded report-window construction and callbacks, and all detached shared self-tests.

These checks are offline evidence. They do not prove Retail or Classic/Forever behavior. Live validation must separately exercise all three addons together, both load orders where practical, each diagnostics/copy command, test command, loading/reload/enable transitions, combat and restriction transitions, protected/forbidden nameplates, and each addon's unique behavior. Preserve saved variables. Record client build, addon revision, test counts, and observed errors/taint; do not infer support for unknown Forever mechanics.

An addon integration branch or pull request is not an addon release. Consumer version tags and deployment require their own authorization and validation.
