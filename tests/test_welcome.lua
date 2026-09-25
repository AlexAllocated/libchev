-- Offline only: all callbacks and library instances belong to these fixtures.
local Test, Equal, Load = ...
local function Fixture(overrides)
	local lib = Load(overrides)
	local state = { messages = {}, opened = {}, registrations = 0 }
	local policy = {
		addonName = "Fixture",
		linkType = "fixturefeedback",
		command = "/fixture",
		clients = "Retail, Forever and Classic",
		curseforgeURL = "https://www.curseforge.com/wow/addons/fixture",
		githubURL = "https://github.com/owner/fixture",
		getVersion = function()
			return "2.3.4"
		end,
		print = function(text)
			state.messages[#state.messages + 1] = text
		end,
		registerLink = function(kind, callback)
			Equal(kind, "fixturefeedback")
			state.registrations = state.registrations + 1
			state.callback = callback
			return true
		end,
		ui = {},
	}
	lib.OpenReportWindow = function(_, url, ui)
		Equal(ui.copyLink, true)
		Equal(ui.title, "Fixture Feedback")
		state.opened[#state.opened + 1] = url
		return true
	end
	return lib, state, policy
end
Test("welcome announces once per instance and routes only its fixed feedback URLs", function()
	local lib, s, p = Fixture()
	local a = lib.NewWelcomeController(p)
	Equal(a:Announce(), true)
	Equal(a:Announce(), false)
	Equal(s.registrations, 1)
	Equal(#s.messages, 1)
	assert(
		s.messages[1]:find(
			"v2.3.4 loaded! Now supports Retail, Forever and Classic. Type /fixture for settings.",
			1,
			true
		)
	)
	assert(s.messages[1]:find("|Hfixturefeedback:curseforge|h[CurseForge]|h", 1, true))
	assert(s.messages[1]:find("|Hfixturefeedback:github|h[GitHub]|h", 1, true))
	Equal(s.callback("fixturefeedback:curseforge"), nil)
	Equal(s.callback("fixturefeedback:github"), nil)
	Equal(s.opened[1], p.curseforgeURL)
	Equal(s.opened[2], p.githubURL)
	for _, link in ipairs({
		"otherfeedback:github",
		"fixturefeedback:https://untrusted.invalid",
		"fixturefeedback:github:extra",
		{},
	}) do
		Equal(a:HandleLink(link), false)
	end
	Equal(#s.opened, 2)
	local b = lib.NewWelcomeController(p)
	Equal(b:Announce(), true)
	Equal(#s.messages, 2)
end)
Test("welcome falls back to plain URLs when registration is missing failed or occupied", function()
	for _, register in ipairs({
		false,
		function()
			return false
		end,
		function()
			error("unavailable")
		end,
	}) do
		local lib, s, p = Fixture()
		p.registerLink = register
		assert(lib.NewWelcomeController(p):Announce())
		assert(s.messages[1]:find(p.curseforgeURL, 1, true))
		assert(s.messages[1]:find(p.githubURL, 1, true))
		assert(not s.messages[1]:find("|H", 1, true))
	end
end)
Test("welcome rejects secret inaccessible or foreign links before interpreting them", function()
	local foreign = setmetatable({}, {
		__tostring = function()
			error("foreign coercion")
		end,
		__index = function()
			error("foreign read")
		end,
	})
	local lib, s, p = Fixture({
		canaccessvalue = function(v)
			return v ~= "fixturefeedback:github"
		end,
	})
	local a = lib.NewWelcomeController(p)
	Equal(a:HandleLink("fixturefeedback:github"), false)
	Equal(a:HandleLink(foreign), false)
	Equal(a:HandleLink(nil), false)
	Equal(#s.opened, 0)
end)
Test("welcome leaves a copyable URL in chat when UI is blocked or fails", function()
	for _, open in ipairs({
		function()
			return false
		end,
		function()
			error("blocked")
		end,
	}) do
		local lib, s, p = Fixture()
		lib.OpenReportWindow = open
		local a = lib.NewWelcomeController(p)
		Equal(a:HandleLink("fixturefeedback:github"), true)
		Equal(s.messages[1], "Feedback: " .. p.githubURL)
	end
end)
Test("welcome sanitizes metadata and can retry a failed chat write without duplicate registration", function()
	local lib, s, p = Fixture()
	p.getVersion = function()
		return "1|Hbad|h"
	end
	local write = p.print
	p.print = function()
		error("chat unavailable")
	end
	local a = lib.NewWelcomeController(p)
	Equal(a:Announce(), false)
	p.print = write
	Equal(a:Announce(), true)
	Equal(s.registrations, 1)
	assert(s.messages[1]:find("v1||Hbad||h loaded!", 1, true))
end)
