local M = {}


local bp_by_id = {}
local hook_id_count = 0
local signs = require('meta-breakpoints.signs')
local dap = require('dap')
local breakpoints = require('dap.breakpoints')
local hooks = require('meta-breakpoints.hooks')
local persistent = require('meta-breakpoints.persistent_bp')


function M.get_all_breakpoints()
  local meta_breakpoints = {}
  for _, bp in pairs(bp_by_id) do
    table.insert(meta_breakpoints, bp)
  end
  return meta_breakpoints
end

local function get_breakpoint_lnum(bp)
    return signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum
end

local function get_breakpoint_at_location(bufnr, lnum)
  local sign_id = signs.get_sign_at_location(bufnr, lnum)
  if not sign_id then
    return nil
  end
  return bp_by_id[sign_id]
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
    return get_breakpoint_at_location(bp_location.bufnr, bp_location.lnum)
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

local function remove_meta_breakpoint(bufnr, lnum, bp_type)
  local bp = get_breakpoint_at_location(bufnr, lnum)
  if not bp then
    return false
  end
  if bp.meta.type ~= bp_type then
    error("Mismatched breakpoint type expected " .. bp.meta.type .. " got " .. bp_type)
  end


  signs.remove_sign(bufnr, bp.sign_id)
  bp_by_id[bp.sign_id] = nil

  if bp.meta.on_remove then
      bp.meta.on_remove()
  end
  persistent.remove_persistent_breakpoint(bp.sign_id)
  return true
end


-- use ignore_persistent if you need to have better control of the breakpoint data being saved
function M.toggle_meta_breakpoint(bp_opts, replace_old, bp_location, ignore_persistent)
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
    if remove_meta_breakpoint(bufnr, lnum, meta_opts.type) and not replace_old then
        if toggle_dap then
            toggle_dap_breakpoint(bp_opts, replace_old, bp_location)
        end
        return nil
    end

    if toggle_dap then
        toggle_dap_breakpoint(bp_opts, replace_old, bp_location)
    end

    local priority = 11
    if meta_opts.type == "HookBreakpoint" then
      priority = 10
    end
    local sign_id = vim.fn.sign_place(
        0,
        signs.sign_group,
        get_breakpoint_type_sign(meta_opts.type),
        bufnr,
        { lnum = lnum; priority = priority }
    )
    local bp = {
        bufnr = bufnr,
        meta = meta_opts,
        sign_id = sign_id
    }
    bp_by_id[sign_id] = bp
    if meta_opts.persistent and not ignore_persistent then
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

    local remove_hook = string.format("INTERNAL-remove-%s", hook_id_count)
    local function on_remove()
        hooks.remove_hook(remove_hook)
        hooks.remove_hook(trigger_hook, hook_id_count)
    end

    meta_opts.type = 'hook'
    meta_opts.hook_name = remove_hook
    meta_opts.toggle_dap = false
    meta_opts.on_remove = on_remove

    local bp = M.toggle_meta_breakpoint({meta = meta_opts}, replace_old, bp_location, true)
    if bp == nil then
        return
    end

    if meta_opts.persistent then
        local saved_bp_opts = vim.deepcopy(bp_opts)
        local saved_meta_opts = saved_bp_opts.meta
        saved_meta_opts.hook_name = nil
        saved_meta_opts.on_remove = nil
        --saved_meta_opts.is_persistent = true
        persistent.add_persistent_breakpoint(bp.sign_id, bp.bufnr, saved_bp_opts, saved_meta_opts, true)
    end

    local function place_breakpoint()
        toggle_dap_breakpoint({}, true, {bufnr = bp.bufnr, lnum = get_breakpoint_lnum(bp)})
        dap.continue()
    end
    local function remove_breakpoint()
        toggle_dap_breakpoint({}, nil, { bufnr = bp.bufnr, lnum = get_breakpoint_lnum(bp)})
    end


    hooks.register_to_hook(trigger_hook, hook_id_count, place_breakpoint)
    hooks.register_to_hook(remove_hook, hook_id_count, remove_breakpoint)
    hook_id_count = hook_id_count + 1
end

function M.simple_meta_breakpoint(hook_name)
    M.toggle_meta_breakpoint({meta = {type = 'meta', hook_name = hook_name}})
end

local function trigger_hooks()
    local bufnr = vim.api.nvim_get_current_buf()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local bp = get_breakpoint_at_location(bufnr, lnum)
    if not bp then
      return
    end
    local hooks_list = hooks.get_hooks_mapping(bp.meta.hook_name) or {}
    for _, func in pairs(hooks_list) do
        func()
    end
end

dap.listeners.after.stackTrace['meta-breakpoints.trigger_hooks'] = trigger_hooks

return M
