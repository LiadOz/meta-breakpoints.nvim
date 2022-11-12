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

return M
