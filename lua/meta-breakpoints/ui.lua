local M = {}
local NEW_HOOK_PROMPT = "Create new hook: "
local breakpoints = require("meta-breakpoints.breakpoints.collection")
local persistence = require("meta-breakpoints.persistence")
local hooks = require("meta-breakpoints.hooks")

local function get_breakpoint_hooks()
  local curr_hooks = {}
  for _, bp in ipairs(breakpoints.get_breakpoints()) do
    local hook_name = bp.meta_opts.hit_hook or nil
    if hook_name then
      curr_hooks[hook_name] = true
    end
  end
  for _, persistent_breakpoints in pairs(persistence.get_persistent_breakpoints()) do
    for _, pb in pairs(persistent_breakpoints) do
      if pb.meta_opts.hit_hook then
        curr_hooks[pb.meta_opts.hit_hook] = true
      end
    end
  end
  for hook_name, _ in pairs(hooks.get_all_hooks()) do
    curr_hooks[hook_name] = true
  end

  local result = {}
  for hook_name, _ in pairs(curr_hooks) do
    if string.sub(hook_name, 0, 1) ~= "_" then
      table.insert(result, hook_name)
    end
  end
  return result
end

local function prompt_hit_hook_selection(on_selection)
  local hook_names = get_breakpoint_hooks()
  table.insert(hook_names, 1, NEW_HOOK_PROMPT)
  vim.ui.select(hook_names, {
    prompt = "Select hook name:",
    kind = "hook_name",
  }, function(choice)
    if choice == NEW_HOOK_PROMPT then
      vim.ui.input({ prompt = "Enter new hook name: " }, function(input)
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

function M.toggle_meta_breakpoint(persistent, replace_old, breakpoint_opts, prompt_hook)
  breakpoint_opts = breakpoint_opts or {}
  breakpoint_opts.meta_opts = breakpoint_opts.meta_opts or {}
  local meta_opts = breakpoint_opts.meta_opts
  if prompt_hook == nil then
    prompt_hook = false
  end
  -- check if breakpoints exist here if it does you want to only remove it unless replace_old is used
  if should_remove() or (meta_opts and meta_opts.hit_hook) or prompt_hook == false then
    breakpoints.toggle_meta_breakpoint({replace = replace_old, persistent = persistent}, breakpoint_opts)
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
    breakpoints.toggle_meta_breakpoint({replace = replace_old, persistent = persistent}, breakpoint_opts)
  end)
end

function M.toggle_hook_breakpoint(persistent, replace_old, breakpoint_opts)
  breakpoint_opts = breakpoint_opts or {}
  breakpoint_opts.meta_opts = breakpoint_opts.meta_opts or {}
  local meta_opts = breakpoint_opts.meta_opts
  if should_remove(replace_old) or meta_opts.trigger_hook then
    if meta_opts.trigger_hook == nil then
      meta_opts.trigger_hook = ""
    end
    breakpoints.toggle_hook_breakpoint({replace = replace_old, persistent = persistent}, breakpoint_opts)
    return
  end
  prompt_hit_hook_selection(function(selection)
    if selection then
      meta_opts.trigger_hook = selection
      breakpoints.toggle_hook_breakpoint({replace = replace_old, persistent = persistent}, breakpoint_opts)
    end
  end)
end

local function treesitter_highlight(lang, input)
  local parser = vim.treesitter.get_string_parser(input, lang)
  local tree = parser:parse()[1]
  local query = vim.treesitter.query.get(lang, "highlights")
  local highlights = {}
  if query then
    for id, node, _ in query:iter_captures(tree:root(), input, 0, -1) do
      local _, cstart, _, cend = node:range()
      table.insert(highlights, { cstart, cend, "@" .. query.captures[id] })
    end
  end
  return highlights
end

function M.put_conditional_breakpoint(bp_opts, replace_old)
  bp_opts = bp_opts or {}
  local lang = vim.bo.filetype
  if bp_opts.condition ~= nil then
    M.toggle_meta_breakpoint(bp_opts, replace_old)
    return
  end
  vim.ui.input({
    prompt = "Enter condition: ",
    highlight = function(input)
      return treesitter_highlight(lang, input)
    end,
  }, function(result)
    if not result then
      return
    end
    bp_opts.condition = result
    M.toggle_meta_breakpoint(bp_opts, replace_old)
  end)
end

return M
