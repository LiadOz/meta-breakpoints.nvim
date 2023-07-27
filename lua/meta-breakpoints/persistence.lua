local M = {}

---@alias PersistentBreakpointFileData {lnum: string, meta_opts: MetaOpts}
---@type table<string, PersistentBreakpointFileData[]>
local persistent_breakpoints = {}

local utils = require('meta-breakpoints.utils')

local function save_breakpoints(breakpoints, callback)
  utils.save_breakpoints(breakpoints, callback)
end

--- Asynchronously get persistent breakpoints
---@param per_bp_callback fun(filename: string, lnum: number, meta_opts: MetaOpts)
---@param callback fun()
function M.get_persistent_breakpoints(per_bp_callback, callback)
  persistent_breakpoints = {}
  utils.read_breakpoints(function(files_data)
    for file_name, breakpoints_data in pairs(files_data) do
      local saved_breakpoints = {}
      for _, breakpoint_data in ipairs(breakpoints_data) do
        table.insert(saved_breakpoints, breakpoint_data)
        pcall(per_bp_callback, file_name, breakpoint_data.lnum, breakpoint_data.meta_opts)
      end
      if #saved_breakpoints then
        persistent_breakpoints[file_name] = saved_breakpoints
      end
    end
    if callback then
      callback()
    end
  end)
end

---@param file_name string
---@param breakpoints_data PersistentBreakpointFileData[]
---@param update_file boolean
---@param callback fun()|nil
function M.update_file_breakpoints(file_name, breakpoints_data, update_file, callback)
  persistent_breakpoints[file_name] = breakpoints_data
  if #breakpoints_data == 0 then
    persistent_breakpoints[file_name] = nil
  end
  if update_file then
    save_breakpoints(persistent_breakpoints, callback)
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
  save_breakpoints(persistent_breakpoints, callback)
end

return M
