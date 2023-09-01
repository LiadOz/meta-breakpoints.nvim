local M = {}
local signs = require("meta-breakpoints.signs")
local dap_utils = require("meta-breakpoints.nvim_dap_utils")

---@type table<string, Breakpoint>
local registered_breakpoints = {}

---@param breakpoint_type string
---@param breakpoint_opts table
---@return Breakpoint
function M.breakpoint_factory(breakpoint_type, breakpoint_opts)
  local breakpoint_class = registered_breakpoints[breakpoint_type]
  assert(breakpoint_class, string.format("Breakpoint type %s not found", breakpoint_type))
  return breakpoint_class.new(breakpoint_opts.file_name, breakpoint_opts.lnum, breakpoint_opts.opts)
end

---@param breakpoint_class Breakpoint
---@param default_sign_opts {text: string, texthl: string, linehl: string, numhl: string}
function M.register_breakpoint_type(breakpoint_class, default_sign_opts)
  registered_breakpoints[breakpoint_class.get_type()] = breakpoint_class
  vim.fn.sign_define(breakpoint_class.get_default_sign(), default_sign_opts)
end

---@alias DapOpts {condition: string, log_message: string, hit_condition: string}
---@alias MetaOpts {hit_hook: string, trigger_hook: string, remove_hook: string, persistent: boolean, starts_active: boolean}

---@class Breakpoint
---@field file_name string
---@field bufnr number|nil
---@field enabled boolean
---@field dap_opts DapOpts
---@field protected active boolean
---@field protected lnum number
---@field private sign_id number|nil
local Breakpoint = {}

---@param file_name string
---@param lnum number
---@param opts {enabled: boolean, dap_opts: DapOpts}
---@return Breakpoint
function Breakpoint.new(file_name, lnum, opts)
  opts = opts or {}
  if opts.enabled == nil then
    opts.enabled = true
  end
  local dap_opts = opts.dap_opts or {}
  local data = {file_name = file_name, lnum = lnum, enabled = opts.enabled, dap_opts = dap_opts}
  ---@type Breakpoint
  local self = setmetatable(data, {__index = Breakpoint})
  self.active = true
  return self
end

function Breakpoint.get_default_sign()
  return 'Breakpoint'
end

function Breakpoint.get_type()
  return 'breakpoint'
end

function Breakpoint:place_dap_breakpoint(bufnr)
  assert(self.enabled, "Can't place dap breakpoint when breakpoint is not enabled")
  dap_utils.toggle_dap_breakpoint(self.dap_opts, {bufnr = bufnr, lnum = self:get_lnum(), replace = true})
end

function Breakpoint:unplace_dap_breakpoint()
    dap_utils.remove_breakpoint(self.bufnr, self:get_lnum())
end

--- Load a breakpoint onto a buffer
---@param bufnr number
function Breakpoint:load(bufnr)
  self.bufnr = bufnr
  self.sign_id = signs.place_sign(bufnr, self.lnum, self.get_default_sign())
  if self.enabled then
    self:place_dap_breakpoint(bufnr)
  end
  return self.sign_id
end

function Breakpoint:get_lnum()
  if self.sign_id then
    return signs.get_sign_id_data(self.sign_id, self.bufnr).lnum
  end
  return self.lnum
end

function Breakpoint:enable()
  self.enabled = true
  self.active = true
  if self.bufnr then
    dap_utils.toggle_dap_breakpoint(self.dap_opts, {bufnr = self.bufnr, lnum = self:get_lnum(), replace = true})
  end
end

function Breakpoint:disable()
  self.enabled = false
  self.active = false
  if self.bufnr then
    self:unplace_dap_breakpoint()
  end
end

function Breakpoint:update_sign(sign_type)
  assert(self.sign_id, "Can't update a breakpoint sign when sign doesn't exist")
  signs.place_sign(self.bufnr, self.lnum, sign_type, nil, self.sign_id)
end

function Breakpoint:is_active()
  return self.active
end

function Breakpoint:get_persistent_data()
  return {file_name = self.file_name, lnum = self:get_lnum(), opts = {enabled = self.enabled, dap_opts = self.dap_opts}}
end

M.Breakpoint = Breakpoint
M.register_breakpoint_type(Breakpoint, {text = "B"})

---@class MetaBreakpoint : Breakpoint
---@field meta_opts MetaOpts
local MetaBreakpoint = setmetatable({}, {__index = Breakpoint})

---@return MetaBreakpoint
function MetaBreakpoint.new(file_name, lnum, opts)
  opts = opts or {}
  local instance = Breakpoint.new(file_name, lnum, opts)
  local self = setmetatable(instance, {__index = MetaBreakpoint})
  self.meta_opts = opts.meta_opts or {}
  if self.meta_opts.starts_active == nil then
    self.meta_opts.starts_active = true
  end
  self.active = self.meta_opts.starts_active
  return self --[[@as MetaBreakpoint]]
end

function MetaBreakpoint.get_default_sign()
  return 'MetaBreakpoint'
end

function MetaBreakpoint.get_type()
  return 'meta_breakpoint'
end

---@param bufnr number
function MetaBreakpoint:load(bufnr)
  self.bufnr = bufnr
  self.sign_id = signs.place_sign(bufnr, self.lnum, self.get_default_sign())
  if self.enabled and self.active then
    self:place_dap_breakpoint(bufnr)
  end
  return self.sign_id
end

function MetaBreakpoint:activate()
  assert(not self.active, "Cannot activate activated breakpoint")
  self.active = true
  if self.enabled and self.bufnr then
    self:place_dap_breakpoint(self.bufnr)
  end
end

function MetaBreakpoint:deactivate()
  assert(self.active, "Cannot deactivate deactivated breakpoint")
  self.active = false
  if self.enabled and self.bufnr then
    dap_utils.remove_breakpoint(self.bufnr, self:get_lnum())
  end
end

function MetaBreakpoint:enable()
  local toggle = self.meta_opts.starts_active
  if toggle then
    return Breakpoint.enable(self)
  end
  self.enabled = true
  self.active = toggle
end

function MetaBreakpoint:get_persistent_data()
  local data = Breakpoint.get_persistent_data(self)
  local meta_opts = vim.deepcopy(self.meta_opts)
  local nullify_hooks = {'hit_hook', 'remove_hook', 'trigger_hook'}
  for _, hook in pairs(nullify_hooks) do
    local value = meta_opts[hook]
    if value and string.sub(value, 0, 1) == "_" then
      meta_opts[hook] = nil
    end
  end
  data.opts.meta_opts = meta_opts
  return data
end

M.MetaBreakpoint = MetaBreakpoint
M.register_breakpoint_type(MetaBreakpoint, {text = 'M'})

return M
