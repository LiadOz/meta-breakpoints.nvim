local M = {}
local uv = vim.loop

local config = require('meta-breakpoints.config')
local log = require('meta-breakpoints.log')

function M.get_breakpoints_file()
  return config.plugin_directory .. '/persistent_breakpoints.json'
end

---@param file_path string
---@param bps PersistentBreakpointsTable
---@param callback fun()
local function save_breakpoints_to_file(file_path, bps, callback)
  uv.fs_open(file_path, 'w', 438, vim.schedule_wrap(function(err, fd)
    assert(not err, err)
    local json = vim.fn.json_encode(bps)
    uv.fs_write(fd, json, function(err, _)
      assert(not err, err)
      uv.fs_close(fd, vim.schedule_wrap(function(err, _)
        assert(not err, err)
        log.fmt_trace('written to file %s', json)
        if callback then
          callback()
        else
        end
      end))
    end)
  end))
end

function M.ensure_plugin_directory(callback)
  local plugin_dir = config.plugin_directory
  local bp_file = M.get_breakpoints_file()
  uv.fs_stat(plugin_dir, function(err, _)
    if err ~= nil then
      log.fmt_trace("Plugin directory %s not found, creating directory", plugin_dir)
      uv.fs_mkdir(plugin_dir, 448, vim.schedule_wrap(function(err, _)
        assert(not err, err)
        save_breakpoints_to_file(bp_file, {}, callback)
      end))
    else
      uv.fs_stat(bp_file, vim.schedule_wrap(function(err, _)
        if err ~= nil then
          log.fmt_trace("Breakpoint file %s not found", bp_file)
          save_breakpoints_to_file(bp_file, {}, callback)
        else
          callback()
        end
      end))
    end
  end)
end

---@param bps PersistentBreakpointsTable
---@param callback fun()
function M.save_breakpoints(bps, callback)
  M.ensure_plugin_directory(function()
    save_breakpoints_to_file(M.get_breakpoints_file(), bps, callback)
  end)
end

---@param callback fun(breakpoints: PersistentBreakpointsTable)
function M.read_breakpoints(callback)
  local bp_file = M.get_breakpoints_file()
  M.ensure_plugin_directory(function()
    uv.fs_open(bp_file, 'r', 438, function(err, fd)
      assert(not err, err)
      uv.fs_stat(bp_file, function(err, stat)
        assert(not err, err)
        uv.fs_read(fd, stat.size, 0, function(err, data)
          assert(not err, err)
          log.fmt_trace('read content %s', data)
          uv.fs_close(fd, vim.schedule_wrap(function(err, _)
            assert(not err, err)
            local ok, result = pcall(vim.fn.json_decode, data)
            if not ok then
              log.fmt_warn('failed to decode data')
            else
            end
            if not ok or not result then
              result = {}
            end
            callback(result)
          end))
        end)
      end)
    end)
  end)
end

return M
