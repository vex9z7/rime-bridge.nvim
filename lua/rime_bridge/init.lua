-- Opt-in ordinary-buffer input; setup never intercepts keys.
local M = {}
local config
local client
local state = { phase = "stopped" }
local input
local serial = 0
local waiting = {}
local wanted = false

local function fail(reason)
	wanted = false
	waiting = {}
	if input then
		input.error = reason
		input.close()
		input = nil
	end
	if client then
		client:close()
	end
	client = nil
	state = { phase = "failed", error = reason }
	vim.notify("Rime stopped; ordinary editing restored. See :RimeInfo for diagnostics", vim.log.levels.ERROR)
end

function M.stop()
	wanted = false
	waiting = {}
	serial = serial + 1
	if input then
		input.close()
		input = nil
	end
	if client then
		client:close()
	end
	client = nil
	state = { phase = "stopped" }
end

function M.status()
	local result = vim.deepcopy(state)
	result.enabled = input ~= nil and not input.closed
	return result
end

function M.config()
	return config and vim.deepcopy(config) or nil
end

function M.setup(opts)
	opts = opts or {}
	assert(type(opts) == "table", "rime_bridge.setup expects a table")
	local next_config = vim.tbl_extend("force", {
		worker = "rime-bridge-worker",
		schema = "wanxiang_pure",
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
	for name, action in pairs({
		RimeEnable = M.enable,
		RimeDisable = M.disable,
		RimeToggle = M.toggle,
		RimeDeploy = M.deploy,
	}) do
		vim.api.nvim_create_user_command(name, action, { force = true })
	end
	local group = vim.api.nvim_create_augroup("RimeBridgeLifecycle", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.stop })
end

-- Explicit backend initialization only; does not deploy or intercept input.
function M.start(callback)
	assert(config, "Call rime_bridge.setup first")
	if client then
		if state.phase == "initialized" and callback then
			callback()
		elseif state.phase == "starting" and callback then
			waiting[#waiting + 1] = callback
		elseif state.phase == "deploying" and callback then
			vim.notify("Rime deployment in progress; retry after RimeInfo reports initialized", vim.log.levels.WARN)
		end
		return
	end
	if callback then
		waiting[#waiting + 1] = callback
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
		local callbacks = waiting
		waiting = {}
		for _, ready in ipairs(callbacks) do
			ready()
		end
	end)
end

function M.disable()
	wanted = false
	serial = serial + 1
	if input then
		input.close()
		input = nil
	end
end

function M.enable()
	M.disable()
	local token, buf, win = serial, vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
	assert(vim.bo[buf].buftype == "" and vim.bo[buf].modifiable, "Enable Rime in a modifiable ordinary buffer")
	wanted = true
	M.start(function()
		if token ~= serial then
			return
		end
		local current = client
		current:request("schema", current.generation or 0, { schema = config.schema }, function()
			if
				token ~= serial
				or current ~= client
				or vim.api.nvim_get_current_buf() ~= buf
				or vim.api.nvim_get_current_win() ~= win
			then
				return
			end
			input = require("rime_bridge.input").attach(current)
		end)
	end)
end

function M.toggle()
	if wanted then
		M.disable()
	else
		M.enable()
	end
end

-- Explicit deployment only. Re-enable after success; no automatic key capture.
function M.deploy()
	M.disable()
	M.start(function()
		local current = client
		state.phase = "deploying"
		current:request("deploy", current.generation or 0, nil, function(info)
			if current == client then
				state = { phase = "initialized", info = info }
			end
		end)
	end)
end

-- Internal snapshot for regression tests and diagnostics, not a stable API.
function M._input()
	return input
end
return M
