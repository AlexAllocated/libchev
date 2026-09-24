-- SPDX-License-Identifier: MIT
-- Shared debug mechanics. All policies, stores, settings and tests are owned by
-- the consumer. Only primitive text/time values may originate outside the addon.
local _, namespace = ...
local L = assert(namespace.LibChev, "Load libchev.lua first")
local Controller = {}
Controller.__index = Controller

local function Text(value, fallback)
	return L.Text(value, fallback or "")
end
local function Category(value)
	return L.Category(value, "ALL")
end
local function Terms(value)
	local search, terms, index = Text(value):lower(), {}, 1
	while index <= #search do
		local start = search:find("%S", index)
		if not start then
			break
		end
		local exact = search:sub(start, start) == '"'
		local finish
		if exact then
			start = start + 1
			finish = search:find('"', start, true) or (#search + 1)
		else
			finish = search:find("%s", start) or (#search + 1)
		end
		local term = search:sub(start, finish - 1)
		if term ~= "" then
			terms[#terms + 1] = { text = term, exact = exact }
		end
		index = finish + 1
	end
	return terms
end
local function Match(text, terms)
	text = text:lower()
	for _, term in ipairs(terms) do
		if term.exact then
			if not text:find(term.text, 1, true) then
				return false
			end
		else
			local start = 1
			for index = 1, #term.text do
				local found = text:find(term.text:sub(index, index), start, true)
				if not found then
					return false
				end
				start = found + 1
			end
		end
	end
	return true
end

function L.NewDebugController(policy)
	policy = policy or {}
	return setmetatable({
		policy = policy,
		log = L.NewLog(),
		category = "ALL",
		search = "",
		title = Text(policy.title, Text(policy.addonName, "Addon") .. " Debug"),
		mode = "log",
		tailPinned = true,
		forceTail = false,
		batchDepth = 0,
		refreshPending = false,
	}, Controller)
end
function Controller:GetLog()
	return self.policy.getLog and self.policy.getLog() or self.log
end
function Controller:Commit(store)
	if self.policy.commitLog then
		self.policy.commitLog(store)
	end
end
function Controller:SaveFilters(category, search)
	self.category, self.search = category, search
	if self.policy.setFilters then
		self.policy.setFilters(category, search)
	end
end
function Controller:HasCategory(category)
	category = Category(category)
	if category == "ALL" then
		return true
	end
	for _, entry in ipairs(self:GetLog().entries) do
		if L.Category(entry.category) == category then
			return true
		end
	end
	return false
end
function Controller:GetFilters()
	local category, search = self.category, self.search
	if self.policy.getFilters then
		category, search = self.policy.getFilters()
	end
	category, search = Category(category), Text(search)
	if not self:HasCategory(category) then
		category = "ALL"
	end
	self:SaveFilters(category, search)
	return category, search
end
function Controller:GetCategory()
	return (self:GetFilters())
end
function Controller:GetSearch()
	local _, search = self:GetFilters()
	return search
end
function Controller:SetCategory(category)
	local _, search = self:GetFilters()
	category = Category(category)
	self:SaveFilters(category, search)
	self:Refresh()
	return category
end
function Controller:SetSearch(search)
	local category = self:GetFilters()
	search = Text(search)
	self:SaveFilters(category, search)
	self:Refresh()
	return search
end
function Controller:GetCategories()
	local found, categories = { ALL = true }, { "ALL" }
	for _, entry in ipairs(self:GetLog().entries) do
		local category = L.Category(entry.category)
		if not found[category] then
			found[category] = true
			categories[#categories + 1] = category
		end
	end
	table.sort(categories, function(a, b)
		if a == b then
			return false
		end
		if a == "ALL" then
			return true
		end
		if b == "ALL" then
			return false
		end
		return a < b
	end)
	return categories
end
function Controller:EntryText(entry)
	if L.Number(entry.elapsed) then
		return L.FormatEntry(entry)
	end
	return "[" .. L.Category(entry.category) .. "] " .. Text(entry.text)
end
function Controller:Matches(entry, category, search)
	category = category == nil and self:GetCategory() or Category(category)
	search = search == nil and self:GetSearch() or Text(search)
	return (category == "ALL" or L.Category(entry.category) == category) and Match(self:EntryText(entry), Terms(search))
end
function Controller:GetEntries(category, search)
	category = category == nil and self:GetCategory() or Category(category)
	search = search == nil and self:GetSearch() or Text(search)
	local result, terms = {}, Terms(search)
	for _, entry in ipairs(self:GetLog().entries) do
		if (category == "ALL" or L.Category(entry.category) == category) and Match(self:EntryText(entry), terms) then
			result[#result + 1] = entry
		end
	end
	return result
end
function Controller:GetText(category, search)
	local lines = {}
	for _, entry in ipairs(self:GetEntries(category, search)) do
		lines[#lines + 1] = self:EntryText(entry)
	end
	return table.concat(lines, "\n")
end
function Controller:GetMetrics(category, search)
	local entries, chars = self:GetEntries(category, search), 0
	for index, entry in ipairs(entries) do
		chars = chars + #self:EntryText(entry) + (index > 1 and 1 or 0)
	end
	return #entries, chars, #self:GetLog().entries
end
function Controller:Refresh()
	if self.batchDepth > 0 then
		self.refreshPending = true
		return false
	end
	self.refreshPending = false
	if not self.window or not L.RefreshDebugWindow then
		return false
	end
	local ok, refreshed = pcall(L.RefreshDebugWindow, self)
	return ok and refreshed == true
end
function Controller:BeginBatch()
	self.batchDepth = self.batchDepth + 1
end
function Controller:EndBatch()
	self.batchDepth = math.max(0, self.batchDepth - 1)
	if self.batchDepth == 0 and self.refreshPending then
		self:Refresh()
	end
end
function Controller:Append(text, category, elapsed)
	if elapsed == nil and self.policy.clock then
		local ok, value = pcall(self.policy.clock)
		if ok then
			elapsed = L.Number(value)
		end
	end
	local store = self:GetLog()
	local entry = L.AppendLog(store, text, category, elapsed, self.policy.limits)
	self:Commit(store)
	self:Refresh()
	return entry
end
function Controller:ClearLog()
	local store = self:GetLog()
	store.entries, store.chars = {}, 0
	self:Commit(store)
	self:Refresh()
end
function Controller:WithBatch(callback)
	local previousDepth = self.batchDepth
	self:BeginBatch()
	local ok, detail = L.GuardCall(callback)
	self.batchDepth = previousDepth
	if previousDepth == 0 and self.refreshPending then
		self:Refresh()
	end
	if not ok then
		error(detail, 0)
	end
end
function Controller:Clear()
	self:WithBatch(function()
		self:ClearLog()
		self:SaveFilters("ALL", "")
	end)
end
function Controller:RemoveCategory(category)
	category = L.Category(category)
	local store, kept, chars = self:GetLog(), {}, 0
	for _, entry in ipairs(store.entries) do
		if L.Category(entry.category) ~= category then
			kept[#kept + 1], chars = entry, chars + #Text(entry.text)
		end
	end
	local removed = #store.entries - #kept
	store.entries, store.chars = kept, chars
	self:Commit(store)
	self:GetFilters()
	self:Refresh()
	return removed
end
function Controller:Print(text)
	if self.policy.print then
		pcall(self.policy.print, Text(text))
	end
end
function Controller:Fallback(text)
	self:Print("Debug console unavailable; results follow in chat.")
	for line in Text(text):gmatch("[^\n]+") do
		self:Print(line)
	end
end
function Controller:Open()
	local ok, shown = pcall(L.OpenDebugWindow, self)
	if ok and shown == true then
		return true
	end
	self:Fallback(self.mode == "report" and self.reportText or self:GetText())
	return false
end
function Controller:ShowLog()
	self.mode, self.forceTail, self.tailPinned = "log", true, true
	return self:Open()
end
function Controller:ShowReport(text, title)
	self.mode, self.reportText, self.reportTitle =
		"report", Text(text):sub(1, 200000), (Text(self.policy.addonName, "Addon") .. " " .. Text(title, "Diagnostics"))
	self.forceTail = false
	return self:Open()
end
function Controller:Header()
	local version, environment = "unknown", {}
	if self.policy.getVersion then
		local ok, value = pcall(self.policy.getVersion)
		if ok then
			version = Text(value, "unknown")
		end
	end
	if self.policy.getEnvironment then
		local ok, value = pcall(self.policy.getEnvironment)
		if ok and type(value) == "table" then
			environment = value
		end
	end
	return L.DiagnosticReport(self.policy.addonName or "Addon", version, environment)
end
function Controller:GetRecentText(maxChars)
	maxChars = math.max(0, math.floor(L.Number(maxChars) or 8192))
	if maxChars == 0 then
		return ""
	end
	local lines, chars = {}, 0
	for _, entry in ipairs(self:GetLog().entries) do
		local line = self:EntryText(entry)
		chars = chars + #line + (#lines > 0 and 1 or 0)
		lines[#lines + 1] = line
	end
	if chars <= maxChars then
		return table.concat(lines, "\n")
	end
	local marker = "[older events omitted]\n"
	if maxChars <= #marker then
		marker = "[...]\n"
	end
	if maxChars <= #marker then
		return (lines[#lines] or ""):sub(-maxChars)
	end
	local available, kept, used = maxChars - #marker, {}, 0
	for index = #lines, 1, -1 do
		local line, separator = lines[index], #kept > 0 and 1 or 0
		if used + #line + separator > available then
			if #kept == 0 then
				kept[1] = line:sub(-available)
			end
			break
		end
		table.insert(kept, 1, line)
		used = used + #line + separator
	end
	return marker .. table.concat(kept, "\n")
end
function Controller:BuildDiagnosticExport(...)
	local ok, report = pcall(self.policy.buildReport, ...)
	if not ok then
		report = self:Header()
		report:Add("diagnostics", "Report unavailable")
		report = report:Text()
	end
	report = Text(report)
	local marker = "\n[diagnostics truncated]"
	if #report > 24576 then
		report = report:sub(1, 24576 - #marker) .. marker
	end
	local heading = "\n\nRecent events:\n"
	return report .. heading .. self:GetRecentText(32768 - #report - #heading)
end
function Controller:ShowDiagnostics(...)
	return self:ShowReport(self:BuildDiagnosticExport(...), "Diagnostics")
end
function Controller:IsShowingAll()
	if not self.window or self.mode ~= "log" or self:GetCategory() ~= "ALL" then
		return false
	end
	local ui = self.policy.ui
	if not ui then
		return false
	end
	local allowed, restricted = pcall(ui.restricted)
	if not allowed or not L.CanAccess(restricted) or restricted ~= false then
		return false
	end
	local queried, mutable = pcall(ui.canMutate, self.window)
	if not queried or not L.CanAccess(mutable) or mutable ~= true then
		return false
	end
	local ok, shown = pcall(function()
		return self.window:IsShown()
	end)
	return ok and L.CanAccess(shown) and shown == true
end
local function AddFailure(result, name, detail)
	result.total, result.failed = result.total + 1, result.failed + 1
	result.failures[#result.failures + 1] = { name = name, error = detail }
end
function Controller:RunTests(reverse, present)
	if self.runningTests then
		return false,
			0,
			1,
			{
				total = 1,
				passed = 0,
				failed = 1,
				failures = { { name = "Test run already active", error = "Reentrant test run rejected" } },
			}
	end
	self.runningTests = true
	local keepAll = false
	if present == true then
		local viewOK, showingAll = pcall(self.IsShowingAll, self)
		keepAll = viewOK and showingAll == true
	end
	local token, result
	local ok, detail = L.GuardCall(function()
		if self.policy.beforeTests then
			token = self.policy.beforeTests()
		end
		local cases = self.policy.getTests and self.policy.getTests() or {}
		local options = self.policy.testOptions and self.policy.testOptions(reverse) or {}
		options.reverse = reverse == true
		result = L.RunTests(cases, options)
	end)
	if not result then
		result = { total = 0, passed = 0, failed = 0, failures = {} }
	end
	if not ok then
		AddFailure(result, "Test execution unavailable", detail)
	end
	if self.policy.afterTests then
		local cleaned, failure = L.GuardCall(self.policy.afterTests, nil, token)
		if not cleaned then
			AddFailure(result, "Test isolation cleanup failed", failure)
		end
	end
	self.runningTests = false
	local report = self:Header()
	report:Add("suite", Text(self.policy.addonName, "Addon") .. " in-game tests")
	report:Add("purpose", "Addon-owned isolated checks; live-client behavior requires separate validation.")
	report:Add("summary", L.TestSummary(result))
	for index, failure in ipairs(result.failures) do
		report:Add("failure." .. index, "[FAIL] " .. Text(failure.name))
		if self.policy.failureDetails == true then
			report:Add("detail." .. index, failure.error)
		end
	end
	if present == true then
		local presented = L.GuardCall(function()
			self:WithBatch(function()
				self:RemoveCategory("TEST")
				for line in report:Text():gmatch("[^\n]+") do
					self:Append(line, "TEST")
				end
				-- Preserve the final summary after bounded history eviction.
				self:Append(L.TestSummary(result), "TEST")
				self:SaveFilters(keepAll and "ALL" or "TEST", "")
			end)
			self:ShowLog()
		end)
		if not presented then
			self:Fallback(report:Text())
		end
	else
		for _, failure in ipairs(result.failures) do
			local line = "[FAIL] " .. Text(failure.name)
			if self.policy.failureDetails == true then
				line = line .. ": " .. Text(failure.error)
			end
			self:Print(line)
		end
		self:Print(L.TestSummary(result))
	end
	return result.failed == 0, result.passed, result.failed, result
end
function Controller:HandleCommand(command, ...)
	command = Text(command):lower():match("^%s*(.-)%s*$")
	if command == "test" or command == "runtests" then
		return true, self:RunTests(false, true)
	elseif command == "diagnostics" or command == "diag" then
		return true, self:ShowDiagnostics(...)
	elseif command == "dump clear" then
		self:Clear()
		return true, self:ShowLog()
	elseif command == "dump" or command == "debug" or command == "debuglog" then
		return true, self:ShowLog()
	end
	local category = command:match("^dump%s+(.+)$")
	if category then
		self:SetCategory(category)
		return true, self:ShowLog()
	end
	return false
end
L.DebugController = Controller
L.DebugSearchTerms = Terms
L.DebugSearchMatches = function(text, search)
	return Match(Text(text), Terms(search))
end
L.DebugEntryText = function(entry)
	return Controller.EntryText(nil, entry)
end
L.DebugEntryMatches = function(entry, category, search)
	return (category == nil or Category(category) == "ALL" or L.Category(entry.category) == Category(category))
		and L.DebugSearchMatches(L.DebugEntryText(entry), search)
end

-- Format templates are addon-owned. Arguments may be foreign primitives and
-- must never reach tostring/format through a foreign object metamethod.
function L.FormatSafe(format, ...)
	local count, arguments = select("#", ...), {}
	for index = 1, count do
		local value = select(index, ...)
		if not L.CanAccess(value) then
			value = "<inaccessible>"
		elseif type(value) ~= "string" and type(value) ~= "number" then
			value = L.Text(value, "<inaccessible>")
		end
		arguments[index] = value
	end
	local safeFormat = L.Text(format, "<inaccessible>")
	local ok, text = pcall(string.format, safeFormat, (unpack or table.unpack)(arguments, 1, count))
	return ok and text or safeFormat
end
function L.StateText(label, value)
	return L.Text(label, "state") .. "=" .. L.Text(value, "<inaccessible>")
end
function Controller:Appendf(category, format, ...)
	return self:Append(L.FormatSafe(format, ...), category)
end
function Controller:AppendState(category, label, value)
	return self:Append(L.StateText(label, value), category)
end
