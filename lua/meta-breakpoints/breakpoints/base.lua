local M = {}
local config = require("meta-breakpoints.config")
local signs = require("meta-breakpoints.signs")
local dap_utils = require("meta-breakpoints.nvim_dap_utils")
local hooks = require("meta-breakpoints.hooks")

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

---@alias SignOpts {text: string, texthl: string, linehl: string, numhl: string}

---@param breakpoint_class Breakpoint
function M.register_breakpoint_type(breakpoint_class)
  registered_breakpoints[breakpoint_class.get_type()] = breakpoint_class
end

function M.get_registered_breakpoints()
  return vim.tbl_values(registered_breakpoints)
end

---@alias DapOpts {condition: string, log_message: string, hit_condition: string}
---@alias MetaOpts {hit_hook: string, trigger_hook: string, remove_hook: string, starts_active: boolean}

---@class Breakpoint
---@field file_name string
---@field bufnr number|nil
---@field enabled boolean
---@field dap_opts DapOpts
---@field sign_id number|nil
---@field protected active boolean
---@field protected lnum number
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
  local data = { file_name = file_name, lnum = lnum, enabled = opts.enabled, dap_opts = dap_opts }
  ---@type Breakpoint
  local self = setmetatable(data, { __index = Breakpoint })
  self.active = true
  return self
end

function Breakpoint.get_type()
  return "breakpoint"
end

function Breakpoint:place_dap_breakpoint(bufnr)
  assert(self.enabled, "Can't place dap breakpoint when breakpoint is not enabled")
  dap_utils.toggle_dap_breakpoint(self.dap_opts, { bufnr = bufnr, lnum = self:get_lnum(), replace = true })
end

function Breakpoint:unplace_dap_breakpoint()
  dap_utils.remove_breakpoint(self.bufnr, self:get_lnum())
end

--- Load a breakpoint onto a buffer
---@param bufnr number
function Breakpoint:load(bufnr)
  self.bufnr = bufnr
  local sign_opts = self:get_sign_opts()
  self.sign_id = signs.place_sign(bufnr, self.lnum, sign_opts.sign_text, sign_opts.sign_hl_group)
  if self.enabled then
    self:place_dap_breakpoint(bufnr)
  end
  return self.sign_id
end

function Breakpoint:is_loaded()
  if self.bufnr then
    if vim.fn.bufloaded(self.bufnr) == 0 then
      self.bufnr = nil
      self.sign_id = nil
      return false
    end
    return true
  end
  return false
end

function Breakpoint:update_lnum()
  if self:is_loaded() then
    self.lnum = signs.get_sign_id_data(self.sign_id, self.bufnr).lnum
  end
end

function Breakpoint:get_lnum()
  self:update_lnum()
  return self.lnum
end

function Breakpoint:enable()
  self.enabled = true
  self.active = true
  if self.bufnr then
    dap_utils.toggle_dap_breakpoint(self.dap_opts, { bufnr = self.bufnr, lnum = self:get_lnum(), replace = true })
  end
end

function Breakpoint:disable()
  self.enabled = false
  self.active = false
  if self.bufnr then
    self:unplace_dap_breakpoint()
  end
end

function Breakpoint:update_sign()
  assert(self.sign_id, "Can't update a breakpoint sign when sign doesn't exist")
  local sign_opts = self:get_sign_opts()
  signs.place_sign(self.bufnr, self.lnum, sign_opts.sign_text, sign_opts.sign_hl_group, self.sign_id)
end

---@return {sign_text: string, sign_hl_group: string}
function Breakpoint:get_sign_opts()
  return { sign_text = "", sign_hl_group = "" }
end

function Breakpoint:remove()
  self:disable()
  if self:is_loaded() then
    signs.remove_sign(self.bufnr, self.sign_id)
  end
end

function Breakpoint:is_active()
  return self.active
end

function Breakpoint:get_persistent_data()
  return {
    file_name = self.file_name,
    lnum = self:get_lnum(),
    opts = { enabled = self.enabled, dap_opts = self.dap_opts },
  }
end

M.Breakpoint = Breakpoint
M.register_breakpoint_type(Breakpoint)

---@class MetaBreakpoint : Breakpoint
---@field meta_opts MetaOpts
---@field injected_sign_data {persistent: boolean}
local MetaBreakpoint = setmetatable({}, { __index = Breakpoint })

---@return MetaBreakpoint
function MetaBreakpoint.new(file_name, lnum, opts)
  opts = opts or {}
  local instance = Breakpoint.new(file_name, lnum, opts)
  local self = setmetatable(instance, { __index = MetaBreakpoint })
  self.meta_opts = opts.meta_opts or {}
  if self.meta_opts.starts_active == nil then
    self.meta_opts.starts_active = true
  end
  self.active = self.meta_opts.starts_active
  self.injected_sign_data = { persistent = false }
  return self --[[@as MetaBreakpoint]]
end

function MetaBreakpoint.get_type()
  return "meta_breakpoint"
end

---@param bufnr number
function MetaBreakpoint:load(bufnr)
  self.bufnr = bufnr
  local sign_opts = self:get_sign_opts()
  self.sign_id = signs.place_sign(bufnr, self.lnum, sign_opts.sign_text, sign_opts.sign_hl_group)
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
    Breakpoint.enable(self)
  else
    self.enabled = true
    self.active = toggle
  end
  if self.sign_id then
    self:update_sign()
  end
end

function MetaBreakpoint:disable()
  Breakpoint.disable(self)
  if self.sign_id then
    self:update_sign()
  end
end

function MetaBreakpoint:remove()
  local remove_hook = self.meta_opts.remove_hook
  if remove_hook then
    for _, func in pairs(hooks.get_hooks_mapping(remove_hook)) do
      func()
    end
  end
  Breakpoint.remove(self)
end

function MetaBreakpoint:get_persistent_data()
  local data = Breakpoint.get_persistent_data(self)
  local meta_opts = vim.deepcopy(self.meta_opts)
  local nullify_hooks = { "hit_hook", "remove_hook", "trigger_hook" }
  for _, hook in pairs(nullify_hooks) do
    local value = meta_opts[hook]
    if value and string.sub(value, 0, 1) == "_" then
      meta_opts[hook] = nil
    end
  end
  data.opts.meta_opts = meta_opts
  return data
end

---@return {sign_text: string, sign_hl_group: string|nil}
function MetaBreakpoint:get_sign_opts()
  local breakpoint_signs = config.signs[self:get_type()]
  assert(
    breakpoint_signs,
    string.format(
      "Signs for %s not found, either add sign data to the config or override get_sign_opts",
      self:get_type()
    )
  )
  local sign_text
  local sign_hl_group
  local mode = self.enabled and "enabled" or "disabled"
  local mode_table = breakpoint_signs[mode] or {}
  local persistent_table = mode_table.persistent or {}
  local default_signs = config.signs.defaults[mode] or { persistent = {} }

  if self.injected_sign_data.persistent then
    sign_text = persistent_table.text
    sign_hl_group = persistent_table.texthl or default_signs.persistent.texthl
  else
    sign_text = mode_table.text
    sign_hl_group = mode_table.texthl or default_signs.texthl
  end
  sign_text = sign_text or breakpoint_signs.text

  assert(sign_text, string.format("Sign text for %s in mode %s not found", self:get_type(), mode))
  return { sign_text = sign_text, sign_hl_group = sign_hl_group }
end

M.MetaBreakpoint = MetaBreakpoint
M.register_breakpoint_type(MetaBreakpoint)

return M
