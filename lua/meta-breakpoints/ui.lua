local M = {}
local NEW_HOOK_PROMPT = 'Create new hook: '
local breakpoints = require('meta-breakpoints.breakpoint_base')
local hooks = require('meta-breakpoints.hooks')


local function get_hooks()
    local curr_hooks = {}
    for _, bp in ipairs(breakpoints.get_all_breakpoints()) do
        local hook_name = bp.meta.hook_name or nil
        if hook_name and string.sub(hook_name, 0, 8) ~= 'INTERNAL' then
            curr_hooks[hook_name] = true
        end
    end
    for hook_name, _ in pairs(hooks.get_all_hooks()) do
        print(string.sub(hook_name, 0, 8))
        if string.sub(hook_name, 0, 8) ~= 'INTERNAL' then
            curr_hooks[hook_name] = true
        end
    end
    local result = {NEW_HOOK_PROMPT}
    for hook_name, _ in pairs(curr_hooks) do
        table.insert(result, hook_name)
    end
    return result
end


local function prompt_hook_name_selection(on_selection)
    vim.ui.select(get_hooks(), {
        prompt = 'Select hook name:',
        kind = 'hook_name'
    }, function(choice)
        if choice == NEW_HOOK_PROMPT then
            vim.ui.input({prompt = 'Enter new hook name: '}, function(input)
                on_selection(input)
            end)
        else
            on_selection(choice)
        end
    end)
end


local function should_remove(replace_old)
    if not replace_old and breakpoints.get_breakpoint() then
        return true
    end
    return false
end

function M.toggle_meta_breakpoint(bp_opts, replace_old, prompt_hook)
    bp_opts = bp_opts or {}
    if prompt_hook == nil then
        prompt_hook = false
    end
    -- check if breakpoitns exist here if it does you want to only remove it unless replace_old is used
    if should_remove() or (bp_opts.meta and bp_opts.meta.hook_name) or prompt_hook == false then
        breakpoints.toggle_meta_breakpoint(bp_opts, replace_old)
        return
    end
    prompt_hook_name_selection(function(selection)
        if not bp_opts.meta then
            bp_opts.meta = {hook_name = selection}
        else
            bp_opts.meta.hook_name = selection
        end
        breakpoints.toggle_meta_breakpoint(bp_opts, replace_old)
    end)
end


function M.toggle_hook_breakpoint(bp_opts, replace_old)
    bp_opts = bp_opts or {}
    local meta_opts = bp_opts.meta or {}
    if should_remove(replace_old) or meta_opts.trigger_hook then
        if meta_opts.trigger_hook == nil then
            meta_opts.trigger_hook = ''
        end
        bp_opts.meta = meta_opts
        breakpoints.toggle_hook_breakpoint(bp_opts, replace_old)
        return
    end
    prompt_hook_name_selection(function(selection)
        if selection then
            meta_opts.trigger_hook = selection
            bp_opts.meta = meta_opts
            breakpoints.toggle_hook_breakpoint(bp_opts, replace_old)
        end
    end)
end

local function treesitter_highlight(lang, input)
  local parser = vim.treesitter.get_string_parser(input, 'python')
  local tree = parser:parse()[1]
  local query = vim.treesitter.query.get('python', 'highlights')
  local highlights = {}
  for id, node, _ in query:iter_captures(tree:root(), input) do
    local _, cstart, _ , cend = node:range()
    table.insert(highlights, { cstart, cend, "@" .. query.captures[id] })
  end
  return highlights
end

function M.put_conditional_breakpoint(bp_opts, replace_old)
  bp_opts = bp_opts or {}
  if bp_opts.condition ~= nil then
    M.toggle_meta_breakpoint(bp_opts, replace_old)
    return
  end
  vim.ui.input({prompt = "Enter condition: ", highlight = function(input)
    return treesitter_highlight(vim.bo.filetype, input)
  end}, function(result)
    if not result then
      return
    end
    bp_opts.condition = result
    M.toggle_meta_breakpoint(bp_opts, replace_old)
  end)
end


return M
