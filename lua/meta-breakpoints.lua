local M = {}

local meta_breakpoints = {}
--local hook_breakpoints = {}
local hooks_mapping = {}
local sign_group = 'meta-breakpoints'
local dap = require('dap')


--local breakpoints = require('dap.breakpoints')
--local Session = require('dap.session')

--local prev_event = Session.event_stopped
--function Session:event_stopped(stopped)
    --print("inside the wrapper")
    --print("calling the wrapped")
    --prev_event(stopped)
    --print("finished the wrapped")
--end
--print(vim.inspect(Session.event_stopped))
--Session.event_stopped = new_event

function M.register_to_hook(hook_name, hook_function)
    if hooks_mapping.hook_name then
        table.insert(hooks_mapping[hook_name], hook_function)
    else
        hooks_mapping[hook_name] = { hook_function }
    end
end

--M.register_to_hook('debug_hook', function() print('hook debug_hook called') end)


function M.toggle_meta_breakpoint(hook_name)
    local bufnr = vim.api.nvim_get_current_buf()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if M.remove_meta_breakpoint(bufnr, lnum) then
        dap.toggle_breakpoint({}, {}, {})
        return
    end
    local sign_id = vim.fn.sign_place(
        0,
        sign_group,
        'MetaBreakpoint',
        bufnr,
        { lnum = lnum; priority = 12 }
    )
    local bp = {
        type = "continue",
        bufnr = bufnr,
        lnum = lnum,
        hook_name = hook_name,
        sign_id = sign_id,
    }
    table.insert(meta_breakpoints, bp)
    dap.toggle_breakpoint({}, {}, {})
end

function M.toggle_hook_breakpoint(hook_name)
    local bufnr = vim.api.nvim_get_current_buf()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    if M.remove_meta_breakpoint(bufnr, lnum) then
        return
    end
    --local sign_id = vim.fn.sign_place(
        --0,
        --sign_group,
        --'HookBreakpoint',
        --bufnr,
        --{ lnum = lnum; priority = 12 }
    --)
    local bp = {
        bufnr = bufnr,
        lnum = lnum,
        hook_name = "",
        --sign_id = sign_id,
    }
    table.insert(meta_breakpoints, bp)
    print('inserted hook breakpoint')
    local function place_breakpoint()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_buf(win) == bufnr then
                print('activating breakpoint')
                vim.api.nvim_win_set_cursor(win, {lnum, 1})
                dap.toggle_breakpoint({}, "1", {})
                vim.cmd('sleep 5') -- instead of sleep you should listen to the add breakpoint hook and continue when it's done
            end
        end
    end
    M.register_to_hook(hook_name, place_breakpoint)
end

function M.remove_meta_breakpoint(bufnr, lnum)
    for i, bp in ipairs(meta_breakpoints) do
        if bp.bufnr == bufnr and bp.lnum == lnum then
            vim.fn.sign_unplace(sign_group, { buffer = bufnr, id = bp.sign_id })
            table.remove(meta_breakpoints, i)
            print('removed breakpoint')
            return true
        end
    end
    return false
end

local function continue_meta_breakpoint()
    local bufnr = vim.api.nvim_get_current_buf()
    --print('bufnr=' .. bufnr)
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    --print('lnum=' .. lnum)
    for _, bp in ipairs(meta_breakpoints) do
        --print('comparing with ' .. vim.inspect(bp))
        if (bp.bufnr == bufnr and bp.lnum == lnum) then
            --print('continuing')
            local hooks = hooks_mapping[bp.hook_name] or {}
            for _, func in ipairs(hooks) do
                func()
            end
            if bp.type == 'continue' then
                print('before continue')
                dap.continue()
            end
        end
    end
end

dap.listeners.after.stackTrace['meta-breakpoints.continue_meta'] = continue_meta_breakpoint

function M.setup()
    vim.fn.sign_define('MetaBreakpoint', { text = "M", texthl = "", linehl = "", numhl = "" })
    --vim.fn.sign_define('HookBreakpoint', { text = "H", texthl = "", linehl = "", numhl = "" })
end
M.setup()

return M
