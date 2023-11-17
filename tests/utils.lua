local M = {}

local dap_bps = require("dap.breakpoints")
local persistence = require("meta-breakpoints.persistence")

function M.clear_persistent_breakpoints()
  local co = coroutine.running()
  persistence.clear(function()
    coroutine.resume(co)
  end)
  coroutine.yield()
end

function M.get_dap_breakpoints()
  local breakpoints = dap_bps.get()
  local result = {}
  for bufnr, buf_bps in pairs(breakpoints) do
    for _, bp_data in ipairs(buf_bps) do
      table.insert(result, { bufnr, bp_data.line })
    end
  end
  table.sort(result, function(a, b)
    return a[1] < b[1]
  end)
  return result
end

return M
