-- Run under nvim --headless -u NONE; no user's configuration or data involved.
local function test()
	vim.opt.runtimepath:prepend(vim.env.RIME_BRIDGE_SOURCE)
	local plugin = require("rime_bridge")
	local diagnostics = require("rime_bridge.diagnostics").new()
	diagnostics.feed({ "error loading shared lib" })
	diagnostics.feed({
		"raries: SECRET_TYPED_CONTENT",
		"Lua component schema dictionary failure SECRET_TYPED_CONTENT",
		"",
	})
	diagnostics.feed({ string.rep("PRIVATE", 20000), "" })
	local summary = diagnostics.snapshot()
	assert(#summary == 6, "diagnostic categories missing or unbounded")
	assert(not vim.inspect(summary):find("SECRET") and not vim.inspect(summary):find("PRIVATE"), "raw stderr retained")
	diagnostics.clear()
	assert(#diagnostics.snapshot() == 6, "safe categories lost on close")
	local buffers = #vim.api.nvim_list_bufs()
	local user = vim.fn.tempname()
	local worker = assert(vim.env.RIME_BRIDGE_WORKER, "worker path required")
	local requests, closed = {}, false
	local callback
	local original = require("rime_bridge.client")
	package.loaded["rime_bridge.client"] = {
		start = function()
			return {
				request = function(_, op, _, _, cb)
					requests[#requests + 1] = op
					callback = cb
				end,
				close = function()
					closed = true
				end,
			}
		end,
	}
	plugin.setup({ worker = worker, user_dir = user })
	assert(#requests == 0 and #vim.api.nvim_list_bufs() == buffers, "setup must not start worker or create buffers")
	assert(vim.fn.isdirectory(user) == 0, "setup must not write user data")
	plugin.start()
	assert(#requests == 1 and requests[1] == "init", "no implicit deployment")
	callback({ protocol = 99 })
	assert(closed and plugin.status().phase == "failed", "mismatch must close worker")
	assert(plugin.status().error:find("protocol"))
	plugin.stop()
	package.loaded["rime_bridge.client"] = original

	-- Pending activation only reserves its target buffer, never the next buffer.
	package.loaded["rime_bridge.client"] = {
		start = function()
			return {
				request = function(_, _, _, _, cb)
					callback = cb
				end,
				close = function() end,
			}
		end,
	}
	plugin.setup({ worker = worker, user_dir = user })
	local target = vim.api.nvim_get_current_buf()
	plugin.enable()
	assert(plugin.is_active() and not require("rime_bridge.minuet").allowed(), "pending target not reserved")
	local other = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(other)
	assert(not plugin.is_active() and require("rime_bridge.minuet").allowed(), "pending target leaked across buffers")
	callback({ protocol = 1 }) -- init; schema callback replaces callback
	callback({})
	vim.api.nvim_set_current_buf(target)
	assert(not plugin.is_active(), "aborted activation retained input ownership")
	vim.api.nvim_buf_delete(other, { force = true })
	plugin.stop()
	package.loaded["rime_bridge.client"] = original

	-- Actual executable, protocol handshake, startup-toggle cancellation and no seeding.
	plugin.setup({ worker = worker, user_dir = user })
	plugin.toggle()
	plugin.toggle()
	assert(vim.wait(10000, function()
		return plugin.status().phase ~= "starting"
	end, 10))
	local status = plugin.status()
	assert(status.phase == "initialized" and not status.enabled, vim.inspect(status))
	assert(status.info.protocol == 1 and status.info.runtime == "0.1.0", "unexpected worker identity")
	assert(vim.fn.filereadable(user .. "/default.custom.yaml") == 0, "must not seed configuration")
	assert(#vim.api.nvim_list_bufs() == buffers, "must not create buffers")
	-- A second editor-side instance fails closed without replacing user data/maps.
	local owned = user .. "/user-note.txt"
	vim.fn.writefile({ "user owned" }, owned)
	local mappings = vim.api.nvim_buf_get_keymap(0, "i")
	local second = dofile(vim.env.RIME_BRIDGE_SOURCE .. "/lua/rime_bridge/init.lua")
	second.setup({ worker = worker, user_dir = user })
	second.enable()
	assert(
		vim.wait(5000, function()
			return second.status().phase == "failed"
		end, 10),
		"busy instance did not fail"
	)
	assert(
		second.status().error:find("busy") and second.status().error:find("do not delete"),
		"busy recovery advice missing"
	)
	assert(not second.status().enabled and not second.is_active(), "busy instance retained ownership")
	assert(vim.deep_equal(mappings, vim.api.nvim_buf_get_keymap(0, "i")), "busy failure changed mappings")
	assert(vim.fn.readfile(owned)[1] == "user owned", "busy instance changed user data")
	second.stop()
	local snapshot = plugin.config()
	snapshot.schema = "modified"
	assert(plugin.config().schema == "wanxiang_pure", "configuration leaked by reference")
	plugin.stop()
	assert(plugin.status().phase == "stopped", "stop failed")
	-- Let normal EOF shutdown complete before deleting disposable data.
	vim.wait(2200, function()
		return false
	end, 20)
	vim.fn.delete(user, "rf")
	assert(not pcall(plugin.setup, { user_dir = "relative" }), "relative path accepted")
	plugin.setup({ worker = "/missing/rime-worker", user_dir = user })
	plugin.start()
	assert(
		plugin.status().phase == "failed" and plugin.status().error:find("not executable"),
		"missing executable not diagnosed"
	)
	plugin.stop()
	-- A loader failure occurs before JSON; retain only safe categories on exit.
	local loader = vim.fn.tempname()
	vim.fn.writefile({ "#!/bin/sh", "echo 'error loading shared libraries: PRIVATE_INPUT' >&2", "exit 127" }, loader)
	vim.fn.setfperm(loader, "rwx------")
	plugin.setup({ worker = loader, user_dir = user })
	plugin.start()
	assert(
		vim.wait(5000, function()
			return plugin.status().phase == "failed"
		end, 10),
		"loader failure missing"
	)
	local failed = plugin.status()
	assert(#failed.diagnostics == 2, "loader diagnostic category missing")
	assert(not vim.inspect(failed):find("PRIVATE_INPUT"), "loader stderr leaked")
	plugin.stop()
	vim.fn.delete(loader)
	print("PASS: setup, protocol, startup ownership, busy editor, privacy-safe diagnostics and worker failures")
end
local ok, err = xpcall(test, debug.traceback)
if not ok then
	vim.api.nvim_err_writeln(err)
	vim.cmd("cquit 1")
else
	vim.cmd("qa!")
end
