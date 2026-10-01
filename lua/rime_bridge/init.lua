-- Foundation API: no editor input hooks until normal-buffer acceptance passes.
local M = {}
local config
local client
local state = { phase = "stopped" }

local function fail(reason)
	if client then
		client:close()
	end
	client = nil
	state = { phase = "failed", error = reason }
end

function M.stop()
	if client then
		client:close()
	end
	client = nil
	state = { phase = "stopped" }
end

function M.status()
	return vim.deepcopy(state)
end

function M.config()
	return config and vim.deepcopy(config) or nil
end

function M.setup(opts)
	opts = opts or {}
	assert(type(opts) == "table", "rime_bridge.setup expects a table")
	local next_config = vim.tbl_extend("force", {
		worker = "rime-bridge-worker",
		schema = "wanxiang",
		require_lua = false,
	}, opts)
	for _, name in ipairs({ "worker", "schema" }) do
		assert(type(next_config[name]) == "string" and next_config[name] ~= "", "Invalid " .. name)
	end
	assert(
		type(next_config.user_dir) == "string" and next_config.user_dir:sub(1, 1) == "/",
		"Configure an absolute dedicated user_dir"
	)
	for _, name in ipairs({ "shared_dir", "lua_plugin" }) do
		assert(
			next_config[name] == nil or (type(next_config[name]) == "string" and next_config[name]:sub(1, 1) == "/"),
			name .. " must be an absolute path"
		)
	end
	assert(type(next_config.require_lua) == "boolean", "require_lua must be boolean")
	M.stop()
	config = next_config
	vim.api.nvim_create_user_command("RimeInfo", function()
		vim.print(M.status())
	end, { force = true })
	local group = vim.api.nvim_create_augroup("RimeBridgeLifecycle", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.stop })
end

-- Explicit backend initialization only; does not deploy or intercept input.
function M.start()
	assert(config, "Call rime_bridge.setup first")
	if client then
		return
	end
	if vim.fn.executable(config.worker) ~= 1 then
		fail("Worker not executable: " .. config.worker .. "; build/install with CMake or configure worker")
		return
	end
	state = { phase = "starting" }
	local ok, started = pcall(require("rime_bridge.client").start, config.worker, fail)
	if not ok then
		fail(tostring(started))
		return
	end
	client = started
	local current = client
	current:request("init", 0, {
		user_dir = config.user_dir,
		shared_dir = config.shared_dir,
		lua_plugin = config.lua_plugin,
		require_lua = config.require_lua,
	}, function(info)
		if client ~= current then
			return
		end
		if type(info) ~= "table" or info.protocol ~= 1 then
			fail("Incompatible worker protocol; install Lua and worker from the same release (expected protocol 1)")
			return
		end
		state = { phase = "initialized", info = info }
	end)
end

return M
