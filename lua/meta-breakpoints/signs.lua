local M = {}

local log = require("meta-breakpoints.log")
local last_sign_id = 100000 -- use a high sign id to take priority over nvim-dap breakpoint signs but not the DapStopped sign
local ns = vim.api.nvim_create_namespace("meta-breakpoints")

---@param sign_id number
---@param bufnr number
---@return {lnum: number}
function M.get_sign_id_data(sign_id, bufnr)
  log.fmt_trace("looking for sign_id %s in bufnr %s", sign_id, bufnr)
  return { lnum = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, sign_id, {})[1] + 1 }
end

---@param bufnr number
---@return {sign_id: number, lnum: number}[]
local function get_buffer_signs(bufnr)
  return vim.tbl_map(function(extmark_data)
    return { sign_id = extmark_data[1], lnum = extmark_data[2] + 1 }
  end, vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}))
end

---@param bufnr number|nil if nil is passed return signs in all of the buffers
---@return {sign_id: number, lnum: number}[]
function M.get_buf_signs(bufnr)
  if bufnr then
    return get_buffer_signs(bufnr)
  end
  local result = {}
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    for _, buf_sign in ipairs(get_buffer_signs(buffer)) do
      table.insert(result, buf_sign)
    end
  end
  return result
end

function M.get_sign_at_location(bufnr, lnum)
  local buf_signs = M.get_buf_signs(bufnr)
  for _, buf_sign in ipairs(buf_signs) do
    if buf_sign.lnum == lnum then
      return buf_sign.sign_id
    end
  end
  return nil
end

local function get_new_sign_id()
  last_sign_id = last_sign_id + 1
  return last_sign_id
end

local priority = 21
if vim.fn.has("nvim-0.10.0") == 0 then
  priority = 22
end

---@param bufnr number
---@param lnum number
---@param sign_text string
---@param sign_hl_group string
---@param sign_id number|nil
---@return number sign_id
function M.place_sign(bufnr, lnum, sign_text, sign_hl_group, sign_id)
  sign_id = sign_id or get_new_sign_id()
  vim.api.nvim_buf_set_extmark(
    bufnr,
    ns,
    lnum - 1,
    0,
    { priority = priority, id = sign_id, sign_text = sign_text, sign_hl_group = sign_hl_group }
  )
  log.fmt_trace("sign placed bufnr:%s lnum:%s sign_id:%s", bufnr, lnum, sign_id)
  return sign_id
end

function M.remove_sign(bufnr, sign_id)
  log.fmt_trace("removing sign_id:%s from bufnr:%s", sign_id, bufnr)
  vim.api.nvim_buf_del_extmark(bufnr, ns, sign_id)
end

function M.clear_signs()
  log.trace("clearing all signs")
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_clear_namespace(buffer, ns, 0, -1)
  end
end

return M
