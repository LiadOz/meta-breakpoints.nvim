local M = {}

---@alias PlacementOpts {bufnr: number, lnum: number, replace: boolean, persistent: boolean}
---@alias BreakpointData {bufnr: number, sign_id: number, dap_opts: DapOpts, meta: MetaOpts}

---@type table<number, MetaBreakpoint>
local bp_by_sign_id = {}
---@type table<MetaBreakpoint, boolean>
local persistent_bps = {}
---@type table<MetaBreakpoint, boolean>
local unloaded_breakpoints = {}
local signs = require("meta-breakpoints.signs")
local dap = require('dap')
local breakpoints = require('dap.breakpoints')
local hooks = require("meta-breakpoints.hooks")
local persistence = require("meta-breakpoints.persistence")
local config = require("meta-breakpoints.config")
local log = require("meta-breakpoints.log")
local dap_utils = require('meta-breakpoints.nvim_dap_utils')
local breakpoint_factory = require('meta-breakpoints.breakpoints').breakpoint_factory

---@return MetaBreakpoint[]
function M.get_breakpoints(bufnr)
  local meta_breakpoints = {}
  for _, sign_data in pairs(signs.get_buf_signs(bufnr)) do
    table.insert(meta_breakpoints, bp_by_sign_id[sign_data.sign_id])
  end
  return meta_breakpoints
end

function M.update_buf_breakpoints(bufnr, update_file, override_changed, callback)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local persistent_data = {}
  for _, bp in ipairs(M.get_breakpoints(bufnr)) do
    if bp.bufnr == bufnr and persistent_bps[bp] then
      table.insert(persistent_data, bp)
    end
  end
  if #persistent_data == 0 then
    persistent_data = nil
  end
  local file_name = vim.uri_to_fname(vim.uri_from_bufnr(bufnr))
  persistence.update_file_breakpoints(file_name, persistent_data, update_file, override_changed, callback)
end

---@param bufnr number
---@param lnum number
---@return MetaBreakpoint|nil
function M.get_breakpoint_at_location(bufnr, lnum)
  local sign_id = signs.get_sign_at_location(bufnr, lnum)
  if not sign_id then
    return nil
  end
  return bp_by_sign_id[sign_id]
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
  if opts.persistent == nil then
    opts.persistent = config.persistent_breakpoints.persistent_by_default
  end
  if opts.persistent and config.persistent_breakpoints.enabled == false then
    error("Cannot set breakpoint to be persistent, persistent breakpoints are disabled")
  end
  return opts
end

function M.get_breakpoint_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  return M.get_breakpoint_at_location(bufnr, lnum)
end

---@param bufnr number
---@param lnum number
---@return boolean removed whether a breakpoint was removed
local function remove_meta_breakpoint(bufnr, lnum)
  local bp = M.get_breakpoint_at_location(bufnr, lnum)
  if not bp then
    return false
  end

  bp_by_sign_id[bp.sign_id] = nil
  bp:remove()
  if persistent_bps[bp] then
    M.update_buf_breakpoints(bufnr, config.persistent_breakpoints.persist_on_placement)
  end
  return true
end


---@param bp MetaBreakpoint
---@param persistent boolean
local function add_breakpoint_to_collections(bp, persistent)
  bp_by_sign_id[bp.sign_id] = bp
  if persistent then
    persistent_bps[bp] = true
  end
end

---@param breakpoint_type string
---@param placement_opts PlacementOpts|nil
---@param opts {dap_opts: DapOpts, meta_opts: MetaOpts}|nil
---@return MetaBreakpoint|nil breakpoint_data
function M.toggle_breakpoint(breakpoint_type, placement_opts, opts)
  breakpoint_type = breakpoint_type or 'meta_breakpoint'
  placement_opts = setup_placement_opts(placement_opts)
  local bufnr = placement_opts.bufnr
  local lnum = placement_opts.lnum
  log.fmt_trace("toggling breakpoint at bufnr:%s lnum:%s", bufnr, lnum)

  if remove_meta_breakpoint(bufnr, lnum) and not placement_opts.replace then
    log.fmt_trace("found breakpoint at at bufnr:%s lnum:%s, not placing new breakpoint", bufnr, lnum)
    return nil
  end

  local file_name = vim.uri_to_fname(vim.uri_from_bufnr(bufnr))
  local bp = breakpoint_factory(breakpoint_type, {file_name = file_name, lnum = lnum, opts = opts}) --[[@as MetaBreakpoint]]
  bp:load(bufnr)
  add_breakpoint_to_collections(bp, placement_opts.persistent)
  if placement_opts.persistent then
    M.update_buf_breakpoints(bufnr, config.persistent_breakpoints.persist_on_placement)
  end
  return bp
end

---@param placement_opts PlacementOpts|nil
---@param opts {dap_opts: DapOpts, meta_opts: MetaOpts}|nil
---@return MetaBreakpoint|nil breakpoint_data
function M.toggle_meta_breakpoint(placement_opts, opts)
  M.toggle_breakpoint('meta_breakpoint', placement_opts, opts)
end

---@param placement_opts PlacementOpts|nil
---@param opts {dap_opts: DapOpts, meta_opts: MetaOpts}|nil
---@return MetaBreakpoint|nil breakpoint_data
function M.toggle_hook_breakpoint(placement_opts, opts)
  M.toggle_breakpoint('hook_breakpoint', placement_opts, opts)
end

function M.load_persistent_breakpoints(callback)
  persistence.load_persistent_breakpoints(function(persistent_breakpoints)
    for file_name, _ in pairs(persistent_breakpoints) do
      if vim.fn.bufloaded(file_name) > 0 then
        M.ensure_persistent_breakpoints(vim.uri_to_bufnr(vim.uri_from_fname(file_name)))
      end
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
    for _, persistent_breakpoint in pairs(persistent_breakpoints) do
      persistent_breakpoint:load(bufnr)
      add_breakpoint_to_collections(persistent_breakpoint, true)
    end
  end
end

---@param file_name string
---@param file_breakpoints MetaBreakpoint[]
local function set_session_file_breakpoints(session, file_name, file_breakpoints, callback)
  local payload = {
    source = {
      path = file_name,
      name = vim.fn.fnamemodify(file_name, ":t"),
    },
    sourceModified = false,
    breakpoints = vim.tbl_map(function(bp)
      -- trim extra information like the state
      return {
        line = bp:get_lnum(),
        condition = bp.dap_opts.condition,
        hitCondition = bp.dap_opts.hit_condition,
        logMessage = bp.dap_opts.log_message,
      }
    end, file_breakpoints),
    lines = vim.tbl_map(function(x)
      return x.lnum
    end, file_breakpoints),
  }
  session:request("setBreakpoints", payload, function(err, resp)
    if err then
      log.fmt_error("Failed to set persistent breakpoint of file %s, error: %s", file_name, err)
    elseif resp then
      for _, bp in pairs(resp.breakpoints) do
        if not bp.verified then
          log.fmt_warning("Server rejected breakpoint in %s:%s", file_name, bp.line)
        end
      end
    end
    callback()
  end)
end

function M.set_persistent_breakpoints(session, callback)
  local persistent_breakpoints = persistence.get_persistent_breakpoints()
  local file_breakpoints = {}
  local num_requests = 0
  for file_name, bps in pairs(persistent_breakpoints) do
    local current_file_breakpoints = vim.tbl_filter(function(bp)
      if not bp:is_active() or bp:is_loaded()then
        return false
      end
      return true
    end, bps)
    if #current_file_breakpoints > 0 then
      file_breakpoints[file_name] = current_file_breakpoints
      num_requests = num_requests + 1
    end
  end
  local loaded_breakpoints = {}
  if num_requests == 0 then
    vim.schedule(function() callback(loaded_breakpoints) end)
  end
  for file_name, bps in pairs(file_breakpoints) do
    set_session_file_breakpoints(session, file_name, bps, function()
      table.insert(loaded_breakpoints, bps)
      num_requests = num_requests - 1
      if num_requests == 0 and callback then
        callback(loaded_breakpoints)
      end
    end)
  end
end

local function set_persistent_breakpoints_sync(session)
  local completed = false
  M.set_persistent_breakpoints(session, function()
    completed = true
  end)
  vim.wait(5000, function()
    return completed
  end)
  if not completed then
    log.fmt_error("Setting persistent breakpoints has timed out")
  end
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
  local hit_hook = bp.meta_opts.hit_hook
  if not hit_hook then
    return
  end
  local hooks_list = hooks.get_hooks_mapping(hit_hook) or {}
  log.fmt_trace("Calling hook %s registered functions (x%s)", hit_hook, #hooks_list)
  for _, func in pairs(hooks_list) do
    func()
  end
end

function M.clear()
  breakpoints.clear()
  hooks.clear_hooks()
  signs.clear_signs()
  bp_by_sign_id = {}
end

dap.listeners.after.event_initialized["meta-breakpoints.initialize"] = function(session)
  set_persistent_breakpoints_sync(session)
end

dap.listeners.after.stackTrace["meta-breakpoints.trigger_hooks"] = function(session)
  local stop_sign = dap_utils.get_dap_stopped_sign(session)
  if stop_sign == nil then
    log.fmt_trace('no stop sign found, not triggering hooks')
    return
  end
  local bufnr = stop_sign.bufnr
  M.ensure_persistent_breakpoints(bufnr)
  M.trigger_hooks(bufnr, stop_sign.lnum)
  set_persistent_breakpoints_sync(dap.session())
  dap_utils.update_dap_breakpoints()
  dap_utils.raise_dap_stopped_priority(stop_sign)
end

return M
