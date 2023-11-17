local hooks = require('meta-breakpoints.hooks')


describe("test hooks", function()
  it("checks adding and removing hooks", function()
    local hook_1 = hooks.register_to_hook('a', function() end)
    local hook_2 = hooks.register_to_hook('a', function() end)
    assert.equals(2, hooks.get_hooks_mapping_count('a'))
    hooks.remove_hook('a', hook_1)
    hooks.remove_hook('a', hook_2)
    assert.are.same({}, hooks.get_hooks_mapping('a'))
  end)

  it("checks removing multiple hooks", function()
    hooks.register_to_hook('a', function() end)
    hooks.register_to_hook('a', function() end)
    assert.equals(2, hooks.get_hooks_mapping_count('a'))
    hooks.remove_hook('a')
    assert.are.same({}, hooks.get_hooks_mapping('a'))
  end)
end)
