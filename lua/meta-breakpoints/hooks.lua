local M = {}

local log = require("meta-breakpoints.log")

local hooks_mapping = {}
local next_hook_id = 0

--- Register a function to a hook
---@param hook_name string hook name to register to, hook names starting with _ are used for internal purposes
---@param hook_function function
---@return number hook_id id that can be used to remove the function from this hook
function M.register_to_hook(hook_name, hook_function)
  log.fmt_trace("Registering function to hook %s", hook_name)
  if not hooks_mapping[hook_name] then
    hooks_mapping[hook_name] = {}
  end
  local hook_id = next_hook_id
  hooks_mapping[hook_name][hook_id] = hook_function
  next_hook_id = next_hook_id + 1
  return hook_id
end

function M.remove_hook(hook_name, hook_id)
  if hook_id then
    hooks_mapping[hook_name][hook_id] = nil
    local item_count = 0
    for _, _ in ipairs(hooks_mapping[hook_name]) do
      item_count = item_count + 1
    end
    if item_count == 0 then
      hooks_mapping[hook_name] = nil
    end
  else
    hooks_mapping[hook_name] = nil
  end
end

function M.get_hooks_mapping(hook_name)
  return hooks_mapping[hook_name] or {}
end

function M.get_all_hooks()
  return hooks_mapping
end

function M.clear_hooks()
  hooks_mapping = {}
end

return M
