-- SPDX-License-Identifier: MIT
-- Safe in-game checks: private Lua values only. No engine mocks, live state
-- resets, frame creation, global writes, saved variables, hooks or timers.
local _, namespace = ...
local T = assert(namespace.LibChev, "Load libchev.lua first")

function T.SelfTests()
	local cases = {}
	local function Test(name, run)
		cases[#cases + 1] = { name = "libchev: " .. name, run = run }
	end
	local Equal = T.AssertEqual
	Test("independent bounded histories", function()
		local a, b = T.NewLog(), T.NewLog()
		for i = 1, 5 do
			T.AppendLog(a, "event" .. i, "test", nil, { maxLines = 2 })
		end
		Equal(#a.entries, 2)
		Equal(a.dropped, 3)
		Equal(a.entries[1].sequence, 4)
		Equal(#b.entries, 0)
	end)
	Test("character bounds include oversized entries", function()
		local log = T.NewLog()
		T.AppendLog(log, string.rep("x", 100), "test", nil, { maxChars = 12 })
		Equal(log.chars, 12)
		Equal(#log.entries[1].text, 12)
	end)
	Test("counter snapshots are detached", function()
		local counters = T.NewCounters()
		T.Count(counters, "reason")
		local snapshot = T.CounterSnapshot(counters)
		snapshot[1].count = 900
		Equal(counters.counts.reason, 1)
	end)
	Test("counter cardinality and value caps", function()
		local counters = T.NewCounters()
		T.Count(counters, "one", 1, 1)
		Equal(T.Count(counters, "one", 1, 1), 1)
		Equal(T.Count(counters, "two", 1, 1), nil)
	end)
	Test("stale request fences", function()
		local state, calls = { generation = 0 }, 0
		local old = T.Fence(state, { "generation" }, function()
			calls = calls + 1
		end)
		T.Advance(state, "generation")
		old()
		Equal(calls, 0)
		T.Fence(state, { "generation" }, function()
			calls = calls + 1
		end)()
		Equal(calls, 1)
	end)
	Test("state stores are independent", function()
		local a, b = T.NewWorkState(), T.NewWorkState()
		a.entries.example = true
		Equal(next(b.entries), nil)
		assert(a.generations ~= b.generations)
	end)
	Test("unambiguous work keys", function()
		assert(T.WorkKey("a::b", "c") ~= T.WorkKey("a", "b::c"))
		assert(T.WorkKey("a", 1) ~= T.WorkKey("a", "1"))
	end)
	Test("report bounds", function()
		local report = T.NewReport(32)
		report:Add("detail", string.rep("x", 100))
		Equal(#report:Text(), 32)
		Equal(report.truncated, true)
	end)
	Test("callback argument and return holes", function()
		local ok, a, b, c = T.GuardCall(function(x, y, z)
			return x, y, z
		end, nil, 1, nil, 3)
		Equal(ok, true)
		Equal(a, 1)
		Equal(b, nil)
		Equal(c, 3)
	end)
	Test("category normalization", function()
		Equal(T.Category(" some category! "), "SOME_CATEGORY")
	end)
	if T.NewDebugController then
		Test("shared debug filters use fuzzy terms and quoted phrases", function()
			assert(T.DebugSearchMatches("Alpha three", "ath"))
			assert(T.DebugSearchMatches("Alpha three", '"alpha th"'))
			assert(not T.DebugSearchMatches("Alpha three", '"alpha two"'))
		end)
		Test("debug controllers keep independent logs and filters", function()
			local first, second = T.NewDebugController(), T.NewDebugController()
			first:Append("owned event", "TEST")
			first:SetCategory("TEST")
			Equal(first:GetCategory(), "TEST")
			Equal(second:GetCategory(), "ALL")
			Equal(#second:GetEntries(), 0)
		end)
		Test("headless debug runner leaves history and windows untouched", function()
			local debug = T.NewDebugController({
				getTests = function()
					return { { name = "private fixture", run = function() end } }
				end,
			})
			local ok, passed, failed = debug:RunTests()
			Equal(ok, true)
			Equal(passed, 1)
			Equal(failed, 0)
			Equal(debug.window, nil)
			Equal(#debug:GetEntries(), 0)
		end)
	end
	return cases
end
