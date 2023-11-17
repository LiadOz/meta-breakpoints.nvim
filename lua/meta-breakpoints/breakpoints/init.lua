local M = {}

M.breakpoint_factory = require("meta-breakpoints.breakpoints.base").breakpoint_factory
require("meta-breakpoints.breakpoints.builtin")

return M
