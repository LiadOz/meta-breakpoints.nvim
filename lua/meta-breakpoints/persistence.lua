local M = {}

---@alias PersistentBreakpointFileData {type: string, lnum: number, opts: table}
---@alias PersistentBreakpointsTable table<string, PersistentBreakpointFileData[]>

---@type table<string, MetaBreakpoint[]>
local persistent_breakpoints = {}

---@type table<string, table>
local saved_breakpoints_data = {}

local utils = require("meta-breakpoints.utils")
local breakpoint_factory = require("meta-breakpoints.breakpoints").breakpoint_factory

---@param breakpoints MetaBreakpoint[]|nil
---@return table|nil
local function get_breakpoints_save_data(breakpoints)
  local data = {}
  if breakpoints == nil then
    data = nil
  else
    for _, bp in ipairs(breakpoints) do
      local bp_data = vim.deepcopy(bp:get_persistent_data())
      bp_data.file_name = nil
      bp_data.type = bp.get_type()
      table.insert(data, bp_data)
    end
  end
  return data
end

---@param file_name string
---@param breakpoints_data table[]|nil
local function save_file_breakpoints(file_name, breakpoints_data, callback)
  saved_breakpoints_data[file_name] = breakpoints_data
  utils.read_breakpoints(function(files_data)
    files_data[file_name] = breakpoints_data
    utils.save_breakpoints(files_data, callback)
  end)
end

--- Asynchronously get persistent breakpoints
---@param callback fun(breakpoints: PersistentBreakpointsTable)|nil
function M.load_persistent_breakpoints(callback)
  persistent_breakpoints = {}
  utils.read_breakpoints(function(files_data)
    for file_name, breakpoints_data in pairs(files_data) do
      if #breakpoints_data > 0 then
        local breakpoints = {}
        for _, breakpoint_data in pairs(breakpoints_data) do
          local opts = { file_name = file_name, lnum = breakpoint_data.lnum, opts = breakpoint_data.opts }
          table.insert(breakpoints, breakpoint_factory(breakpoint_data.type, opts))
        end
        persistent_breakpoints[file_name] = breakpoints
      end
    end
    if callback then
      callback(persistent_breakpoints)
    end
  end)
end

---@param file_name string
---@param breakpoints Breakpoint[]|nil
---@param update_file boolean
---@param override_changed boolean still update file if detected no change
---@param callback fun()|nil
function M.update_file_breakpoints(file_name, breakpoints, update_file, override_changed, callback)
  override_changed = override_changed or false
  local breakpoints_data = get_breakpoints_save_data(breakpoints)
  local changed = not vim.deep_equal(breakpoints_data, saved_breakpoints_data[file_name])

  persistent_breakpoints[file_name] = breakpoints
  if update_file and (changed or override_changed) then
    save_file_breakpoints(file_name, breakpoints_data, callback)
  else
    if callback then
      vim.schedule(callback)
    end
  end
end

function M.clear(callback)
  persistent_breakpoints = {}
  utils.save_breakpoints(persistent_breakpoints, callback)
end

function M.get_persistent_breakpoints()
  return persistent_breakpoints
end

return M
