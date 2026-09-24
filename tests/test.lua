-- OFFLINE ONLY: no TOC may load this file or its simulated client globals.
local root = arg[1] or "."
local function Load(overrides, namespace)
	local env = setmetatable(overrides or {}, { __index = _G })
	local chunk
	if setfenv then
		chunk = assert(loadfile(root .. "/LibTogether.lua"))
		setfenv(chunk, env)
	else
		chunk = assert(loadfile(root .. "/LibTogether.lua", "t", env))
	end
	return chunk("Fixture", namespace or {})
end
local T = Load()
local cases = {}
local function Test(name, run)
	cases[#cases + 1] = { name = name, run = run }
end
local function Equal(a, b)
	T.AssertEqual(a, b)
end
local function Policy()
	local owner = { state = T.NewWorkState(), active = true, blocked = false, timers = {}, errors = {} }
	local policy = {
		getState = function()
			return owner.state
		end,
		enabled = function()
			return owner.active
		end,
		blocked = function()
			return owner.blocked
		end,
		delay = function(_, callback)
			owner.timers[#owner.timers + 1] = callback
		end,
		invoke = function(_, _, _, callback)
			T.GuardCall(callback, function(err)
				owner.errors[#owner.errors + 1] = err
			end)
		end,
	}
	return policy, owner
end

Test("private copies in either load order cannot replace each other", function()
	for _ = 1, 2 do
		local first, second = {}, {}
		local a, b = Load(nil, first), Load(nil, second)
		Equal(first.Together, a)
		Equal(second.Together, b)
		assert(a ~= b)
		a.VERSION, a.AppendLog = "older-fixture", nil
		Equal(b.VERSION, "1.0.0")
		Equal(type(b.AppendLog), "function")
	end
end)
Test("loader never writes globals", function()
	local env = setmetatable({}, {
		__index = _G,
		__newindex = function()
			error("global write")
		end,
	})
	Load(env)
end)
Test("no coercion of foreign tables", function()
	local foreign = setmetatable({}, {
		__tostring = function()
			error("foreign tostring")
		end,
		__pairs = function()
			error("foreign traversal")
		end,
	})
	Equal(T.Text(foreign), "<table>")
	Equal(T.Number(foreign), nil)
end)
Test("secret and inaccessible values fail closed", function()
	local hidden = {}
	local lib = Load({
		issecretvalue = function(v)
			return v == hidden
		end,
		canaccessvalue = function(v)
			return v ~= "denied"
		end,
	})
	Equal(lib.Text(hidden), "<inaccessible>")
	Equal(lib.Text("denied"), "<inaccessible>")
	Equal(lib.Category(hidden), "DEBUG")
	Equal(lib.Number(hidden), nil)
end)
Test("failed safety queries fail closed", function()
	local lib = Load({
		canaccessvalue = function()
			error("restricted")
		end,
	})
	Equal(lib.Text("visible"), "<inaccessible>")
end)
Test("nonboolean safety query responses fail closed", function()
	Equal(
		Load({
			issecretvalue = function()
				return nil
			end,
		}).Text("visible"),
		"<inaccessible>"
	)
	Equal(
		Load({
			canaccessvalue = function()
				return 1
			end,
		}).Text("visible"),
		"<inaccessible>"
	)
end)
Test("finite primitive conversion", function()
	Equal(T.Number(0 / 0), nil)
	Equal(T.Number(math.huge), nil)
	Equal(T.Number("10"), nil)
	Equal(T.Text(false), "false")
	Equal(T.Text(nil, "unknown"), "unknown")
	Equal(T.Number(0), 0)
end)
Test("category normalization and length bounds", function()
	Equal(T.Category(" some category! "), "SOME_CATEGORY")
	Equal(T.Category("!!!", "CORE"), "CORE")
	assert(#T.Category(string.rep("a", 1000)) <= 64)
end)
Test("line cap preserves most recent entries and sequence", function()
	local log = T.NewLog()
	for i = 1, 5 do
		T.AppendLog(log, "event" .. i, "quest", 123.5, { maxLines = 3 })
	end
	Equal(#log.entries, 3)
	Equal(log.dropped, 2)
	Equal(log.entries[1].sequence, 3)
	assert(T.FormatEntry(log.entries[1]):find("123.500", 1, true))
end)
Test("character cap counts separators and caps one huge entry", function()
	local log = T.NewLog()
	T.AppendLog(log, "123456", "x", nil, { maxChars = 10 })
	T.AppendLog(log, "7890", "x", nil, { maxChars = 10 })
	Equal(#log.entries, 1)
	Equal(log.chars, 4)
	Equal(log.dropped, 1)
	T.AppendLog(log, string.rep("x", 10000), "x", nil, { maxChars = 10 })
	Equal(log.chars, 10)
	Equal(#log.entries, 1)
end)
Test("logs never share mutable history", function()
	local a, b = T.NewLog(), T.NewLog()
	T.AppendLog(a, "only a")
	Equal(#b.entries, 0)
end)
Test("counter cardinality value and reason limits", function()
	local counters = T.NewCounters()
	for _ = 1, 8 do
		T.Count(counters, "one", 2, 5)
	end
	Equal(T.Count(counters, "two", 2, 5), 1)
	Equal(T.Count(counters, "three", 2, 5), nil)
	Equal(T.Count(counters, "invalid reason"), nil)
	Equal(counters.counts.one, 5)
end)
Test("counter snapshots are sorted detached copies", function()
	local counters = T.NewCounters()
	T.Count(counters, "z")
	T.Count(counters, "a")
	local snapshot = T.CounterSnapshot(counters)
	Equal(snapshot[1].reason, "a")
	snapshot[1].count = 8
	Equal(counters.counts.a, 1)
end)
Test("bounded reports reject foreign tostring", function()
	local report = T.NewReport(40)
	report:Add("addon", "Fixture")
	report:Add("payload", string.rep("x", 100))
	Equal(#report:Text(), 40)
	Equal(report.truncated, true)
	assert(report:Text():find("[truncated]", 1, true))
	Equal(report:Add("after", "ignored"), false)
end)
Test("guard preserves argument holes and multiple results", function()
	local ok, a, b, c = T.GuardCall(function(x, y, z)
		Equal(y, nil)
		return x, y, z
	end, nil, 1, nil, 3)
	Equal(ok, true)
	Equal(a, 1)
	Equal(b, nil)
	Equal(c, 3)
end)
Test("guard sanitizes errors and isolates failing reporters", function()
	local ok, err = T.GuardCall(function()
		error({})
	end, function()
		error("reporter")
	end)
	Equal(ok, false)
	Equal(err, "<table>")
end)
Test("weak side tables do not keep frames alive", function()
	local side = T.WeakKeys()
	do
		local frame = {}
		side[frame] = true
	end
	collectgarbage("collect")
	Equal(next(side), nil)
end)
Test("fences reject stale requests and independent lifetime changes", function()
	local owner, calls = { request = 0, lifetime = 0 }, 0
	local callback = T.Fence(owner, { "request", "lifetime" }, function()
		calls = calls + 1
	end)
	callback()
	Equal(calls, 1)
	T.Advance(owner, "lifetime")
	callback()
	Equal(calls, 1)
	local nextCallback = T.Fence(owner, { "request", "lifetime" }, function()
		calls = calls + 1
	end)
	T.Advance(owner, "request")
	nextCallback()
	Equal(calls, 1)
end)
Test("fence captures keys instead of retaining caller list", function()
	local owner, keys, calls = { generation = 0 }, { "generation" }, 0
	local callback = T.Fence(owner, keys, function()
		calls = calls + 1
	end)
	keys[1] = "different"
	T.Advance(owner, "generation")
	callback()
	Equal(calls, 0)
end)
Test("new request replaces pending work", function()
	local p, o = Policy()
	local calls = 0
	T.ScheduleWork(p, "class", "key", function()
		calls = calls + 1
	end, 1)
	T.ScheduleWork(p, "class", "key", function()
		calls = calls + 10
	end, 1)
	o.timers[1]()
	o.timers[2]()
	o.timers[2]()
	Equal(calls, 10)
end)
Test("reset invalidates old timers after reenable", function()
	local p, o = Policy()
	local calls = 0
	T.ScheduleWork(p, "class", "key", function()
		calls = calls + 1
	end, 1)
	o.state = T.NewWorkState()
	o.timers[1]()
	Equal(calls, 0)
end)
Test("restricted work parks without timer retry loops", function()
	local p, o = Policy()
	o.blocked = true
	local calls = 0
	T.ScheduleWork(p, "class", "key", function()
		calls = calls + 1
	end, 0)
	Equal(#o.timers, 0)
	Equal(calls, 0)
	assert(next(o.state.entries))
	o.blocked = false
	T.FlushWork(p)
	Equal(calls, 1)
	Equal(next(o.state.entries), nil)
end)
Test("immediate requests supersede parked work", function()
	local p, o = Policy()
	o.blocked = true
	local calls = 0
	T.RunOrDeferWork(p, "class", "key", function()
		calls = calls + 1
	end)
	o.blocked = false
	T.RunOrDeferWork(p, "class", "key", function()
		calls = calls + 10
	end)
	T.FlushWork(p)
	Equal(calls, 10)
end)
Test("disabled work does not run until explicitly enabled and flushed", function()
	local p, o = Policy()
	o.active = false
	local calls = 0
	Equal(
		T.RunOrDeferWork(p, "class", "key", function()
			calls = calls + 1
		end),
		false
	)
	Equal(T.FlushWork(p), false)
	Equal(calls, 0)
	o.active = true
	T.FlushWork(p)
	Equal(calls, 1)
end)
Test("work keys cannot collide through separators or number coercion", function()
	local p, o = Policy()
	o.blocked = true
	local calls = 0
	for _, pair in ipairs({ { "a::b", "c" }, { "a", "b::c" }, { "a", 1 }, { "a", "1" } }) do
		T.ScheduleWork(p, pair[1], pair[2], function()
			calls = calls + 1
		end)
	end
	o.blocked = false
	T.FlushWork(p)
	Equal(calls, 4)
end)
Test("flush does not resurrect consumed or replaced work", function()
	local p, o = Policy()
	o.blocked = true
	local stale, fresh = 0, 0
	T.ScheduleWork(p, "class", "a", function() end)
	T.ScheduleWork(p, "class", "b", function() end)
	local key = next(o.state.entries)
	local other = next(o.state.entries, key)
	local first, second = o.state.entries[key], o.state.entries[other]
	first.callback = function()
		T.ScheduleWork(p, second.workClass, second.key, function()
			fresh = fresh + 1
		end, 0)
	end
	second.callback = function()
		stale = stale + 1
	end
	o.blocked = false
	T.FlushWork(p)
	Equal(stale, 0)
	Equal(fresh, 1)
end)
Test("flush stops after a callback resets the store", function()
	local p, o = Policy()
	o.blocked = true
	local calls = 0
	for _, key in ipairs({ "a", "b" }) do
		T.ScheduleWork(p, "class", key, function()
			calls = calls + 1
			o.state = T.NewWorkState()
		end)
	end
	o.blocked = false
	T.FlushWork(p)
	Equal(calls, 1)
end)
Test("callback failures do not prevent unrelated work", function()
	local p, o = Policy()
	o.blocked = true
	local calls = 0
	T.ScheduleWork(p, "class", "bad", function()
		error("fixture")
	end)
	T.ScheduleWork(p, "class", "good", function()
		calls = calls + 1
	end)
	o.blocked = false
	T.FlushWork(p)
	Equal(calls, 1)
	Equal(#o.errors, 1)
end)
Test("test teardown runs after failed setup and failed body", function()
	local clean = 0
	for _, failSetup in ipairs({ true, false }) do
		local result = T.RunTests({ {
			name = "failure",
			run = function()
				error("body")
			end,
		} }, {
			setup = function()
				if failSetup then
					error("setup")
				end
				return "fixture"
			end,
			teardown = function()
				clean = clean + 1
			end,
		})
		Equal(result.failed, 1)
	end
	Equal(clean, 2)
end)
Test("cleanup failures fail the case without stopping later cases", function()
	local result = T.RunTests({ { name = "one", run = function() end }, { name = "two", run = function() end } }, {
		teardown = function()
			error("cleanup")
		end,
	})
	Equal(result.failed, 2)
	assert(result.failures[1].error:find("cleanup", 1, true))
end)
Test("runner supports reverse order and private isolation adapter", function()
	local order = {}
	local result = T.RunTests(
		{
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
		},
		{
			reverse = true,
			run = function(fn)
				fn()
			end,
		}
	)
	Equal(result.passed, 2)
	Equal(order[1], 2)
end)
Test("runner snapshots registration and callback functions", function()
	local list, count = {}, 0
	list[1] = {
		name = "first",
		run = function()
			list[2].run = function()
				error("replacement")
			end
			list[#list + 1] = {
				name = "new",
				run = function()
					error("new")
				end,
			}
		end,
	}
	list[2] = {
		name = "second",
		run = function()
			count = count + 1
		end,
	}
	local result = T.RunTests(list)
	Equal(result.total, 2)
	Equal(result.passed, 2)
	Equal(count, 1)
end)

local result = T.RunTests(cases, {
	reverse = arg[2] == "reverse",
	onFailure = function(failure)
		print("FAIL " .. failure.name .. ": " .. failure.error)
	end,
})
print(string.format("LibTogether: %d passed, %d failed", result.passed, result.failed))
os.exit(result.failed == 0 and 0 or 1)
