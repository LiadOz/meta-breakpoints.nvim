local logger

local ok, log = pcall(require, 'plenary.log')
if not ok then
  -- logger will only be available when plenary is installed
  logger = setmetatable({}, {__index = function() return function(...) end end})
else
  logger = log.new({plugin = 'meta-breakpoints.nvim'})
end

function logger:set_level(level)
  self.level = level
end

return logger
