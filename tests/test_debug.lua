-- OFFLINE ONLY. Private controllers and injected UI adapters, no client globals.
local Test, Equal, Load = ...
local function Fixture(extra)
	local L, store, messages = Load(), nil, {}
	local policy = {
		addonName = "Fixture",
		print = function(text)
			messages[#messages + 1] = text
		end,
		getVersion = function()
			return "2.0.0"
		end,
		getEnvironment = function()
			return { version = "12", locale = "enUS" }
		end,
	}
	for key, value in pairs(extra or {}) do
		policy[key] = value
	end
	local controller = L.NewDebugController(policy)
	return controller, L, messages
end
local function FakeWindow(L)
	local opens, refreshes = 0, 0
	L.OpenDebugWindow = function(c)
		c.policy.ui = c.policy.ui
			or {
				restricted = function()
					return false
				end,
				canMutate = function()
					return true
				end,
			}
		opens = opens + 1
		c.window = c.window or {
			IsShown = function()
				return true
			end,
		}
		return true
	end
	L.RefreshDebugWindow = function()
		refreshes = refreshes + 1
		return true
	end
	return function()
		return opens, refreshes
	end
end
Test("shared console filters implement fuzzy AND quoted exact and unmatched quotes", function()
	local c = Fixture()
	c:Append("alpha three", "quest")
	c:Append("alpha two", "quest")
	c:Append("alpha three", "state")
	Equal(#c:GetEntries("QUEST", "ath"), 1)
	Equal(#c:GetEntries("QUEST", '"alpha th"'), 1)
	Equal(#c:GetEntries("ALL", '"alpha three'), 2)
	Equal(#c:GetEntries("QUEST", '"alpha" two'), 1)
	Equal(#c:GetEntries("ALL", '"[STATE]" "alpha"'), 1)
	c:SetCategory("quest")
	c:SetSearch('"alpha th"')
	local shown, chars, total = c:GetMetrics()
	Equal(shown, 1)
	Equal(chars, #c:GetText())
	Equal(total, 3)
end)
Test("shared category settings are normalized sorted and recover after removal", function()
	local settings = { category = "all", search = "" }
	local c = Fixture({
		getFilters = function()
			return settings.category, settings.search
		end,
		setFilters = function(category, search)
			settings.category, settings.search = category, search
		end,
	})
	c:Append("z", "z")
	c:Append("a", "a")
	c:Append("test", "test")
	Equal(table.concat(c:GetCategories(), ","), "ALL,A,TEST,Z")
	c:SetCategory("TEST")
	c:SetSearch("foo")
	Equal(c:RemoveCategory("TEST"), 1)
	Equal(c:GetCategory(), "ALL")
	c:Clear()
	Equal(#c:GetEntries(), 0)
	Equal(settings.category, "ALL")
	Equal(settings.search, "")
end)
Test("shared logging retains dense bounds and uses dynamic owned stores", function()
	local L = Load()
	local store = L.NewLog()
	local c = L.NewDebugController({
		getLog = function()
			return store
		end,
		commitLog = function(value)
			store = value
		end,
		limits = { maxLines = 2, maxChars = 20 },
		clock = function()
			return 4
		end,
	})
	c:Append("one", "A")
	c:Append("two", "B")
	c:Append("three", "B")
	Equal(#store.entries, 2)
	Equal(store.dropped, 1)
	Equal(store.entries[2].sequence, 3)
	assert(c:GetText():find("4.000", 1, true))
	store = L.NewLog()
	c:Append("fresh", "A")
	Equal(#store.entries, 1)
	Equal(store.sequence, 1)
	c:ClearLog()
	Equal(store.sequence, 1)
	Equal(store.chars, 0)
end)
Test("shared batching refreshes once and never opens a window during logging", function()
	local c, L = Fixture()
	local counts = FakeWindow(L)
	c:Append("before")
	Equal(counts(), 0)
	c:ShowLog()
	c:BeginBatch()
	c:BeginBatch()
	c:Append("one")
	c:Append("two")
	c:EndBatch()
	local opens, refreshes = counts()
	Equal(opens, 1)
	Equal(refreshes, 0)
	c:EndBatch()
	opens, refreshes = counts()
	Equal(refreshes, 1)
	c:EndBatch()
	opens, refreshes = counts()
	Equal(refreshes, 1)
end)
Test("headless shared tests preserve log and UI while restoring isolation hooks", function()
	local active, restored = false, false
	local c, L, messages = Fixture({
		getTests = function()
			return { {
				name = "private",
				run = function()
					assert(active)
				end,
			} }
		end,
		beforeTests = function()
			active = true
			return "token"
		end,
		afterTests = function(token)
			Equal(token, "token")
			active = false
			restored = true
		end,
	})
	local counts = FakeWindow(L)
	c:Append("runtime", "STATE")
	local history = c:GetLog().entries
	local ok, passed, failed = c:RunTests()
	Equal(ok, true)
	Equal(passed, 1)
	Equal(failed, 0)
	Equal(active, false)
	Equal(restored, true)
	Equal(counts(), 0)
	Equal(c:GetLog().entries, history)
	Equal(#history, 1)
	assert(table.concat(messages):find("1 passed, 0 failed", 1, true))
end)
Test("shared test commands replace TEST history show results and retain other categories", function()
	local fail = false
	local c, L = Fixture({
		getTests = function()
			return {
				{
					name = "case",
					run = function()
						if fail then
							error("private detail")
						end
					end,
				},
			}
		end,
	})
	local counts = FakeWindow(L)
	c:Append("runtime", "STATE")
	c:SetSearch("unrelated")
	local handled, ok = c:HandleCommand(" test ")
	Equal(handled, true)
	Equal(ok, true)
	Equal(c:GetCategory(), "TEST")
	Equal(c:GetSearch(), "")
	Equal(counts(), 1)
	assert(c:GetText():find("1 passed, 0 failed", 1, true))
	local _, summaries = c:GetText():gsub("Test summary:", "")
	Equal(summaries, 1)
	fail = true
	c:HandleCommand("test")
	assert(c:GetText():find("0 passed, 1 failed", 1, true))
	_, summaries = c:GetText():gsub("Test summary:", "")
	Equal(summaries, 1)
	assert(not c:GetText():find("1 passed, 0 failed", 1, true))
	assert(not c:GetText():find("private detail", 1, true))
	Equal(#c:GetEntries("STATE", ""), 1)
	assert(c:GetText():find("library=libchev 1.3.0", 1, true))
end)
Test("shared tests preserve visible ALL view but clear its search", function()
	local c, L = Fixture()
	FakeWindow(L)
	c:Append("runtime", "STATE")
	c:ShowLog()
	c:SetSearch("something")
	c:RunTests(false, true)
	Equal(c:GetCategory(), "ALL")
	Equal(c:GetSearch(), "")
end)
Test("test summary survives history eviction and failed presentation exactly once", function()
	for _, failPresentation in ipairs({ false, true }) do
		local c, L, messages = Fixture({ limits = { maxLines = 1, maxChars = 512 } })
		FakeWindow(L)
		if failPresentation then
			c.policy.setFilters = function()
				error("cannot save filters")
			end
		end
		Equal(c:RunTests(false, true), true)
		local text = failPresentation and table.concat(messages, "\n") or c:GetText()
		local _, summaries = text:gsub("Test summary:", "")
		Equal(summaries, 1)
		assert(text:find("Test summary: 0 passed, 0 failed (0 total).", 1, true))
		if not failPresentation then
			Equal(#c:GetLog().entries, 1)
		end
	end
end)
Test("shared runner guarantees cleanup after setup failure and contains cleanup errors", function()
	local cleanup = false
	local c = Fixture({
		beforeTests = function()
			error("before")
		end,
		afterTests = function(token)
			Equal(token, nil)
			cleanup = true
			error("cleanup")
		end,
	})
	local ok, passed, failed, result = c:RunTests()
	Equal(ok, false)
	Equal(passed, 0)
	Equal(failed, 2)
	Equal(cleanup, true)
	Equal(c.runningTests, false)
	Equal(result.total, 2)
end)
Test("shared runner forwards reverse and addon isolation adapter", function()
	local order = {}
	local c = Fixture({
		getTests = function()
			return {
				{
					name = "one",
					run = function()
						order[#order + 1] = 1
					end,
				},
				{
					name = "two",
					run = function()
						order[#order + 1] = 2
					end,
				},
			}
		end,
		testOptions = function()
			return {
				run = function(fn)
					fn()
				end,
			}
		end,
	})
	Equal(c:RunTests(true), true)
	Equal(order[1], 2)
	Equal(order[2], 1)
end)
Test("shared failure details are opt-in for both console and chat", function()
	for _, enabled in ipairs({ false, true }) do
		local c, L, messages = Fixture({
			failureDetails = enabled,
			getTests = function()
				return { {
					name = "owned case",
					run = function()
						error("DETAIL_MARKER")
					end,
				} }
			end,
		})
		FakeWindow(L)
		c:RunTests()
		c:RunTests(false, true)
		Equal(not not table.concat(messages):find("DETAIL_MARKER", 1, true), enabled)
		Equal(not not c:GetText():find("DETAIL_MARKER", 1, true), enabled)
	end
end)
Test("shared console unavailable or throwing falls back to current results", function()
	for _, throw in ipairs({ false, true }) do
		local c, L, messages = Fixture()
		L.OpenDebugWindow = function()
			if throw then
				error("PRIVATE_UI_ERROR")
			end
			return false
		end
		Equal(c:RunTests(false, true), true)
		local text = table.concat(messages, "\n")
		assert(text:find("0 passed, 0 failed", 1, true))
		assert(not text:find("PRIVATE_UI_ERROR", 1, true))
	end
end)
Test("shared diagnostic and debug commands use one owned controller", function()
	local argument
	local c, L = Fixture({
		buildReport = function(value)
			argument = value
			return "domain=" .. value
		end,
	})
	local counts = FakeWindow(L)
	Equal(c:HandleCommand("diagnostics", 42), true)
	Equal(argument, 42)
	Equal(c.mode, "report")
	assert(c.reportText:find("domain=42", 1, true))
	c:Append("item", "QUEST")
	c:HandleCommand("dump QUEST")
	Equal(c.mode, "log")
	Equal(c:GetCategory(), "QUEST")
	c:HandleCommand("dump clear")
	Equal(#c:GetEntries(), 0)
	Equal(c:GetSearch(), "")
	Equal(c:HandleCommand("options"), false)
	Equal(counts(), 3)
end)
Test("shared diagnostic callback failures emit static fallback without foreign detail", function()
	local c, L = Fixture({
		buildReport = function()
			error("foreign detail")
		end,
	})
	FakeWindow(L)
	Equal(c:ShowDiagnostics(), true)
	assert(c.reportText:find("Report unavailable", 1, true))
	assert(not c.reportText:find("foreign detail", 1, true))
end)
Test("shared reentrant test invocation is rejected without corrupting outer run", function()
	local c
	c = Fixture({
		getTests = function()
			return {
				{
					name = "outer",
					run = function()
						local ok, _, failed = c:RunTests()
						Equal(ok, false)
						Equal(failed, 1)
					end,
				},
			}
		end,
	})
	Equal(c:RunTests(), true)
	Equal(c.runningTests, false)
end)
Test("shared debug sanitizers never invoke foreign tostring", function()
	local c = Fixture()
	local foreign = setmetatable({}, {
		__tostring = function()
			error("foreign")
		end,
	})
	c:Append(foreign, foreign)
	c:SetSearch(foreign)
	Equal(c:GetSearch(), "")
	c:ShowReport(foreign)
	Equal(c.reportText, "")
end)

Test("shared diagnostic export reserves newest history within total budget", function()
	local c = Fixture({
		buildReport = function()
			return "domain=" .. string.rep("x", 40000)
		end,
		limits = { maxLines = 1000, maxChars = 200000 },
	})
	for index = 1, 1000 do
		c:Append("event" .. index .. string.rep("x", 100), "STATE")
	end
	local text = c:BuildDiagnosticExport()
	assert(#text <= 32768)
	assert(text:find("[diagnostics truncated]", 1, true))
	assert(text:find("[older events omitted]", 1, true))
	assert(text:find("event1000", 1, true))
	assert(not text:find("event1x", 1, true))
end)

Test("recent history retains exact fits and bounds tiny budgets", function()
	local c = Fixture()
	c:Append("old", "A")
	c:Append("new", "A")
	Equal(c:GetRecentText(15), "[A] old\n[A] new")
	Equal(c:GetRecentText(0), "")
	Equal(c:GetRecentText(3), "new")
	assert(#c:GetRecentText(10) <= 10)
end)
Test("failed filter presentation releases run lock and balanced nested batches", function()
	local bad = true
	local c, L, messages = Fixture({
		getFilters = function()
			if bad then
				error("policy")
			end
			return "ALL", ""
		end,
	})
	FakeWindow(L)
	c.window = {
		IsShown = function()
			return true
		end,
	}
	Equal(c:RunTests(false, true), true)
	Equal(c.runningTests, false)
	Equal(c.batchDepth, 0)
	assert(table.concat(messages):find("0 passed, 0 failed", 1, true))
	bad = false
	Equal(c:RunTests(), true)
	local fail = true
	c.policy.setFilters = function()
		if fail then
			error("save")
		end
	end
	c:BeginBatch()
	Equal(pcall(c.Clear, c), false)
	Equal(c.batchDepth, 1)
	c:EndBatch()
	Equal(c.batchDepth, 0)
	fail = false
	c:Append("recovered")
	Equal(c.batchDepth, 0)
	Equal(c:RunTests(false, true), true)
end)
Test("shared formatted logging contains invalid formats and foreign objects", function()
	local c, L = Fixture()
	local foreign = setmetatable({}, {
		__tostring = function()
			error("foreign")
		end,
	})
	Equal(L.FormatSafe("%s/%d/%s", false, 2, nil), "false/2/<inaccessible>")
	Equal(L.FormatSafe("%d", foreign), "%d")
	c:Appendf("STATE", "%s", foreign)
	assert(not c:GetText():find("foreign", 1, true))
	c:AppendState("STATE", "enabled", true)
	assert(c:GetText():find("enabled=true", 1, true))
end)

Test("translated controller summaries and fallback leave diagnostic keys and failures intact", function()
	local translations = {
		["Debug console unavailable; results follow in chat."] = "Console indisponible.",
		["Recent events:"] = "Evenements recents:",
		["Report unavailable"] = "Rapport indisponible",
		["Test summary: %d passed, %d failed (%d total)."] = "Tests: %d reussis, %d echecs (%d total).",
		["%s in-game tests"] = "Tests de %s",
		["Addon-owned isolated checks; live-client behavior requires separate validation."] = "Verification isolee.",
	}
	local c, L, messages = Fixture({
		translate = function(text)
			return translations[text] or text
		end,
		getTests = function()
			return {
				{
					name = "raw failure name",
					run = function()
						error("raw failure detail")
					end,
				},
			}
		end,
	})
	L.OpenDebugWindow = function()
		return false
	end
	c:Append("raw event", "CORE")
	assert(not c:ShowLog())
	Equal(messages[1], "Console indisponible.")
	assert(messages[2]:find("[CORE] raw event", 1, true))
	local report = c:BuildDiagnosticExport()
	assert(report:find("diagnostics=Rapport indisponible", 1, true))
	assert(report:find("Evenements recents:", 1, true))
	c:RunTests(false, false)
	Equal(messages[#messages - 1], "[FAIL] raw failure name")
	Equal(messages[#messages], "Tests: 0 reussis, 1 echecs (1 total).")
	c:RunTests(false, true)
	assert(c:GetText():find("suite=Tests de Fixture", 1, true))
	assert(c:GetText():find("purpose=Verification isolee.", 1, true))
	assert(c:GetText():find("[FAIL] raw failure name", 1, true))
	Equal(c:GetCategory(), "TEST")
end)

local function Frames()
	local pending = {}
	return function(callback)
		pending[#pending + 1] = callback
	end, function()
		local current = pending
		pending = {}
		for _, callback in ipairs(current) do
			callback()
		end
		return current
	end, function()
		return #pending
	end
end

Test("presented async tests yield between whole isolated cases and reject duplicate callbacks", function()
	local schedule, frame, queued = Frames()
	local active, order, cleaned = false, {}, 0
	local c, L = Fixture({
		getTests = function(reverse, present)
			Equal(reverse, true)
			Equal(present, true)
			return {
				{
					name = "one",
					run = function()
						assert(active)
						order[#order + 1] = 1
					end,
				},
				{
					name = "skip",
					offline = true,
					run = function()
						error("offline")
					end,
				},
				{
					name = "two",
					run = function()
						assert(active)
						order[#order + 1] = 2
					end,
				},
			}
		end,
		testOptions = function(reverse, present)
			Equal(reverse, true)
			Equal(present, true)
			return {
				schedule = schedule,
				include = function(case)
					return not case.offline
				end,
				setup = function()
					active = true
				end,
				teardown = function()
					active = false
				end,
			}
		end,
		beforeTests = function()
			return "token"
		end,
		afterTests = function(token)
			Equal(token, "token")
			assert(not active)
			cleaned = cleaned + 1
		end,
	})
	FakeWindow(L)
	local ok, passed, failed, result = c:RunTests(true, true)
	Equal(ok, true)
	Equal(passed, 0)
	Equal(failed, 0)
	Equal(result.status, "running")
	Equal(result.total, 2)
	Equal(result.skipped, 1)
	Equal(#order, 0)
	Equal(queued(), 1)
	assert(c:GetText():find("Tests running: 0/2 complete.", 1, true))
	Equal(c:RunTests(), false)
	local stale = frame()[1]
	Equal(active, false)
	Equal(order[1], 2)
	Equal(result.completed, 1)
	stale()
	Equal(result.completed, 1)
	Equal(queued(), 1)
	frame()
	Equal(active, false)
	Equal(order[2], 1)
	Equal(cleaned, 1)
	Equal(result.status, "complete")
	Equal(result.passed, 2)
	Equal(c.runningTests, false)
	stale()
	frame()
	Equal(cleaned, 1)
	Equal(queued(), 0)
	local _, summaries = c:GetText():gsub("Test summary:", "")
	Equal(summaries, 1)
end)

Test("headless tests ignore injected scheduling and remain synchronous", function()
	local count = 0
	local c = Fixture({
		getTests = function()
			return { {
				name = "case",
				run = function()
					count = count + 1
				end,
			} }
		end,
		testOptions = function()
			return {
				schedule = function()
					error("headless scheduling")
				end,
			}
		end,
	})
	local ok, passed, failed, result = c:RunTests()
	Equal(ok, true)
	Equal(passed, 1)
	Equal(failed, 0)
	Equal(count, 1)
	Equal(result.status, "complete")
end)

Test("async scheduler failure preserves partial results cleans up and unlocks", function()
	for _, mode in ipairs({ "throw", "reject", "inline" }) do
		local schedule, frame = Frames()
		local requested, cleanup, cases = 0, 0, 0
		local c, L = Fixture({
			getTests = function()
				return {
					{
						name = "first",
						run = function()
							cases = cases + 1
						end,
					},
					{
						name = "second",
						run = function()
							cases = cases + 1
						end,
					},
				}
			end,
			testOptions = function()
				return {
					schedule = function(callback)
						requested = requested + 1
						if requested == 1 then
							return schedule(callback)
						end
						if mode == "throw" then
							error("scheduler failure")
						end
						if mode == "reject" then
							return false
						end
						callback()
					end,
				}
			end,
			afterTests = function()
				cleanup = cleanup + 1
				error("cleanup failure")
			end,
		})
		FakeWindow(L)
		local _, _, _, result = c:RunTests(false, true)
		frame()
		Equal(result.passed, 1)
		Equal(result.failed, 2)
		Equal(result.completed, 1)
		Equal(result.status, "aborted")
		Equal(result.unrun, 1)
		assert(c:GetText():find("unrun=1", 1, true))
		Equal(cases, 1)
		Equal(cleanup, 1)
		Equal(c.runningTests, false)
		Equal(result.failures[1].name, "Test scheduling unavailable")
		Equal(result.failures[2].name, "Test isolation cleanup failed")
	end
end)

Test("async setup and case failures finish whole teardown before returning to frames", function()
	local schedule, frame = Frames()
	local active, calls, cleanup = false, 0, 0
	local c, L = Fixture({
		getTests = function()
			return {
				{
					name = "setup fails",
					run = function()
						error("unreachable")
					end,
				},
				{
					name = "body fails",
					run = function()
						error("body")
					end,
				},
				{
					name = "passes",
					run = function()
						assert(active)
					end,
				},
			}
		end,
		testOptions = function()
			return {
				schedule = schedule,
				setup = function()
					calls = calls + 1
					active = true
					if calls == 1 then
						error("setup")
					end
				end,
				teardown = function()
					active = false
					cleanup = cleanup + 1
				end,
			}
		end,
	})
	FakeWindow(L)
	local _, _, _, result = c:RunTests(false, true)
	for _ = 1, 3 do
		frame()
		Equal(active, false)
	end
	Equal(result.passed, 1)
	Equal(result.failed, 2)
	Equal(cleanup, 3)
	Equal(c.runningTests, false)
end)

Test("async cancellation rejects stale callbacks without affecting subsequent runs", function()
	local schedule, frame = Frames()
	local count, cleanup = 0, 0
	local c, L = Fixture({
		getTests = function()
			return { {
				name = "case",
				run = function()
					count = count + 1
				end,
			} }
		end,
		testOptions = function()
			return { schedule = schedule }
		end,
		afterTests = function()
			cleanup = cleanup + 1
		end,
	})
	FakeWindow(L)
	local _, _, _, cancelled = c:RunTests(false, true)
	Equal(c:CancelTests("disabled"), true)
	Equal(c:CancelTests(), false)
	Equal(cancelled.status, "cancelled")
	Equal(cancelled.cancelled, 1)
	local _, _, _, completed = c:RunTests(false, true)
	frame()
	Equal(count, 1)
	Equal(cleanup, 2)
	Equal(completed.passed, 1)
	Equal(c.runningTests, false)
end)

Test("async progress refreshes are bounded and preserve a visible ALL view", function()
	local schedule, frame = Frames()
	local cases = {}
	for index = 1, 201 do
		cases[index] = { name = "case", run = function() end }
	end
	local c, L = Fixture({
		getTests = function()
			return cases
		end,
		testOptions = function()
			return { schedule = schedule }
		end,
	})
	local counts = FakeWindow(L)
	c:Append("runtime", "STATE")
	c:ShowLog()
	c:SetSearch("old")
	local _, before = counts()
	local _, _, _, result = c:RunTests(false, true)
	Equal(c:GetCategory(), "ALL")
	Equal(c:GetSearch(), "")
	for _ = 1, 201 do
		frame()
	end
	local _, after = counts()
	Equal(result.completed, 201)
	assert(after - before <= 4)
	Equal(c:GetCategory(), "ALL")
	Equal(#c:GetEntries("STATE", ""), 1)
end)

Test("cancellation inside a case waits for per-case isolation cleanup", function()
	local schedule, frame = Frames()
	local active, cleaned, c = false, 0
	local L
	c, L = Fixture({
		getTests = function()
			return {
				{
					name = "cancel",
					run = function()
						assert(active)
						Equal(c:CancelTests("disabled"), true)
						Equal(cleaned, 0)
					end,
				},
				{
					name = "unrun",
					run = function()
						error("cancelled case")
					end,
				},
			}
		end,
		testOptions = function()
			return {
				schedule = schedule,
				setup = function()
					active = true
				end,
				teardown = function()
					active = false
				end,
			}
		end,
		afterTests = function()
			assert(not active)
			cleaned = cleaned + 1
		end,
	})
	FakeWindow(L)
	local _, _, _, result = c:RunTests(false, true)
	frame()
	Equal(result.status, "cancelled")
	Equal(result.passed, 1)
	Equal(result.cancelled, 1)
	Equal(cleaned, 1)
	Equal(c.runningTests, false)
end)
