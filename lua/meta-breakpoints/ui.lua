local M = {}
local NEW_HOOK_PROMPT = 'Create new hook: '
local breakpoints = require('meta-breakpoints.breakpoint_base')
local hooks = require('meta-breakpoints.hooks')


local function get_hooks()
  local curr_hooks = {}
  for _, bp in ipairs(breakpoints.get_breakpoints()) do
    local hook_name = bp.meta.hit_hook or nil
    if hook_name and string.sub(hook_name, 0, 8) ~= 'INTERNAL' then
      curr_hooks[hook_name] = true
    end
  end
  for hook_name, _ in pairs(hooks.get_all_hooks()) do
    if string.sub(hook_name, 0, 8) ~= 'INTERNAL' then
      curr_hooks[hook_name] = true
    end
  end
  local result = { NEW_HOOK_PROMPT }
  for hook_name, _ in pairs(curr_hooks) do
    table.insert(result, hook_name)
  end
  return result
end


local function prompt_hit_hook_selection(on_selection)
  vim.ui.select(get_hooks(), {
    prompt = 'Select hook name:',
    kind = 'hook_name'
  }, function(choice)
    if choice == NEW_HOOK_PROMPT then
      vim.ui.input({ prompt = 'Enter new hook name: ' }, function(input)
        on_selection(input)
      end)
    else
      on_selection(choice)
    end
  end)
end


local function should_remove(replace_old)
  if not replace_old and breakpoints.get_breakpoint_at_cursor() then
    return true
  end
  return false
end

function M.toggle_meta_breakpoint(dap_opts, meta_opts, replace_old, prompt_hook)
  meta_opts = meta_opts or {}
  if prompt_hook == nil then
    prompt_hook = false
  end
  -- check if breakpoints exist here if it does you want to only remove it unless replace_old is used
  if should_remove() or (meta_opts and meta_opts.hit_hook) or prompt_hook == false then
    breakpoints.toggle_meta_breakpoint(dap_opts, meta_opts, replace_old)
    return
  end
  prompt_hit_hook_selection(function(selection)
    if not selection then
      return
    end
    if not meta_opts then
      meta_opts = { hit_hook = selection }
    else
      meta_opts.hit_hook = selection
    end
    breakpoints.toggle_meta_breakpoint(dap_opts, meta_opts, replace_old)
  end)
end

function M.toggle_hook_breakpoint(dap_opts, meta_opts, replace_old)
  meta_opts = meta_opts or {}
  if should_remove(replace_old) or meta_opts.trigger_hook then
    if meta_opts.trigger_hook == nil then
      meta_opts.trigger_hook = ''
    end
    breakpoints.toggle_hook_breakpoint(dap_opts, meta_opts, replace_old)
    return
  end
  prompt_hit_hook_selection(function(selection)
    if selection then
      meta_opts.trigger_hook = selection
      breakpoints.toggle_hook_breakpoint(dap_opts, meta_opts, replace_old)
    end
  end)
end

local function treesitter_highlight(lang, input)
  local parser = vim.treesitter.get_string_parser(input, 'python')
  local tree = parser:parse()[1]
  local query = vim.treesitter.query.get(lang, 'highlights')
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
