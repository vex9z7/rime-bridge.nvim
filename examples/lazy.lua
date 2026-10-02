-- Copy into your lazy.nvim/LazyVim plugins directory; merge with existing Blink
-- options rather than calling Blink setup twice. Prepare scheme data separately.
return {
	{
		"vex9z7/rime-bridge.nvim",
		main = "rime_bridge",
		lazy = false,
		build = "cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF && cmake --build build --parallel 2",
		opts = { ui = "blink" },
		keys = { { "<leader>uR", "<cmd>RimeToggle<cr>", desc = "Toggle Chinese input (Rime)" } },
	},
	{
		"saghen/blink.cmp",
		version = "v1.10.2",
		dependencies = { "vex9z7/rime-bridge.nvim" },
		opts = function(_, opts)
			-- Avoid requiring a separately downloaded native matcher for this example.
			opts.fuzzy = vim.tbl_extend("force", opts.fuzzy or {}, { implementation = "lua" })
			return require("rime_bridge.blink").options(opts)
		end,
	},
}
