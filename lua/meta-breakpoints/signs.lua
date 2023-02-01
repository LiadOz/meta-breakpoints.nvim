local M = {}
M.sign_group = 'meta-breakpoints'

function M.get_sign_id_data(sign_id, bufnr)
    local placements = vim.fn.sign_getplaced(bufnr, {group = M.sign_group, id = sign_id})
    local lnum = placements[1].signs[1].lnum
    return {lnum = lnum}
end

function M.get_buf_signs(bufnr)
    local placement = vim.fn.sign_getplaced(bufnr, {group = M.sign_group})[1]
    local result = {}
    for _, sign_data in ipairs(placement.signs) do
        table.insert(result, {sign_id = sign_data.id, lnum = sign_data.lnum})
    end
    return result
end

function M.get_sign_at_location(bufnr, lnum)
  local signs = vim.fn.sign_getplaced(bufnr, {group = M.sign_group, lnum = lnum})[1].signs
  if #signs > 0 then
    return signs[1].id
  end
  return nil
end

function M.remove_sign(bufnr, sign_id)
  vim.fn.sign_unplace(M.sign_group, { buffer = bufnr, id = sign_id})
end

return M
