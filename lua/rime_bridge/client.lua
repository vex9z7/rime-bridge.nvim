-- One outstanding request, bounded framing and timeout. No editor behavior here.
local M = {}
function M.start(executable, on_error)
	local c = { queue = {}, id = 0, partial = "", closed = false }
	c.diagnostics = require("rime_bridge.diagnostics").new()
	local function fail(reason)
		if c.closed then
			return
		end
		c.closed = true
		c.diagnostics.clear()
		vim.fn.jobstop(c.job)
		on_error(reason)
	end
	local pump
	pump = function()
		if c.closed or c.pending or #c.queue == 0 then
			return
		end
		local item = table.remove(c.queue, 1)
		c.id = c.id + 1
		item.request.id = c.id
		c.pending = item
		local sent = vim.fn.chansend(c.job, vim.json.encode(item.request) .. "\n")
		if sent <= 0 then
			fail("Cannot write to Rime worker")
			return
		end
		vim.defer_fn(function()
			if c.pending == item then
				fail("Rime worker timeout; pending input was not replayed")
			end
		end, item.request.op == "deploy" and 60000 or 5000)
	end
	local function receive(line)
		if c.closed then
			return
		end
		local ok, r = pcall(vim.json.decode, line)
		local p = c.pending
		if
			not ok
			or type(r) ~= "table"
			or not p
			or r.id ~= p.request.id
			or r.generation ~= p.request.generation
			or type(r.ok) ~= "boolean"
		then
			fail("Invalid Rime worker response")
			return
		end
		c.pending = nil
		if not r.ok then
			fail("Rime worker: " .. tostring(r.error))
			return
		end
		local called = pcall(p.callback, r.result)
		if not called then
			fail("Rime response callback failed; ordinary editing restored")
			return
		end
		pump()
	end
	c.job = vim.fn.jobstart({ executable }, {
		env = { LD_LIBRARY_PATH = "", LD_PRELOAD = "", RIME_PLUGINS_DIR = "" },
		on_stdout = function(_, data)
			vim.schedule(function()
				for i, chunk in ipairs(data) do
					c.partial = c.partial .. chunk
					if #c.partial > 65536 then
						fail("Rime response exceeds 64 KiB")
						return
					end
					if i < #data then
						local line = c.partial
						c.partial = ""
						receive(line)
					end
				end
			end)
		end,
		on_stderr = function(_, data)
			c.diagnostics.feed(data)
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				fail("Rime worker exited (" .. code .. "); pending input was not replayed")
			end)
		end,
	})
	assert(c.job > 0, "Cannot start Rime worker: " .. executable)
	function c:request(op, generation, args, callback)
		if self.closed then
			return
		end
		args = args or {}
		args.op, args.generation = op, generation
		self.queue[#self.queue + 1] = { request = args, callback = callback or function() end }
		pump()
	end
	function c:cancel_queued()
		self.queue = {}
	end
	function c:close()
		if self.closed then
			return
		end
		self.closed = true
		self.diagnostics.clear()
		self.queue = {}
		self.pending = nil
		-- EOF finalizes the engine, flushing learning data and releasing the lock.
		pcall(vim.fn.chanclose, self.job, "stdin")
		vim.defer_fn(function()
			if vim.fn.jobwait({ self.job }, 0)[1] == -1 then
				vim.fn.jobstop(self.job)
			end
		end, 2000)
	end
	return c
end
return M
