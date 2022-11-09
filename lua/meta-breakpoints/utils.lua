local M = {}
local uv = vim.loop


local plugin_dir = vim.fn.stdpath('data') .. '/meta_breakpoints'
local bp_file = plugin_dir .. '/persistent_breakpoints.json'


local function save_breakpoints_to_file(file_path, bps, callback)
    uv.fs_open(file_path, 'w', 438, vim.schedule_wrap(function(err, fd)
        assert(not err, err)
        local json = vim.fn.json_encode(bps)
        uv.fs_write(fd, json, function(err, _)
            assert(not err, err)
            uv.fs_close(fd, function(err, _)
                assert(not err, err)
                if callback then
                    callback()
                end
            end)
        end)
    end))
end

local function ensure_plugin_directory(callback)
    uv.fs_stat(plugin_dir, function(err, _)
        if err ~= nil then
            uv.fs_mkdir(plugin_dir, 448, function(err, _)
                assert(not err, err)
                save_breakpoints_to_file(bp_file, {}, callback)
            end)
        else
            uv.fs_stat(bp_file, function(err, _)
                if err ~= nil then
                    save_breakpoints_to_file(bp_file, {}, callback)
                else
                    callback()
                end
            end)
        end
    end)
end

function M.save_breakpoints(bps, callback)
    ensure_plugin_directory(function()
        save_breakpoints_to_file(bp_file, bps, callback)
    end)
end

function M.read_breakpoints(callback)
    ensure_plugin_directory(function()
        uv.fs_open(bp_file, 'r', 438, function(err, fd)
            assert(not err, err)
            uv.fs_stat(bp_file, function(err, stat)
                assert(not err, err)
                uv.fs_read(fd, stat.size, 0, function(err, data)
                assert(not err, err)
                    uv.fs_close(fd, vim.schedule_wrap(function(err, _)
                    assert(not err, err)
                    local result = vim.fn.json_decode(data)
                    callback(result)
                    end))
                end)
            end)
        end)
    end)
end

return M
