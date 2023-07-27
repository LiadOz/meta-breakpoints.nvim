local M = {}

local breakpoints = require('meta-breakpoints.breakpoint_base')
local persistence = require('meta-breakpoints.persistence')
local config = require('meta-breakpoints.config')
local hooks = require('meta-breakpoints.hooks')
local ui = require('meta-breakpoints.ui')
M.toggle_meta_breakpoint = ui.toggle_meta_breakpoint
M.toggle_hook_breakpoint = ui.toggle_hook_breakpoint
M.put_conditional_breakpoint = ui.put_conditional_breakpoint
M.get_all_breakpoints = breakpoints.get_all_breakpoints
M.load_persistent_breakpoints = breakpoints.load_persistent_breakpoints
M.get_all_hooks = hooks.get_all_hooks


function M.setup(opts)
  config.setup_opts(opts)
  if config.persistent_breakpoints.enabled then
    if config.persistent_breakpoints.load_breakpoints_on_setup then
      breakpoints.load_persistent_breakpoints(function() end, {all_buffers = true})
    end
    if config.persistent_breakpoints.save_breakpoints_on_buf_write then
      vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
        pattern = { "*" },
        callback = function() breakpoints.update_buf_breakpoints(nil, true) end
      })
    end
  end
  vim.fn.sign_define('MetaBreakpoint', { text = config.signs.meta_breakpoint_sign, texthl = "", linehl = "", numhl = "" })
  vim.fn.sign_define('HookBreakpoint', { text = config.signs.hook_breakpoint_sign, texthl = "", linehl = "", numhl = "" })
end

return M
