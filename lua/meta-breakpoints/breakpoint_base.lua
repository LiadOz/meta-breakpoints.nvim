local M = {}


---@alias PlacementOpts {bufnr: number, lnum: number, replace: boolean}
---@alias DapOpts {condition: string, log_message: string, hit_condition: string}
---@alias MetaOpts {type: string, hit_hook: string, trigger_hook: string, remove_hook: string, persistent: boolean, toggle_dap_breakpoint: boolean}
---@alias BreakpointData {bufnr: number, sign_id: number, dap_opts: DapOpts, meta: MetaOpts}

---@type table<number, BreakpointData>
local bp_by_id = {}
local hook_breakpoint_count = 0
local signs = require('meta-breakpoints.signs')
local dap = require('dap')
local breakpoints = require('dap.breakpoints')
local hooks = require('meta-breakpoints.hooks')
local persistence = require('meta-breakpoints.persistence')
local config = require('meta-breakpoints.config')
local log = require('meta-breakpoints.log')


---@return BreakpointData[]
function M.get_breakpoints(bufnr)
  local meta_breakpoints = {}
  for _, sign_data in pairs(signs.get_buf_signs(bufnr)) do
    table.insert(meta_breakpoints, bp_by_id[sign_data.sign_id])
  end
  return meta_breakpoints
end

---@param bp BreakpointData
---@return number
local function get_breakpoint_lnum(bp)
  return signs.get_sign_id_data(bp.sign_id, bp.bufnr).lnum
end

function M.update_buf_breakpoints(bufnr, update_file, override_changed, callback)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local breakpoints_data = M.get_breakpoints(bufnr)

  local persistent_data = {}
  local file_name = vim.uri_to_fname(vim.uri_from_bufnr(bufnr))
  for _, breakpoint_data in ipairs(breakpoints_data) do
    local meta_opts = breakpoint_data.meta
    if meta_opts.persistent then
      meta_opts = vim.deepcopy(meta_opts)
      if meta_opts.hit_hook and string.sub(meta_opts.hit_hook, 0, 1) == '_' then
        meta_opts.hit_hook = nil
      end
      if meta_opts.remove_hook and string.sub(meta_opts.remove_hook, 0, 1) == '_' then
        meta_opts.remote_hook = nil
      end
      table.insert(persistent_data,
        {
          lnum = get_breakpoint_lnum(breakpoint_data),
          dap_opts = breakpoint_data.dap_opts,
          meta_opts = meta_opts
        })
    end
  end
  if #persistent_data == 0 then
    persistent_data = nil
  end
  persistence.update_file_breakpoints(file_name, persistent_data, update_file, override_changed, callback)
end

---@param bufnr number
---@param lnum number
---@return BreakpointData|nil
function M.get_breakpoint_at_location(bufnr, lnum)
  local sign_id = signs.get_sign_at_location(bufnr, lnum)
  if not sign_id then
    return nil
  end
  return bp_by_id[sign_id]
end

local breakpoint_sign_type = { hook = 'HookBreakpoint' }
--- Returns the breakpoint sign name
---@param breakpoint_type string breakpoint passed in the meta options
---@return string
local function get_breakpoint_type_sign(breakpoint_type)
  local result = breakpoint_sign_type[breakpoint_type]
  if not result then
    result = 'MetaBreakpoint'
  end
  return result
end

--- Create a breakpoint location
---@param opts PlacementOpts|nil
---@return PlacementOpts
local function setup_placement_opts(opts)
  opts = opts or {}
  local bufnr = opts.bufnr
  local lnum = opts.lnum
  if bufnr == nil and lnum == nil then
    opts.bufnr = vim.api.nvim_get_current_buf()
    opts.lnum = vim.api.nvim_win_get_cursor(0)[1]
  elseif not (bufnr ~= nil and lnum ~= nil) then
    error("Bad location passed, must use both bufnr and lnum")
  end
  opts.replace = opts.replace or false
  return opts
end

function M.get_breakpoint_at_cursor()
  local placement_opts = setup_placement_opts()
  return M.get_breakpoint_at_location(placement_opts.bufnr, placement_opts.lnum)
end

--- Toggle breakpoint using nvim-dap
---@param dap_opts DapOpts|nil
---@param placement_opts PlacementOpts
local function toggle_dap_breakpoint(dap_opts, placement_opts)
  local opts = vim.deepcopy(dap_opts or {})
  opts.replace = placement_opts.replace
  breakpoints.toggle(opts, placement_opts.bufnr, placement_opts.lnum)
  local session = dap.session()
  if session then
    local bps = breakpoints.get(placement_opts.bufnr)
    session:set_breakpoints(bps)
  end
end

---@param bufnr number
---@param lnum number
---@return boolean removed whether a breakpoint was removed
local function remove_meta_breakpoint(bufnr, lnum)
  local bp = M.get_breakpoint_at_location(bufnr, lnum)
  if not bp then
    return false
  end

  signs.remove_sign(bufnr, bp.sign_id)
  bp_by_id[bp.sign_id] = nil

  if bp.meta.remove_hook then
    for _, func in pairs(hooks.get_hooks_mapping(bp.meta.remove_hook)) do
      func()
    end
  end
  if bp.meta.persistent then
    M.update_buf_breakpoints(bufnr, config.persistent_breakpoints.persist_on_placement)
  end
  return true
end

--- Place a meta breakpoint
---@param dap_opts DapOpts|nil
---@param meta_opts MetaOpts|nil
---@param placement_opts PlacementOpts|nil
---@return BreakpointData|nil breakpoint_data
function M.toggle_meta_breakpoint(dap_opts, meta_opts, placement_opts)
  meta_opts = meta_opts or {}
  meta_opts.type = meta_opts.type or 'meta'
  placement_opts = setup_placement_opts(placement_opts)
  local bufnr = placement_opts.bufnr
  local lnum = placement_opts.lnum
  log.fmt_trace('toggling breakpoint at bufnr:%s lnum:%s', bufnr, lnum)

  if meta_opts.persistent == nil then
    meta_opts.persistent = config.persistent_breakpoints.persistent_by_default
  end
  if meta_opts.persistent and config.persistent_breakpoints.enabled == false then
    error("Cannot set breakpoint to be persistent, persistent breakpoints are disabled")
  end

  if meta_opts.toggle_dap_breakpoint == nil then
    meta_opts.toggle_dap_breakpoint = true
  end
  if meta_opts.toggle_dap_breakpoint then
    toggle_dap_breakpoint(dap_opts, placement_opts)
  end

  if remove_meta_breakpoint(bufnr, lnum) and not placement_opts.replace then
    -- no need to replace removed breakpoint
    breakpoints.remove(bufnr, lnum)
    return nil
  end


  local sign_id = signs.place_sign(bufnr, lnum, get_breakpoint_type_sign(meta_opts.type))
  local bp = {
    bufnr = bufnr,
    sign_id = sign_id,
    dap_opts = dap_opts,
    meta = meta_opts,
  }
  bp_by_id[sign_id] = bp
  if meta_opts.persistent then
    M.update_buf_breakpoints(bufnr, config.persistent_breakpoints.persist_on_placement)
  end
  return bp
end

---@param bufnr number
---@param persistent_data PersistentBreakpointFileData
local function load_buffer_persistent_breakpoint(bufnr, persistent_data)
  local meta_opts = persistent_data.meta_opts
  local dap_opts = persistent_data.dap_opts

  local placement_opts = setup_placement_opts({ bufnr = bufnr, lnum = persistent_data.lnum })
  if meta_opts.type == 'hook' then
    M.toggle_hook_breakpoint(dap_opts, meta_opts, placement_opts)
  else
    M.toggle_meta_breakpoint(dap_opts, meta_opts, placement_opts)
  end
end

local count = 0
---@param callback function|nil
---@param opts {all_buffers: boolean, bufnr: number}|nil
function M.load_persistent_breakpoints(callback, opts)
  local my_count = count
  count = count + 1
  opts = opts or { all_buffers = true }
  local target_bufnr = opts.bufnr == 0 and vim.fn.bufnr() or opts.bufnr
  if opts.all_buffers then
    log.debug('loading breakpoints in all buffers clearing all breakpoints')
    M.clear()
  end
  persistence.read_persistent_breakpoints(function(persistent_breakpoints)
    for fname, breakpoints_data in pairs(persistent_breakpoints) do
      if vim.fn.bufloaded(fname) == 0 then
        goto continue
      end
      local bufnr = vim.uri_to_bufnr(vim.uri_from_fname(fname))
      for _, persistent_data in pairs(breakpoints_data) do
        if opts.all_buffers or bufnr == target_bufnr then
          load_buffer_persistent_breakpoint(bufnr, persistent_data)
        end
      end
      ::continue::
    end
    if callback then
      callback()
    end
  end)
end

---@param bufnr number
function M.ensure_persistent_breakpoints(bufnr)
  if #M.get_breakpoints(bufnr) == 0 then
    local fname = vim.uri_to_fname(vim.uri_from_bufnr(bufnr))
    local persistent_breakpoints = persistence.get_persistent_breakpoints()[fname]
    if not persistent_breakpoints or #persistent_breakpoints == 0 then
      return
    end
    for _, data in pairs(persistent_breakpoints) do
      load_buffer_persistent_breakpoint(bufnr, data)
    end
  end
end

--- Place a hook breakpoint
---@param dap_opts DapOpts|nil
---@param meta_opts MetaOpts
---@param placement_opts PlacementOpts|nil
function M.toggle_hook_breakpoint(dap_opts, meta_opts, placement_opts)
  placement_opts = setup_placement_opts(placement_opts)
  meta_opts = meta_opts or {}
  assert(meta_opts.trigger_hook, "Must have trigger_hook for hook breakpoint")
  assert(not meta_opts.toggle_dap_breakpoint, "Can't set toggle_dap_breakpoint for hook breakpoint")
  local trigger_hook = meta_opts.trigger_hook

  meta_opts.type = 'hook'
  meta_opts.hit_hook = meta_opts.hit_hook or string.format("_hit-%s", hook_breakpoint_count)
  meta_opts.remove_hook = meta_opts.remove_hook or string.format("_remove-%s", hook_breakpoint_count)
  meta_opts.toggle_dap_breakpoint = false

  local bp = M.toggle_meta_breakpoint(dap_opts, meta_opts, placement_opts)
  if bp == nil then
    return
  end

  local function place_breakpoint()
    toggle_dap_breakpoint(dap_opts, { bufnr = bp.bufnr, lnum = get_breakpoint_lnum(bp) })
    if dap.session() then
      dap.continue()
    end
  end
  local function remove_breakpoint()
    toggle_dap_breakpoint({}, { bufnr = bp.bufnr, lnum = get_breakpoint_lnum(bp) })
  end

  local trigger_id = hooks.register_to_hook(trigger_hook, place_breakpoint)
  local hit_id = hooks.register_to_hook(meta_opts.hit_hook, remove_breakpoint)

  local function on_remove()
    hooks.remove_hook(meta_opts.hit_hook, hit_id)
    hooks.remove_hook(trigger_hook, trigger_id)
    hooks.remove_hook(meta_opts.remove_hook)
  end

  hooks.register_to_hook(meta_opts.remove_hook, on_remove)
  hook_breakpoint_count = hook_breakpoint_count + 1
end

function M.set_persistent_breakpoints(session, callback)
  local persistent_breakpoints = persistence.get_persistent_breakpoints()
  local unloaded_files = {}
  for file_name, _ in pairs(persistent_breakpoints) do
    if vim.fn.bufloaded(file_name) == 0 or #M.get_breakpoints(vim.uri_to_bufnr(vim.uri_from_fname(file_name))) == 0 then
      table.insert(unloaded_files, file_name)
    end
  end
  local loaded_breakpoints = {}
  if #unloaded_files == 0 then
    callback(loaded_breakpoints)
  end
  local num_requests = #unloaded_files
  for _, file_name in pairs(unloaded_files) do
    local file_breakpoints = persistent_breakpoints[file_name]
    table.insert(loaded_breakpoints, file_breakpoints)
    local payload = {
      source = {
        path = file_name,
        name = vim.fn.fnamemodify(file_name, ':t')
      },
      sourceModified = false,
      breakpoints = vim.tbl_map(
        function(bp)
          -- trim extra information like the state
          return {
            line = bp.lnum,
            condition = bp.dap_opts.condition,
            hitCondition = bp.dap_opts.hit_condition,
            logMessage = bp.dap_opts.log_message,
          }
        end,
        file_breakpoints
      ),
      lines = vim.tbl_map(function(x) return x.lnum end, file_breakpoints),
    }
    session:request('setBreakpoints', payload, function(err, resp)
      if err then
        log.fmt_error("Failed to set persistent breakpoint of file %s, error: %s", file_name, err)
      elseif resp then
        for _, bp in pairs(resp.breakpoints) do
          if not bp.verified then
            log.fmt_warning("Server rejected breakpoint in %s:%s", file_name, bp.line)
          end
        end
      end
      num_requests = num_requests - 1
      if num_requests == 0 and callback then
        callback(loaded_breakpoints)
      end
    end)
  end
end

function M.simple_meta_breakpoint(hook_name)
  M.toggle_meta_breakpoint({}, { type = 'meta', hit_hook = hook_name })
end

---@param bufnr number|nil
---@param lnum number|nil
function M.trigger_hooks(bufnr, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
  local bp = M.get_breakpoint_at_location(bufnr, lnum)
  if not bp then
    return
  end
  if not bp.meta.hit_hook then
    return
  end
  local hooks_list = hooks.get_hooks_mapping(bp.meta.hit_hook) or {}
  log.fmt_trace('Calling hook %s registered functions (x%s)', bp.meta.hit_hook, #hooks_list)
  for _, func in pairs(hooks_list) do
    func()
  end
end

function M.clear()
  breakpoints.clear()
  hooks.clear_hooks()
  signs.clear_signs()
  bp_by_id = {}
end

dap.listeners.after.event_initialized['meta-breakpoints.initialize'] = function(session)
  local completed = false
  M.set_persistent_breakpoints(session, function() completed = true end)
  vim.wait(5000, function()
    return completed
  end)
  if not completed then
    log.fmt_error("Setting persistent breakpoints has timed out")
  end
end

dap.listeners.after.stackTrace['meta-breakpoints.trigger_hooks'] = function()
  local bufnr = vim.api.nvim_get_current_buf()
  M.ensure_persistent_breakpoints(bufnr)
  M.trigger_hooks(bufnr)
end

return M
