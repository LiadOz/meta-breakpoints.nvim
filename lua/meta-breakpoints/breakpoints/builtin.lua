local M = {}

local base = require("meta-breakpoints.breakpoints.base")
local MetaBreakpoint = base.MetaBreakpoint
local hooks = require("meta-breakpoints.hooks")

local builtin_breakpoint_count = 0

---@param breakpoint_type string
function M.breakpoint_creator(breakpoint_type)
  local class = setmetatable({}, { __index = MetaBreakpoint })

  class.get_type = function()
    return breakpoint_type
  end

  base.register_breakpoint_type(class)

  return class
end

---@class HookBreakpoint : MetaBreakpoint
local HookBreakpoint = M.breakpoint_creator("hook_breakpoint")
M.HookBreakpoint = HookBreakpoint

function HookBreakpoint.new(file_name, lnum, opts)
  opts = opts or {}
  local meta_opts = opts.meta_opts or {}
  assert(not meta_opts.starts_active, "Can't set starts_active for hook breakpoint")
  assert(meta_opts.trigger_hook, "Must have trigger_hook for hook breakpoint")
  meta_opts.starts_active = false

  local instance = MetaBreakpoint.new(file_name, lnum, opts)
  local self = setmetatable(instance, { __index = HookBreakpoint })

  self.meta_opts.hit_hook = self.meta_opts.hit_hook or string.format("_hit-%s", builtin_breakpoint_count)
  self.meta_opts.remove_hook = self.meta_opts.remove_hook or string.format("_remove-%s", builtin_breakpoint_count)
  builtin_breakpoint_count = builtin_breakpoint_count + 1

  local trigger_id = hooks.register_to_hook(self.meta_opts.trigger_hook, function()
    if self.enabled and not self.active then
      self:activate()
    end
  end)
  local hit_id = hooks.register_to_hook(self.meta_opts.hit_hook, function()
    if self.enabled then
      self:deactivate()
    end
  end)

  local remove_id
  remove_id = hooks.register_to_hook(meta_opts.remove_hook, function()
    hooks.remove_hook(meta_opts.hit_hook, hit_id)
    hooks.remove_hook(meta_opts.trigger_hook, trigger_id)
    hooks.remove_hook(meta_opts.remove_hook, remove_id)
  end)

  return self
end

M.continue_breakpoint_activated = false
---@class ContinueBreakpoint : MetaBreakpoint
local ContinueBreakpoint = M.breakpoint_creator("continue_breakpoint")
M.ContinueBreakpoint = ContinueBreakpoint

function ContinueBreakpoint.new(file_name, lnum, opts)
  opts = opts or {}
  local meta_opts = opts.meta_opts or {}
  assert(meta_opts.hit_hook, "Must have hit hook for continue breakpoint")
  local instance = MetaBreakpoint.new(file_name, lnum, opts)
  local self = setmetatable(instance, { __index = ContinueBreakpoint })

  self.meta_opts.remove_hook = self.meta_opts.remove_hook or string.format("_remove-%s", builtin_breakpoint_count)
  builtin_breakpoint_count = builtin_breakpoint_count + 1

  local hit_id = hooks.register_to_hook(self.meta_opts.hit_hook, function()
    M.continue_breakpoint_activated = true
  end, 1)

  local remove_id
  remove_id = hooks.register_to_hook(meta_opts.remove_hook, function()
    hooks.remove_hook(meta_opts.hit_hook, hit_id)
    hooks.remove_hook(meta_opts.remove_hook, remove_id)
  end)

  return self
end

return M
