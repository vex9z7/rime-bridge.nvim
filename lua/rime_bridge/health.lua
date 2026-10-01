local M = {}
function M.check()
	local health = vim.health
	health.start("rime-bridge.nvim (implementation in progress)")
	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim >= 0.10 is required")
	end
	local plugin = require("rime_bridge")
	local config = plugin.config()
	if not config then
		health.error("Call setup with an absolute dedicated user_dir")
		return
	end
	if vim.fn.executable(config.worker) == 1 then
		health.ok("Worker executable: " .. config.worker)
	else
		health.error("Worker missing: " .. config.worker, { "Build/install with CMake or configure worker" })
	end
	if vim.fn.isdirectory(config.user_dir) == 1 then
		health.ok("User directory exists: " .. config.user_dir)
	else
		health.warn("User directory not created: " .. config.user_dir)
	end
	local state = plugin.status()
	if state.error then
		health.error(state.error)
	end
	for _, message in ipairs(state.diagnostics or {}) do
		health.warn(message)
	end
	if state.info then
		health.ok("Protocol " .. state.info.protocol .. "; engine " .. tostring(state.info.engine))
		health.info("Loaded library: " .. tostring(state.info.library))
		health.info("Registered extensions: " .. table.concat(state.info.extensions or {}, ", "))
	else
		health.info("Worker has not initialized; executable presence alone does not verify dependencies")
	end
	if config.ui == "blink" then
		if require("rime_bridge.blink").ready() then
			health.ok("Blink options wrapper configured")
		else
			health.error("Configure Blink with rime_bridge.blink.options before enabling input")
		end
	end
	health.warn("Real-configuration/standalone AI virtual-text integration remains unvalidated")
end
return M
