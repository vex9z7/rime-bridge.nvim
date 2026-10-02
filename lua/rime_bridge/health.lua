-- Passive checks only. :RimeCheck is the explicit worker/engine probe.
local M = {}
function M.check()
	local health = vim.health
	health.start("rime-bridge.nvim")
	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim >= 0.10 is required")
	end
	local plugin = require("rime_bridge")
	local config = plugin.config()
	if not config then
		health.error("Call require('rime_bridge').setup() first")
		return
	end
	local install = require("rime_bridge.installation")
	if vim.fn.executable(config.worker) == 1 then
		health.ok("Worker executable (" .. config.worker_source .. "): " .. config.worker)
	else
		health.error("Worker missing or not executable: " .. config.worker, {
			install.build_hint(),
			"An explicit worker setting never falls back; correct/remove it if it points to an old installation.",
		})
		for _, tool in ipairs({ "cmake", "c++", "make" }) do
			if vim.fn.executable(tool) ~= 1 then
				health.warn("Build tool missing: " .. tool, {
					"Install your distribution's C++17 compiler, CMake and Make (or configure another CMake generator).",
				})
			end
		end
		health.info(
			"Build needs system librime development files (Ubuntu: librime-dev); JSON is fetched, not a system package."
		)
	end
	local data = require("rime_bridge.data").inspect(config)
	if data.user_exists and data.user_writable then
		health.ok("Writable user directory: " .. config.user_dir)
	elseif data.user_exists then
		health.error("User directory is not writable: " .. config.user_dir)
	else
		health.warn("Dedicated user directory not prepared: " .. config.user_dir)
	end
	if vim.fn.isdirectory(data.shared_dir) ~= 1 then
		health.error("Shared Rime data directory missing: " .. data.shared_dir, {
			"Install distribution Rime data or configure an existing absolute shared_dir.",
		})
	end
	if data.deployment == "compiled" then
		health.info(data.advice)
	else
		health.warn("Scheme " .. config.schema .. ": " .. data.deployment, { data.advice })
	end
	health.info(
		"File freshness checks cover direct schema/global YAML only; after dictionary/Lua/model updates explicitly redeploy."
	)
	local state = plugin.status()
	health.info("Engine: " .. state.phase .. "; current buffer: " .. state.mode)
	if state.error then
		health.error(state.error, { state.advice })
	end
	for _, message in ipairs(state.diagnostics or {}) do
		health.warn(message)
	end
	if state.info then
		health.ok("Protocol " .. state.info.protocol .. "; engine " .. tostring(state.info.engine))
		health.info("Loaded library: " .. tostring(state.info.library))
		health.info("Registered extensions: " .. table.concat(state.info.extensions or {}, ", "))
	else
		health.info(
			"Runtime not verified. Run :RimeCheck explicitly; executable presence does not prove dependencies can load."
		)
	end
	if state.checked then
		if state.schema_available then
			health.ok("Configured schema appears in the engine schema list; actual candidate quality is not checked")
		else
			health.warn("Configured schema is absent from the engine schema list", {
				"Check schema_list in default.custom.yaml and run :RimeDeploy explicitly.",
			})
		end
	end
	if config.ui == "blink" then
		if require("rime_bridge.blink").ready() then
			health.ok("Blink options wrapper configured")
		else
			health.error("Configure Blink with rime_bridge.blink.options before enabling input")
		end
	end
	health.info(
		"Only the documented Blink/Minuet integrations are covered; arbitrary AI plugins and model effectiveness are not verified."
	)
end
return M
