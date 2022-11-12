local M = {}


local breakpoints = require('meta-breakpoints.breakpoint_base')
local persistent = require('meta-breakpoints.persistent_bp')
M.toggle_meta_breakpoint = breakpoints.toggle_meta_breakpoint
M.simple_meta_breakpoint = breakpoints.simple_meta_breakpoint
M.toggle_hook_breakpoint = breakpoints.toggle_hook_breakpoint
M.load_persistent_breakpoints = breakpoints.load_persistent_breakpoints


local function setup_opts(opts)
    opts.meta_breakpoint_sign = opts.meta_breakpoint_sign or 'M'
    opts.hook_breakpoint_sign = opts.hook_breakpoint_sign or 'H'
end

function M.setup(opts)
    setup_opts(opts)
    breakpoints.load_persistent_breakpoints()
    vim.api.nvim_create_autocmd({'BufWritePost'}, {
        pattern = {"*"},
        callback = function() persistent.update_curr_buf_breakpoints(true) end
    })
    vim.fn.sign_define('MetaBreakpoint', { text = opts.meta_breakpoint_sign, texthl = "", linehl = "", numhl = "" })
    vim.fn.sign_define('HookBreakpoint', { text = opts.hook_breakpoint_sign, texthl = "", linehl = "", numhl = "" })
end

return M
