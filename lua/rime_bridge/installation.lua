-- Discovery only: never builds, downloads, installs or starts a process.
local M = {}
local source = debug.getinfo(1, "S").source:sub(2)
M.root = vim.fn.fnamemodify(source, ":p:h:h:h")

function M.worker(explicit)
	if explicit then
		return explicit, "configured"
	end
	local bundled = M.root .. "/build/rime-bridge-worker"
	-- A broken local build must not silently fall back to an unrelated PATH worker.
	if (vim.uv or vim.loop).fs_stat(bundled) then
		return bundled, "plugin build"
	end
	local path = vim.fn.exepath("rime-bridge-worker")
	if path ~= "" then
		return path, "PATH"
	end
	return bundled, "plugin build (missing)"
end

function M.build_hint()
	return "Run cmake -S "
		.. vim.fn.shellescape(M.root)
		.. " -B "
		.. vim.fn.shellescape(M.root .. "/build")
		.. " -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF && cmake --build "
		.. vim.fn.shellescape(M.root .. "/build")
		.. " --parallel 2"
end

return M
