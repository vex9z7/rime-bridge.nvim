-- Opt-in ordinary-buffer input; setup never intercepts keys.
local M = {}
local config
local explicit_worker
local client
local state = { phase = "stopped" }
local input
local serial = 0
local waiting = {}
local wanted = false
local wanted_buf
local deploying = false

local function fail(reason)
	local diagnostics = client and client.diagnostics and client.diagnostics.snapshot() or {}
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
	state = { phase = "failed", error = reason, diagnostics = diagnostics, deployment = deploying and "failed" or nil }
	deploying = false
	if reason:find("schema", 1, true) then
		state.advice =
			"Check schema_list in default.custom.yaml and scheme resources; run :RimeDeploy, then :RimeCheck."
	elseif reason:find("busy", 1, true) then
		state.advice = "Stop the other writer or use a separate user_dir; do not delete lock files."
	elseif reason:find("protocol", 1, true) then
		state.advice = require("rime_bridge.installation").build_hint()
	else
		state.advice = "Run :checkhealth rime_bridge; after correcting the problem retry :RimeCheck."
	end
	vim.notify(
		state.deployment == "failed"
				and "Rime deployment failed; input remains off. See :RimeInfo and :checkhealth rime_bridge"
			or "Rime stopped; ordinary editing restored. See :RimeInfo for diagnostics",
		vim.log.levels.ERROR
	)
end

function M.stop()
	deploying = false
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

-- Configuration integrations may query this without loading any AI provider.
function M.is_active()
	return wanted
		and wanted_buf == vim.api.nvim_get_current_buf()
		and (input == nil or (not input.closed and input.buf == vim.api.nvim_get_current_buf()))
end

function M.status()
	local result = vim.deepcopy(state)
	if client and client.diagnostics then
		result.diagnostics = client.diagnostics.snapshot()
	end
	result.enabled = input ~= nil and not input.closed
	result.buffer = result.enabled and input.buf or (wanted and wanted_buf or nil)
	result.active = M.is_active()
	result.mode = state.phase == "failed" and "error"
		or deploying and "deploying"
		or (result.active and (result.enabled and "on" or "starting"))
		or (state.phase == "starting" and not wanted and "starting")
		or "off"
	return result
end

-- Fixed labels only: no preedit/typed content and no filesystem work on redraw.
function M.statusline()
	return "Rime:" .. M.status().mode
end

function M.config()
	if config then
		config.worker, config.worker_source = require("rime_bridge.installation").worker(explicit_worker)
	end
	return config and vim.deepcopy(config) or nil
end

function M.setup(opts)
	opts = opts or {}
	assert(type(opts) == "table", "rime_bridge.setup expects a table")
	local next_config = vim.tbl_extend("force", {
		user_dir = vim.fn.stdpath("data") .. "/rime-bridge",
		ui = "native",
		schema = "wanxiang_pure",
		require_lua = false,
	}, opts)
	assert(opts.worker == nil or (type(opts.worker) == "string" and opts.worker ~= ""), "Invalid worker")
	next_config.worker, next_config.worker_source = require("rime_bridge.installation").worker(opts.worker)
	for _, name in ipairs({ "worker", "schema" }) do
		assert(type(next_config[name]) == "string" and next_config[name] ~= "", "Invalid " .. name)
	end
	assert(
		not next_config.schema:find("[/\\]") and next_config.schema ~= "." and next_config.schema ~= "..",
		"schema must be an ID, not a path"
	)
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
	assert(next_config.ui == "native" or next_config.ui == "blink", "ui must be native or blink")
	M.stop()
	explicit_worker = opts.worker
	config = next_config
	vim.api.nvim_create_user_command("RimeInfo", function()
		vim.print({ state = M.status(), config = M.config(), data = require("rime_bridge.data").inspect(config) })
	end, { force = true })
	vim.api.nvim_create_user_command("RimeCheck", function()
		M.check()
	end, { force = true })
	for name, action in pairs({
		RimeEnable = M.enable,
		RimeDisable = M.disable,
		RimeToggle = M.toggle,
		RimeDeploy = M.deploy,
		RimeStop = M.stop,
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
	M.config() -- Discover a worker built after setup, without rebuilding automatically.
	if vim.fn.executable(config.worker) ~= 1 then
		fail(
			"Worker not executable: "
				.. config.worker
				.. "; "
				.. require("rime_bridge.installation").build_hint()
				.. "; or configure worker explicitly"
		)
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
			fail(
				"Incompatible worker protocol; rebuild the worker from this plugin checkout (expected protocol 1). "
					.. require("rime_bridge.installation").build_hint()
					.. ""
			)
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
	assert(config, "Call setup first")
	if deploying then
		vim.notify("Rime deployment in progress; wait for completion, then :RimeEnable", vim.log.levels.WARN)
		return
	end
	if config.ui == "blink" then
		assert(require("rime_bridge.blink").ready(), "Wrap Blink setup with rime_bridge.blink.options first")
		require("blink.cmp").cancel()
	end
	M.disable()
	local token, buf, win = serial, vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
	assert(vim.bo[buf].buftype == "" and vim.bo[buf].modifiable, "Enable Rime in a modifiable ordinary buffer")
	wanted = true
	wanted_buf = buf
	require("rime_bridge.minuet").dismiss()
	M.start(function()
		if token ~= serial then
			return
		end
		local current = client
		current:request("schema", current.generation or 0, { schema = config.schema }, function()
			if token ~= serial or current ~= client then
				return
			end
			if vim.api.nvim_get_current_buf() ~= buf or vim.api.nvim_get_current_win() ~= win then
				wanted = false
				return
			end
			input = require("rime_bridge.input").attach(current, config.ui)
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

-- Explicit runtime verification: initialization may create user_dir and acquire its
-- lock, but never deploys, selects a schema, intercepts keys or writes source files.
function M.check()
	assert(config, "Call setup first")
	if deploying then
		vim.notify("Rime deployment in progress; retry :RimeCheck after completion", vim.log.levels.WARN)
		return
	end
	M.start(function()
		local current = client
		current:request("schemas", current.generation or 0, nil, function(schemas)
			if current ~= client then
				return
			end
			state.schemas = schemas
			state.schema_available = false
			for _, schema in ipairs(schemas) do
				if schema.id == config.schema then
					state.schema_available = true
				end
			end
			state.checked = true
			vim.notify(
				state.schema_available and "Rime worker and schema list checked; verify candidates with actual input."
					or "Configured schema is not in the engine schema list; check default.custom.yaml and run :RimeDeploy.",
				state.schema_available and vim.log.levels.INFO or vim.log.levels.WARN
			)
		end)
	end)
end

-- Explicit deployment only. Re-enable after success; no automatic key capture.
function M.deploy()
	assert(config, "Call setup first")
	if deploying then
		vim.notify("Rime deployment already in progress", vim.log.levels.WARN)
		return
	end
	M.disable()
	deploying = true
	vim.notify("Rime deployment started; input is disabled", vim.log.levels.INFO)
	M.start(function()
		local current = client
		state.phase = "deploying"
		state.deployment = "running"
		current:request("deploy", current.generation or 0, nil, function(info)
			if current ~= client then
				return
			end
			current:request("schemas", current.generation or 0, nil, function(schemas)
				if current ~= client then
					return
				end
				local available = false
				for _, schema in ipairs(schemas) do
					if schema.id == config.schema then
						available = true
					end
				end
				if not available then
					fail("Deployment finished but configured schema is not in schema_list: " .. config.schema)
					return
				end
				deploying = false
				state = {
					phase = "initialized",
					info = info,
					schemas = schemas,
					schema_available = true,
					checked = true,
					deployment = "succeeded",
				}
				vim.notify("Rime deployment completed; use :RimeEnable to turn on input", vim.log.levels.INFO)
			end)
		end)
	end)
end

-- Internal snapshot for regression tests and diagnostics, not a stable API.
function M._input()
	return input
end
return M
