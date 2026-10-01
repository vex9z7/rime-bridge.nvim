-- Uses the Minuet fork's public predicates/actions. Requires late-result gating.
local M = {}
function M.allowed()
	local plugin = package.loaded.rime_bridge
	return not plugin or not plugin.is_active()
end
function M.options(opts)
	opts = vim.deepcopy(opts or {})
	opts.enable_predicates = opts.enable_predicates or {}
	table.insert(opts.enable_predicates, M.allowed)
	return opts
end
function M.dismiss()
	local vt = package.loaded["minuet.virtualtext"]
	if vt then
		vt.action.dismiss()
	end
end
return M
