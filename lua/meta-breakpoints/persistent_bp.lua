local M = {}


local persistent_breakpoints = {}
local utils = require('meta-breakpoints.utils')
local signs = require('meta-breakpoints.signs')

local function save_breakpoints(breakpoints)
    local bps = {}
    for _, bp in pairs(breakpoints) do
        table.insert(bps, bp)
    end
    utils.save_breakpoints(bps)
end

function M.get_persistent_breakpoints(callback)
    utils.read_breakpoints(function(breakpoints_data)
        for _, bp_data in ipairs(breakpoints_data) do
            local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(bp_data.file_name))
            local bp_location = { lnum = bp_data.lnum, bufnr = bufnr }
            callback(bp_data.bp_opts, bp_data.meta_opts, bp_location)
        end
    end)
end

function M.add_persistent_breakpoint(sign_id, bufnr, bp_opts, meta_opts, update_file)
    local bp_location = signs.get_sign_id_data(sign_id, bufnr)
    local file_name = vim.api.nvim_buf_get_name(bufnr)

    local bp = {
        file_name = file_name,
        lnum = bp_location.lnum,
        bp_opts = bp_opts,
        meta_opts = meta_opts
    }
    persistent_breakpoints[sign_id] = bp
    if update_file then
        save_breakpoints(persistent_breakpoints)
    end
end

function M.update_curr_buf_breakpoints(update_file)
    local bufnr = vim.fn.bufnr()
    local file_name = vim.api.nvim_buf_get_name(bufnr)
    local buf_signs = signs.get_buf_signs(bufnr)
    local modified = false
    for _, sign_data in ipairs(buf_signs) do
        local curr_bp = persistent_breakpoints[sign_data.sign_id]
        if curr_bp and (curr_bp.lnum ~= sign_data.lnum or curr_bp.file_name ~= file_name) then
            modified = true
            curr_bp.lnum = sign_data.lnum
            curr_bp.file_name = file_name
        end    end
    if modified and update_file then
        save_breakpoints(persistent_breakpoints)
    end
end

function M.remove_persistent_breakpoint(sign_id)
    persistent_breakpoints[sign_id] = nil
    save_breakpoints(persistent_breakpoints)
end

return M
