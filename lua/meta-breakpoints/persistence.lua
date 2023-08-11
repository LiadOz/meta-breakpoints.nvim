local M = {}

---@alias PersistentBreakpointFileData {lnum: number, dap_opts: DapOpts, meta_opts: MetaOpts}
---@alias PersistentBreakpointsTable table<string, PersistentBreakpointFileData[]>

---@type PersistentBreakpointsTable
local persistent_breakpoints = {}

local utils = require("meta-breakpoints.utils")

local function save_file_breakpoints(file_name, breakpoints, callback)
  utils.read_breakpoints(function(files_data)
    files_data[file_name] = breakpoints
    utils.save_breakpoints(files_data, callback)
  end)
end

--- Asynchronously get persistent breakpoints
---@param callback fun(breakpoints: PersistentBreakpointsTable)
function M.read_persistent_breakpoints(callback)
  persistent_breakpoints = {}
  utils.read_breakpoints(function(files_data)
    for file_name, breakpoints_data in pairs(files_data) do
      if #breakpoints_data > 0 then
        persistent_breakpoints[file_name] = breakpoints_data
      end
    end
    if callback then
      callback(persistent_breakpoints)
    end
  end)
end

local log = require("meta-breakpoints.log")
---@param file_name string
---@param breakpoints_data PersistentBreakpointFileData[]|nil
---@param update_file boolean
---@param override_changed boolean still update file if the breakpoints have been already updated
---@param callback fun()|nil
function M.update_file_breakpoints(file_name, breakpoints_data, update_file, override_changed, callback)
  override_changed = override_changed or false
  local changed = not vim.deep_equal(breakpoints_data, persistent_breakpoints[file_name])

  persistent_breakpoints[file_name] = breakpoints_data
  if update_file and (changed or override_changed) then
    save_file_breakpoints(file_name, breakpoints_data, callback)
  else
    if callback then
      vim.schedule(callback)
    end
  end
end

function M.clear(callback)
  for key, _ in pairs(persistent_breakpoints) do
    persistent_breakpoints[key] = nil
  end
  utils.save_breakpoints(persistent_breakpoints, callback)
end

function M.get_persistent_breakpoints()
  return persistent_breakpoints
end

return M
