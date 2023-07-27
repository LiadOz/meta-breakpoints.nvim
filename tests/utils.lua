local M = {}

local persistence = require('meta-breakpoints.persistence')

function M.clear_persistent_breakpoints()
  local co = coroutine.running()
  persistence.clear(function()
    coroutine.resume(co)
  end)
  coroutine.yield()
end

return M
