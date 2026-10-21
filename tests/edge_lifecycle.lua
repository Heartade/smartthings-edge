package.path = "src/?.lua;src/?/init.lua;" .. package.path
local sdk = assert(os.getenv("SMARTTHINGS_LUA_LIBS"), "set SMARTTHINGS_LUA_LIBS")
package.path = sdk .. "/?.lua;" .. sdk .. "/?/init.lua;" .. package.path
local build_cap = require("st.capabilities").build_cap_from_json_string
package.loaded["st.capabilities"] = nil
local template
local capability = {
  build_cap_from_json_string = build_cap,
  refresh = { ID = "refresh", commands = { refresh = { NAME = "refresh" } } },
  switch = { ID = "switch", commands = {
    on = { NAME = "on" }, off = { NAME = "off" }
  }, switch = {
    on = function() return { value = "on" } end,
    off = function() return { value = "off" } end
  } },
  thermostatMode = { ID = "thermostatMode" }
}
local driver_object = { run = function() end }
package.preload["st.zigbee"] = function()
  return function(_, t) template = t; return driver_object end
end
package.preload["st.capabilities"] = function()
  return capability
end
package.preload["socket"] = function()
  return { gettime = function() return 100000 end }
end
package.preload["ir.edge_zigbee"] = function()
  return { send = function() end, received = function() return nil, "unused" end }
end
dofile("src/init.lua")
assert(template.lifecycle_handlers.infoChanged)
local created, fields = {}, {}
local parent = {
  id = "parent", device_network_id = "ieee",
  preferences = { addRemoteRequest = "001|ac-protocol|Bedroom AC" },
  log = { info = function() end },
  get_child_by_parent_assigned_key = function() return nil end,
  get_field = function(_, k) return fields[k] end,
  set_field = function(_, k, v) fields[k] = v end
}
driver_object.try_create_device = function(_, m) created[#created + 1] = m end
template.lifecycle_handlers.infoChanged(driver_object, parent, "infoChanged",
  { old_st_store = { preferences = { addRemoteRequest = "" } } })
assert(#created == 1 and created[1].profile == "ac-protocol")
assert(created[1].parent_device_id == "parent")
template.lifecycle_handlers.infoChanged(driver_object, parent, "infoChanged",
  { old_st_store = { preferences = { addRemoteRequest = "001|ac-protocol|Bedroom AC" } } })
assert(#created == 1)
print("Edge lifecycle request test passed")
