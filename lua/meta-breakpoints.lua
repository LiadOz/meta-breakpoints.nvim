local M = {}

local breakpoints = require("meta-breakpoints.breakpoints.collection")
local config = require("meta-breakpoints.config")
local hooks = require("meta-breakpoints.hooks")
local ui = require("meta-breakpoints.ui")
local log = require("meta-breakpoints.log")
M.toggle_breakpoint = ui.toggle_breakpoint
M.put_conditional_breakpoint = ui.put_conditional_breakpoint
M.get_all_breakpoints = breakpoints.get_breakpoints
M.get_all_hooks = hooks.get_all_hooks
M.toggle_breakpoint_state = ui.toggle_breakpoint_state

function M.setup(opts)
  config.setup_opts(opts)
  local augroup = vim.api.nvim_create_augroup("MetaBreakpoints", {})
  if config.persistent_breakpoints.enabled then
    if config.persistent_breakpoints.load_breakpoints_on_setup then
      breakpoints.load_persistent_breakpoints()
    end
    if config.persistent_breakpoints.load_breakpoints_on_buf_enter then
      vim.api.nvim_create_autocmd({ "BufEnter" }, {
        group = augroup,
        pattern = { "*" },
        callback = function(ev)
          breakpoints.ensure_persistent_breakpoints(ev.buf)
        end,
      })
    end
    if config.persistent_breakpoints.save_breakpoints_on_buf_write then
      vim.api.nvim_create_autocmd({ "BufWritePost" }, {
        group = augroup,
        pattern = { "*" },
        callback = function()
          breakpoints.update_buf_breakpoints(0, true)
        end,
      })
    end
    for breakpoint_type, breakpoint_signs in pairs(config.signs) do
      vim.fn.sign_undefine({ breakpoint_type, breakpoint_type .. "Disabled" })
      vim.fn.sign_define(breakpoint_type, breakpoint_signs.enabled)
      vim.fn.sign_define(breakpoint_type .. "Disabled", breakpoint_signs.disabled or breakpoint_signs.enabled)
    end
    log:set_level(config.log.level)
  end
end

return M
