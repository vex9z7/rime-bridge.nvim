-- Retain only fixed diagnostic categories, never engine text or typed content.
local M = {}
function M.new()
	local seen, tail = {}, ""
	local messages = {
		runtime = "System runtime dependency could not load; rebuild locally and check system librime/Lua packages.",
		lua = "Lua extension/script error; check installed extension compatibility and the scheme's Lua files.",
		component = "Rime component could not load; check scheme requirements against installed engine/extensions.",
		schema = "Rime configuration error; check YAML/schema files and explicitly run RimeDeploy after correcting them.",
		dictionary = "Rime dictionary/data error; check scheme dictionary and conversion data, then deploy.",
		engine = "Engine wrote diagnostics; raw stderr is discarded for privacy. Verify scheme files and actual candidates.",
	}
	return {
		feed = function(data)
			for i, chunk in ipairs(data) do
				-- Bounded transient window also recognizes split stderr lines.
				local text = (tail .. chunk:sub(1, 4096)):lower()
				if text ~= "" then
					seen.engine = true
				end
				if
					text:find("shared libraries", 1, true)
					or text:find("symbol lookup error", 1, true)
					or text:find("version", 1, true) and text:find("not found", 1, true)
				then
					seen.runtime = true
				end
				if text:find("lua", 1, true) then
					seen.lua = true
				end
				if text:find("component", 1, true) then
					seen.component = true
				end
				if text:find("yaml", 1, true) or text:find("schema", 1, true) then
					seen.schema = true
				end
				if text:find("dictionary", 1, true) or text:find("opencc", 1, true) then
					seen.dictionary = true
				end
				tail = i == #data and text:sub(-4096) or ""
			end
		end,
		snapshot = function()
			local result = {}
			for _, kind in ipairs({ "runtime", "lua", "component", "schema", "dictionary", "engine" }) do
				if seen[kind] then
					result[#result + 1] = messages[kind]
				end
			end
			return result
		end,
		clear = function()
			tail = ""
		end,
	}
end
return M
