-- Read-only hints, not a YAML parser or a replacement for Rime's deployer.
local M = {}
local uv = vim.uv or vim.loop
function M.inspect(config)
	local shared = config.shared_dir or "/usr/share/rime-data"
	local name = config.schema
	local result = { user_dir = config.user_dir, shared_dir = shared, schema = name }
	local user = uv.fs_stat(config.user_dir)
	result.user_exists = user ~= nil and user.type == "directory"
	result.user_writable = result.user_exists and vim.fn.filewritable(config.user_dir) == 2
	local compiled = config.user_dir .. "/build/" .. name .. ".schema.yaml"
	local built = uv.fs_stat(compiled)
	result.compiled = built and built.type == "file" and compiled or nil
	local source
	for _, dir in ipairs({ config.user_dir, shared }) do
		local path = dir .. "/" .. name .. ".schema.yaml"
		if vim.fn.filereadable(path) == 1 then
			source = path
			break
		end
	end
	result.source = source
	if not source and not result.compiled then
		result.deployment = "missing"
		result.advice =
			"Prepare the scheme and its dictionaries in a dedicated user_dir; no files are downloaded automatically."
	elseif not result.compiled then
		result.deployment = "needed"
		result.advice = "Source exists but no compiled schema was found; run :RimeDeploy explicitly."
	else
		result.deployment = "compiled"
		result.advice =
			"Compiled schema exists; use :RimeCheck to verify the worker and schema list, then test actual input."
		-- Only directly identifiable YAML is inspected. Included dictionaries/Lua/models
		-- can also change, so absence of this hint never proves a fully current cache.
		local paths = { source }
		for _, dir in ipairs({ config.user_dir, shared }) do
			for _, file in ipairs({ "default.yaml", "default.custom.yaml", name .. ".custom.yaml" }) do
				paths[#paths + 1] = dir .. "/" .. file
			end
		end
		for _, path in ipairs(paths) do
			local stat = uv.fs_stat(path)
			if
				stat
				and (
					stat.mtime.sec > built.mtime.sec
					or (stat.mtime.sec == built.mtime.sec and stat.mtime.nsec > built.mtime.nsec)
				)
			then
				result.deployment = "possibly_stale"
				result.advice =
					"Schema/global patch YAML is newer than the compiled schema; run :RimeDeploy explicitly."
				break
			end
		end
	end
	return result
end
return M
