local M = {}


local breakpoints = require('meta-breakpoints.breakpoint_base')
local persistent = require('meta-breakpoints.persistent_bp')
local hooks = require('meta-breakpoints.hooks')
local ui = require('meta-breakpoints.ui')
M.toggle_meta_breakpoint = ui.toggle_meta_breakpoint
M.toggle_hook_breakpoint = ui.toggle_hook_breakpoint
M.put_conditional_breakpoint = ui.put_conditional_breakpoint
M.get_all_breakpoints = breakpoints.get_all_breakpoints
M.load_persistent_breakpoints = breakpoints.load_persistent_breakpoints
M.get_all_hooks = hooks.get_all_hooks


local function setup_opts(opts)
    opts.meta_breakpoint_sign = opts.meta_breakpoint_sign or 'M'
    opts.hook_breakpoint_sign = opts.hook_breakpoint_sign or 'H'
    opts.allow_persistent_breakpoints = opts or true
end

function M.setup(opts)
    setup_opts(opts)
    if opts.allow_persistent_breakpoints then
      breakpoints.load_persistent_breakpoints()
      vim.api.nvim_create_autocmd({'BufWritePost'}, {
          pattern = {"*"},
          callback = function() persistent.update_curr_buf_breakpoints(true) end
      })
      end
    vim.fn.sign_define('MetaBreakpoint', { text = opts.meta_breakpoint_sign, texthl = "", linehl = "", numhl = "" })
    vim.fn.sign_define('HookBreakpoint', { text = opts.hook_breakpoint_sign, texthl = "", linehl = "", numhl = "" })
end

return M
