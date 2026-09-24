-- SPDX-License-Identifier: MIT
local _, namespace = ...
local LibChev = assert(namespace.LibChev, "Load libchev.lua first")

-- Every region is created by this module. Policies and controllers are owned
-- by the embedding addon. No shared dropdown pools or input-scroll helpers.
local function Allowed(controller)
	local policy = controller.policy.ui
	local ok, restricted = pcall(policy.restricted)
	return ok and LibChev.CanAccess(restricted) and restricted == false
end

local function Guard(controller, region)
	if not Allowed(controller) then
		return false
	end
	local ok, allowed = pcall(controller.policy.ui.canMutate, region)
	return ok and LibChev.CanAccess(allowed) and allowed == true
end

local function Call(controller, region, method, ...)
	if not Guard(controller, region) then
		error("debug window mutation denied", 0)
	end
	return region[method](region, ...)
end

local function SafeCallback(controller, region, callback)
	return function(_, ...)
		-- Capture owned references; an event's self argument is never trusted.
		if Guard(controller, region) and Guard(controller, controller.window) then
			pcall(callback, ...)
		end
	end
end

local function SetScroll(controller, state, value, fromUser)
	local maximum = LibChev.Number(Call(controller, state.scroll, "GetVerticalScrollRange"))
	value = LibChev.Number(value)
	if not maximum or not value then
		return false
	end
	maximum = math.max(0, maximum)
	value = math.max(0, math.min(maximum, value))
	state.syncScroll = true
	Call(controller, state.scroll, "SetVerticalScroll", value)
	Call(controller, state.slider, "SetMinMaxValues", 0, maximum)
	Call(controller, state.slider, "SetValue", value)
	state.syncScroll = false
	if fromUser and controller.mode ~= "report" then
		controller.tailPinned = maximum - value <= 2
		controller.forceTail = false
		Call(
			controller,
			state.footer,
			"SetText",
			controller.tailPinned and "Following newest events" or "Scroll to the bottom to follow new events"
		)
	end
	return true
end

local function Create(controller)
	local policy, state = controller.policy.ui, { rows = {}, popupOffset = 0 }
	local function New(kind, parent)
		if not Allowed(controller) then
			error("debug window creation denied", 0)
		end
		local region = policy.createFrame(kind, nil, parent)
		if not Guard(controller, region) then
			error("debug window region denied", 0)
		end
		return region
	end
	local function Label(parent, font)
		local label = Call(controller, parent, "CreateFontString", nil, "OVERLAY", font or "GameFontHighlightSmall")
		if not Guard(controller, label) then
			error("debug window label denied", 0)
		end
		return label
	end
	local function Background(parent, shade)
		local texture = Call(controller, parent, "CreateTexture", nil, "BACKGROUND")
		Call(controller, texture, "SetAllPoints")
		Call(controller, texture, "SetColorTexture", shade, shade, shade, 0.98)
		return texture
	end
	local function Button(parent, label, width)
		local button = New("Button", parent)
		Call(controller, button, "SetSize", width or 90, 24)
		Background(button, 0.18)
		local text = Label(button)
		Call(controller, text, "SetPoint", "CENTER")
		Call(controller, text, "SetText", label)
		button.Label = text
		return button
	end
	local frame = New("Frame", policy.parent)
	Call(controller, frame, "Hide")
	Call(controller, frame, "SetSize", 900, 560)
	Call(controller, frame, "SetPoint", "CENTER")
	Call(controller, frame, "SetFrameStrata", "DIALOG")
	Call(controller, frame, "SetClampedToScreen", true)
	Call(controller, frame, "EnableMouse", true)
	Call(controller, frame, "SetMovable", true)
	Call(controller, frame, "SetResizable", true)
	if type(frame.SetResizeBounds) == "function" then
		Call(controller, frame, "SetResizeBounds", 740, 420, 1400, 1000)
	elseif type(frame.SetMinResize) == "function" then
		Call(controller, frame, "SetMinResize", 740, 420)
	end
	Background(frame, 0.055)
	state.frame = frame
	state.title = Label(frame, "GameFontNormalLarge")
	Call(controller, state.title, "SetPoint", "TOPLEFT", 16, -15)
	Call(controller, state.title, "SetPoint", "TOPRIGHT", frame, "TOPRIGHT", -78, -15)
	Call(controller, state.title, "SetJustifyH", "LEFT")
	local drag = New("Frame", frame)
	Call(controller, drag, "SetPoint", "TOPLEFT", 0, 0)
	Call(controller, drag, "SetPoint", "TOPRIGHT", -78, 0)
	Call(controller, drag, "SetHeight", 34)
	Call(controller, drag, "EnableMouse", true)
	Call(controller, drag, "RegisterForDrag", "LeftButton")
	local close = Button(frame, "Close", 58)
	Call(controller, close, "SetPoint", "TOPRIGHT", -12, -10)

	state.buttons = {}
	local previous
	for _, definition in ipairs({
		{ "select", "Select All" },
		{ "clear", "Clear" },
		{ "reload", "Reload UI" },
		{ "tests", "Run Tests" },
		{ "diagnostics", "Diagnostics" },
		{ "log", "Log" },
	}) do
		local button = Button(frame, definition[2])
		if previous then
			Call(controller, button, "SetPoint", "LEFT", previous, "RIGHT", 6, 0)
		else
			Call(controller, button, "SetPoint", "TOPLEFT", 14, -43)
		end
		state.buttons[definition[1]], previous = button, button
	end
	state.category = Button(frame, "Category: ALL", 184)
	Call(controller, state.category, "SetPoint", "TOPLEFT", 14, -77)
	state.searchLabel = Label(frame)
	Call(controller, state.searchLabel, "SetPoint", "LEFT", state.category, "RIGHT", 12, 0)
	Call(controller, state.searchLabel, "SetText", "Search:")
	state.search = New("EditBox", frame)
	Background(state.search, 0.13)
	Call(controller, state.search, "SetPoint", "TOPLEFT", frame, "TOPLEFT", 265, -77)
	Call(controller, state.search, "SetPoint", "TOPRIGHT", frame, "TOPRIGHT", -16, -77)
	Call(controller, state.search, "SetHeight", 24)
	Call(controller, state.search, "SetFontObject", "ChatFontNormal")
	Call(controller, state.search, "SetAutoFocus", false)
	Call(controller, state.search, "SetTextInsets", 5, 5, 0, 0)
	Call(controller, state.search, "SetMaxLetters", 256)
	state.hint = Label(frame)
	Call(controller, state.hint, "SetPoint", "TOPLEFT", 16, -111)
	Call(
		controller,
		state.hint,
		"SetText",
		'Search is fuzzy; use "quotes" for an exact phrase. Select All, then Ctrl+C to copy.'
	)
	state.scroll = New("ScrollFrame", frame)
	Call(controller, state.scroll, "SetPoint", "TOPLEFT", 14, -135)
	Call(controller, state.scroll, "SetPoint", "BOTTOMRIGHT", -38, 29)
	Call(controller, state.scroll, "EnableMouseWheel", true)
	Background(state.scroll, 0.09)
	state.box = New("EditBox", state.scroll)
	Call(controller, state.box, "SetMultiLine", true)
	Call(controller, state.box, "SetAutoFocus", false)
	Call(controller, state.box, "SetFontObject", "ChatFontNormal")
	Call(controller, state.box, "SetTextInsets", 4, 4, 4, 4)
	Call(controller, state.box, "SetWidth", 830)
	Call(controller, state.box, "SetHeight", 1)
	Call(controller, state.box, "SetMaxLetters", 0)
	Call(controller, state.scroll, "SetScrollChild", state.box)
	state.measure = Label(frame, "ChatFontNormal")
	Call(controller, state.measure, "Hide")
	state.slider = New("Slider", frame)
	Call(controller, state.slider, "SetPoint", "TOPLEFT", state.scroll, "TOPRIGHT", 8, 0)
	Call(controller, state.slider, "SetPoint", "BOTTOMLEFT", state.scroll, "BOTTOMRIGHT", 8, 0)
	Call(controller, state.slider, "SetWidth", 14)
	Call(controller, state.slider, "SetOrientation", "VERTICAL")
	Call(controller, state.slider, "SetMinMaxValues", 0, 0)
	Call(controller, state.slider, "SetValueStep", 1)
	Call(controller, state.slider, "EnableMouseWheel", true)
	Background(state.slider, 0.16)
	local thumb = Call(controller, state.slider, "CreateTexture", nil, "OVERLAY")
	Call(controller, thumb, "SetSize", 14, 30)
	Call(controller, thumb, "SetColorTexture", 0.65, 0.65, 0.65, 1)
	Call(controller, state.slider, "SetThumbTexture", thumb)
	state.footer = Label(frame)
	Call(controller, state.footer, "SetPoint", "BOTTOMLEFT", 16, 10)
	local resize = Button(frame, "/", 20)
	Call(controller, resize, "SetPoint", "BOTTOMRIGHT", -4, 3)
	state.popup = New("Frame", frame)
	Call(controller, state.popup, "Hide")
	Call(controller, state.popup, "SetPoint", "TOPLEFT", state.category, "BOTTOMLEFT", 0, -2)
	Call(controller, state.popup, "SetWidth", 240)
	Call(controller, state.popup, "SetFrameStrata", "TOOLTIP")
	Call(controller, state.popup, "EnableMouse", true)
	Call(controller, state.popup, "EnableMouseWheel", true)
	Background(state.popup, 0.09)
	for index = 1, 10 do
		local row = Button(state.popup, "", 232)
		Call(controller, row, "SetPoint", "TOPLEFT", 4, -(index - 1) * 26 - 4)
		state.rows[index] = row
	end
	local function Script(region, event, callback)
		Call(controller, region, "SetScript", event, SafeCallback(controller, region, callback))
	end
	local function Popup()
		local categories = controller:GetCategories()
		state.popupOffset = math.max(0, math.min(math.max(0, #categories - 10), state.popupOffset))
		for index, row in ipairs(state.rows) do
			local category = categories[state.popupOffset + index]
			Call(controller, row, "SetShown", category ~= nil)
			row.category = category
			if category then
				Call(controller, row.Label, "SetText", LibChev.Text(category))
			end
		end
		Call(controller, state.popup, "SetHeight", math.min(10, #categories) * 26 + 8)
	end
	for _, row in ipairs(state.rows) do
		local ownedRow = row
		Script(row, "OnClick", function()
			Call(controller, state.popup, "Hide")
			controller:SetCategory(ownedRow.category)
		end)
	end
	Script(state.category, "OnClick", function()
		if Call(controller, state.popup, "IsShown") then
			Call(controller, state.popup, "Hide")
		else
			state.popupOffset = 0
			Popup()
			Call(controller, state.popup, "Show")
		end
	end)
	Script(state.popup, "OnMouseWheel", function(delta)
		delta = LibChev.Number(delta)
		if delta then
			state.popupOffset = state.popupOffset + (delta > 0 and -1 or 1)
			Popup()
		end
	end)
	Script(state.search, "OnTextChanged", function()
		if not state.syncText then
			local text = Call(controller, state.search, "GetText")
			if LibChev.CanAccess(text) and type(text) == "string" then
				controller:SetSearch(text)
			end
		end
	end)
	local function ClearSearchFocus()
		Call(controller, state.search, "ClearFocus")
	end
	Script(state.search, "OnEscapePressed", ClearSearchFocus)
	Script(state.search, "OnEnterPressed", ClearSearchFocus)
	Script(state.box, "OnTextChanged", function(userInput)
		if not state.syncText and LibChev.CanAccess(userInput) and userInput == true then
			state.syncText = true
			Call(controller, state.box, "SetText", state.text or "")
			Call(controller, state.box, "HighlightText")
			state.syncText = false
		end
	end)
	local function Wheel(delta)
		delta = LibChev.Number(delta)
		local current = LibChev.Number(Call(controller, state.scroll, "GetVerticalScroll"))
		if delta and current then
			SetScroll(controller, state, current - delta * 36, true)
		end
	end
	Script(state.scroll, "OnMouseWheel", Wheel)
	Script(state.slider, "OnMouseWheel", Wheel)
	Script(state.slider, "OnValueChanged", function(value)
		if not state.syncScroll then
			SetScroll(controller, state, value, true)
		end
	end)
	Script(state.scroll, "OnVerticalScroll", function(value)
		if not state.syncScroll then
			SetScroll(controller, state, value, true)
		end
	end)
	Script(state.buttons.select, "OnClick", function()
		Call(controller, state.box, "SetFocus")
		Call(controller, state.box, "HighlightText")
	end)
	Script(state.buttons.clear, "OnClick", function()
		controller:Clear()
	end)
	Script(state.buttons.reload, "OnClick", function()
		if type(controller.policy.reload) == "function" then
			controller.policy.reload()
		end
	end)
	Script(state.buttons.tests, "OnClick", function()
		controller:RunTests(false, true)
	end)
	Script(state.buttons.diagnostics, "OnClick", function()
		controller:ShowDiagnostics()
	end)
	Script(state.buttons.log, "OnClick", function()
		controller:ShowLog()
	end)
	local function Close()
		Call(controller, frame, "Hide")
	end
	Script(close, "OnClick", Close)
	Script(state.box, "OnEscapePressed", Close)
	Script(drag, "OnDragStart", function()
		Call(controller, frame, "StartMoving")
	end)
	Script(drag, "OnDragStop", function()
		Call(controller, frame, "StopMovingOrSizing")
	end)
	Script(resize, "OnMouseDown", function(button)
		if LibChev.CanAccess(button) and button == "LeftButton" then
			Call(controller, frame, "StartSizing", "BOTTOMRIGHT")
		end
	end)
	Script(resize, "OnMouseUp", function()
		Call(controller, frame, "StopMovingOrSizing")
	end)
	Script(frame, "OnHide", function()
		Call(controller, frame, "StopMovingOrSizing")
		Call(controller, state.box, "ClearFocus")
		Call(controller, state.search, "ClearFocus")
		Call(controller, state.popup, "Hide")
	end)
	Script(frame, "OnSizeChanged", function()
		if not state.refreshing then
			controller:Refresh()
		end
	end)
	frame.TextBox, frame.Scroll, frame.Search, frame.Category = state.box, state.scroll, state.search, state.category
	frame.Buttons, frame.Slider, frame.Popup = state.buttons, state.slider, state.popup
	frame.Close, frame.Drag, frame.Resize = close, drag, resize
	controller.window, controller._debugWindowState = frame, state
	if controller.policy.onWindow then
		controller.policy.onWindow(frame)
	end
	return state
end

local function Refresh(controller, state)
	state.refreshing = true
	local report = controller.mode == "report"
	local category, search = controller:GetCategory(), controller:GetSearch()
	local text = report and controller.reportText or controller:GetText(category, search)
	text = LibChev.Text(text, "")
	local title = LibChev.Text(report and controller.reportTitle or controller.title, "Debug")
	if not report then
		local shown, chars, total = controller:GetMetrics(category, search)
		title = title .. string.format(" [%s] (%d/%d lines, %d chars)", LibChev.Text(category), shown, total, chars)
	end
	Call(controller, state.title, "SetText", title)
	Call(controller, state.buttons.reload, "SetShown", type(controller.policy.reload) == "function")
	Call(controller, state.buttons.clear, "SetShown", not report)
	Call(controller, state.category, "SetShown", not report)
	Call(controller, state.search, "SetShown", not report)
	Call(controller, state.searchLabel, "SetShown", not report)
	Call(controller, state.category.Label, "SetText", "Category: " .. LibChev.Text(category) .. " v")
	Call(
		controller,
		state.hint,
		"SetText",
		report and "Select All, then Ctrl+C to copy this report. Log returns to event history."
			or 'Search is fuzzy; use "quotes" for an exact phrase. Scroll categories with the mouse wheel.'
	)
	if report then
		Call(controller, state.popup, "Hide")
	end
	state.syncText = true
	if Call(controller, state.search, "GetText") ~= search then
		Call(controller, state.search, "SetText", search)
	end
	local previous = LibChev.Number(Call(controller, state.scroll, "GetVerticalScroll")) or 0
	local width = LibChev.Number(Call(controller, state.scroll, "GetWidth"))
	local viewport = LibChev.Number(Call(controller, state.scroll, "GetHeight"))
	if not width or not viewport then
		error("debug window size unavailable", 0)
	end
	Call(controller, state.box, "SetWidth", math.max(1, width))
	Call(controller, state.measure, "SetWidth", math.max(1, width - 8))
	Call(controller, state.measure, "SetText", text)
	local height = LibChev.Number(Call(controller, state.measure, "GetStringHeight"))
	if not height then
		error("debug window text height unavailable", 0)
	end
	state.text = text
	Call(controller, state.box, "SetText", text)
	Call(controller, state.box, "SetHeight", math.max(1, viewport, height + 16))
	state.syncText = false
	local maximum = LibChev.Number(Call(controller, state.scroll, "GetVerticalScrollRange")) or 0
	local tail = not report and (controller.forceTail == true or controller.tailPinned == true)
	local target = tail and maximum or previous
	if report and (state.mode ~= "report" or state.reportText ~= text or state.opening) then
		target = 0
	end
	SetScroll(controller, state, target, false)
	if not report then
		controller.tailPinned = tail
	end
	controller.forceTail = false
	state.mode, state.reportText, state.opening = controller.mode, report and text or nil, false
	Call(
		controller,
		state.footer,
		"SetText",
		report and "Report" or (tail and "Following newest events" or "Scroll to the bottom to follow new events")
	)
	state.refreshing = false
	return true
end

function LibChev.RefreshDebugWindow(controller)
	local state = controller._debugWindowState
	if not state or state.refreshing then
		return false
	end
	if not state.opening then
		local readable, shown = pcall(Call, controller, state.frame, "IsShown")
		if not readable or not LibChev.CanAccess(shown) or shown ~= true then
			return false
		end
	end
	local ok, result = pcall(Refresh, controller, state)
	state.refreshing, state.syncText, state.syncScroll, state.opening = false, false, false, false
	return ok and result == true
end

function LibChev.OpenDebugWindow(controller)
	local ok, result = pcall(function()
		if not Allowed(controller) then
			return false
		end
		local state = controller._debugWindowState or Create(controller)
		state.opening = true
		if not LibChev.RefreshDebugWindow(controller) then
			return false
		end
		Call(controller, state.frame, "Show")
		Call(controller, state.frame, "Raise")
		if controller.mode == "report" then
			Call(controller, state.box, "SetFocus")
			Call(controller, state.box, "HighlightText")
		end
		return true
	end)
	return ok and result == true
end
