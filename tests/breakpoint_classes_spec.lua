local get_dap_breakpoints = require('tests.utils').get_dap_breakpoints
local base = require('meta-breakpoints.breakpoints.base')
local builtin = require('meta-breakpoints.breakpoints.builtin')
local Breakpoint = base.Breakpoint
local MetaBreakpoint = base.MetaBreakpoint
local HookBreakpoint = builtin.HookBreakpoint
local breakpoint_factory = require('meta-breakpoints.breakpoints').breakpoint_factory
local hooks = require('meta-breakpoints.hooks')

---@param bp Breakpoint
local function create_from_breakpoint(bp)
  return breakpoint_factory(bp.get_type(), bp:get_persistent_data())
end

local function trigger_hook(hook_name)
  local hooks_list = hooks.get_hooks_mapping(hook_name) or {}
  for _, func in pairs(hooks_list) do
    func()
  end
end

describe("test breakpoint classes", function()
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {"", "", "", "", ""})

  it("checks loading enabled breakpoint", function()
    local bp = Breakpoint.new('f1', 1, {enabled = true})
    assert.equals(0, #get_dap_breakpoints())
    bp:load(buffer)
    assert.equals(1, #get_dap_breakpoints())
    bp:remove()
    assert.equals(0, #get_dap_breakpoints())
  end)

  it("checks loading disabled breakpoint", function()
    local bp = Breakpoint.new('f1', 1, {enabled = false})
    assert.equals(0, #get_dap_breakpoints())
    bp:load(buffer)
    assert.equals(0, #get_dap_breakpoints())
    bp:enable()
    assert.equals(1, #get_dap_breakpoints())
    bp:remove()
    assert.equals(0, #get_dap_breakpoints())
  end)

  it("checks base breakpoint factory", function()
    local bp = Breakpoint.new('f1', 1, {enabled = true, dap_opts = {condition = '1', log_message = '2', hit_condition = '3'}})
    assert.are.same(bp:get_persistent_data(), create_from_breakpoint(bp):get_persistent_data())
  end)

  it("checks lnum in loaded buffer", function()
    local bp = Breakpoint.new('f1', 1, {})
    bp:load(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "" })
    assert.equals(2, bp:get_lnum())
    assert.equals(2, create_from_breakpoint(bp):get_lnum())
    bp:remove()
  end)

  it("checks meta breakpoint", function()
    local bp = MetaBreakpoint.new('f1', 1, {meta_opts = {hit_hook = 'a', remove_hook = 'b', trigger_hook = 'c'}})
    assert.are.same(bp:get_persistent_data(), create_from_breakpoint(bp):get_persistent_data())
  end)

  it("checks internal hooks are not persistent", function()
    local bp = MetaBreakpoint.new('f1', 1, {meta_opts = {hit_hook = '_a', remove_hook = '_b', trigger_hook = '_c'}})
    assert.are.same(nil, bp:get_persistent_data().meta_opts)
  end)

  it("checks starts_active", function()
    local bp = MetaBreakpoint.new('f1', 1, {meta_opts = {starts_active = false}})
    assert.falsy(bp:is_active())
    bp:remove()
  end)

  it("checks lnum in deleted buffer", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {"", "", "", "", ""})
    local bp = Breakpoint.new('f1', 1, {})
    bp:load(buf)
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "" })
    bp:update_lnum()
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.equals(2, bp:get_lnum())
  end)

  it("checks activate deactivate", function()
    local bp = MetaBreakpoint.new('f1', 1, {})
    bp:deactivate()
    assert.falsy(bp:is_active())
    bp:load(buffer)
    assert.falsy(bp:is_active())
    assert.equals(0, #get_dap_breakpoints())
    bp:disable()
    assert.equals(0, #get_dap_breakpoints())
    bp:activate()
    assert.equals(0, #get_dap_breakpoints())
    bp:enable()
    assert.equals(1, #get_dap_breakpoints())
    bp:remove()
  end)

  it("checks creation of hook breakpoint", function()
    assert.has_error(function()
      -- missing trigger_hook
      HookBreakpoint.new('f1', 1, {})
    end)
    assert.has_error(function()
      HookBreakpoint.new('f1', 1, {meta_opts = {trigger_hook = 'a', starts_active = true}})
    end)
    local bp = HookBreakpoint.new('f1', 1, {meta_opts = {trigger_hook = 'a'}})
    assert.is_false(bp:is_active())
    bp:load(buffer)
    assert.equals(0, #get_dap_breakpoints())
    local new_bp = create_from_breakpoint(bp)
    assert.are.same(bp:get_persistent_data(), new_bp:get_persistent_data())
    bp:remove()
    new_bp:remove()
  end)

  it("checks triggering hook activates breakpoint", function()
    local bp =  HookBreakpoint.new('f1', 1, {meta_opts = {trigger_hook = 'a', hit_hook = 'b'}})
    bp:disable()
    trigger_hook('a')
    assert.is_false(bp:is_active())
    bp:enable()
    assert.is_false(bp:is_active())
    trigger_hook('a')
    assert.is_true(bp:is_active())
    trigger_hook('b')
    assert.is_false(bp:is_active())
    bp:remove()
  end)
end)
