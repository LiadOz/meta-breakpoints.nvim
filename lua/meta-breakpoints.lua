local M = {}


local breakpoints = require('meta-breakpoints.breakpoint_base')
M.toggle_meta_breakpoint = breakpoints.simple_meta_breakpoint
M.toggle_hook_breakpoint = breakpoints.toggle_hook_breakpoint


local function setup_opts(opts)
    opts.meta_breakpoint_sign = opts.meta_breakpoint_sign or 'M'
    opts.hook_breakpoint_sign = opts.hook_breakpoint_sign or 'H'
end

function M.setup(opts)
    setup_opts(opts)
    vim.fn.sign_define('MetaBreakpoint', { text = opts.meta_breakpoint_sign, texthl = "", linehl = "", numhl = "" })
    vim.fn.sign_define('HookBreakpoint', { text = opts.hook_breakpoint_sign, texthl = "", linehl = "", numhl = "" })
end

return M
