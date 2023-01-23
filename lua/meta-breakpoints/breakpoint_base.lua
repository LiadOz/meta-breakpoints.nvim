local M = {}


local meta_breakpoints = {}
local signs = require('meta-breakpoints.signs')
local dap = require('dap')
local breakpoints = require('dap.breakpoints')
local hooks = require('meta-breakpoints.hooks')
local persistent = require('meta-breakpoints.persistent_bp')


function M.get_all_breakpoints()
    return meta_breakpoints
end


local function get_breakpoint_lnum(bp)
    return signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum
end


local breakpoint_sign_type = {hook = 'HookBreakpoint'}
local function get_breakpoint_type_sign(breakpoint_type)
    local result = breakpoint_sign_type[breakpoint_type]
    if not result then
        result = 'MetaBreakpoint'
    end
    return result
end

local function setup_breakpoint_location(bp_location)
    bp_location = bp_location or {}
    local bufnr = bp_location.bufnr
    local lnum = bp_location.lnum
    if bufnr == nil and lnum == nil then
        bp_location.bufnr = vim.api.nvim_get_current_buf()
        bp_location.lnum = vim.api.nvim_win_get_cursor(0)[1]
    elseif not (bufnr ~= nil and lnum ~= nil) then
        error("Bad location passed, must use both bufnr and lnum")
    end
    return bp_location
end

function M.get_breakpoint(bp_location)
    bp_location = setup_breakpoint_location()
    for _, bp in ipairs(meta_breakpoints) do
        if bp.bufnr == bp_location.bufnr and get_breakpoint_lnum(bp) == bp_location.lnum then
            return bp
        end
    end
    return false
end

local function toggle_dap_breakpoint(bp_opts, replace_old, bp_location)
    bp_opts = bp_opts or {}
    bp_location = setup_breakpoint_location(bp_location)
    bp_opts.replace = replace_old
    local bufnr = bp_location.bufnr
    local lnum = bp_location.lnum

    breakpoints.toggle(bp_opts, bufnr, lnum)
    local session = dap.session()
    if session then
        local bps = breakpoints.get(bufnr)
        session:set_breakpoints(bps)
    end
end

local function remove_meta_breakpoint(bufnr, lnum)
    for i, bp in ipairs(meta_breakpoints) do
        if bp.bufnr == bufnr and get_breakpoint_lnum(bp)== lnum then
            vim.fn.sign_unplace(signs.sign_group, { buffer = bufnr, id = bp.sign_id })
            table.remove(meta_breakpoints, i)
            if bp.meta.on_remove then
                bp.meta.on_remove()
            end
            persistent.remove_persistent_breakpoint(bp.sign_id)
            return true
        end
    end
    return false
end

function M.toggle_meta_breakpoint(bp_opts, replace_old, bp_location)
    bp_opts = bp_opts or {}
    bp_location = setup_breakpoint_location(bp_location)
    local bufnr = bp_location.bufnr
    local lnum = bp_location.lnum
    bp_opts.replace = replace_old

    local meta_opts = bp_opts.meta or {}
    meta_opts.type = meta_opts.type or 'meta'
    bp_opts.meta = nil
    local toggle_dap = meta_opts.toggle_dap
    if toggle_dap == nil then
        toggle_dap = true
    end
    if remove_meta_breakpoint(bufnr, lnum) and not replace_old then
        if toggle_dap then
            toggle_dap_breakpoint(bp_opts, replace_old, bp_location)
        end
        return nil
    end

    local sign_id = vim.fn.sign_place(
        0,
        signs.sign_group,
        get_breakpoint_type_sign(meta_opts.type),
        bufnr,
        { lnum = lnum; priority = 12 }
    )
    local bp = {
        bufnr = bufnr,
        sign_id = sign_id,
        meta = meta_opts
    }
    table.insert(meta_breakpoints, bp)
    if toggle_dap then
        toggle_dap_breakpoint(bp_opts, replace_old, bp_location)
    end
    if meta_opts.persistent then
        persistent.add_persistent_breakpoint(sign_id, bufnr, bp_opts, meta_opts, true)
    end
    return bp
end


function M.load_persistent_breakpoints(callback)
    persistent.get_persistent_breakpoints(function(bp_opts, meta_opts, bp_location)
        bp_opts.meta = meta_opts
        if meta_opts.type == 'hook' then
            M.toggle_hook_breakpoint(bp_opts, false, bp_location)
        else
            M.toggle_meta_breakpoint(bp_opts, false, bp_location)
        end
    end, callback)
end


function M.toggle_hook_breakpoint(bp_opts, replace_old, bp_location)
    bp_opts = bp_opts or {}
    bp_location = setup_breakpoint_location(bp_location)
    local meta_opts = bp_opts.meta or {}
    assert(meta_opts.hook_name == nil, "Cannot set hook_name for hook breakpoint")
    assert(meta_opts.on_remove == nil, "Cannot set on_remove for hook breakpoint")
    assert(meta_opts.trigger_hook, "Must have trigger_hook for hook breakpoint")
    local trigger_hook = meta_opts.trigger_hook

    local bufnr = bp_location.bufnr
    local lnum = bp_location.lnum
    local id = string.format("%d-%d", bufnr, lnum)
    local remove_hook = string.format("INTERNAL-remove-%s", id)
    local function on_remove()
        hooks.remove_hook(remove_hook)
        hooks.remove_hook(trigger_hook, id)
    end

    meta_opts.type = 'hook'
    meta_opts.hook_name = remove_hook
    meta_opts.toggle_dap = false
    meta_opts.on_remove = on_remove
    local is_persistent = meta_opts.persistent
    meta_opts.persistent = false
    local bp = M.toggle_meta_breakpoint({meta = meta_opts}, replace_old, bp_location)
    if bp == nil then
        return
    end

    if is_persistent then
        local saved_bp_opts = vim.deepcopy(bp_opts)
        local saved_meta_opts = saved_bp_opts.meta
        saved_meta_opts.hook_name = nil
        saved_meta_opts.on_remove = nil
        saved_meta_opts.is_persistent = true
        persistent.add_persistent_breakpoint(bp.sign_id, bp.bufnr, saved_bp_opts, saved_meta_opts, true)
    end

    local function place_breakpoint()
        toggle_dap_breakpoint({}, true, {bufnr = bp.bufnr, lnum = get_breakpoint_lnum(bp)})
        dap.continue()
    end
    local function remove_breakpoint()
        toggle_dap_breakpoint({}, nil, { bufnr = bp.bufnr, lnum = get_breakpoint_lnum(bp)})
    end


    hooks.register_to_hook(trigger_hook, id, place_breakpoint)
    hooks.register_to_hook(remove_hook, id, remove_breakpoint)
end

function M.simple_meta_breakpoint(hook_name)
    M.toggle_meta_breakpoint({meta = {type = 'meta', hook_name = hook_name}})
end

local function trigger_hooks()
    local bufnr = vim.api.nvim_get_current_buf()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    for _, bp in ipairs(meta_breakpoints) do
        if bp.bufnr == bufnr and get_breakpoint_lnum(bp) == lnum then
            local hooks_list = hooks.get_hooks_mapping(bp.meta.hook_name) or {}
            for id, func in pairs(hooks_list) do
                print("calling hook: " .. bp.meta.hook_name .. " id: " .. id)
                func()
            end
        end
    end
end

--local function log_event(session, event)
    --print("event " .. vim.inspect(event))
    --print("session " .. vim.inspect(session))
--end

dap.listeners.after.stackTrace['meta-breakpoints.trigger_hooks'] = trigger_hooks
--dap.listeners.after.event_stopped['meta-breakpoints.log'] = log_event


return M
