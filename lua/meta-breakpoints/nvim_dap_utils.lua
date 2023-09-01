local M = {}

--- Toggle breakpoint using nvim-dap
---@param dap_opts DapOpts|nil
---@param placement_opts DapPlacementOpts
function M.toggle_dap_breakpoint(dap_opts, placement_opts)
  local breakpoints = require('dap.breakpoints')
  local opts = vim.deepcopy(dap_opts or {})
  opts.replace = placement_opts.replace
  breakpoints.toggle(opts, placement_opts.bufnr, placement_opts.lnum)
  local session = require('dap').session()
  if session then
    local bps = breakpoints.get(placement_opts.bufnr)
    session:set_breakpoints(bps)
  end
end

function M.remove_breakpoint(bufnr, lnum)
  local breakpoints = require('dap.breakpoints')
  return breakpoints.remove(bufnr, lnum)
end

return M
