local uv = vim.loop
local clear_persistent_breakpoints = require("tests.utils").clear_persistent_breakpoints
local bps = require("meta-breakpoints.breakpoint_base")
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

  local function load_breakpoints(opts)
    local co = coroutine.running()
    bps.load_persistent_breakpoints(function()
      coroutine.resume(co)
    end, opts)
    coroutine.yield()
  end

  -- this is a workaround for an issue where a setup in which load_breakpoints_on_setup was enabled in a previous configuration and
  -- the autocmd has not finished executing loading breakpoints, which causes bad breakpoints to be loaded inside tests
  -- so this causes the test to block until previous load_breakpoints have been called
  load_breakpoints()

  local function get_breakpoints_for_buffer(bufnr)
    local result = {}
    for _, breakpoint_data in pairs(bps.get_breakpoints()) do
      if breakpoint_data.bufnr == bufnr then
        local breakpoint = vim.deepcopy(breakpoint_data)
        breakpoint.bufnr = nil
        breakpoint.sign_id = nil
        breakpoint.lnum = signs.get_sign_id_data(breakpoint.sign_id, bufnr).lnum
        table.insert(result, breakpoint)
      end
    end
    return result
  end

  local function assert_saved_breakpoints(bufnr, all_buffers)
    bufnr = bufnr or buffer
    local file_name = vim.uri_from_bufnr(bufnr)
    save_breakpoints(bufnr)
    local original_breakpoints = get_breakpoints_for_buffer(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })

    local new_bufnr = vim.uri_to_bufnr(file_name)
    vim.fn.bufload(new_bufnr)
    assert.are_not.equals(bufnr, new_bufnr)
    log.fmt_info("created new buffer %s old one was %s", new_bufnr, bufnr)

    local load_opts
    if all_buffers then
      load_opts = { all_buffers = true }
    else
      load_opts = { bufnr = new_bufnr }
    end
    load_breakpoints(load_opts)

    assert.are.same(original_breakpoints, get_breakpoints_for_buffer(new_bufnr))

    return new_bufnr
  end

  it("checks meta breakpoint is saved", function()
    bps.toggle_meta_breakpoint({}, {}, { bufnr = buffer, lnum = 1 })
    buffer = assert_saved_breakpoints(buffer)
  end)

  it("checks meta breakpoint is saved after being moved", function()
    bps.toggle_meta_breakpoint({}, {}, { bufnr = buffer, lnum = 1 })
    vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "0" })
    buffer = assert_saved_breakpoints(buffer)
  end)

  it("checks load breakpoints doesn't change current buffer", function()
    bps.toggle_meta_breakpoint({}, {}, { bufnr = buffer, lnum = 1 })
    save_breakpoints(buffer)
    load_breakpoints({ bufnr = false })
    local bp = bps.get_breakpoints()[1]
    assert.truthy(bp)
    assert.equals(1, signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum)
  end)

  it("checks load per buffer", function()
    local second_buffer = vim.uri_to_bufnr("file://" .. file .. "2")
    vim.api.nvim_buf_set_lines(second_buffer, 0, -1, false, { "11", "12", "13", "14", "15" })
    bps.toggle_meta_breakpoint({}, {}, { bufnr = buffer, lnum = 1 })
    bps.toggle_meta_breakpoint({}, {}, { bufnr = second_buffer, lnum = 2 })

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
    bps.toggle_meta_breakpoint({}, {}, { bufnr = buffer, lnum = 3 })
    buffer = assert_saved_breakpoints(buffer, { bufnr = buffer })
    bps.toggle_meta_breakpoint({}, {}, { bufnr = buffer, lnum = 3 })
    save_breakpoints()
    load_breakpoints()
    assert.equals(0, #bps.get_breakpoints())
  end)

  it("checks setting persistent to false does not get overridden by default value", function()
    bps.toggle_meta_breakpoint({}, { persistent = false }, { bufnr = buffer, lnum = 3 })
    assert.equals(false, bps.get_breakpoints(buffer)[1].meta.persistent)
    save_breakpoints()
    bps.clear()
    load_breakpoints()
    assert.equals(0, #bps.get_breakpoints())
  end)

  it("checks dap_opts and meta_opts are saved", function()
    local dap_opts = { condition = "a", hit_condition = "b", log_message = "c" }
    local meta_opts = { hit_hook = "d", trigger_hook = "e", remove_hook = "f", toggle_dap_breakpoint = false }
    bps.toggle_meta_breakpoint(dap_opts, meta_opts, { bufnr = buffer, lnum = 1 })
    buffer = assert_saved_breakpoints(buffer)
    local breakpoint = bps.get_breakpoints(buffer)[1]
    for key, value in pairs(dap_opts) do
      assert.equals(value, breakpoint.dap_opts[key])
    end
    for key, value in pairs(meta_opts) do
      assert.equals(value, breakpoint.meta[key])
    end
  end)

  it("checks set_persistent_breakpoints", function()
    local second_buffer = vim.uri_to_bufnr("file://" .. file .. "2")
    vim.api.nvim_buf_set_lines(second_buffer, 0, -1, false, { "11", "12", "13", "14", "15" })
    bps.toggle_meta_breakpoint({}, {}, { bufnr = buffer, lnum = 1 })
    local placed_bps = bps.get_breakpoints(buffer)
    bps.toggle_meta_breakpoint({}, {}, { bufnr = second_buffer, lnum = 2 })
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
    assert.are.same({ { { lnum = 1, dap_opts = {}, meta_opts = placed_bps[1].meta } } }, loaded_breakpoints)

    vim.fn.bufload(buffer) -- check again for loaded buffer without signs
    loaded_breakpoints = nil
    bps.set_persistent_breakpoints(session, function(result)
      loaded_breakpoints = result
      coroutine.resume(co)
    end)
    coroutine.yield()

    assert.are.same({}, bps.get_breakpoints(buffer))
    assert.are.same({ { { lnum = 1, dap_opts = {}, meta_opts = placed_bps[1].meta } } }, loaded_breakpoints)

    uv.fs_unlink(file .. "2")
  end)

  it("checks ensure_persistent_breakpoints", function()
    bps.toggle_meta_breakpoint({}, {}, { bufnr = buffer, lnum = 1 })
    local placed_bps = bps.get_breakpoints(buffer)
    save_breakpoints()

    vim.api.nvim_buf_delete(buffer, { force = true })
    buffer = vim.uri_to_bufnr(vim.uri_from_fname(file))
    assert.are.same({}, bps.get_breakpoints(buffer))
    bps.ensure_persistent_breakpoints(buffer)
    assert.are.same(placed_bps[1].meta, bps.get_breakpoints(buffer)[1].meta)
  end)

  it("checks persistent breakpoints with toggle_dap_breakpoint=false", function()
    bps.toggle_meta_breakpoint({}, { toggle_dap_breakpoint = false }, { bufnr = buffer, lnum = 1 })
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
