-- OFFLINE ONLY: owned mock regions; never included by an addon TOC.
local Test, Equal, Load = ...
local T = Load()
local function Fixture(deniedIndex)
	local state = { regions = {}, writes = 0, restricted = false }
	local function Region(kind)
		local region = { kind = kind, scripts = {} }
		state.regions[#state.regions + 1] = region
		region.denied = #state.regions == deniedIndex
		return setmetatable(region, {
			__index = function(_, method)
				if method == "IsProtected" or method == "IsForbidden" then
					return function()
						return region.denied
					end
				elseif method == "CreateTexture" or method == "CreateFontString" then
					return function()
						return Region(method)
					end
				elseif method == "GetStringHeight" then
					return function()
						return 72
					end
				elseif method == "GetVerticalScroll" then
					return function()
						return 36
					end
				elseif method == "GetVerticalScrollRange" then
					return function()
						return 100
					end
				end
				return function(_, ...)
					assert(not region.denied, "mutated denied region")
					assert(state.restricted == false, "mutated while restricted")
					state.writes = state.writes + 1
					if method == "SetScript" then
						local event, callback = ...
						region.scripts[event] = callback
					elseif method == "SetText" then
						region.text = ...
					elseif method == "SetSize" then
						region.width, region.height = ...
					elseif method == "HighlightText" then
						region.selected = true
					end
				end
			end,
		})
	end
	state.policy = {
		restricted = function()
			return state.restricted
		end,
		canMutate = T.CanMutateOwnedRegion,
		createFrame = function(kind, name)
			Equal(name, nil)
			return Region(kind)
		end,
		title = "Fixture",
	}
	return state
end
Test("owned region guard rejects unknown protected forbidden or failed checks", function()
	local function Safe()
		return false
	end
	Equal(T.CanMutateOwnedRegion({ IsProtected = Safe, IsForbidden = Safe }), true)
	for _, bad in ipairs({
		function()
			return true
		end,
		function()
			return nil
		end,
		function()
			error("denied")
		end,
	}) do
		Equal(T.CanMutateOwnedRegion({ IsProtected = bad, IsForbidden = Safe }), false)
		Equal(T.CanMutateOwnedRegion({ IsProtected = Safe, IsForbidden = bad }), false)
	end
	Equal(T.CanMutateOwnedRegion({}), false)
	Equal(T.CanMutateOwnedRegion(nil), false)
	for _, query in ipairs({
		function()
			return false
		end,
		function()
			return nil
		end,
		function()
			error("denied")
		end,
	}) do
		Equal(Load({ canaccesstable = query }).CanMutateOwnedRegion({ IsProtected = Safe, IsForbidden = Safe }), false)
	end
end)
Test("window creation fails closed on restriction errors and unknown answers", function()
	for _, query in ipairs({
		function()
			return true
		end,
		function()
			return nil
		end,
		function()
			error("denied")
		end,
	}) do
		local s = Fixture()
		s.policy.restricted = query
		Equal(T.OpenReportWindow({}, "report", s.policy), false)
		Equal(#s.regions, 0)
	end
end)
Test("window guards every child before its first mutation", function()
	for index = 1, 9 do
		local s = Fixture(index)
		Equal(T.OpenReportWindow({}, "report", s.policy), false)
		Equal(#s.regions, index)
	end
end)
Test("window reuses owned frame and bounds selectable report", function()
	local s, owner = Fixture(), {}
	Equal(T.OpenReportWindow(owner, string.rep("x", 40000), s.policy), true)
	Equal(#owner.diagnosticsWindow.reportText, 32768)
	Equal(#s.regions, 9)
	Equal(T.OpenReportWindow(owner, "updated", s.policy), true)
	Equal(#s.regions, 9)
	Equal(owner.diagnosticsWindow.TextBox.text, "updated")
end)
Test("window callbacks stop when restriction changes or region becomes protected", function()
	for _, restricted in ipairs({ true, "unknown", false }) do
		local s, owner = Fixture(), {}
		assert(T.OpenReportWindow(owner, "report", s.policy))
		s.restricted = restricted
		if restricted == false then
			for _, region in ipairs(s.regions) do
				region.denied = true
			end
		end
		local before = s.writes
		for _, region in ipairs(s.regions) do
			for name, callback in pairs(region.scripts) do
				callback(region, name == "OnMouseWheel" and 1 or true)
			end
		end
		Equal(s.writes, before)
		Equal(T.OpenReportWindow(owner, "blocked", s.policy), false)
	end
end)
Test("window callbacks fail closed when restriction query starts failing", function()
	local s, owner = Fixture(), {}
	assert(T.OpenReportWindow(owner, "report", s.policy))
	s.policy.restricted = function()
		error("unavailable")
	end
	local before = s.writes
	for _, region in ipairs(s.regions) do
		for name, callback in pairs(region.scripts) do
			callback(region, name == "OnMouseWheel" and 1 or true)
		end
	end
	Equal(s.writes, before)
end)
Test("window callbacks operate on safe detached regions", function()
	local s, owner = Fixture(), {}
	assert(T.OpenReportWindow(owner, "report", s.policy))
	local before = s.writes
	for _, region in ipairs(s.regions) do
		for name, callback in pairs(region.scripts) do
			callback(region, name == "OnMouseWheel" and 1 or true)
		end
	end
	assert(s.writes > before)
end)

Test("feedback window copies only the selected URL and reuses its own compact frame", function()
	local s, owner = Fixture(), {}
	s.policy.copyLink = true
	s.policy.title = "Fixture Feedback"
	local first = "https://www.curseforge.com/wow/addons/fixture"
	local second = "https://github.com/owner/fixture"
	assert(T.OpenReportWindow(owner, first, s.policy))
	local frame = owner.diagnosticsWindow
	Equal(frame.width, 620)
	Equal(frame.height, 200)
	Equal(frame.TextBox.text, first)
	Equal(frame.TextBox.selected, true)
	Equal(s.regions[9].text, "Select Link")
	assert(T.OpenReportWindow(owner, second, s.policy))
	Equal(owner.diagnosticsWindow, frame)
	Equal(frame.TextBox.text, second)
	Equal(#s.regions, 9)
	s.restricted = true
	local writes = s.writes
	Equal(T.OpenReportWindow(owner, first, s.policy), false)
	Equal(s.writes, writes)
	Equal(frame.TextBox.text, second)
end)
