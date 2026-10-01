-- Run under nvim --headless -u NONE; no user's configuration or data involved.
local function test()
	vim.opt.runtimepath:prepend(vim.env.RIME_BRIDGE_SOURCE)
	local plugin = require("rime_bridge")
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

	-- Actual executable, protocol handshake, shutdown and no schema seeding.
	plugin.setup({ worker = worker, user_dir = user })
	plugin.start()
	assert(vim.wait(10000, function()
		return plugin.status().phase ~= "starting"
	end, 10))
	local status = plugin.status()
	assert(status.phase == "initialized", vim.inspect(status))
	assert(status.info.protocol == 1 and status.info.runtime == "0.1.0", "unexpected worker identity")
	assert(vim.fn.filereadable(user .. "/default.custom.yaml") == 0, "must not seed configuration")
	assert(#vim.api.nvim_list_bufs() == buffers, "must not create buffers")
	local snapshot = plugin.config()
	snapshot.schema = "modified"
	assert(plugin.config().schema == "wanxiang", "configuration leaked by reference")
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
	print("PASS: Lua setup isolation, protocol rejection, actual init/stop and missing worker")
end
local ok, err = xpcall(test, debug.traceback)
if not ok then
	vim.api.nvim_err_writeln(err)
	vim.cmd("cquit 1")
else
	vim.cmd("qa!")
end
