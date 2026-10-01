-- Actual Blink + actual worker: delayed foreign sources, execute and stale items.
vim.opt.runtimepath:prepend(vim.env.RIME_BRIDGE_SOURCE)
vim.opt.runtimepath:prepend(vim.env.RIME_TEST_BLINK)
local bridge, adapter = require("rime_bridge"), require("rime_bridge.blink")
local cmp = require("blink.cmp")
local foreign_calls, foreign_delivered = 0, 0
package.preload["rime_test_delayed"] = function()
	return {
		new = function()
			return {
				get_completions = function(_, ctx, callback)
					foreign_calls = foreign_calls + 1
					vim.defer_fn(function()
						foreign_delivered = foreign_delivered + 1
						callback({
							items = {
								{
									label = "FOREIGN",
									insertText = "UNWANTED",
									filterText = ctx.get_keyword(),
									kind = 15,
								},
							},
							is_incomplete_forward = true,
							is_incomplete_backward = true,
						})
					end, 800)
				end,
			}
		end,
	}
end
local opts = adapter.options({
	fuzzy = { implementation = "lua" },
	sources = { default = { "foreign" }, providers = { foreign = { name = "Foreign", module = "rime_test_delayed" } } },
	completion = { list = { selection = { auto_insert = true } }, ghost_text = { enabled = true } },
})
cmp.setup(opts)
local user = vim.fn.tempname()
vim.fn.mkdir(user, "p")
for _, name in ipairs({ "default.custom.yaml", "input_fixture.schema.yaml", "input_fixture.dict.yaml" }) do
	vim.fn.writefile(vim.fn.readfile(vim.env.RIME_BRIDGE_SOURCE .. "/tests/fixtures/" .. name), user .. "/" .. name)
end
vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.tempname() .. ".txt"))
bridge.setup({ worker = vim.env.RIME_BRIDGE_WORKER, user_dir = user, schema = "input_fixture", ui = "blink" })
bridge.deploy()
local function line()
	return vim.api.nvim_get_current_line()
end
local function key(k)
	vim.api.nvim_input(k)
end
local paused, s, stale, expected
local steps = {
	function()
		if bridge.status().phase ~= "initialized" then
			return false
		end
		key("i")
	end,
	function()
		key("prefix")
	end,
	function()
		cmp.show({ providers = { "foreign" } })
	end,
	function()
		assert(foreign_calls > 0, "foreign source did not run")
		bridge.enable()
	end,
	function()
		s = bridge._input()
		if not s then
			return false
		end
		key("nihao")
	end,
	function()
		if s.pending > 0 or not cmp.is_menu_visible() then
			return false
		end
		assert(line() == "prefix", "preview/foreign source changed prefix")
		assert(not cmp.is_ghost_text_visible(), "ghost text leaked")
		local items = cmp.get_items()
		assert(#items == #s.context.candidates, "prefix fuzzy-filtered Rime candidates")
		for i, item in ipairs(items) do
			assert(item.source_id == "rime_bridge" and item.label == s.context.candidates[i].text, "foreign/order leak")
		end
		stale = vim.deepcopy(items[1])
		expected = "prefix" .. s.context.candidates[2].text
		paused = vim.fn.jobpid(s.client.job)
		assert(vim.uv.kill(paused, "sigstop") == 0, "pause failed")
		cmp.accept({ index = 2 }) -- Exercise Blink source.execute, not the custom key guard.
	end,
	function()
		if foreign_delivered == 0 then
			return false
		end
		assert(line() == "prefix", "Blink inserted a label without engine commit")
		assert(s.pending > 0, "Blink execute did not request engine selection")
		vim.uv.kill(paused, "sigcont")
		paused = nil
	end,
	function()
		if s.pending > 0 then
			return false
		end
		assert(line() == expected, "engine-selected commit missing/duplicated")
		key("nihao")
	end,
	function()
		if s.pending > 0 then
			return false
		end
		local callbacks = 0
		adapter.new():execute(nil, stale, function()
			callbacks = callbacks + 1
		end)
		assert(callbacks == 1 and line() == expected and s.pending == 0, "stale item was accepted")
		key("<Esc>")
	end,
	function()
		bridge.disable()
		key("A")
	end,
	function()
		assert(not adapter.active(), "Rime isolation did not turn off")
		assert(opts.completion.list.selection.auto_insert() == true, "normal auto-insert not restored")
		cmp.show({ providers = { "foreign" } })
	end,
	function()
		if not cmp.is_menu_visible() or #cmp.get_items() == 0 then
			return false
		end
		assert(cmp.get_items()[1].source_id == "foreign", "ordinary completions not restored")
		bridge.stop()
	end,
}
local index, ticks = 0, 0
local function run()
	local ok, err = pcall(function()
		ticks = ticks + 1
		assert(ticks < 150, "Blink isolation test timeout: " .. vim.inspect(bridge.status()))
		assert(not bridge.status().error, vim.inspect(bridge.status()))
		index = index + 1
		if steps[index] and steps[index]() == false then
			index = index - 1
		end
	end)
	if not ok then
		if paused then
			vim.uv.kill(paused, "sigcont")
		end
		bridge.stop()
		print(err)
		vim.cmd("cquit 1")
	elseif index > #steps then
		vim.defer_fn(function()
			vim.fn.delete(user, "rf")
			print(
				"PASS: real Blink isolation, prefix/order, engine-only execute, stale rejection and ordinary completion restoration"
			)
			vim.cmd("qa!")
		end, 2200)
	else
		vim.defer_fn(run, 200)
	end
end
vim.defer_fn(run, 200)
