package.path = "src/?.lua;src/?/init.lua;" .. package.path
local actions = require "ir.learned_actions"

local parsed = assert(actions.parse_request("learn-01|power_on"))
assert(parsed.token == "learn-01" and parsed.action == "power_on")
assert(actions.parse_request("cancel-01|cancel").action == "cancel")
assert(actions.parse_request("same|other") == nil)
assert(actions.parse_request("|power_on") == nil)

local store = actions.new()
assert(store:put("power_on", "YWJj") == "power_on")
assert(store:get("power_on") == "YWJj")
assert(actions.to_payload("YWJj") ==
  '{"key_num":1,"delay":300,"key1":{"num":1,"freq":38000,"type":1,"key_code":"YWJj"}}')
assert(store:put("power_off", "ZA==") == "power_off")
assert(store:put("power_on", "ZWY=") == "power_on") -- Relearn replaces the action.
assert(store:get("power_on") == "ZWY=")
assert(store:put("volume_up", "YWJj") == nil)
assert(store:put("power_off", "not base64!") == nil)
assert(store:put("power_off", string.rep("A", actions.MAX_CODE_LENGTH + 4)) == nil)

local restored = actions.new(store.codes)
assert(restored:get("power_on") == "ZWY=")
assert(restored:remove("power_on"))
assert(restored:get("power_on") == nil)
print("IR learned-action tests passed")
