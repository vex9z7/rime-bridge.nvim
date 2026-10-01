-- Isolated ordinary-file-buffer regression. All composing uses nvim_input.
vim.opt.runtimepath:prepend(assert(vim.env.RIME_BRIDGE_SOURCE, "source required"))
local blink
if vim.env.RIME_TEST_BLINK then
	vim.opt.runtimepath:prepend(vim.env.RIME_TEST_BLINK)
	blink = require("blink.cmp")
	package.preload["rime_test_foreign"] = function()
		return {
			new = function()
				return {
					get_completions = function(_, _, callback)
						vim.defer_fn(function()
							callback({
								items = { { label = "FOREIGN", kind = 15, insertText = "UNWANTED" } },
								is_incomplete_forward = true,
								is_incomplete_backward = true,
							})
						end, 500)
					end,
				}
			end,
		}
	end
	blink.setup(require("rime_bridge.blink").options({
		fuzzy = { implementation = "lua" },
		keymap = {
			preset = vim.env.RIME_TEST_BLINK_PRESET or "default",
			["<C-y>"] = {
				function()
					assert(not require("rime_bridge.blink").active(), "foreign accept hook ran during Rime")
				end,
				"select_and_accept",
				"fallback",
			},
		},
		sources = {
			default = { "foreign" },
			providers = { foreign = { name = "Foreign", module = "rime_test_foreign" } },
		},
		completion = { list = { selection = { auto_insert = true } }, ghost_text = { enabled = true } },
	}))
end
local plugin = require("rime_bridge")
local user = vim.env.RIME_TEST_USER_DIR or vim.fn.tempname()
if not vim.env.RIME_TEST_USER_DIR then
	vim.fn.mkdir(user, "p")
	for _, name in ipairs({ "default.custom.yaml", "input_fixture.schema.yaml", "input_fixture.dict.yaml" }) do
		vim.fn.writefile(vim.fn.readfile(vim.env.RIME_BRIDGE_SOURCE .. "/tests/fixtures/" .. name), user .. "/" .. name)
	end
end
local file = vim.fn.tempname() .. ".txt"
vim.o.hidden = true
vim.cmd("edit " .. vim.fn.fnameescape(file))
assert(vim.bo.buftype == "", "must be an ordinary file buffer")
local buf = vim.api.nvim_get_current_buf()
-- Verify a user buffer mapping is restored, including a Lua callback.
local original = function()
	return "ORIGINAL"
end
vim.keymap.set("i", "q", original, { buffer = buf, expr = true })
plugin.setup({
	ui = blink and "blink" or "native",
	worker = assert(vim.env.RIME_BRIDGE_WORKER, "worker required"),
	user_dir = user,
	schema = vim.env.RIME_TEST_SCHEMA or "input_fixture",
})
plugin.deploy()
vim.keymap.set({ "i", "n" }, "<F6>", plugin.toggle)
local s
local function key(k)
	vim.api.nvim_input(k)
end
local function line()
	return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
end
local function visible()
	return blink and blink.is_menu_visible() or s.popup ~= nil
end
local expected, page, before, other, paused_pid
local timeout_wait = 0
local steps = {
	function()
		assert(s.ready, s.error or "not ready")
		key("i")
	end,
	function()
		key("nihao")
	end,
	function()
		assert(line() == "", line())
		assert(s.context.preedit ~= "" and visible(), "no visible composition")
		if blink then
			local items = blink.get_items()
			assert(#items == #s.context.candidates, "Blink filtered candidates")
			for i, item in ipairs(items) do
				assert(
					item.source_id == "rime_bridge" and item.label == s.context.candidates[i].text,
					"Blink order/isolation mismatch"
				)
			end
			assert(not blink.is_ghost_text_visible(), "ghost text leaked")
		end
		key(blink and "<C-y>" or " ")
	end,
	function()
		assert(line() == "你好", line())
		key("nihao nihao")
	end,
	function()
		assert(line() == "你好你好", line())
		assert(
			s.context.preedit ~= "",
			vim.inspect({
				context = s.context,
				generation = s.generation,
				pending = s.pending,
				error = s.error,
				line = line(),
				mode = vim.api.nvim_get_mode(),
			})
		)
		key("<Esc>")
	end,
	function()
		assert(s.context.preedit == "", "cancel failed")
		assert(line() == "你好你好", line())
		key("u")
	end,
	function()
		assert(line() ~= "你好你好", "undo had no effect")
		key("<C-r>")
	end,
	function()
		assert(line() == "你好你好", "redo failed")
		key("A")
	end,
	function()
		key("nihao<BS>")
	end,
	function()
		assert(
			s.context.preedit ~= "",
			vim.inspect({
				context = s.context,
				generation = s.generation,
				pending = s.pending,
				error = s.error,
				line = line(),
				mode = vim.api.nvim_get_mode(),
			})
		)
		key("<Esc>")
	end,
	function()
		key("A")
	end,
	function()
		key("nihao")
	end,
	function()
		expected = line() .. s.context.candidates[2].text
		key("2")
	end,
	function()
		assert(line() == expected, "digit selection failed")
		key("nihao")
	end,
	function()
		page = s.context.page
		key("=")
	end,
	function()
		assert(s.context.page > page, "next page failed")
		key("-")
	end,
	function()
		assert(s.context.page == page, "previous page failed")
		key("<C-n>")
	end,
	function()
		expected = line() .. s.context.candidates[s.context.selected + 1].text
		key("<CR>")
	end,
	function()
		assert(line() == expected, "Enter must commit selected candidate: " .. vim.inspect({
			line = line(),
			expected = expected,
			ctx = s.context,
			selected = blink and blink.get_selected_item(),
		}))
		key("<F6>")
	end,
	function()
		key("abc")
	end,
	function()
		assert(line() == expected .. "abc", "disabled fallback failed")
		assert(vim.fn.maparg("q", "i", false, true).callback == original, "original mapping not restored")
		key("<F6>")
	end,
	function()
		assert(not plugin.status().error, vim.inspect(plugin.status()))
		if not plugin._input() then
			return false
		end
		s = plugin._input()
		before = line()
		assert(vim.uv.kill(vim.fn.jobpid(s.client.job), "sigstop") == 0, "cannot pause child")
		key("nihao")
	end,
	function()
		key("<Esc>")
	end,
	function()
		assert(vim.uv.kill(vim.fn.jobpid(s.client.job), "sigcont") == 0, "cannot resume child")
	end,
	function()
		assert(line() == before and not visible(), "delayed response leaked after cancel")
		key("A")
	end,
	function()
		key("nihao")
	end,
	function()
		assert(s.context.preedit ~= "", "new generation did not recover")
		key("<Left>")
	end,
	function()
		assert(s.context.preedit == "" and not visible(), "cursor movement did not cancel")
		key("<End>nihao")
	end,
	function()
		assert(s.context.preedit ~= "", "composition before paste missing")
		vim.api.nvim_paste("PASTE", false, -1)
	end,
	function()
		assert(s.context.preedit == "" and line() == before .. "PASTE", "paste/cancel failed")
		before = line()
		key("nihao")
	end,
	function()
		vim.cmd("enew")
		other = vim.api.nvim_get_current_buf()
	end,
	function()
		assert(s.context.preedit == "" and not visible(), "buffer switch did not cancel")
		assert(vim.api.nvim_buf_get_lines(other, 0, 1, false)[1] == "", "text leaked to another buffer")
		assert(line() == before, "text leaked into original buffer")
		vim.api.nvim_set_current_buf(buf)
		key("<Esc>A")
	end,
	function()
		paused_pid = vim.fn.jobpid(s.client.job)
		assert(vim.uv.kill(paused_pid, "sigstop") == 0, "cannot stop for timeout")
		key("nihao")
	end,
	function()
		timeout_wait = timeout_wait + 1
		assert(timeout_wait < 40, "worker timeout did not fire")
		if not s.error then
			return false
		end
		assert(s.error:find("timeout"), "expected timeout error")
		vim.uv.kill(paused_pid, "sigcont")
		paused_pid = nil
		assert(not visible() and line() == before, "timeout leaked UI/text")
	end,
	function()
		plugin.enable()
	end,
	function()
		local attached = plugin._input()
		if not attached then
			return false
		end
		s = attached
		key("nihao")
	end,
	function()
		assert(s.context.preedit ~= "", "restart failed")
		vim.fn.jobstop(s.client.job)
	end,
	function()
		assert(s.error and not s.ready and not visible(), "worker failure not isolated")
		key("z")
	end,
	function()
		assert(line() == before .. "z", "normal editing not restored")
		key("q")
	end,
	function()
		assert(line() == before .. "zORIGINAL", "restored mapping did not execute")
		s.close()
		assert(vim.fn.maparg("q", "i", false, true).callback == original, "maps leaked after fault")
		plugin.stop()
	end,
}
local index, startup, total = 0, 0, 0
local requested = false
local function run()
	local ok, err = pcall(function()
		total = total + 1
		assert(total < 240, "test overall timeout")
		if not s and index == 0 then
			local state = plugin.status()
			assert(not state.error, state.error)
			if state.phase == "initialized" and not requested then
				requested = true
				plugin.enable()
			end
			s = plugin._input()
		end
		if (not s or not s.ready) and index == 0 then
			startup = startup + 1
			assert(startup < 100, "startup timeout")
			return
		end
		index = index + 1
		if steps[index] then
			if steps[index]() == false then
				index = index - 1
			end
		end
	end)
	if not ok then
		if paused_pid then
			vim.uv.kill(paused_pid, "sigcont")
		end
		plugin.stop()
		print(tostring(err))
		vim.cmd("cquit 1")
	elseif index > #steps then
		assert(vim.fn.jobwait({ s.client.job }, 3000)[1] ~= -1, "worker still running")
		if not vim.env.RIME_TEST_USER_DIR then
			vim.fn.delete(user, "rf")
		end
		print(
			"PASS: ordinary-file real keys, preedit, candidates, commit, paging, cancel, undo/redo, mapping restore and faults"
		)
		vim.cmd("qa!")
	else
		vim.defer_fn(run, 200)
	end
end
vim.defer_fn(run, 200)
