-- Blink's public source/configuration API only. No private completion state edits.
local M = {}
local configured = false
local function session()
	local s = require("rime_bridge")._input()
	if
		s
		and s.ui == "blink"
		and not s.closed
		and s.buf == vim.api.nvim_get_current_buf()
		and vim.api.nvim_get_mode().mode:match("^i")
	then
		return s
	end
end
function M.active()
	return session() ~= nil
end
function M.ready()
	return configured
end
function M.hide()
	local cmp = package.loaded["blink.cmp"]
	if cmp then
		local items = cmp.get_items()
		if M.active() or (items[1] and items[1].source_id == "rime_bridge") then
			cmp.hide()
		end
	end
end
function M.show(s)
	if s.pending ~= 0 or s.context.preedit == "" or #s.context.candidates == 0 then
		return
	end
	local cmp, revision, generation = require("blink.cmp"), s.revision, s.generation
	local selected = s.context.selected + 1
	cmp.show({
		providers = { "rime_bridge" },
		initial_selected_item_idx = selected,
		callback = function()
			vim.schedule(function()
				if session() ~= s or s.revision ~= revision or s.generation ~= generation or s.pending ~= 0 then
					return
				end
				local current = cmp.get_selected_item_idx() or 0
				if selected > current then
					cmp.select_next({ count = selected - current, auto_insert = false })
				elseif selected < current then
					cmp.select_prev({ count = current - selected, auto_insert = false })
				end
			end)
		end,
	})
end
function M.accept()
	local s = session()
	if not s then
		return false
	end
	local item = require("blink.cmp").get_selected_item()
	if item and item.source_id == "rime_bridge" then
		local d = item.data
		return s.select(d.index, d.generation, d.revision, d.instance)
	end
	return false
end

function M.new()
	return setmetatable({}, { __index = M })
end
function M:enabled()
	return M.active()
end
function M:get_completions(ctx, callback)
	local s, items = session(), {}
	if s and s.pending == 0 and s.context.preedit ~= "" then
		for index, candidate in ipairs(s.context.candidates) do
			items[#items + 1] = {
				label = candidate.text,
				labelDetails = { description = candidate.comment },
				kind = 1,
				filterText = ctx.get_keyword(),
				insertText = "",
				sortText = string.format("%05d", index),
				data = { index = index - 1, generation = s.generation, revision = s.revision, instance = s.instance },
			}
		end
	end
	callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
end
function M:execute(_, item, callback)
	local s, d = session(), item.data
	-- Never call Blink's default insertion: only Rime may produce committed text.
	if not s or not d or not s.select(d.index, d.generation, d.revision, d.instance, callback) then
		callback()
	end
end

local function value(v, fallback, ...)
	if v == nil then
		return fallback
	end
	if type(v) == "function" then
		return v(...)
	end
	return v
end

-- Call before blink.cmp.setup; returns an independent options table.
function M.options(opts)
	opts = vim.deepcopy(opts or {})
	opts.sources = opts.sources or {}
	local sources = opts.sources
	local function guarded(list, fallback)
		return function(...)
			if M.active() then
				return { "rime_bridge" }
			end
			return value(list, fallback, ...)
		end
	end
	sources.default = guarded(sources.default, { "lsp", "path", "snippets", "buffer" })
	sources.per_filetype = sources.per_filetype or {}
	for ft, list in pairs(sources.per_filetype) do
		sources.per_filetype[ft] = guarded(list, {})
	end
	sources.providers = sources.providers or {}
	for _, name in ipairs({ "lsp", "path", "snippets", "buffer", "omni" }) do
		sources.providers[name] = sources.providers[name] or {}
	end
	for name, provider in pairs(sources.providers) do
		if name ~= "rime_bridge" then
			local enabled = provider.enabled
			provider.enabled = function(...)
				return not M.active() and value(enabled, true, ...)
			end
		end
	end
	sources.providers.rime_bridge =
		{ name = "Rime", module = "rime_bridge.blink", fallbacks = {}, min_keyword_length = 0 }
	local transform = sources.transform_items
	sources.transform_items = function(ctx, items)
		if M.active() then
			return vim.tbl_filter(function(item)
				return item.source_id == "rime_bridge"
			end, items)
		end
		items = vim.tbl_filter(function(item)
			return item.source_id ~= "rime_bridge"
		end, items)
		return transform and transform(ctx, items) or items
	end
	opts.completion = opts.completion or {}
	local completion = opts.completion
	completion.list = completion.list or {}
	completion.list.selection = completion.list.selection or {}
	local auto = completion.list.selection.auto_insert
	completion.list.selection.auto_insert = function(ctx)
		return not M.active() and value(auto, true, ctx)
	end
	completion.ghost_text = completion.ghost_text or {}
	local ghost = completion.ghost_text.enabled
	completion.ghost_text.enabled = function(ctx)
		return not M.active() and value(ghost, false, ctx)
	end
	opts.fuzzy = opts.fuzzy or {}
	local sorts = opts.fuzzy.sorts or { "score", "sort_text" }
	assert(type(sorts) == "table", "rime_bridge expects a Blink sorts list")
	table.insert(sorts, 1, function(a, b)
		if a.source_id == "rime_bridge" and b.source_id == "rime_bridge" then
			return a.data.index < b.data.index
		end
	end)
	opts.fuzzy.sorts = sorts
	-- Guard explicit accept/snippet mappings; buffer-local Rime mappings own the
	-- ordinary composing keys. Existing custom chains still run outside Rime mode.
	opts.keymap = opts.keymap or {}
	local keys = {
		["<C-y>"] = { "select_and_accept", "fallback" },
		["<C-e>"] = { "cancel", "fallback" },
		["<C-n>"] = { "select_next", "fallback_to_mappings" },
		["<C-p>"] = { "select_prev", "fallback_to_mappings" },
		["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
		["<Up>"] = { "select_prev", "fallback" },
		["<Down>"] = { "select_next", "fallback" },
		["<Tab>"] = { "snippet_forward", "fallback" },
		["<S-Tab>"] = { "snippet_backward", "fallback" },
	}
	local preset = opts.keymap.preset or "default"
	assert(
		preset == "default" or preset == "enter" or preset == "super-tab" or preset == "none",
		"Unsupported Blink preset"
	)
	if preset == "none" then
		for lhs in pairs(keys) do
			keys[lhs] = { "fallback" }
		end
	elseif preset == "enter" then
		keys["<CR>"] = { "accept", "fallback" }
		keys["<C-y>"] = { "fallback" }
	elseif preset == "super-tab" then
		keys["<C-y>"] = { "fallback" }
		keys["<Tab>"] = {
			function(cmp)
				if cmp.snippet_active() then
					return cmp.accept()
				end
				return cmp.select_and_accept()
			end,
			"snippet_forward",
			"fallback",
		}
	end
	for lhs, chain in pairs(opts.keymap) do
		if type(chain) == "table" then
			keys[lhs] = chain
		end
	end
	for lhs, chain in pairs(keys) do
		if opts.keymap[lhs] == nil or type(opts.keymap[lhs]) == "table" then
			local key = lhs
			local wrapped = {
				function()
					if not M.active() then
						return
					end
					if key == "<Tab>" or key == "<S-Tab>" or key == "<Up>" or key == "<Down>" then
						local s = session()
						if s then
							s.cancel(true)
						end
						return vim.api.nvim_replace_termcodes(key, true, false, true)
					end
					if key == "<CR>" then
						if not M.accept() then
							local s = session()
							if s and (s.pending > 0 or s.context.preedit ~= "") then
								s.key(32, "\n")
							else
								return "\r"
							end
						end
					end
					if key == "<C-n>" or key == "<C-p>" then
						local s = session()
						if s and s.context.preedit ~= "" then
							s.key(key == "<C-n>" and 0xff54 or 0xff52, "")
						end
					end
					if key == "<C-e>" then
						local s = session()
						if s then
							s.cancel(true)
						end
					end
					if key == "<C-y>" then
						M.accept()
					end
					if key == "<C-space>" then
						local s = session()
						if s then
							M.show(s)
						end
					end
					return true
				end,
			}
			vim.list_extend(wrapped, chain)
			opts.keymap[lhs] = wrapped
		end
	end
	configured = true
	return opts
end
return M
