local M = {}


local persistent_breakpoints = {}

local utils = require('meta-breakpoints.utils')
local signs = require('meta-breakpoints.signs')

local function save_breakpoints(breakpoints, callback)
  local bps = {}
  print(string.format("saving %s breakpoints", #breakpoints))
  for _, bp in pairs(breakpoints) do
    table.insert(bps, bp)
  end
  print(string.format("found %s breakpoints", #bps))
  utils.save_breakpoints(bps, callback)
end

--- Asynchronously get persistent breakpoints
---@param per_bp_callback fun(bufnr: number, lnum: number, meta_opts: MetaOpts)
---@param callback fun()
function M.get_persistent_breakpoints(per_bp_callback, callback)
  utils.read_breakpoints(function(breakpoints_data)
    for _, bp_data in ipairs(breakpoints_data) do
      local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(bp_data.file_name))
      per_bp_callback(bufnr, bp_data.lnum, bp_data.meta_opts)
    end
    if callback then
      callback()
    end
  end)
end

---@param sign_id number
---@param bufnr number
---@param meta_opts MetaOpts
---@param update_file boolean
function M.add_persistent_breakpoint(sign_id, bufnr, meta_opts, update_file)
  local sign_data = signs.get_sign_id_data(sign_id, bufnr)
  local file_name = vim.api.nvim_buf_get_name(bufnr)

  local bp = {
    file_name = file_name,
    lnum = sign_data.lnum,
    meta_opts = meta_opts
  }
  persistent_breakpoints[sign_id] = bp
  print('adding persistent breakpoint sign_id:' .. sign_id)
  if update_file then
    print('updating breakpoints file')
    save_breakpoints(persistent_breakpoints)
  end
end

function M.update_buf_breakpoints(bufnr, update_file, override_modified, callback)
  bufnr = bufnr or vim.fn.bufnr()
  local file_name = vim.api.nvim_buf_get_name(bufnr)
  local buf_signs = signs.get_buf_signs(bufnr)
  local modified = false
  print(string.format('updating buf %s breakpoints sign_count:%s', bufnr, #buf_signs))
  for _, sign_data in ipairs(buf_signs) do
    local curr_bp = persistent_breakpoints[sign_data.sign_id]
    if curr_bp and (curr_bp.lnum ~= sign_data.lnum or curr_bp.file_name ~= file_name) then
      modified = true
      curr_bp.lnum = sign_data.lnum
      curr_bp.file_name = file_name
    end
  end
  if (modified or override_modified) and update_file then
    save_breakpoints(persistent_breakpoints, callback)
  else
    vim.schedule(callback)
  end
end

function M.remove_persistent_breakpoint(sign_id, update_file)
  persistent_breakpoints[sign_id] = nil
  if update_file then
    save_breakpoints(persistent_breakpoints)
  end
end

function M.clear(callback)
  for key, _ in pairs(persistent_breakpoints) do
    persistent_breakpoints[key] = nil
  end
  save_breakpoints(persistent_breakpoints, callback)
end

return M
