-- SPDX-License-Identifier: MIT
local _, namespace = ...
local LibChev = assert(namespace.LibChev, "Load libchev.lua first")

-- UI policy is injected by the owning addon. This module has no frame access
-- until explicitly opened, and stores references only on frames it creates.
-- policy: restricted(), canMutate(frame), createFrame(...), parent, title.
function LibChev.OpenReportWindow(owner, text, policy)
	local function Allowed()
		local ok, restricted = pcall(policy.restricted)
		return ok and LibChev.CanAccess(restricted) and restricted == false
	end
	if not Allowed() or not LibChev.CanAccess(text) or type(text) ~= "string" then
		return false
	end
	local function CanMutate(region)
		if not Allowed() then
			return false
		end
		local success, allowed = pcall(policy.canMutate, region)
		return success and LibChev.CanAccess(allowed) and allowed == true
	end
	local frame = owner.diagnosticsWindow
	if not frame then
		frame = policy.createFrame("Frame", nil, policy.parent)
		if not CanMutate(frame) then
			return false
		end
		frame:SetSize(660, 460)
		frame:SetPoint("CENTER")
		frame:SetFrameStrata("DIALOG")
		frame:SetClampedToScreen(true)
		frame:EnableMouse(true)
		frame:Hide()
		local background = frame:CreateTexture(nil, "BACKGROUND")
		if not CanMutate(background) then
			return false
		end
		background:SetAllPoints()
		background:SetColorTexture(0.04, 0.04, 0.04, 0.97)
		local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		if not CanMutate(title) then
			return false
		end
		title:SetPoint("TOPLEFT", 20, -18)
		title:SetText(LibChev.Text(policy.title))
		local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		if not CanMutate(hint) then
			return false
		end
		hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
		hint:SetText("Report selected: press Ctrl+C to copy. Use the mouse wheel to scroll.")
		local scroll = policy.createFrame("ScrollFrame", nil, frame)
		if not CanMutate(scroll) then
			return false
		end
		scroll:SetPoint("TOPLEFT", 20, -72)
		scroll:SetPoint("BOTTOMRIGHT", -20, 54)
		scroll:EnableMouseWheel(true)
		local box = policy.createFrame("EditBox", nil, scroll)
		if not CanMutate(box) then
			return false
		end
		box:SetWidth(600)
		box:SetHeight(1)
		box:SetMultiLine(true)
		box:SetAutoFocus(false)
		box:SetFontObject("ChatFontNormal")
		box:SetTextInsets(4, 4, 4, 4)
		scroll:SetScrollChild(box)
		local measure = frame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
		if not CanMutate(measure) then
			return false
		end
		measure:SetWidth(592)
		measure:Hide()
		frame.TextBox, frame.Scroll, frame.Measure = box, scroll, measure
		scroll:SetScript("OnMouseWheel", function(_, delta)
			if not CanMutate(scroll) then
				return
			end
			local amount = LibChev.Number(delta)
			local current, maximum =
				LibChev.Number(scroll:GetVerticalScroll()), LibChev.Number(scroll:GetVerticalScrollRange())
			if amount and current and maximum then
				scroll:SetVerticalScroll(math.max(0, math.min(maximum, current - amount * 36)))
			end
		end)
		box:SetScript("OnTextChanged", function(self, userInput)
			if LibChev.CanAccess(userInput) and userInput and CanMutate(self) then
				self:SetText(frame.reportText or "")
				self:HighlightText()
			end
		end)
		box:SetScript("OnEditFocusGained", function(self)
			if CanMutate(self) then
				self:HighlightText()
			end
		end)
		local function Close()
			if CanMutate(frame) then
				frame:Hide()
			end
		end
		box:SetScript("OnEscapePressed", Close)
		frame:SetScript("OnHide", function()
			if CanMutate(box) then
				box:ClearFocus()
			end
		end)
		local close = policy.createFrame("Button", nil, frame, "UIPanelButtonTemplate")
		if not CanMutate(close) then
			return false
		end
		close:SetSize(100, 24)
		close:SetPoint("BOTTOMRIGHT", -20, 16)
		close:SetText("Close")
		close:SetScript("OnClick", Close)
		local selectAll = policy.createFrame("Button", nil, frame, "UIPanelButtonTemplate")
		if not CanMutate(selectAll) then
			return false
		end
		selectAll:SetSize(120, 24)
		selectAll:SetPoint("BOTTOMLEFT", 20, 16)
		selectAll:SetText("Select Report")
		selectAll:SetScript("OnClick", function()
			if CanMutate(box) then
				box:SetFocus()
				box:HighlightText()
			end
		end)
		owner.diagnosticsWindow = frame
	end
	if
		not CanMutate(frame)
		or not CanMutate(frame.TextBox)
		or not CanMutate(frame.Scroll)
		or not CanMutate(frame.Measure)
	then
		return false
	end
	frame.reportText = text:sub(1, 32768)
	frame.TextBox:SetText(frame.reportText)
	frame.Measure:SetText(frame.reportText)
	local height = LibChev.Number(frame.Measure:GetStringHeight())
	if not height then
		return false
	end
	frame.TextBox:SetHeight(math.max(1, height + 16))
	frame:Show()
	frame.TextBox:SetFocus()
	frame.TextBox:HighlightText()
	frame.Scroll:SetVerticalScroll(0)
	return true
end
