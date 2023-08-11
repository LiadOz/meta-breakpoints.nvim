local M = {}

local log = require("meta-breakpoints.log")
local last_sign_id = 0
local sign_group = "meta-breakpoints"

---@param sign_id number
---@param bufnr number
---@return {lnum: number}
function M.get_sign_id_data(sign_id, bufnr)
  local placements = vim.fn.sign_getplaced(bufnr, { group = sign_group, id = sign_id })
  local lnum = placements[1].signs[1].lnum
  return { lnum = lnum }
end

---@param bufnr number|nil
---@return {sign_id: number, lnum: number}[]
function M.get_buf_signs(bufnr)
  local buffers = {}
  if bufnr then
    table.insert(buffers, bufnr)
  else
    for _, placement in ipairs(vim.fn.sign_getplaced()) do
      local ff = placement.bufnr
      table.insert(buffers, ff)
    end
  end

  local result = {}
  for _, buffer in ipairs(buffers) do
    local placement = vim.fn.sign_getplaced(buffer, { group = sign_group })[1]
    for _, sign_data in ipairs(placement.signs) do
      table.insert(result, { sign_id = sign_data.id, lnum = sign_data.lnum })
    end
  end
  return result
end

function M.get_sign_at_location(bufnr, lnum)
  local signs = vim.fn.sign_getplaced(bufnr, { group = sign_group, lnum = lnum })[1].signs
  if #signs > 0 then
    return signs[1].id
  end
  return nil
end

local function get_new_sign_id()
  last_sign_id = last_sign_id + 1
  return last_sign_id
end

---@param bufnr number
---@param lnum number
---@param sign_type string
---@param priority number|nil
---@return number sign_id
function M.place_sign(bufnr, lnum, sign_type, priority)
  priority = priority or 11
  local sign_id = vim.fn.sign_place(get_new_sign_id(), sign_group, sign_type, bufnr, { lnum = lnum, priority = 11 })
  log.fmt_trace("sign placed bufnr:%s lnum:%s sign_id:%s", bufnr, lnum, sign_id)
  return sign_id
end

function M.remove_sign(bufnr, sign_id)
  log.fmt_trace("removing sign_id:%s from bufnr:%s", sign_id, bufnr)
  vim.fn.sign_unplace(sign_group, { buffer = bufnr, id = sign_id })
end

function M.clear_signs()
  log.trace("clearing all signs")
  vim.fn.sign_unplace(sign_group)
end

return M
