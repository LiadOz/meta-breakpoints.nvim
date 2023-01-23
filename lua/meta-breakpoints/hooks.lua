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


return M
