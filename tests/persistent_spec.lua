local uv = vim.loop
local persistence = require('meta-breakpoints.persistence')
local utils = require('meta-breakpoints.utils')
local plugin_dir = '/tmp/meta_breakpoints'
local clear_persistent_breakpoints = require('tests.utils').clear_persistent_breakpoints

describe("test persistent data", function()
  require('meta-breakpoints').setup({
    plugin_directory = plugin_dir,
    persistent_breakpoints = {
      load_breakpoints_on_setup = false,
    },
  })

  clear_persistent_breakpoints()

  after_each(function()
    clear_persistent_breakpoints()
  end)

  it('reads without directory', function()
    local co = coroutine.running()
    local status = uv.fs_unlink(utils.get_breakpoints_file())
    assert.truthy(status)
    status = uv.fs_rmdir(plugin_dir)
    assert.truthy(status)

    utils.read_breakpoints(function(breakpoints)
      assert.are.same({}, breakpoints)
      coroutine.resume(co)
    end)
    coroutine.yield()
  end)

  it('reads invalid file', function()
    local co = coroutine.running()
    local fd = uv.fs_open(utils.get_breakpoints_file(), 'w', 438)
    assert.truthy(fd)
    uv.fs_write(fd, 'invalid file')
    uv.fs_close(fd)
    utils.read_breakpoints(function(breakpoints)
      assert.are.same({}, breakpoints)
      coroutine.resume(co)
    end)
    coroutine.yield()
  end)

  it('checks saved data equals to read data', function()
    local co = coroutine.running()
    local data = {{1}, {2}, {3}}
    utils.save_breakpoints(data, function()
      coroutine.resume(co)
    end)
    coroutine.yield()
    utils.read_breakpoints(function(read_data)
      assert.are.same(data, read_data)
      coroutine.resume(co)
    end)
    coroutine.yield()

    data = {{1}}
    utils.save_breakpoints(data, function()
      coroutine.resume(co)
    end)
    coroutine.yield()

    utils.read_breakpoints(function(read_data)
      assert.are.same(data, read_data)
      coroutine.resume(co)
    end)
    coroutine.yield()
  end)
end)
