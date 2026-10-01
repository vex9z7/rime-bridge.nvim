-- Ordinary-buffer adapter: temporary input hooks; never creates or resets user buffers.
local M = {}
local instance = 0
local function keys(s)
	return vim.api.nvim_replace_termcodes(s, true, false, true)
end
function M.attach(client, ui)
	local buf = vim.api.nvim_get_current_buf()
	assert(vim.bo[buf].buftype == "" and vim.bo[buf].modifiable, "Enable Rime in a modifiable ordinary buffer")
	instance = instance + 1
	local s = {
		ui = ui,
		revision = 0,
		instance = instance,
		buf = vim.api.nvim_get_current_buf(),
		win = vim.api.nvim_get_current_win(),
		generation = client.generation or 0,
		ready = true,
		enabled = true,
		closed = false,
		pending = 0,
		context = { preedit = "", candidates = {} },
	}
	s.client = client
	s.maps = {}
	local function map(mode, lhs, callback, options)
		local previous = vim.fn.maparg(lhs, mode, false, true)
		vim.keymap.set(mode, lhs, callback, options)
		s.maps[#s.maps + 1] = { mode = mode, lhs = lhs, previous = previous, callback = callback }
	end
	local ns = vim.api.nvim_create_namespace("rime-bridge-" .. s.buf)
	local function hide()
		if ui == "blink" then
			require("rime_bridge.blink").hide()
		end
		if vim.api.nvim_buf_is_valid(s.buf) then
			vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
		end
		if s.popup and vim.api.nvim_win_is_valid(s.popup) then
			vim.api.nvim_win_close(s.popup, true)
		end
		s.popup = nil
	end
	local function anchor()
		s.win = vim.api.nvim_get_current_win()
		s.position = vim.api.nvim_win_get_cursor(s.win)
		s.tick = vim.api.nvim_buf_get_changedtick(s.buf)
	end
	local function valid()
		return not s.closed
			and vim.api.nvim_buf_is_valid(s.buf)
			and vim.bo[s.buf].modifiable
			and vim.api.nvim_get_current_buf() == s.buf
			and vim.api.nvim_get_current_win() == s.win
			and vim.api.nvim_get_mode().mode:match("^i")
			and s.tick == vim.api.nvim_buf_get_changedtick(s.buf)
			and vim.deep_equal(s.position, vim.api.nvim_win_get_cursor(s.win))
	end
	local function render()
		hide()
		local c = s.context
		if c.preedit == "" or not valid() then
			return
		end
		vim.api.nvim_buf_set_extmark(s.buf, ns, s.position[1] - 1, s.position[2], {
			virt_text = { { c.preedit, "IncSearch" } },
			virt_text_pos = "inline",
		})
		if #c.candidates == 0 then
			return
		end
		if ui == "blink" then
			require("rime_bridge.blink").show(s)
			return
		end
		if not s.menu or not vim.api.nvim_buf_is_valid(s.menu) then
			s.menu = vim.api.nvim_create_buf(false, true)
		end
		local lines = {}
		for i, candidate in ipairs(c.candidates) do
			lines[#lines + 1] = (i == c.selected + 1 and "> " or "  ") .. i .. " " .. candidate.text
		end
		vim.api.nvim_buf_set_lines(s.menu, 0, -1, false, lines)
		s.popup = vim.api.nvim_open_win(s.menu, false, {
			relative = "cursor",
			row = 1,
			col = 0,
			width = math.max(1, math.min(40, vim.o.columns - 2)),
			height = #lines,
			style = "minimal",
			border = "rounded",
			focusable = false,
		})
	end
	local function insert(text)
		if text == "" then
			return
		end
		local row, col = unpack(s.position)
		local lines = vim.split(text, "\n", { plain = true })
		vim.api.nvim_buf_set_text(s.buf, row - 1, col, row - 1, col, lines)
		vim.api.nvim_win_set_cursor(s.win, { row + #lines - 1, #lines == 1 and col + #text or #lines[#lines] })
		anchor()
	end
	local function cancel(defer)
		if s.closed or not s.ready then
			return
		end
		s.generation = s.generation + 1
		client.generation = s.generation
		s.pending = 0
		s.context = { preedit = "", candidates = {} }
		s.client:cancel_queued()
		if s.finish_selection then
			vim.schedule(s.finish_selection)
		end
		local generation = s.generation
		local function clear()
			if s.closed or generation ~= s.generation then
				return
			end
			s.client:request("clear", generation)
			hide()
		end
		if defer == true then
			vim.schedule(clear)
		else
			clear()
		end
	end
	s.cancel = cancel
	local function input(key, fallback, op, done)
		s.revision = s.revision + 1
		if s.pending == 0 and s.context.preedit == "" then
			anchor()
		end
		s.pending = s.pending + 1
		local gen = s.generation
		-- Schedule outside expression mapping textlock.
		vim.schedule(function()
			if s.closed or gen ~= s.generation then
				return
			end
			s.client:request(op or "key", gen, op == "select" and { index = key } or { key = key }, function(result)
				if gen ~= s.generation then
					return
				end
				if not valid() then
					cancel()
					return
				end
				s.pending = s.pending - 1
				insert(result.commit)
				if not result.handled then
					if fallback == "\b" then
						local row, col = unpack(s.position)
						if col > 0 then
							local line = vim.api.nvim_buf_get_lines(s.buf, row - 1, row, false)[1]
							local prefix = line:sub(1, col)
							local previous = vim.fn.byteidx(prefix, vim.fn.strchars(prefix) - 1)
							vim.api.nvim_buf_set_text(s.buf, row - 1, previous, row - 1, col, { "" })
							vim.api.nvim_win_set_cursor(s.win, { row, previous })
						elseif row > 1 then
							local previous = vim.api.nvim_buf_get_lines(s.buf, row - 2, row - 1, false)[1]
							vim.api.nvim_buf_set_text(s.buf, row - 2, #previous, row - 1, 0, { "" })
							vim.api.nvim_win_set_cursor(s.win, { row - 1, #previous })
						end
						anchor()
					else
						insert(fallback)
					end
				end
				s.context = result
				render()
				if done then
					done()
				end
			end)
		end)
	end
	s.key = input
	function s.select(index, generation, revision, owner, done)
		if
			s.closed
			or s.pending ~= 0
			or not valid()
			or s.context.preedit == ""
			or generation ~= s.generation
			or revision ~= s.revision
			or owner ~= s.instance
		then
			return false
		end
		local called = false
		local function finish()
			if called then
				return
			end
			called = true
			if s.finish_selection == finish then
				s.finish_selection = nil
			end
			if done then
				done()
			end
		end
		s.finish_selection = finish
		input(index, "", "select", finish)
		return true
	end
	for code = 32, 126 do
		local char = string.char(code)
		map("i", char == "<" and "<lt>" or char, function()
			if not s.ready or not s.enabled or vim.o.paste or not vim.bo[s.buf].modifiable then
				return char
			end
			if ui == "blink" and char == " " and require("rime_bridge.blink").accept() then
				return ""
			end
			input(
				(s.pending > 0 or s.context.preedit ~= "") and (char == "=" and 0xff56 or char == "-" and 0xff55)
					or code,
				char
			)
			return ""
		end, { buffer = s.buf, expr = true, replace_keycodes = false })
	end
	for lhs, spec in pairs({
		["<BS>"] = { 0xff08, "\b" },
		["<CR>"] = { 32, "\n" },
		["<C-n>"] = { 0xff54, "" },
		["<C-p>"] = { 0xff52, "" },
	}) do
		map("i", lhs, function()
			if not s.ready or not s.enabled or (s.pending == 0 and s.context.preedit == "") then
				return keys(lhs)
			end
			if ui == "blink" and lhs == "<CR>" and require("rime_bridge.blink").accept() then
				return ""
			end
			input(spec[1], spec[2])
			return ""
		end, { buffer = s.buf, expr = true, replace_keycodes = false })
	end
	-- Movement cancels synchronously; only UI/native cleanup is deferred under textlock.
	for _, lhs in ipairs({
		"<Esc>",
		"<C-c>",
		"<Left>",
		"<Right>",
		"<Up>",
		"<Down>",
		"<Home>",
		"<End>",
		"<Del>",
		"<Tab>",
	}) do
		map("i", lhs, function()
			-- Invalidate immediately; UI/native work must wait until textlock is released.
			cancel(true)
			return keys(lhs)
		end, { buffer = s.buf, expr = true, replace_keycodes = false })
	end
	local group = vim.api.nvim_create_augroup("RimeBridgeInput" .. s.buf, { clear = true })
	vim.api.nvim_create_autocmd(
		{ "InsertLeave", "BufLeave", "WinLeave" },
		{ group = group, buffer = s.buf, callback = cancel }
	)
	vim.api.nvim_create_autocmd({ "CursorMovedI", "TextChangedI" }, {
		group = group,
		buffer = s.buf,
		callback = function()
			if s.position and (s.pending > 0 or s.context.preedit ~= "") and not valid() then
				cancel()
			end
		end,
	})
	function s.close()
		if s.closed then
			return
		end
		cancel()
		s.closed = true
		s.ready, s.enabled = false, false
		if vim.api.nvim_buf_is_valid(s.buf) then
			vim.api.nvim_buf_call(s.buf, function()
				for _, mapping in ipairs(s.maps) do
					local current = vim.fn.maparg(mapping.lhs, mapping.mode, false, true)
					if current.callback == mapping.callback then
						vim.keymap.del(mapping.mode, mapping.lhs, { buffer = s.buf })
						if mapping.previous.buffer == 1 then
							vim.fn.mapset(mapping.mode, false, mapping.previous)
						end
					end
				end
			end)
		end
		hide()
		if s.menu and vim.api.nvim_buf_is_valid(s.menu) then
			vim.api.nvim_buf_delete(s.menu, { force = true })
		end
		vim.api.nvim_del_augroup_by_id(group)
	end
	vim.api.nvim_create_autocmd({ "BufWipeout", "VimLeavePre" }, {
		group = group,
		callback = function(ev)
			if ev.event == "VimLeavePre" or ev.buf == s.buf then
				s.close()
			end
		end,
	})
	local previous_paste = vim.paste
	local function paste(lines, phase)
		cancel()
		return previous_paste(lines, phase)
	end
	vim.paste = paste
	local close = s.close
	function s.close()
		if vim.paste == paste then
			vim.paste = previous_paste
		end
		close()
	end
	return s
end
return M
