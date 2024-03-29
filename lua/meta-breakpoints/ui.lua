local M = {}
local NEW_HOOK_PROMPT = "Create new hook: "
local base = require("meta-breakpoints.breakpoints.base")
local breakpoints = require("meta-breakpoints.breakpoints.collection")
local persistence = require("meta-breakpoints.persistence")
local hooks = require("meta-breakpoints.hooks")
local config = require("meta-breakpoints.config")

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

local function prompt_hook_selection(on_selection)
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

---@alias UiSelectionOpts {prompt_field: string, prompt_if_missing: table<string, string>}

---@param breakpoint_type string
---@param selection_opts UiSelectionOpts
---@return string|nil prompt_field
local function determine_prompt_field(breakpoint_type, selection_opts)
  if selection_opts.prompt_field then
    return selection_opts.prompt_field
  elseif selection_opts.prompt_if_missing and selection_opts.prompt_if_missing[breakpoint_type] then
    return selection_opts.prompt_if_missing[breakpoint_type]
  end
  return config.ui.prompt_if_missing[breakpoint_type] or nil
end

---@param breakpoint_type string
---@param placement_opts PlacementOpts
---@param breakpoint_opts {dap_opts: DapOpts, meta_opts: MetaOpts}
---@param selection_opts UiSelectionOpts|nil
local function toggle_breakpoint(breakpoint_type, placement_opts, breakpoint_opts, selection_opts)
  breakpoint_opts.meta_opts = breakpoint_opts.meta_opts or {}
  selection_opts = selection_opts or {}
  local meta_opts = breakpoint_opts.meta_opts
  local prompt_field = determine_prompt_field(breakpoint_type, selection_opts)
  if prompt_field and breakpoint_opts[prompt_field] == nil then
    prompt_hook_selection(function(selection)
      if selection then
        meta_opts[prompt_field] = selection
        breakpoints.toggle_breakpoint(breakpoint_type, placement_opts, breakpoint_opts)
      end
    end)
  else
    breakpoints.toggle_breakpoint(breakpoint_type, placement_opts, breakpoint_opts)
  end
end

---@param breakpoint_type string | nil
---@param placement_opts PlacementOpts | nil
---@param breakpoint_opts {dap_opts: DapOpts, meta_opts: MetaOpts}|nil
---@param selection_opts UiSelectionOpts|nil
function M.toggle_breakpoint(breakpoint_type, placement_opts, breakpoint_opts, selection_opts)
  placement_opts = placement_opts or {}
  breakpoint_opts = breakpoint_opts or {}
  if should_remove(placement_opts.replace or false) then
    breakpoints.remove_breakpoint(placement_opts)
    return
  end
  if not breakpoint_type then
    vim.ui.select(
      vim.tbl_filter(
        function(bp_type)
          return bp_type ~= "breakpoint"
        end,
        vim.tbl_map(function(bp)
          return bp:get_type()
        end, base.get_registered_breakpoints())
      ),
      {},
      function(selection)
        if not selection then
          return
        end
        toggle_breakpoint(selection, placement_opts, breakpoint_opts, selection_opts)
      end
    )
  else
    toggle_breakpoint(breakpoint_type, placement_opts, breakpoint_opts, selection_opts)
  end
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

function M.toggle_breakpoint_state()
  local bp = breakpoints.get_breakpoint_at_cursor()
  if not bp then
    return
  end
  if bp.enabled then
    bp:disable()
  else
    bp:enable()
  end
  breakpoints.update_buf_breakpoints(0, true)
end

return M
