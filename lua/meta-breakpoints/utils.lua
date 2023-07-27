local M = {}
local uv = vim.loop

local config = require('meta-breakpoints.config')


function M.get_breakpoints_file()
  return config.plugin_directory .. '/persistent_breakpoints.json'
end

local function save_breakpoints_to_file(file_path, bps, callback)
  print("saving breakpoints to file " .. #bps)
  uv.fs_open(file_path, 'w', 438, vim.schedule_wrap(function(err, fd)
    assert(not err, err)
    local json = vim.fn.json_encode(bps)
    uv.fs_write(fd, json, function(err, _)
      assert(not err, err)
      uv.fs_close(fd, vim.schedule_wrap(function(err, _)
        assert(not err, err)
        print('finished writing breakpoints to file')
        vim.print('written content ' .. json)
        if callback then
          print('save_breakpoints_to_file calling callback')
          callback()
        else
          print('save_breakpoints_to_file not calling callback')
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
      uv.fs_mkdir(plugin_dir, 448, vim.schedule_wrap(function(err, _)
        assert(not err, err)
        save_breakpoints_to_file(bp_file, {}, callback)
      end))
    else
      uv.fs_stat(bp_file, vim.schedule_wrap(function(err, _)
        if err ~= nil then
          save_breakpoints_to_file(bp_file, {}, callback)
        else
          callback()
        end
      end))
    end
  end)
end

function M.save_breakpoints(bps, callback)
  M.ensure_plugin_directory(function()
    save_breakpoints_to_file(M.get_breakpoints_file(), bps, callback)
  end)
end

---@param callback fun(breakpoints: table[])
function M.read_breakpoints(callback)
  local bp_file = M.get_breakpoints_file()
  M.ensure_plugin_directory(function()
    uv.fs_open(bp_file, 'r', 438, function(err, fd)
      assert(not err, err)
      uv.fs_stat(bp_file, function(err, stat)
        assert(not err, err)
        uv.fs_read(fd, stat.size, 0, function(err, data)
          assert(not err, err)
          print('read content ' .. data)
          uv.fs_close(fd, vim.schedule_wrap(function(err, _)
            assert(not err, err)
            local ok, result = pcall(vim.fn.json_decode, data)
            if not ok then
              vim.notify(string.format("Failed to decode data in %s", bp_file), vim.log.levels.WARN)
            else
            end
            if not ok or not result then
              result = {}
            end
            vim.print(result)
            callback(result)
          end))
        end)
      end)
    end)
  end)
end

return M
