local M = {}

--- Toggle breakpoint using nvim-dap
---@param dap_opts DapOpts|nil
---@param placement_opts PlacementOpts
function M.toggle_dap_breakpoint(dap_opts, placement_opts)
  local breakpoints = require("dap.breakpoints")
  local opts = vim.deepcopy(dap_opts or {})
  opts.replace = placement_opts.replace
  breakpoints.toggle(opts, placement_opts.bufnr, placement_opts.lnum)
  M.update_dap_breakpoints(placement_opts.bufnr)
end

function M.update_dap_breakpoints(bufnr)
  local dap = require("dap")
  local breakpoints = require("dap.breakpoints")
  local session = dap.session()
  if session then
    local bps = breakpoints.get(bufnr)
    session:set_breakpoints(bps)
  end
end

function M.remove_breakpoint(bufnr, lnum)
  local breakpoints = require("dap.breakpoints")
  local bp = breakpoints.remove(bufnr, lnum)
  M.update_dap_breakpoints(bufnr)
  return bp
end

function M.get_dap_stopped_sign(session)
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    local buffer_signs = vim.fn.sign_getplaced(buffer, { group = session.sign_group })[1].signs
    for _, buffer_sign in pairs(buffer_signs) do
      if buffer_sign.name == "DapStopped" then
        buffer_sign.bufnr = buffer
        return buffer_sign
      end
    end
  end
  return nil
end

function M.raise_dap_stopped_priority(sign)
  vim.fn.sign_place(sign.id, sign.group, "DapStopped", sign.bufnr, { lnum = sign.lnum, priority = 22 })
end

return M
