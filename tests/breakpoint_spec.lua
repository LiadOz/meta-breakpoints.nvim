vim.o.swapfile = false
local bps = require('meta-breakpoints.breakpoint_base')
local signs = require('meta-breakpoints.signs')
local hooks = require('meta-breakpoints.hooks')
local dap_bps = require('dap.breakpoints')
local clear_persistent_breakpoints = require('tests.utils').clear_persistent_breakpoints

local function get_dap_breakpoints()
  local breakpoints = dap_bps.get()
  local result = {}
  for bufnr, buf_bps in pairs(breakpoints) do
    for _, bp_data in ipairs(buf_bps) do
      table.insert(result, { bufnr, bp_data.line })
    end
  end
  table.sort(result, function(a, b) return a[1] < b[1] end)
  return result
end
local spy = require('luassert.spy')

describe("test breakpoints without persistence", function()
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "1", "2", "3", "4", "5" })
  require('meta-breakpoints').setup({ persistent_breakpoints = { enabled = false } })

  after_each(function()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "1", "2", "3", "4", "5" })
    bps.clear()
  end)

  it("setup meta breakpoint", function()
    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 1 })
    local bp = bps.get_breakpoints()[1]
    assert.equals(1, signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum)
    assert.are.same({ { buffer, 1 } }, get_dap_breakpoints())

    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 1, replace = true })
    bp = bps.get_breakpoints()[1]
    assert.equals(1, signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum)
    assert.are.same({ { buffer, 1 } }, get_dap_breakpoints())

    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 1 })
    assert.are.same({}, bps.get_breakpoints())
    assert.are.same({}, get_dap_breakpoints())
  end)

  it("setup meta breakpoint and add line", function()
    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 1 })
    local bp = bps.get_breakpoints()[1]
    vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { '0' })
    assert.equals(2, signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum)
  end)

  it("toggle_dap_breakpoint is false", function()
    bps.toggle_meta_breakpoint({ toggle_dap_breakpoint = false }, { bufnr = buffer, lnum = 1 })
    local bp = bps.get_breakpoints()[1]
    assert.equals(1, signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum)
    assert.are.same({}, get_dap_breakpoints())
  end)

  it('hit hook', function()
    local s = spy.new(function() end)
    bps.toggle_meta_breakpoint({ hit_hook = 'l1' }, { bufnr = buffer, lnum = 1 })
    hooks.register_to_hook('l1', 1, s)
    bps.trigger_hooks(buffer, 1)

    assert.spy(s).was.called(1)
    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 1 })
    bps.trigger_hooks(buffer, 1)
    assert.spy(s).was.called(1)
  end)

  it('remove hook', function()
    local s = spy.new(function() end)
    bps.toggle_meta_breakpoint({ remove_hook = 'l1' }, { bufnr = buffer, lnum = 1 })
    hooks.register_to_hook('l1', 1, s)

    assert.spy(s).was.called(0)
    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 1 })
    assert.spy(s).was.called(1)
  end)

  it("simple hook breakpoint", function()
    bps.toggle_meta_breakpoint({ hit_hook = 'l1' }, { bufnr = buffer, lnum = 1 })
    bps.toggle_hook_breakpoint({ trigger_hook = 'l1' }, { bufnr = buffer, lnum = 2 })
    assert.are.same({ { buffer, 1 } }, get_dap_breakpoints())
    bps.trigger_hooks(buffer, 1)

    assert.are.same({ { buffer, 1 }, { buffer, 2 } }, get_dap_breakpoints())

    bps.trigger_hooks(buffer, 2)
    assert.are.same({ { buffer, 1 } }, get_dap_breakpoints())
  end)

  it("hook breakpoint with added lines", function()
    bps.toggle_meta_breakpoint({ hit_hook = 'l1' }, { bufnr = buffer, lnum = 1 })
    bps.toggle_hook_breakpoint({ trigger_hook = 'l1' }, { bufnr = buffer, lnum = 2 })
    assert.are.same({ { buffer, 1 } }, get_dap_breakpoints())

    vim.api.nvim_buf_set_lines(buffer, 1, 1, false, { '11' })
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
    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 1 })
    bps.toggle_meta_breakpoint({}, { bufnr = buffer2, lnum = 2 })

    local breakpoints = bps.get_breakpoints()
    assert(#breakpoints == 2)
    local bp1 = breakpoints[1]
    local bp2 = breakpoints[2]
    assert.equals(1, signs.get_sign_id_data(bp1.sign_id, bp1.bufnr).lnum)
    assert.equals(2, signs.get_sign_id_data(bp2.sign_id, bp2.bufnr).lnum)

    assert.are.same({ { buffer, 1 }, {buffer2, 2} }, get_dap_breakpoints())
  end)
end)

local persistence = require('meta-breakpoints.persistence')
local uv = vim.loop

describe("test breakpoints with persistence", function()
  local directory = '/tmp/meta_breakpoints'
  local file = directory .. '/file'
  local buffer
  require('meta-breakpoints').setup({
      persistent_breakpoints = {
        enabled = true,
        persistent_by_default = true,
        load_breakpoints_on_setup = false,
        save_breakpoints_on_buf_write = false,
        persist_on_placement = false,
      },
      plugin_directory = directory
    })

  before_each(function()
    local file_uri = 'file://' .. file
    buffer = vim.uri_to_bufnr(file_uri)
    vim.fn.bufload(buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "11", "12", "13", "14", "15" })
  end)


  clear_persistent_breakpoints()

  after_each(function()
    bps.clear()
    clear_persistent_breakpoints()
    vim.api.nvim_buf_delete(buffer, {force = true})

    uv.fs_unlink(file)
  end)

  local function save_breakpoints(bufnr)
    bufnr = bufnr or buffer
    vim.api.nvim_buf_call(bufnr, function()
      vim.api.nvim_cmd({cmd = "write"}, {})
    end)
    local co = coroutine.running()
    bps.update_buf_breakpoints(bufnr, true, function()
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
    vim.api.nvim_buf_delete(bufnr, {force = true})

    local new_bufnr = vim.uri_to_bufnr(file_name)
    vim.fn.bufload(new_bufnr)
    assert(new_bufnr ~= bufnr)
    print(string.format("created new buffer %s old one was %s", new_bufnr, bufnr))

    local load_opts
    if all_buffers then
      load_opts = {all_buffers = true}
    else
      load_opts = {bufnr = new_bufnr}
    end
    load_breakpoints(load_opts)

    assert.are.same(original_breakpoints, get_breakpoints_for_buffer(new_bufnr))

    return new_bufnr
  end

  it("checks meta breakpoint is saved", function()
    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 1 })
    buffer = assert_saved_breakpoints(buffer)
  end)

  it("checks meta breakpoint is saved after being moved", function()
    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 1 })
    vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { '0' })
    buffer = assert_saved_breakpoints(buffer)
  end)

  it("checks load breakpoints doesn't change current buffer", function()
    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 1 })
    save_breakpoints(buffer)
    load_breakpoints({bufnr = false})
    local bp = bps.get_breakpoints()[1]
    assert(bp)
    assert.equals(1, signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum)
  end)

  it('checks load per buffer', function()
    local second_buffer = vim.uri_to_bufnr('file://' .. file .. '2')
    vim.api.nvim_buf_set_lines(second_buffer, 0, -1, false, { "11", "12", "13", "14", "15" })
    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 1 })
    bps.toggle_meta_breakpoint({}, { bufnr = second_buffer, lnum = 2 })

    local bp_before_saving = bps.get_breakpoints()[2]
    save_breakpoints(second_buffer)
    assert(#bps.get_breakpoints() == 2)
    buffer = assert_saved_breakpoints(buffer)

    vim.print(bps.get_breakpoints())
    local all_breakpoints = bps.get_breakpoints()
    assert(#all_breakpoints == 2)
    local bp1 = all_breakpoints[1]
    local bp2 = all_breakpoints[2]
    assert.are.same(bp_before_saving, bp1)
    assert.equals(2, signs.get_sign_id_data(bp1.sign_id, bp1.bufnr).lnum)
    assert.equals(1, signs.get_sign_id_data(bp2.sign_id, bp2.bufnr).lnum)

    uv.fs_unlink(file .. '2')
  end)

  it('checks removed breakpoint does not persist', function()
    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 3 })
    buffer = assert_saved_breakpoints(buffer, {bufnr = buffer})
    bps.toggle_meta_breakpoint({}, { bufnr = buffer, lnum = 3 })
    save_breakpoints()
    load_breakpoints()
    assert.equals(0, #bps.get_breakpoints())
  end)

  pending('checks closing then opening buffer keeps breakpoint, needs to setup different config')

end)
