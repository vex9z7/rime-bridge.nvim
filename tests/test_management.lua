-- Installation/data/status checks; never use the user's configuration or data.
vim.opt.runtimepath:prepend(assert(vim.env.RIME_BRIDGE_SOURCE))
local plugin = require("rime_bridge")
local root = vim.fn.tempname() .. " space"
local old_path = vim.env.PATH
local original_client = require("rime_bridge.client")
local original_input = require("rime_bridge.input")
local original_health = vim.health
local original_installation = require("rime_bridge.installation")
local function test()
	vim.fn.mkdir(root .. "/lua/rime_bridge", "p")
	vim.fn.writefile(
		vim.fn.readfile(vim.env.RIME_BRIDGE_SOURCE .. "/lua/rime_bridge/installation.lua"),
		root .. "/lua/rime_bridge/installation.lua"
	)
	local install = dofile(root .. "/lua/rime_bridge/installation.lua")
	assert(install.root == root)
	package.loaded["rime_bridge.installation"] = install
	vim.fn.mkdir(root .. "/bin", "p")
	vim.env.PATH = root .. "/bin"
	plugin.setup()
	assert(plugin.config().user_dir == vim.fn.stdpath("data") .. "/rime-bridge")
	assert(plugin.config().worker == root .. "/build/rime-bridge-worker")
	assert(plugin.status().phase == "stopped", "setup must not start the worker")
	local function executable(path)
		vim.fn.writefile({ "#!/bin/sh", "exit 0" }, path)
		vim.fn.setfperm(path, "rwx------")
	end
	executable(root .. "/bin/rime-bridge-worker")
	assert(plugin.config().worker == root .. "/bin/rime-bridge-worker", "PATH lookup failed")
	vim.fn.mkdir(root .. "/build", "p")
	executable(root .. "/build/rime-bridge-worker")
	assert(plugin.config().worker == root .. "/build/rime-bridge-worker", "late local build not discovered")
	vim.fn.setfperm(root .. "/build/rime-bridge-worker", "rw-------")
	assert(plugin.config().worker == root .. "/build/rime-bridge-worker", "broken build silently fell back")
	plugin.setup({ worker = "/explicit/missing", user_dir = root .. "/data" })
	assert(plugin.config().worker == "/explicit/missing", "explicit override ignored")
	plugin.start()
	assert(plugin.status().error:find("not executable") and plugin.status().error:find("cmake"))
	assert(vim.fn.isdirectory(root .. "/data") == 0, "missing worker created user data")
	assert(install.build_hint():find(vim.fn.shellescape(root), 1, true), "space-containing path not quoted")
	plugin.stop()
	package.loaded["rime_bridge.installation"] = original_installation
	vim.env.PATH = old_path
	-- Passive scheme hints distinguish missing/source/compiled/stale, without YAML
	-- rewriting or claiming that timestamps validate every dictionary dependency.
	local data = require("rime_bridge.data")
	local cfg = { user_dir = root .. "/data", shared_dir = root .. "/shared", schema = "fixture" }
	assert(data.inspect(cfg).deployment == "missing")
	vim.fn.mkdir(cfg.user_dir .. "/build", "p")
	vim.fn.mkdir(cfg.shared_dir, "p")
	local source = cfg.shared_dir .. "/fixture.schema.yaml"
	local compiled = cfg.user_dir .. "/build/fixture.schema.yaml"
	vim.fn.writefile({ "schema: {schema_id: fixture}" }, source)
	assert(data.inspect(cfg).deployment == "needed")
	vim.fn.writefile({ "schema: {schema_id: fixture}" }, compiled)
	local uv = vim.uv or vim.loop
	assert(uv.fs_utime(source, 100, 100))
	assert(uv.fs_utime(compiled, 200, 200))
	assert(data.inspect(cfg).deployment == "compiled")
	local custom = cfg.user_dir .. "/default.custom.yaml"
	vim.fn.writefile({ "patch: {schema_list: [{schema: fixture}]}" }, custom)
	assert(uv.fs_utime(custom, 300, 300))
	assert(data.inspect(cfg).deployment == "possibly_stale")
	assert(not pcall(plugin.setup, { schema = "../outside" }), "schema path traversal accepted")

	-- Control asynchronous replies without sleeps; verify state/ownership races.
	local requests, errors, closes = {}, nil, 0
	package.loaded["rime_bridge.client"] = {
		start = function(_, on_error)
			errors = on_error
			return {
				request = function(_, op, _, _, cb)
					requests[#requests + 1] = { op = op, callback = cb }
				end,
				close = function()
					closes = closes + 1
				end,
			}
		end,
	}
	local function reply(op, result)
		local r = table.remove(requests, 1)
		assert(r and r.op == op, "unexpected request; expected " .. op)
		r.callback(result)
	end
	local worker = root .. "/bin/rime-bridge-worker"
	local options = vim.tbl_extend("force", cfg, { worker = worker })
	plugin.setup(options)
	local messages = {}
	vim.health = {}
	for _, name in ipairs({ "start", "ok", "info", "warn", "error" }) do
		vim.health[name] = function(message)
			messages[#messages + 1] = message
		end
	end
	require("rime_bridge.health").check()
	assert(#requests == 0 and plugin.status().phase == "stopped", "health must be passive")
	assert(table.concat(messages, "\n"):find("RimeCheck"), "runtime probe advice missing")
	vim.health = original_health
	local buffers = #vim.api.nvim_list_bufs()
	plugin.check()
	reply("init", { protocol = 1, engine = "test", extensions = {} })
	reply("schemas", { { id = "fixture" } })
	assert(plugin.status().checked and plugin.status().schema_available and not plugin.is_active())
	assert(#requests == 0 and #vim.api.nvim_list_bufs() == buffers, "check deployed or changed editor buffers")
	plugin.deploy()
	assert(plugin.status().mode == "deploying" and plugin.status().deployment == "running")
	plugin.deploy()
	plugin.enable()
	assert(
		not plugin.is_active() and #requests == 1,
		"deploy duplicated or activation reserved input during deployment"
	)
	reply("deploy", { protocol = 1 })
	reply("schemas", { { id = "fixture" } })
	assert(plugin.status().deployment == "succeeded" and plugin.statusline() == "Rime:off")
	assert(vim.fn.readfile(custom)[1] == "patch: {schema_list: [{schema: fixture}]}", "source patch overwritten")
	plugin.deploy()
	reply("deploy", { protocol = 1 })
	reply("schemas", {})
	assert(plugin.status().deployment == "failed" and plugin.status().mode == "error")
	assert(plugin.status().advice:find("schema_list") and closes > 0)

	package.loaded["rime_bridge.input"] = {
		attach = function()
			local input = { buf = vim.api.nvim_get_current_buf(), closed = false }
			input.close = function()
				input.closed = true
			end
			return input
		end,
	}
	plugin.enable()
	assert(plugin.statusline() == "Rime:starting")
	reply("init", { protocol = 1 })
	reply("schema", {})
	assert(plugin.statusline() == "Rime:on")
	local target = vim.api.nvim_get_current_buf()
	local other = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(other)
	assert(plugin.statusline() == "Rime:off" and not plugin.status().active)
	vim.api.nvim_set_current_buf(target)
	assert(plugin.statusline() == "Rime:on")
	vim.api.nvim_buf_delete(other, { force = true })
	plugin.disable()
	assert(plugin.statusline() == "Rime:off")
	errors("test runtime failure")
	assert(plugin.statusline() == "Rime:error" and not plugin.is_active())
	plugin.stop()
	assert(plugin.statusline() == "Rime:off")
	plugin.deploy()
	local late = table.remove(requests, 1)
	assert(late.op == "init")
	plugin.stop()
	late.callback({ protocol = 1 })
	assert(#requests == 0 and plugin.status().phase == "stopped", "late initialization restarted deployment")
	package.loaded["rime_bridge.client"] = original_client
	package.loaded["rime_bridge.input"] = original_input

	local example = dofile(vim.env.RIME_BRIDGE_SOURCE .. "/examples/lazy.lua")
	assert(example[1].opts.ui == "blink" and example[1].build:find("BUILD_TESTING=OFF", 1, true))
	assert(example[1].opts.worker == nil, "example must exercise automatic discovery")
	local opts = example[2].opts(nil, {})
	assert(
		opts.sources.providers.rime_bridge and opts.fuzzy.implementation == "lua",
		"example Blink integration missing"
	)
	print(
		"PASS: installation discovery, read-only data hints, deployment/check lifecycle, buffer-local status and Lazy example"
	)
end
local ok, err = xpcall(test, debug.traceback)
plugin.stop()
package.loaded["rime_bridge.installation"] = original_installation
vim.env.PATH = old_path
vim.health = original_health
package.loaded["rime_bridge.client"] = original_client
package.loaded["rime_bridge.input"] = original_input
vim.fn.delete(root, "rf")
if not ok then
	vim.api.nvim_err_writeln(err)
	vim.cmd("cquit 1")
else
	vim.cmd("qa!")
end
