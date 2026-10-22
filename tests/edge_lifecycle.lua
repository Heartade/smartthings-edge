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

local child_fields, child_events, metadata_updates = {}, {}, {}
local child = {
  id = "child", model = "remote-generic", preferences = {},
  parent_assigned_child_key = "remote-test",
  log = { info = function() end, warn = function() end },
  get_parent_device = function() return parent end,
  get_field = function(_, k) return child_fields[k] end,
  set_field = function(_, k, v) child_fields[k] = v end,
  supports_capability = function(_, cap) return cap == capability.switch end,
  try_update_metadata = function(_, metadata) metadata_updates[#metadata_updates + 1] = metadata end,
  emit_event = function(_, event) child_events[#child_events + 1] = event end
}
template.lifecycle_handlers.init(driver_object, child)
assert(#metadata_updates == 1 and metadata_updates[1].profile == "remote-generic")
assert(child_fields.gui_profile_revision == 8)
assert(child_fields.gui_profile_migration_requested == "remote-generic")
assert(#child_events == 1 and child_events[1].value == "off")

print("Edge lifecycle request and migration-state tests passed")
