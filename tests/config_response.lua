-- Lua 5.1: lua tests/config_response.lua <controller.lua>
-- Run the real POST handler with a tunnel that is lost on synchronous restart.
local controller = assert(arg[1], "controller path required")
local form, response, committed, closed, scheduled, writes
local commit_ok, schedule_status
local cursor = {
  foreach = function(_, _, _, callback) callback({[".name"] = "main"}) end,
  set = function() writes = writes + 1 end,
  commit = function() committed = commit_ok; return commit_ok end,
}
package.preload["luci.model.uci"] = function()
  return { cursor = function() return cursor end }
end
package.preload["luci.dispatcher"] = function()
  return { context = { authsession = "test-session", token = "test-csrf" } }
end
package.preload["luci.jsonc"] = function()
  return { stringify = function(value) return value end }
end
package.preload["luci.http"] = function()
  return {
    getenv = function(key)
      if key == "REQUEST_METHOD" then return "POST" end
      if key == "CONTENT_TYPE" then return "application/x-www-form-urlencoded" end
    end,
    formvalue = function(key) return form[key] end,
    prepare_content = function() end,
    write = function(value) response = value end,
    close = function() closed = true end,
  }
end
package.preload["luci.sys"] = function()
  return { call = function(command)
    assert(committed, "must commit before scheduling restart")
    assert(command:match("sleep%s+[1-9]%d*%s*;") and command:match("&%s*$"),
      "HTTP 503: synchronous restart disconnects the tunnel before response")
    assert(command:find("/etc/init.d/ddnsto restart", 1, true))
    assert(command:find("</dev/null", 1, true), "detach stdin")
    assert(command:find(">/dev/null 2>&1", 1, true), "detach output")
    scheduled = true
    return schedule_status
  end }
end
dofile(controller)

local function run(overrides, commit_result, launch_result)
  form = { token = "test-csrf", ddnsto_token = "test-service-token",
    enabled = "1", index = "0", feat_enabled = "0" }
  for key, value in pairs(overrides or {}) do form[key] = value end
  response, committed, closed, scheduled, writes = nil, false, false, false, 0
  commit_ok = commit_result ~= false
  schedule_status = launch_result or 0
  luci.controller.ddnsto.api_config()
end

run()
assert(committed and scheduled and closed)
assert(response.ok and response.restart_pending)
run({ enabled = "0" })
assert(response.ok and scheduled and closed, "disabling also needs a response before disconnect")
run({ token = "wrong-csrf" })
assert(not response.ok and writes == 0 and not scheduled)
run({ index = "invalid" })
assert(not response.ok and writes == 0 and not scheduled)
run(nil, false)
assert(not response.ok and not scheduled, "failed commit must not restart or report success")
run(nil, true, 1)
assert(not response.ok, "failed scheduling must not report success")
print("PASS: save response survives restart; validation and failure paths remain errors")
