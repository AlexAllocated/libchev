# libchev

- The library is privately embedded into each addon's loader namespace. Never create a global library registry or replace another addon's implementation at runtime.
- All state containers, configuration tables, keys, fixtures, adapters and callbacks must be addon-owned. Foreign values may enter only primitive sanitizers; never traverse foreign objects or invoke their metamethods.
- Never write Blizzard globals, frames, shared tables, mixins, C_* APIs or global error handlers. `pcall` is error containment, not a taint barrier.
- The consumer decides restriction policy. Unknown or failed restriction checks must fail closed there. Keep domain-specific lifecycle and secure-boundary decisions in consumers.
- In-game tests use detached fixtures or explicit addon-owned isolation; offline client mocks and library tests stay out of all TOCs.
- Preserve Lua 5.1 compatibility. Run `lua tests/test.lua`, its reverse order, Python vendor checks, Lua parsing and `git diff --check`. Live Retail/Forever validation is separate.
- Publish immutable tags. Consumers vendor exact revisions via `scripts/vendor.py`; never edit embedded copies directly.
