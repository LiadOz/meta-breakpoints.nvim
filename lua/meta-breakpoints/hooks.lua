local M = {}

local hooks_mapping = {}


function M.register_to_hook(hook_name, hook_id, hook_function)
    if not hooks_mapping[hook_name] then
        hooks_mapping[hook_name] = {}
    end
    hooks_mapping[hook_name][hook_id] = hook_function
end


function M.remove_hook(hook_name, hook_id)
    if hook_id then
        hooks_mapping[hook_name][hook_id] = nil
    else
        hooks_mapping[hook_name] = nil
    end
end


function M.get_hooks_mapping(hook_name)
    return hooks_mapping[hook_name] or {}
end


return M
