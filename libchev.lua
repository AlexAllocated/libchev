-- SPDX-License-Identifier: MIT
-- Private embedding: every addon receives its own library through its loader
-- namespace. No global registry, Blizzard mutation, hooks, events or saved data.
local _, namespace = ...
local LibChev = { VERSION = "1.1.3", API_VERSION = 1 }
local unpackValues = unpack or table.unpack
local secret = type(issecretvalue) == "function" and issecretvalue or nil
local accessible = type(canaccessvalue) == "function" and canaccessvalue or nil
local accessibleTable = type(canaccesstable) == "function" and canaccesstable or nil
local stackTrace = type(debugstack) == "function" and debugstack or nil

function LibChev.CanAccess(value)
	if accessible then
		local ok, allowed = pcall(accessible, value)
		if not ok or allowed ~= true then
			return false
		end
	end
	if secret then
		local ok, hidden = pcall(secret, value)
		if not ok or hidden ~= false then
			return false
		end
	end
	return true
end

-- No foreign __tostring, recursive dumps, table traversal or secret coercion.
function LibChev.Text(value, fallback)
	if not LibChev.CanAccess(value) then
		return fallback or "<inaccessible>"
	end
	local kind = type(value)
	if kind == "string" then
		return value
	end
	if kind == "number" or kind == "boolean" then
		return tostring(value)
	end
	if kind == "nil" then
		return fallback or "nil"
	end
	return fallback or ("<" .. kind .. ">")
end

function LibChev.Number(value)
	if not LibChev.CanAccess(value) or type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

-- Only for regions CREATED AND OWNED by the caller. This does not establish
-- ownership or grant permission to modify arbitrary Blizzard frames.
function LibChev.CanMutateOwnedRegion(region)
	if not LibChev.CanAccess(region) then
		return false
	end
	local kind = type(region)
	if kind ~= "table" and kind ~= "userdata" then
		return false
	end
	if kind == "table" and accessibleTable then
		local ok, allowed = pcall(accessibleTable, region)
		if not ok or allowed ~= true then
			return false
		end
	end
	for _, name in ipairs({ "IsForbidden", "IsProtected" }) do
		local read, method = pcall(function()
			return region[name]
		end)
		if not read or not LibChev.CanAccess(method) or type(method) ~= "function" then
			return false
		end
		local ok, result = pcall(method, region)
		if not ok or not LibChev.CanAccess(result) or result ~= false then
			return false
		end
	end
	return true
end

function LibChev.ReadEnvironment(api)
	local environment = {}
	if type(api.GetBuildInfo) == "function" then
		local ok, version, build, _, interface = pcall(api.GetBuildInfo)
		if ok then
			environment.version = LibChev.Text(version, "unknown")
			environment.build = LibChev.Text(build, "unknown")
			environment.interface = LibChev.Text(interface, "unknown")
		end
	end
	if type(api.GetLocale) == "function" then
		local ok, locale = pcall(api.GetLocale)
		if ok then
			environment.locale = LibChev.Text(locale, "unknown")
		end
	end
	return environment
end

local function Limit(value, default, maximum)
	return math.max(1, math.min(maximum, math.floor(LibChev.Number(value) or default)))
end

function LibChev.Category(value, fallback)
	if not LibChev.CanAccess(value) or type(value) ~= "string" then
		return fallback or "DEBUG"
	end
	local normalized = value:sub(1, 64):match("^%s*(.-)%s*$"):upper():gsub("%s+", "_"):gsub("[^%w_%-]", "")
	return normalized ~= "" and normalized or (fallback or "DEBUG")
end

function LibChev.NewLog()
	return { entries = {}, sequence = 0, dropped = 0, chars = 0 }
end

-- Dense, bounded entries intentionally support existing addon filter/view code.
-- Store, limits and entries are PRIVATE owned tables, never foreign API results.
function LibChev.AppendLog(store, text, category, elapsed, limits)
	limits = limits or {}
	local maxLines = Limit(limits.maxLines, 1000, 10000)
	local maxChars = Limit(limits.maxChars, 200000, 2000000)
	local maxEntry = math.min(maxChars, Limit(limits.maxEntry, 4096, 16384))
	text = LibChev.Text(text):sub(1, maxEntry)
	store.sequence = store.sequence + 1
	local entry = {
		text = text,
		category = LibChev.Category(category),
		elapsed = LibChev.Number(elapsed),
		sequence = store.sequence,
	}
	store.entries[#store.entries + 1] = entry
	store.chars = store.chars + #text
	while #store.entries > maxLines or store.chars + math.max(0, #store.entries - 1) > maxChars do
		local removed = table.remove(store.entries, 1)
		store.chars = store.chars - #removed.text
		store.dropped = store.dropped + 1
	end
	return entry
end

function LibChev.FormatEntry(entry)
	local elapsed = LibChev.Number(entry.elapsed)
	local time = elapsed and string.format("%.3f ", elapsed) or ""
	return "["
		.. LibChev.Category(entry.category)
		.. "] ["
		.. time
		.. "#"
		.. LibChev.Text(entry.sequence)
		.. "] "
		.. LibChev.Text(entry.text)
end

function LibChev.NewCounters()
	return { counts = {}, size = 0 }
end

function LibChev.Count(store, reason, maxReasons, maxCount)
	if not LibChev.CanAccess(reason) or type(reason) ~= "string" or #reason > 48 or not reason:match("^[%w_%-]+$") then
		return nil
	end
	if store.counts[reason] == nil then
		if store.size >= Limit(maxReasons, 24, 1000) then
			return nil
		end
		store.size = store.size + 1
	end
	local count = math.min(Limit(maxCount, 99999, 1000000000), (store.counts[reason] or 0) + 1)
	store.counts[reason] = count
	return count
end

function LibChev.CounterSnapshot(store)
	local result = {}
	for reason, count in pairs(store.counts) do
		result[#result + 1] = { reason = reason, count = count }
	end
	table.sort(result, function(a, b)
		return a.reason < b.reason
	end)
	return result
end

function LibChev.NewReport(maxChars)
	local report = { lines = {}, chars = 0, limit = Limit(maxChars, 32768, 2000000), truncated = false }
	function report:Add(label, value)
		if self.truncated then
			return false
		end
		local line = LibChev.Text(label):sub(1, 128) .. "=" .. LibChev.Text(value, "unknown"):sub(1, 4096)
		local remaining = self.limit - self.chars - (#self.lines > 0 and 1 or 0)
		if #line > remaining then
			-- Reserve room for an explicit marker inside the overall bound.
			local marker = "[truncated]"
			line = remaining >= #marker and (line:sub(1, remaining - #marker) .. marker)
				or marker:sub(1, math.max(0, remaining))
			self.truncated = true
		end
		if remaining <= 0 then
			return false
		end
		self.chars = self.chars + #line + (#self.lines > 0 and 1 or 0)
		self.lines[#self.lines + 1] = line
		return not self.truncated
	end
	function report:Text()
		return table.concat(self.lines, "\n")
	end
	return report
end

function LibChev.DiagnosticReport(addon, version, environment)
	local report = LibChev.NewReport()
	report:Add("addon", addon)
	report:Add("version", version)
	report:Add("library", "libchev " .. LibChev.VERSION)
	for _, key in ipairs({ "version", "build", "interface", "locale" }) do
		report:Add("client." .. key, environment[key])
	end
	return report
end

-- An error boundary contains failures, NOT taint. onError belongs to the caller;
-- it is itself isolated and never installed as a global error handler.
function LibChev.GuardCall(callback, onError, ...)
	local args, count = { ... }, select("#", ...)
	return xpcall(function()
		return callback(unpackValues(args, 1, count))
	end, function(err)
		local detail = LibChev.Text(err):sub(1, 1200)
		if stackTrace then
			local ok, stack = pcall(stackTrace, 2, 12, 12)
			if ok then
				detail = detail .. "\n" .. LibChev.Text(stack):sub(1, 4096)
			end
		end
		if onError then
			pcall(onError, detail)
		end
		return detail
	end)
end

-- State helpers accept OWNED tables/keys only. They never inspect Blizzard data.
function LibChev.WeakKeys()
	return setmetatable({}, { __mode = "k" })
end

function LibChev.Advance(owner, key)
	owner[key] = (owner[key] or 0) + 1
	return owner[key]
end

-- Capture multiple independent lifetimes (e.g. request AND loading/enable cycle).
-- A stale callback cannot become valid again when a newer request completes.
function LibChev.Fence(owner, keys, callback)
	local captured = {}
	for index, key in ipairs(keys) do
		captured[index] = { key, owner[key] }
	end
	return function(...)
		for _, pair in ipairs(captured) do
			if owner[pair[1]] ~= pair[2] then
				return
			end
		end
		return callback(...)
	end
end

function LibChev.NewWorkState()
	return { entries = {}, generations = {} }
end

local function WorkKey(workClass, key)
	-- Owned primitive keys only. Preserve full double precision; tostring can
	-- alias adjacent numeric keys on Lua 5.1/5.2.
	assert(type(workClass) == "string" and #workClass > 0, "workClass must be an owned nonempty string")
	local kind = type(key)
	assert(kind == "nil" or kind == "string" or kind == "boolean" or kind == "number", "key must be an owned primitive")
	local keyText
	if kind == "number" then
		assert(LibChev.Number(key), "key must be finite")
		keyText = key == 0 and "0" or string.format("%.17g", key)
	else
		keyText = LibChev.Text(key, "global")
	end
	return #workClass .. ":" .. workClass .. ":" .. kind .. ":" .. keyText
end
LibChev.WorkKey = WorkKey

-- Policy is an owned adapter: getState, enabled, blocked, delay, defaultDelay,
-- invoke. No library code guesses whether a Blizzard operation is safe.
function LibChev.ScheduleWork(policy, workClass, key, callback, delay, reason)
	if type(callback) ~= "function" then
		return false
	end
	local state, workKey = policy.getState(), WorkKey(workClass, key)
	local generation = LibChev.Advance(state.generations, workKey)
	local entry = {
		workClass = workClass,
		key = key,
		callback = callback,
		delaySeconds = delay,
		reason = reason,
		generation = generation,
	}
	state.entries[workKey] = entry
	local function run()
		if policy.getState() ~= state or state.entries[workKey] ~= entry then
			return
		end
		if not policy.enabled() or policy.blocked(workClass) then
			return
		end
		state.entries[workKey], state.generations[workKey] = nil, nil
		policy.invoke(workClass, key, reason, callback)
	end
	local seconds = math.max(0, LibChev.Number(delay) or (policy.defaultDelay and policy.defaultDelay(workClass)) or 0)
	if seconds == 0 or not policy.delay then
		run()
	else
		policy.delay(seconds, run)
	end
	return true
end

function LibChev.RunOrDeferWork(policy, workClass, key, callback, delay, reason)
	if type(callback) ~= "function" then
		return false
	end
	if (not policy.enabled() and not policy.allowImmediateWhenDisabled) or policy.blocked(workClass) then
		LibChev.ScheduleWork(policy, workClass, key, callback, delay, reason)
		return false
	end
	local state, workKey = policy.getState(), WorkKey(workClass, key)
	state.entries[workKey], state.generations[workKey] = nil, nil
	policy.invoke(workClass, key, reason, callback)
	return true
end

function LibChev.FlushWork(policy, reason)
	local state = policy.getState()
	if not policy.enabled() then
		return false
	end
	local pending = {}
	for key, entry in pairs(state.entries) do
		pending[#pending + 1] = { key, entry }
	end
	for _, pair in ipairs(pending) do
		if policy.getState() ~= state or not policy.enabled() then
			break
		end
		local key, entry = pair[1], pair[2]
		if state.entries[key] == entry then
			LibChev.ScheduleWork(policy, entry.workClass, entry.key, entry.callback, 0, reason or entry.reason)
		end
	end
	return true
end

function LibChev.AssertEqual(actual, expected, message)
	if actual ~= expected then
		error(
			(message or "values differ") .. ": expected " .. LibChev.Text(expected) .. ", got " .. LibChev.Text(actual),
			2
		)
	end
end

-- Cases are private {name, run} records. Fixtures/mocks are supplied by each
-- addon; this runner never snapshots or patches globals or live addon state.
-- Teardown runs even after setup/body failure. Registration is snapshotted.
function LibChev.RunTests(cases, options)
	options = options or {}
	local pending, result = {}, { total = #cases, passed = 0, failed = 0, failures = {} }
	for index, case in ipairs(cases) do
		pending[index] = { name = case.name, run = case.run or case.fn }
	end
	for index = 1, #pending do
		local case = pending[options.reverse and (#pending - index + 1) or index]
		local fixture
		local ok, err = LibChev.GuardCall(function()
			if options.setup then
				fixture = options.setup(case)
			end
			if options.run then
				options.run(case.run, fixture)
			else
				case.run(fixture)
			end
		end)
		if options.teardown then
			local clean, cleanupError = LibChev.GuardCall(options.teardown, nil, fixture, case)
			if not clean then
				err = ok and cleanupError or (err .. "\nTeardown: " .. cleanupError)
				ok = false
			end
		end
		if ok then
			result.passed = result.passed + 1
		else
			result.failed = result.failed + 1
			local failure = { name = LibChev.Text(case.name), error = err }
			result.failures[#result.failures + 1] = failure
			if options.onFailure then
				pcall(options.onFailure, failure)
			end
		end
	end
	return result
end

function LibChev.TestSummary(result)
	return string.format("Test summary: %d passed, %d failed (%d total).", result.passed, result.failed, result.total)
end

if type(namespace) == "table" then
	namespace.LibChev = LibChev
end
return LibChev
