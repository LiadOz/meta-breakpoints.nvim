local paths = { "~/projects/nvim_plugins/nvim-dap" }
for _, path in pairs(paths) do
  vim.opt.rtp:prepend(path)
end
require("dap")
