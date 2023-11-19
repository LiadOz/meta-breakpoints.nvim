local M = {
  signs = {
    meta_breakpoint = {
      enabled = { text = "M" },
      disabled = { text = "M", texthl = "Comment" },
    },
    hook_breakpoint = {
      enabled = { text = "H" },
      disabled = { text = "H", texthl = "Comment" },
    },
    continue_breakpoint = {
      enabled = { text = "c" },
      disabled = { text = "c", texthl = "Comment" },
    },
  },
  persistent_breakpoints = {
    enabled = true,
    load_breakpoints_on_setup = true,
    load_breakpoints_on_buf_enter = true,
    save_breakpoints_on_buf_write = true,
    persistent_by_default = false,
    persist_on_placement = true, -- useful in tests
  },
  plugin_directory = vim.fn.stdpath("data") .. "/meta_breakpoints",
  ui = {
    prompt_if_missing = {
      continue_breakpoint = "hit_hook",
      hook_breakpoint = "trigger_hook",
    },
  },
}

local function update_config(config, opts)
  for key, value in pairs(opts) do
    if type(value) == "table" and type(config[key]) == "table" then
      update_config(config[key], value) -- Recursive call for nested tables
    else
      config[key] = value
    end
  end
end

local function validate_opts(opts)
  local pb_config = opts.persistent_breakpoints
  if pb_config then
    if pb_config.enabled == false then
      local err_msg = "Persistent breakpoints not enabled"
      assert(pb_config.load_breakpoints_on_setup ~= true, err_msg)
      assert(pb_config.load_breakpoints_on_buf_enter ~= true, err_msg)
      assert(pb_config.save_breakpoints_on_buf_write ~= true, err_msg)
      assert(pb_config.persistent_by_default ~= true, err_msg)
      assert(pb_config.persist_on_placement ~= true, err_msg)
    end
  end
end

function M.setup_opts(opts)
  validate_opts(opts)
  update_config(M, opts)
end

return M
