local M = {}

local log = require("meta-breakpoints.log")

---@type table<string, { id: number, priority: number, func: function }[]>
local hooks_mapping = {}
local next_hook_id = 0

--- Register a function to a hook
---@param hook_name string hook name to register to, hook names starting with _ are used for internal purposes
---@param hook_function function
---@param priority number|nil priority of the hook function, default value is 100
---@return number hook_id id that can be used to remove the function from this hook
function M.register_to_hook(hook_name, hook_function, priority)
  priority = priority or 100
  log.fmt_trace("Registering function to hook %s", hook_name)
  local hook_id = next_hook_id
  if not hooks_mapping[hook_name] then
    hooks_mapping[hook_name] = { { id = hook_id, priority = priority, func = hook_function } }
  else
    table.insert(hooks_mapping[hook_name], { id = hook_id, priority = priority, func = hook_function })
    table.sort(hooks_mapping[hook_name], function(a, b)
      return a.priority > b.priority
    end)
  end
  next_hook_id = next_hook_id + 1
  return hook_id
end

function M.remove_hook(hook_name, hook_id)
  if hook_id then
    hooks_mapping[hook_name] = vim.tbl_filter(function(hook_data)
      return hook_data.id ~= hook_id
    end, hooks_mapping[hook_name])
    if #hooks_mapping[hook_name] == 0 then
      hooks_mapping[hook_name] = nil
    end
  else
    hooks_mapping[hook_name] = nil
  end
end

---@param hook_name string
---@return function[] functions registered to hook name
function M.get_hooks_mapping(hook_name)
  return vim.tbl_map(function(hook_data)
    return hook_data.func
  end, hooks_mapping[hook_name] or {})
end

function M.get_all_hooks()
  return hooks_mapping
end

function M.clear_hooks()
  hooks_mapping = {}
end

return M
