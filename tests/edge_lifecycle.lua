package.path = "src/?.lua;src/?/init.lua;" .. package.path
local template
package.preload["st.zigbee"] = function()
  return function(_, t) template = t; return { run = function() end } end
end
package.preload["st.capabilities"] = function()
  return { refresh = { ID = "refresh", commands = { refresh = { NAME = "refresh" } } } }
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
local driver = { try_create_device = function(_, m) created[#created + 1] = m end }
template.lifecycle_handlers.infoChanged(driver, parent, "infoChanged",
  { old_st_store = { preferences = { addRemoteRequest = "" } } })
assert(#created == 1 and created[1].profile == "ac-protocol")
assert(created[1].parent_device_id == "parent")
template.lifecycle_handlers.infoChanged(driver, parent, "infoChanged",
  { old_st_store = { preferences = { addRemoteRequest = "001|ac-protocol|Bedroom AC" } } })
assert(#created == 1)
print("Edge lifecycle request test passed")
