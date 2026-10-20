package.path = "src/?.lua;src/?/init.lua;" .. package.path
local children = require "children"
local spec = assert(children.parse("living-ac|ac-protocol|Bedroom AC"))
assert(spec.key == "remote-living-ac" and spec.profile == "ac-protocol")
assert(children.parse("x|unknown|Test") == nil)
assert(children.parse("x|ac-protocol| ") == nil)
assert(children.parse("x|ac-protocol|a|b") == nil)
assert(children.parse("ko|remote-tv|" .. string.rep("방", 60)))
assert(children.parse("ko|remote-tv|" .. string.rep("방", 61)) == nil)
local saved, calls = {}, {}
local parent = {
  id = "parent-id", device_network_id = "zigbee-ieee",
  get_field = function(_, k) return saved[k] end,
  set_field = function(_, k, v, opts) assert(opts.persist); saved[k] = v end,
  get_child_by_parent_assigned_key = function(_, k) return calls.existing == k end
}
local driver = { try_create_device = function(_, metadata) calls[#calls + 1] = metadata end }
local _, status = children.create(driver, parent, "one|remote-tv|Living room TV")
assert(status == "requested" and #calls == 1)
assert(calls[1].type == "EDGE_CHILD" and calls[1].parent_device_id == "parent-id")
assert(calls[1].profile == "remote-tv" and calls[1].parent_assigned_child_key == "remote-one")
_, status = children.create(driver, parent, "one|remote-tv|Living room TV")
assert(status == "already requested" and #calls == 1)
calls.existing = "remote-one"
_, status = children.create(driver, parent, "one|remote-tv|Living room TV")
assert(status == "already exists" and #calls == 1)
_, status = children.create(driver, parent, "two|ac-protocol|Bedroom AC")
assert(status == "requested" and #calls == 2)
print("Child creation tests passed")
