local bps = require("meta-breakpoints.breakpoints.collection")
local signs = require("meta-breakpoints.signs")
local hooks = require("meta-breakpoints.hooks")
local get_dap_breakpoints = require("tests.utils").get_dap_breakpoints

local spy = require("luassert.spy")

describe("test breakpoints", function()
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "1", "2", "3", "4", "5" })
  require("meta-breakpoints").setup({ persistent_breakpoints = { enabled = false } })

  after_each(function()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "1", "2", "3", "4", "5" })
    bps.clear()
  end)

  it("setup meta breakpoint", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 })
    local bp = bps.get_breakpoints()[1]
    assert.equals(1, signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum)
    assert.are.same({ { buffer, 1 } }, get_dap_breakpoints())

    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1, replace = true })
    bp = bps.get_breakpoints()[1]
    assert.equals(1, signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum)
    assert.are.same({ { buffer, 1 } }, get_dap_breakpoints())

    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 })
    assert.are.same({}, bps.get_breakpoints())
    assert.are.same({}, get_dap_breakpoints())
  end)

  it("setup meta breakpoint and add line", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 })
    local bp = bps.get_breakpoints()[1]
    vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "0" })
    assert.equals(2, signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum)
  end)

  it("toggle_dap_breakpoint is false", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 }, { meta_opts = { starts_active = false } })
    local bp = bps.get_breakpoints()[1]
    assert.equals(1, signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum)
    assert.are.same({}, get_dap_breakpoints())
  end)

  it("checks dap options are saved", function()
    local dap_opts = { condition = "a", hit_condition = "b", log_message = "c" }
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 }, { dap_opts = dap_opts })
    local dap_breakpoint = require("dap.breakpoints").get()[buffer][1]

    local expected_dap_opts = { condition = "a", hitCondition = "b", logMessage = "c" }
    for key, value in pairs(expected_dap_opts) do
      assert.equals(value, dap_breakpoint[key])
    end
  end)

  it("hit hook", function()
    local s = spy.new(function() end)
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 }, { meta_opts = { hit_hook = "l1" } })
    hooks.register_to_hook("l1", s)
    bps.trigger_hooks(buffer, 1)

    assert.spy(s).was.called(1)
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 })
    bps.trigger_hooks(buffer, 1)
    assert.spy(s).was.called(1)
  end)

  it("remove hook", function()
    local s = spy.new(function() end)
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 }, { meta_opts = { remove_hook = "l1" } })
    hooks.register_to_hook("l1", s)

    assert.spy(s).was.called(0)
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 })
    assert.spy(s).was.called(1)
  end)

  it("simple hook breakpoint", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 }, { meta_opts = { hit_hook = "l1" } })
    bps.toggle_hook_breakpoint({ bufnr = buffer, lnum = 2 }, { meta_opts = { trigger_hook = "l1" } })
    assert.are.same({ { buffer, 1 } }, get_dap_breakpoints())
    bps.trigger_hooks(buffer, 1)

    assert.are.same({ { buffer, 1 }, { buffer, 2 } }, get_dap_breakpoints())

    bps.trigger_hooks(buffer, 2)
    assert.are.same({ { buffer, 1 } }, get_dap_breakpoints())
  end)

  it("puts meta breakpoint on hook breakpoint", function()
    bps.toggle_hook_breakpoint({ bufnr = buffer, lnum = 2 }, { meta_opts = { trigger_hook = "l2" } })
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 2 }, { meta_opts = {} })
    assert.are.same({}, bps.get_breakpoints())
    assert.are.same({}, get_dap_breakpoints())
  end)

  it("hook breakpoint with added lines", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 }, { meta_opts = { hit_hook = "l1" } })
    bps.toggle_hook_breakpoint({ bufnr = buffer, lnum = 2 }, { meta_opts = { trigger_hook = "l1" } })
    assert.are.same({ { buffer, 1 } }, get_dap_breakpoints())

    vim.api.nvim_buf_set_lines(buffer, 1, 1, false, { "11" })
    bps.trigger_hooks(buffer, 1)

    assert.are.same({ { buffer, 1 }, { buffer, 3 } }, get_dap_breakpoints())

    bps.trigger_hooks(buffer, 2)
    assert.are.same({ { buffer, 1 }, { buffer, 3 } }, get_dap_breakpoints())

    bps.trigger_hooks(buffer, 3)
    assert.are.same({ { buffer, 1 } }, get_dap_breakpoints())
  end)

  it("checks multiple buffers", function()
    local buffer2 = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buffer2, 0, -1, false, { "1", "2", "3", "4", "5" })
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 }, { meta_opts = {} })
    bps.toggle_meta_breakpoint({ bufnr = buffer2, lnum = 2 }, { meta_opts = {} })

    local breakpoints = bps.get_breakpoints()
    assert.equals(2, #breakpoints)
    local bp1 = breakpoints[1]
    local bp2 = breakpoints[2]
    assert.equals(1, signs.get_sign_id_data(bp1.sign_id, bp1.bufnr).lnum)
    assert.equals(2, signs.get_sign_id_data(bp2.sign_id, bp2.bufnr).lnum)

    assert.are.same({ { buffer, 1 }, { buffer2, 2 } }, get_dap_breakpoints())
  end)
end)
