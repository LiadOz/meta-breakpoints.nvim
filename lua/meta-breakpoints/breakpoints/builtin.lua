local M = {}

local base = require('meta-breakpoints.breakpoints.base')
local MetaBreakpoint = base.MetaBreakpoint
local hooks = require('meta-breakpoints.hooks')


---@class HookBreakpoint : MetaBreakpoint
local HookBreakpoint = setmetatable({}, {__index = MetaBreakpoint})

local hook_breakpoint_count = 0
function HookBreakpoint.new(file_name, lnum, opts)
  opts = opts or {}
  local meta_opts = opts.meta_opts or {}
  assert(not meta_opts.starts_active, "Can't set starts_active for hook breakpoint")
  assert(meta_opts.trigger_hook, "Must have trigger_hook for hook breakpoint")
  meta_opts.starts_active = false

  local instance = MetaBreakpoint.new(file_name, lnum, opts)
  local self = setmetatable(instance, {__index = HookBreakpoint})

  self.meta_opts.hit_hook = self.meta_opts.hit_hook or string.format("_hit-%s", hook_breakpoint_count)
  self.meta_opts.remove_hook = self.meta_opts.remove_hook or string.format("_remove-%s", hook_breakpoint_count)
  hook_breakpoint_count = hook_breakpoint_count + 1

  local trigger_id = hooks.register_to_hook(self.meta_opts.trigger_hook, function()
    if self.enabled then
      self:activate()
    end
  end)
  local hit_id = hooks.register_to_hook(self.meta_opts.hit_hook, function()
    if self.enabled then
      self:deactivate()
    end
  end)

  hooks.register_to_hook(meta_opts.remove_hook, function()
    hooks.remove_hook(meta_opts.hit_hook, hit_id)
    hooks.remove_hook(meta_opts.trigger_hook, trigger_id)
    hooks.remove_hook(meta_opts.remove_hook)
  end)

  return self
end

function HookBreakpoint.get_default_sign()
  return 'HookBreakpoint'
end

function HookBreakpoint.get_type()
  return 'hook_breakpoint'
end
M.HookBreakpoint = HookBreakpoint
base.register_breakpoint_type(HookBreakpoint, {text = "H"})

return M
