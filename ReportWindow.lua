-- SPDX-License-Identifier: MIT
local _, namespace = ...
local Together = assert(namespace.Together, "Load LibTogether.lua first")

-- UI policy is injected by the owning addon. This module has no frame access
-- until explicitly opened, and stores references only on frames it creates.
-- policy: restricted(), canMutate(frame), createFrame(...), parent, title.
function Together.OpenReportWindow(owner, text, policy)
	if policy.restricted() or not Together.CanAccess(text) or type(text) ~= "string" then
		return false
	end
	local frame = owner.diagnosticsWindow
	if not frame then
		frame = policy.createFrame("Frame", nil, policy.parent)
		frame:SetSize(660, 460)
		frame:SetPoint("CENTER")
		frame:SetFrameStrata("DIALOG")
		frame:SetClampedToScreen(true)
		frame:EnableMouse(true)
		frame:Hide()
		local background = frame:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints()
		background:SetColorTexture(0.04, 0.04, 0.04, 0.97)
		local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", 20, -18)
		title:SetText(Together.Text(policy.title))
		local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
		hint:SetText("Report selected: press Ctrl+C to copy. Use the mouse wheel to scroll.")
		local scroll = policy.createFrame("ScrollFrame", nil, frame)
		scroll:SetPoint("TOPLEFT", 20, -72)
		scroll:SetPoint("BOTTOMRIGHT", -20, 54)
		scroll:EnableMouseWheel(true)
		local box = policy.createFrame("EditBox", nil, scroll)
		box:SetWidth(600)
		box:SetHeight(1)
		box:SetMultiLine(true)
		box:SetAutoFocus(false)
		box:SetFontObject("ChatFontNormal")
		box:SetTextInsets(4, 4, 4, 4)
		scroll:SetScrollChild(box)
		local measure = frame:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
		measure:SetWidth(592)
		measure:Hide()
		frame.TextBox, frame.Scroll, frame.Measure = box, scroll, measure
		scroll:SetScript("OnMouseWheel", function(_, delta)
			if not policy.canMutate(scroll) then
				return
			end
			local amount = Together.Number(delta)
			local current, maximum =
				Together.Number(scroll:GetVerticalScroll()), Together.Number(scroll:GetVerticalScrollRange())
			if amount and current and maximum then
				scroll:SetVerticalScroll(math.max(0, math.min(maximum, current - amount * 36)))
			end
		end)
		box:SetScript("OnTextChanged", function(self, userInput)
			if Together.CanAccess(userInput) and userInput and policy.canMutate(self) then
				self:SetText(frame.reportText or "")
				self:HighlightText()
			end
		end)
		box:SetScript("OnEditFocusGained", function(self)
			if policy.canMutate(self) then
				self:HighlightText()
			end
		end)
		local function Close()
			if policy.canMutate(frame) then
				frame:Hide()
			end
		end
		box:SetScript("OnEscapePressed", Close)
		frame:SetScript("OnHide", function()
			if policy.canMutate(box) then
				box:ClearFocus()
			end
		end)
		local close = policy.createFrame("Button", nil, frame, "UIPanelButtonTemplate")
		close:SetSize(100, 24)
		close:SetPoint("BOTTOMRIGHT", -20, 16)
		close:SetText("Close")
		close:SetScript("OnClick", Close)
		local selectAll = policy.createFrame("Button", nil, frame, "UIPanelButtonTemplate")
		selectAll:SetSize(120, 24)
		selectAll:SetPoint("BOTTOMLEFT", 20, 16)
		selectAll:SetText("Select Report")
		selectAll:SetScript("OnClick", function()
			if policy.canMutate(box) then
				box:SetFocus()
				box:HighlightText()
			end
		end)
		owner.diagnosticsWindow = frame
	end
	if
		not policy.canMutate(frame)
		or not policy.canMutate(frame.TextBox)
		or not policy.canMutate(frame.Scroll)
		or not policy.canMutate(frame.Measure)
	then
		return false
	end
	frame.reportText = text:sub(1, 32768)
	frame.TextBox:SetText(frame.reportText)
	frame.Measure:SetText(frame.reportText)
	local height = Together.Number(frame.Measure:GetStringHeight())
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
