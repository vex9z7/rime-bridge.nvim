-- Actual Rime worker and Minuet virtual text; only AI network IO is stubbed.
vim.opt.runtimepath:prepend(assert(vim.env.RIME_BRIDGE_SOURCE, "source required"))
vim.opt.runtimepath:prepend(assert(vim.env.RIME_TEST_MINUET, "Minuet checkout required"))
local plugin = require("rime_bridge")
local adapter = require("rime_bridge.minuet")
local config = vim.deepcopy(require("minuet.config"))
local requests = {}
config.notify = false
config.provider = "rime_test"
config.virtualtext.auto_trigger_ft = {}
config.virtualtext.keymap = {}
local predicate_calls = 0
config.enable_predicates = {
	function()
		predicate_calls = predicate_calls + 1
		return true
	end,
}
config.presets = { other = { enable_predicates = {
	function()
		return true
	end,
} } }
package.loaded.minuet = { config = adapter.options(config) }
assert(#config.presets.other.enable_predicates == 1, "adapter mutated original preset")
assert(#config.enable_predicates == 1, "adapter mutated original options")
package.loaded["minuet.backends.rime_test"] = {
	complete = function(_, done, partial)
		requests[#requests + 1] = { done = done, partial = partial }
	end,
}
local vt = require("minuet.virtualtext")
vt.setup()
local user = vim.fn.tempname()
vim.fn.mkdir(user, "p")
for _, name in ipairs({ "default.custom.yaml", "input_fixture.schema.yaml", "input_fixture.dict.yaml" }) do
	vim.fn.writefile(vim.fn.readfile(vim.env.RIME_BRIDGE_SOURCE .. "/tests/fixtures/" .. name), user .. "/" .. name)
end
vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.tempname() .. ".txt"))
plugin.setup({
	worker = assert(vim.env.RIME_BRIDGE_WORKER, "worker required"),
	user_dir = user,
	schema = "input_fixture",
})
plugin.deploy()
local job
local steps = {
	function()
		assert(not plugin.status().error, plugin.status().error)
		if plugin.status().phase ~= "initialized" then
			return false
		end
		vim.api.nvim_input("i")
	end,
	function()
		assert(vim.fn.mode() == "i", "real input did not enter Insert mode")
		vt.action.next()
		assert(#requests == 1, "initial AI request missing")
		requests[1].partial({ "AI_BEFORE_RIME" })
		assert(vt.action.is_visible())
		plugin.enable()
		assert(not adapter.allowed() and not vt.action.is_visible(), "enable did not dismiss AI immediately")
		local preset = package.loaded.minuet.config.presets.other
		assert(not preset.enable_predicates[2](), "preset bypassed isolation")
		requests[1].done({ "LATE_AI" })
		assert(not vt.action.has_suggestion(), "old request survived enable")
	end,
	function()
		assert(not plugin.status().error, plugin.status().error)
		local s = plugin._input()
		if not s or not s.ready then
			return false
		end
		job = s.client.job
		vt.action.next()
		assert(#requests == 1, "manual AI request allowed during Rime")
		vim.api.nvim_input("nihao")
	end,
	function()
		assert(vim.api.nvim_get_current_line() == "", "preedit leaked into text")
		assert(plugin._input().context.preedit ~= "", "Rime preedit missing")
		assert(not vt.action.is_visible(), "AI preview escaped isolation")
		vim.api.nvim_input(" ")
	end,
	function()
		assert(vim.api.nvim_get_current_line() == "你好", "Rime commit failed")
		vt.action.next()
		assert(#requests == 1, "AI escaped isolation between compositions")
		plugin.disable()
		assert(adapter.allowed())
		requests[1].partial({ "STALE_AFTER_DISABLE" })
		assert(not vt.action.has_suggestion(), "old AI resurrected after disable")
		vt.action.next()
		assert(#requests == 2, "AI request did not resume")
		requests[2].done({ " world" })
		assert(vt.action.is_visible())
		vt.action.accept()
	end,
	function()
		assert(vim.api.nvim_get_current_line() == "你好 world", "AI did not resume")
		assert(predicate_calls > 0, "existing predicate lost")
		vim.api.nvim_input("<Esc>")
		plugin.stop()
	end,
}
local index, ticks = 0, 0
local function run()
	local ok, err = xpcall(function()
		ticks = ticks + 1
		assert(ticks < 150, "integration timeout")
		if steps[index + 1]() ~= false then
			index = index + 1
		end
	end, debug.traceback)
	if not ok then
		plugin.stop()
		print(err)
		vim.cmd("cquit 1")
	elseif index == #steps then
		assert(vim.fn.jobwait({ job }, 3000)[1] ~= -1, "worker did not exit")
		vim.fn.delete(user, "rf")
		print("PASS: real Rime + Minuet keys, pending/visible AI isolation, stale callbacks and AI recovery")
		vim.cmd("qa!")
	else
		vim.defer_fn(run, 100)
	end
end
vim.defer_fn(run, 100)
