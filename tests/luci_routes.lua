-- Run with Lua 5.1:
-- lua tests/luci_routes.lua luci-app-ddnsto/luasrc/controller/ddnsto.lua
-- Exercise the real controller index() without a router or UCI writes.
local controller = assert(arg[1], "controller path required")
package.preload["nixio.fs"] = function()
  return { access = function() return true end }
end
dofile(controller)

local entries = {}
local scope = setmetatable({
  entry = function(path, target)
    local node = { action = target }
    entries[table.concat(path, "/")] = node
    return node
  end,
  call = function(name) return { type = "call", name = name } end,
  firstchild = function() return { type = "firstchild" } end,
  _ = function(value) return value end,
}, { __index = _G })
setfenv(luci.controller.ddnsto.index, scope)()

-- Older LuCI dispatchers only mark explicitly registered nodes satisfied.
-- Thus a registered leaf can still return 404 at an implicit parent node.
local function resolve(path)
  local prefix = "admin/services/ddnsto"
  for part in path:sub(#prefix + 2):gmatch("[^/]+") do
    assert(entries[prefix] and not entries[prefix].leaf,
      "HTTP 404 at " .. prefix .. " while resolving " .. path)
    prefix = prefix .. "/" .. part
  end
  return assert(entries[prefix], "HTTP 404 at " .. prefix).action
end

local base = "admin/services/ddnsto/"
assert(resolve(base .. "api/config").name == "api_config")
assert(resolve(base .. "api/onboarding/start").name == "api_onboarding_start")
assert(resolve(base .. "api/onboarding/address").name == "api_onboarding_address")
assert(resolve(base .. "page").name == "action_page")
for path, node in pairs(entries) do
  if node.action and node.action.type == "call" then
    assert(resolve(path) == node.action)
  end
end
print("PASS: config, onboarding and all controller call routes are reachable")
