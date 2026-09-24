-- OFFLINE ONLY: private region and controller simulations.
local Test, Equal, Load = ...
local T = Load()

local function Fixture(deniedIndex)
	local state = { regions = {}, writes = 0, restricted = false, range = 300, calls = {} }
	local function Region(kind)
		local region = { kind = kind, scripts = {}, shown = false, text = "", value = 0 }
		state.regions[#state.regions + 1] = region
		region.denied = #state.regions == deniedIndex
		local function Event(name, ...)
			if region.scripts[name] then
				region.scripts[name](region, ...)
			end
		end
		return setmetatable(region, {
			__index = function(_, method)
				if method == "CreateTexture" or method == "CreateFontString" then
					return function()
						return Region(method)
					end
				elseif method == "GetText" then
					return function()
						return region.text
					end
				elseif method == "GetWidth" then
					return function()
						return rawget(region, "width") or 830
					end
				elseif method == "GetHeight" then
					return function()
						return rawget(region, "height") or 396
					end
				elseif method == "GetStringHeight" then
					return function()
						return 700
					end
				elseif method == "GetVerticalScroll" then
					return function()
						return rawget(region, "scroll") or 0
					end
				elseif method == "GetVerticalScrollRange" then
					return function()
						return state.range
					end
				elseif method == "IsShown" then
					return function()
						return region.shown
					end
				end
				return function(_, ...)
					assert(not region.denied, "mutation of denied child")
					assert(state.restricted == false, "mutation while restricted")
					state.writes = state.writes + 1
					if method == "SetScript" then
						local event, callback = ...
						region.scripts[event] = callback
					elseif method == "SetText" then
						region.text = ...
						Event("OnTextChanged", false)
					elseif method == "SetValue" then
						region.value = ...
						Event("OnValueChanged", region.value)
					elseif method == "SetVerticalScroll" then
						region.scroll = ...
						Event("OnVerticalScroll", region.scroll)
					elseif method == "SetWidth" then
						region.width = ...
					elseif method == "SetHeight" then
						region.height = ...
					elseif method == "Show" then
						region.shown = true
					elseif method == "SetShown" then
						region.shown = ...
					elseif method == "Hide" then
						local shown = region.shown
						region.shown = false
						if shown then
							Event("OnHide")
						end
					elseif method == "SetFocus" then
						region.focused = true
					elseif method == "ClearFocus" then
						region.focused = false
					elseif method == "HighlightText" then
						region.selected = true
					elseif method == "StartMoving" then
						region.moving = true
					elseif method == "StartSizing" then
						region.sizing = true
					elseif method == "StopMovingOrSizing" then
						region.moving, region.sizing = false, false
					end
				end
			end,
		})
	end
	local controller = { title = "Fixture Debug", mode = "log", category = "ALL", search = "", tailPinned = true }
	controller.policy = {
		ui = {
			restricted = function()
				return state.restricted
			end,
			canMutate = function(region)
				for _, owned in ipairs(state.regions) do
					if owned == region then
						return not owned.denied
					end
				end
				return false
			end,
			createFrame = function(kind, name)
				Equal(name, nil)
				return Region(kind)
			end,
		},
		reload = function()
			state.calls.reload = (state.calls.reload or 0) + 1
		end,
		onWindow = function()
			state.calls.window = (state.calls.window or 0) + 1
		end,
	}
	function controller:GetCategory()
		return self.category
	end
	function controller:GetSearch()
		return self.search
	end
	function controller:GetCategories()
		local categories = { "ALL", "CORE", "TEST" }
		for index = 1, 12 do
			categories[#categories + 1] = "CATEGORY" .. index
		end
		return categories
	end
	function controller:GetText()
		return self.cleared and "" or "first event\nsecond event"
	end
	function controller:GetMetrics()
		return self.cleared and 0 or 2, #self:GetText(), self.cleared and 0 or 2
	end
	function controller:Refresh()
		return T.RefreshDebugWindow(self)
	end
	function controller:SetCategory(value)
		self.category, self.forceTail = value, true
		self:Refresh()
	end
	function controller:SetSearch(value)
		self.search, self.forceTail = value, true
		self:Refresh()
	end
	function controller:Clear()
		self.cleared, self.category, self.search, self.mode = true, "ALL", "", "log"
		self:Refresh()
	end
	function controller:ShowLog()
		self.mode = "log"
		self.forceTail = true
		return T.OpenDebugWindow(self)
	end
	function controller:ShowDiagnostics()
		state.calls.diagnostics = (state.calls.diagnostics or 0) + 1
		self.mode, self.reportText, self.reportTitle = "report", "diagnostic=owned", "Fixture Diagnostics"
		return T.OpenDebugWindow(self)
	end
	function controller:RunTests(reverse, present)
		Equal(reverse, false)
		Equal(present, true)
		state.calls.tests = (state.calls.tests or 0) + 1
		self.mode, self.reportText, self.reportTitle = "report", "Tests passed", "Fixture Tests"
		return T.OpenDebugWindow(self)
	end
	state.controller = controller
	return state, controller
end

local function Click(region)
	region.scripts.OnClick(region)
end

Test("debug window creates no UI until open and reuses one unnamed frame", function()
	local s, c = Fixture()
	Equal(#s.regions, 0)
	Equal(T.RefreshDebugWindow(c), false)
	Equal(T.OpenDebugWindow(c), true)
	local count, frame = #s.regions, c.window
	Equal(s.calls.window, 1)
	Equal(c.window.TextBox.text, c:GetText())
	Equal(c.window.Scroll.scroll, 300)
	Equal(T.OpenDebugWindow(c), true)
	Equal(#s.regions, count)
	Equal(c.window, frame)
	Equal(s.calls.window, 1)
	assert(c._debugWindowState.title.text:find("2/2 lines", 1, true))
end)

Test("debug window guards every created region before its first mutation", function()
	local baseline, controller = Fixture()
	assert(T.OpenDebugWindow(controller))
	for index = 1, #baseline.regions do
		local s, c = Fixture(index)
		Equal(T.OpenDebugWindow(c), false)
		Equal(#s.regions, index)
	end
end)

Test("debug window fails closed before creation on unknown or failed policy", function()
	for _, query in ipairs({
		function()
			return nil
		end,
		function()
			return true
		end,
		function()
			error("unknown")
		end,
	}) do
		local s, c = Fixture()
		c.policy.ui.restricted = query
		Equal(T.OpenDebugWindow(c), false)
		Equal(#s.regions, 0)
	end
end)

Test("debug window tail follows new events until user scrolls up", function()
	local s, c = Fixture()
	assert(T.OpenDebugWindow(c))
	c.window.Scroll.scripts.OnMouseWheel({}, 1)
	Equal(c.window.Scroll.scroll, 264)
	Equal(c.tailPinned, false)
	s.range = 500
	assert(c:Refresh())
	Equal(c.window.Scroll.scroll, 264)
	c.window.Slider.scripts.OnValueChanged({}, 500)
	Equal(c.tailPinned, true)
	s.range = 600
	assert(c:Refresh())
	Equal(c.window.Scroll.scroll, 600)
end)

Test("debug window diagnostics and tests reuse console and start at top", function()
	local s, c = Fixture()
	assert(T.OpenDebugWindow(c))
	local frame, count = c.window, #s.regions
	Click(frame.Buttons.diagnostics)
	Equal(c.window, frame)
	Equal(#s.regions, count)
	Equal(frame.Scroll.scroll, 0)
	Equal(frame.TextBox.text, "diagnostic=owned")
	Equal(frame.Search.shown, false)
	Equal(frame.Buttons.clear.shown, false)
	Equal(frame.TextBox.selected, true)
	frame.Slider.scripts.OnValueChanged({}, 80)
	assert(c:Refresh())
	Equal(frame.Scroll.scroll, 80)
	Click(frame.Buttons.tests)
	Equal(frame.TextBox.text, "Tests passed")
	Equal(frame.Scroll.scroll, 0)
	Equal(s.calls.tests, 1)
	Click(frame.Buttons.log)
	Equal(frame.Search.shown, true)
	Equal(frame.Buttons.clear.shown, true)
	Equal(frame.Scroll.scroll, 300)
end)

Test("debug window live search category paging and clear use controller", function()
	local s, c = Fixture()
	assert(T.OpenDebugWindow(c))
	c.window.Search.text = '"exact phrase" fuzzy'
	c.window.Search.scripts.OnTextChanged({}, true)
	Equal(c.search, '"exact phrase" fuzzy')
	Click(c.window.Category)
	Equal(c.window.Popup.shown, true)
	Click(c._debugWindowState.rows[2])
	Equal(c.category, "CORE")
	Equal(c.window.Popup.shown, false)
	Click(c.window.Category)
	c.window.Popup.scripts.OnMouseWheel({}, -1)
	Equal(c._debugWindowState.rows[1].category, "CORE")
	Click(c.window.Buttons.clear)
	Equal(c.category, "ALL")
	Equal(c.search, "")
	Equal(c.window.TextBox.text, "")
	Click(c.window.Buttons.reload)
	Equal(s.calls.reload, 1)
end)

Test("debug window read-only copy does not trust event self", function()
	local _, c = Fixture()
	assert(T.OpenDebugWindow(c))
	local foreign = setmetatable({}, {
		__index = function()
			error("foreign read")
		end,
		__newindex = function()
			error("foreign write")
		end,
	})
	c.window.TextBox.text = "edited"
	c.window.TextBox.scripts.OnTextChanged(foreign, true)
	Equal(c.window.TextBox.text, c:GetText())
	c.window.Buttons.select.scripts.OnClick(foreign)
	Equal(c.window.TextBox.focused, true)
	Equal(c.window.TextBox.selected, true)
	c.window.Search.scripts.OnEscapePressed(foreign)
	Equal(c.window.Search.focused, false)
end)

Test("debug window guarded drag resize close and reload availability", function()
	local _, c = Fixture()
	c.policy.reload = nil
	assert(T.OpenDebugWindow(c))
	Equal(c.window.Buttons.reload.shown, false)
	c.window.Drag.scripts.OnDragStart({})
	Equal(c.window.moving, true)
	c.window.Drag.scripts.OnDragStop({})
	Equal(c.window.moving, false)
	c.window.Resize.scripts.OnMouseDown({}, "LeftButton")
	Equal(c.window.sizing, true)
	c.window.Resize.scripts.OnMouseUp({})
	Equal(c.window.sizing, false)
	Click(c.window.Close)
	Equal(c.window.shown, false)
end)

Test("debug window callbacks and refresh fail closed after permission changes", function()
	for _, failure in ipairs({ "restricted", "unknown", "throws", "protected" }) do
		local s, c = Fixture()
		assert(T.OpenDebugWindow(c))
		if failure == "restricted" then
			s.restricted = true
		elseif failure == "unknown" then
			c.policy.ui.restricted = function()
				return nil
			end
		elseif failure == "throws" then
			c.policy.ui.restricted = function()
				error("blocked")
			end
		else
			for _, region in ipairs(s.regions) do
				region.denied = true
			end
		end
		local writes = s.writes
		for _, region in ipairs(s.regions) do
			for _, callback in pairs(region.scripts) do
				callback({}, 1, true)
			end
		end
		Equal(s.writes, writes)
		Equal(T.RefreshDebugWindow(c), false)
		Equal(T.OpenDebugWindow(c), false)
		Equal(s.writes, writes)
	end
end)

Test("debug window integrates shared controller filtering tests and diagnostics", function()
	local s, fixture = Fixture()
	local policy = fixture.policy
	policy.addonName = "Fixture"
	policy.buildReport = function()
		return "fixture=diagnostics"
	end
	policy.getTests = function()
		return { { name = "private check", run = function() end } }
	end
	local controller = T.NewDebugController(policy)
	controller:Append("first thing", "CORE")
	controller:Append("second thing", "OTHER")
	assert(controller:ShowLog())
	local frame, count = controller.window, #s.regions
	frame.Search.text = '"first"'
	frame.Search.scripts.OnTextChanged({}, true)
	assert(frame.TextBox.text:find("first thing", 1, true))
	assert(not frame.TextBox.text:find("second thing", 1, true))
	Click(frame.Buttons.tests)
	Equal(controller.window, frame)
	assert(frame.TextBox.text:find("1 passed, 0 failed", 1, true))
	Equal(controller:GetSearch(), "")
	Click(frame.Buttons.diagnostics)
	assert(frame.TextBox.text:find("fixture=diagnostics", 1, true))
	Equal(frame.Scroll.scroll, 0)
	Equal(#s.regions, count)
	Click(frame.Buttons.log)
	Equal(controller.mode, "log")
end)

Test("closed debug console does not refresh on append and reopens with current history", function()
	local s, fixture = Fixture()
	local controller = T.NewDebugController(fixture.policy)
	controller:Append("before close", "CORE")
	assert(controller:ShowLog())
	local frame = controller.window
	Click(frame.Close)
	local writes = s.writes
	controller:Append("while hidden", "CORE")
	Equal(s.writes, writes)
	assert(not frame.TextBox.text:find("while hidden", 1, true))
	assert(controller:ShowLog())
	Equal(controller.window, frame)
	assert(frame.TextBox.text:find("while hidden", 1, true))
end)

Test("debug console visibility read fails closed", function()
	for _, query in ipairs({
		function()
			return nil
		end,
		function()
			error("unknown visibility")
		end,
	}) do
		local s, controller = Fixture()
		assert(T.OpenDebugWindow(controller))
		controller.window.IsShown = query
		local writes = s.writes
		Equal(controller:Refresh(), false)
		Equal(s.writes, writes)
	end
end)
