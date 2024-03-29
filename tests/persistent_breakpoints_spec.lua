local uv = vim.loop
local clear_persistent_breakpoints = require("tests.utils").clear_persistent_breakpoints
local persistance = require("meta-breakpoints.persistence")
local bps = require("meta-breakpoints.breakpoints.collection")
local signs = require("meta-breakpoints.signs")
local log = require("meta-breakpoints.log")

describe("test breakpoints persistence", function()
  local directory = "/tmp/meta_breakpoints"
  local file = directory .. "/file"
  local buffer
  require("meta-breakpoints").setup({
    persistent_breakpoints = {
      enabled = true,
      persistent_by_default = true,
      load_breakpoints_on_setup = false,
      load_breakpoints_on_buf_enter = false,
      save_breakpoints_on_buf_write = false,
      persist_on_placement = false,
    },
    plugin_directory = directory,
  })

  before_each(function()
    buffer = vim.uri_to_bufnr(vim.uri_from_fname(file))
    vim.fn.bufload(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "11", "12", "13", "14", "15" })
  end)

  clear_persistent_breakpoints()

  after_each(function()
    bps.clear()
    clear_persistent_breakpoints()
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end

    uv.fs_unlink(file)
    bps.clear()
  end)

  local function save_breakpoints(bufnr)
    bufnr = bufnr or buffer
    vim.api.nvim_buf_call(bufnr, function()
      vim.api.nvim_cmd({ cmd = "write" }, {})
    end)
    local co = coroutine.running()
    bps.update_buf_breakpoints(bufnr, true, true, function()
      coroutine.resume(co)
    end)
    coroutine.yield()
  end

  local function load_breakpoints()
    local co = coroutine.running()
    persistance.load_persistent_breakpoints(function()
      coroutine.resume(co)
    end)
    coroutine.yield()
  end

  local function get_breakpoints_for_buffer(bufnr)
    local result = {}
    for _, breakpoint_data in pairs(bps.get_breakpoints()) do
      if breakpoint_data.bufnr == bufnr then
        local breakpoint = vim.deepcopy(breakpoint_data)
        breakpoint.lnum = signs.get_sign_id_data(breakpoint.sign_id, bufnr).lnum
        breakpoint.bufnr = nil
        breakpoint.sign_id = nil
        table.insert(result, breakpoint)
      end
    end
    return result
  end

  local function assert_saved_breakpoints(bufnr)
    bufnr = bufnr or buffer
    local file_name = vim.uri_from_bufnr(bufnr)
    save_breakpoints(bufnr)
    local original_breakpoints = get_breakpoints_for_buffer(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })

    local new_bufnr = vim.uri_to_bufnr(file_name)
    vim.fn.bufload(new_bufnr)
    assert.are_not.equals(bufnr, new_bufnr)
    log.fmt_info("created new buffer %s old one was %s", new_bufnr, bufnr)

    load_breakpoints()
    bps.ensure_persistent_breakpoints(new_bufnr)

    assert.are.same(original_breakpoints, get_breakpoints_for_buffer(new_bufnr))

    return new_bufnr
  end

  it("checks meta breakpoint is saved", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 })
    buffer = assert_saved_breakpoints(buffer)
  end)

  it("checks meta breakpoint is saved after being moved", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 })
    vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "0" })
    buffer = assert_saved_breakpoints(buffer)
  end)

  it("checks load breakpoints doesn't change current buffer", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 })
    save_breakpoints(buffer)
    load_breakpoints()
    bps.ensure_persistent_breakpoints(buffer)
    local bp = bps.get_breakpoints()[1]
    assert.truthy(bp)
    assert.equals(1, signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum)
  end)

  it("checks load per buffer", function()
    local second_buffer = vim.uri_to_bufnr("file://" .. file .. "2")
    vim.api.nvim_buf_set_lines(second_buffer, 0, -1, false, { "11", "12", "13", "14", "15" })
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 })
    bps.toggle_meta_breakpoint({ bufnr = second_buffer, lnum = 2 })

    local bp_before_saving = bps.get_breakpoints()[2]
    save_breakpoints(second_buffer)
    assert.equals(2, #bps.get_breakpoints())
    buffer = assert_saved_breakpoints(buffer)

    local all_breakpoints = bps.get_breakpoints()
    assert.equals(2, #bps.get_breakpoints())
    local bp1 = all_breakpoints[1]
    local bp2 = all_breakpoints[2]
    assert.are.same(bp_before_saving, bp1)
    assert.equals(2, signs.get_sign_id_data(bp1.sign_id, bp1.bufnr).lnum)
    assert.equals(1, signs.get_sign_id_data(bp2.sign_id, bp2.bufnr).lnum)

    uv.fs_unlink(file .. "2")
  end)

  it("checks removed breakpoint does not persist", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 3 })
    buffer = assert_saved_breakpoints(buffer)
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 3 })
    save_breakpoints()
    load_breakpoints()
    assert.equals(0, #bps.get_breakpoints())
  end)

  it("checks setting persistent to false does not get overridden by default value", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 3, persistent = false })
    save_breakpoints()
    bps.clear()
    load_breakpoints()
    assert.equals(0, #bps.get_breakpoints())
  end)

  it("checks dap_opts and meta_opts are saved", function()
    local dap_opts = { condition = "a", hit_condition = "b", log_message = "c" }
    local meta_opts = { hit_hook = "d", trigger_hook = "e", remove_hook = "f", starts_active = false }
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 }, { dap_opts = dap_opts, meta_opts = meta_opts })
    buffer = assert_saved_breakpoints(buffer)
    local breakpoint = bps.get_breakpoints(buffer)[1]
    for key, value in pairs(dap_opts) do
      assert.equals(value, breakpoint.dap_opts[key])
    end
    for key, value in pairs(meta_opts) do
      assert.equals(value, breakpoint.meta_opts[key])
    end
  end)

  it("checks ensure_persistent_breakpoints", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 })
    local placed_bps = bps.get_breakpoints(buffer)
    save_breakpoints()

    vim.api.nvim_buf_delete(buffer, { force = true })
    buffer = vim.uri_to_bufnr(vim.uri_from_fname(file))
    vim.fn.bufload(buffer)
    assert.are.same({}, bps.get_breakpoints(buffer))
    bps.ensure_persistent_breakpoints(buffer)
    assert.are.same(placed_bps[1].meta_opts, bps.get_breakpoints(buffer)[1].meta_opts)
  end)

  it("checks set_persistent_breakpoints", function()
    local second_buffer = vim.uri_to_bufnr("file://" .. file .. "2")
    vim.api.nvim_buf_set_lines(second_buffer, 0, -1, false, { "11", "12", "13", "14", "15" })
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 })
    local placed_bps = bps.get_breakpoints(buffer)
    bps.toggle_meta_breakpoint({ bufnr = second_buffer, lnum = 2 })
    save_breakpoints()

    vim.api.nvim_buf_delete(buffer, { force = true })
    buffer = vim.uri_to_bufnr(vim.uri_from_fname(file))
    local session = {
      request = function(_, _, _, callback)
        vim.schedule(callback)
      end,
    }
    local co = coroutine.running()
    local loaded_breakpoints = nil
    bps.set_persistent_breakpoints(session, function(result)
      loaded_breakpoints = result
      coroutine.resume(co)
    end)
    coroutine.yield()

    assert.are.same({}, bps.get_breakpoints(buffer))
    assert.equals(1, #loaded_breakpoints)
    assert.equals(1, #loaded_breakpoints[1])
    assert.equals(placed_bps[1], loaded_breakpoints[1][1])

    vim.fn.bufload(buffer) -- check again for loaded buffer without signs
    loaded_breakpoints = nil
    bps.set_persistent_breakpoints(session, function(result)
      loaded_breakpoints = result
      coroutine.resume(co)
    end)
    coroutine.yield()

    assert.are.same({}, bps.get_breakpoints(buffer))
    assert.equals(placed_bps[1], loaded_breakpoints[1][1])

    uv.fs_unlink(file .. "2")
  end)

  it("checks persistent breakpoints with starts_active=false", function()
    bps.toggle_meta_breakpoint({ bufnr = buffer, lnum = 1 }, { meta_opts = { starts_active = false } })
    save_breakpoints()

    vim.api.nvim_buf_delete(buffer, { force = true })
    buffer = vim.uri_to_bufnr(vim.uri_from_fname(file))

    local session = {
      request = function(_, _, _, callback)
        vim.schedule(callback)
      end,
    }
    local co = coroutine.running()
    local loaded_breakpoints = nil
    bps.set_persistent_breakpoints(session, function(result)
      loaded_breakpoints = result
      coroutine.resume(co)
    end)
    coroutine.yield()
    assert.are.same({}, loaded_breakpoints)
  end)

  pending("checks closing then opening buffer keeps breakpoint, needs to setup different config")
end)
