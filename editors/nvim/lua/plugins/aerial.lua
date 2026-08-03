-- Symbol/function outline (VS Code "Outline" feel), navigable, LSP-backed.
-- Complements Telescope symbol fuzzy-jump (<leader>ss / <leader>sS).
return {
  {
    "stevearc/aerial.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      backends = { "lsp", "treesitter", "markdown" },
      layout = { default_direction = "right", min_width = 30 },
    },
    keys = {
      { "<leader>cs", "<cmd>AerialToggle!<cr>", desc = "Symbols outline (aerial)" },
    },
  },
}
