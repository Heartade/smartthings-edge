-- Real capability schemas with a fake driver/device; no hub or AC is needed.
local sdk = assert(os.getenv("SMARTTHINGS_LUA_LIBS"), "set SMARTTHINGS_LUA_LIBS")
package.path = "src/?.lua;src/?/init.lua;" .. sdk .. "/?.lua;" .. sdk .. "/?/init.lua;" .. package.path
local template
local driver = { run = function() end }
package.preload["st.zigbee"] = function()
  return function(_, value) template = value; return driver end
end
package.preload["socket"] = function() return { gettime = function() return 0 end } end
package.preload["ir.edge_zigbee"] = function() return {} end
local capabilities = require "st.capabilities"
dofile("src/init.lua")
local fields, events, warnings, payloads = {}, {}, {}, {}
local child = {
  id = "ac", preferences = { acProtocol = "irac_electra_ac", acModel = 0 },
  supports_capability = function(_, capability) return capability.ID == "airConditionerMode" end,
  get_field = function(_, key) return fields[key] end,
  set_field = function(_, key, value) fields[key] = value end,
  get_parent_device = function() return { id = "parent", get_field = function() end } end,
  emit_event = function(_, event) events[event.capability.ID .. "." .. event.attribute.NAME] = event end,
  log = { warn = function(message) warnings[#warnings + 1] = message end, info = function() end }
}
driver.send_ir_code = function(_, _, payload)
  payloads[#payloads + 1] = payload
  return #payloads
end
local function command(capability, name, args)
  template.capability_handlers[capability][name](driver, child, { args = args })
end
template.lifecycle_handlers.init(driver, child)
command("airConditionerMode", "setAirConditionerMode", { mode = "dry" })
assert(fields.ac_desired_state.power and fields.ac_desired_state.mode == "dry")
command("airConditionerMode", "setAirConditionerMode", { mode = "heat" })
command("temperatureSetpoint", "setTemperatureSetpoint", { setpoint = 32 })
assert(fields.ac_desired_state.mode == "heat" and fields.ac_desired_state.temperature == 32)
command("fanOscillationMode", "setFanOscillationMode", { fanOscillationMode = "all" })
assert(fields.ac_desired_state.temperature == 32) -- Survives reload from persisted desired state.
assert(fields.ac_desired_state.swing_vertical == "on" and fields.ac_desired_state.swing_horizontal == "on")
command("fanOscillationMode", "setFanOscillationMode", { fanOscillationMode = "off" })
assert(fields.ac_desired_state.swing_vertical == "off" and fields.ac_desired_state.swing_horizontal == "off")
child.preferences.acTemperatureUnit = "F"
command("temperatureSetpoint", "setTemperatureSetpoint", { setpoint = 75.2 })
assert(fields.ac_desired_state.temperature == 24)
assert(#warnings == 0, table.concat(warnings, "; "))
assert(events["airConditionerMode.airConditionerMode"].value.value == "heat")
assert(events["temperatureSetpoint.temperatureSetpoint"].value.value == 75.2)
assert(events["temperatureSetpoint.temperatureSetpointRange"].value.value.maximum == 89.6)
assert(events["fanOscillationMode.fanOscillationMode"].value.value == "off")
assert(events["thermostatHeatingSetpoint.heatingSetpoint"] == nil)
assert(events["thermostatCoolingSetpoint.coolingSetpoint"] == nil)

-- Unsupported swing leaves both desired state and the send count unchanged.
fields.ac_desired_state = require("ac.state").initial()
child.preferences.acProtocol = "lg_28"
fields.ac_protocol_selection = nil
template.lifecycle_handlers.init(driver, child)
assert(fields.ac_protocol_selection == "irac_lg_m1")
local before = #payloads
command("fanOscillationMode", "setFanOscillationMode", { fanOscillationMode = "vertical" })
assert(#payloads == before and fields.ac_desired_state.swing_vertical == "off")
child.preferences.acProtocol = "lg2_akb74955603"
fields.ac_protocol_selection = nil
template.lifecycle_handlers.init(driver, child)
assert(fields.ac_protocol_selection == "irac_lg2_m3")
command("fanOscillationMode", "setFanOscillationMode", { fanOscillationMode = "vertical" })
assert(#payloads == before + 1 and fields.ac_desired_state.swing_vertical == "on")
assert(fields.ac_protocol_selection == "irac_lg2_m3")
local updated
local legacy = {
  model = "ac-protocol", id = "legacy", preferences = {},
  supports_capability = function(_, cap) return cap.ID == "thermostatMode" end,
  get_field = function() return nil end,
  set_field = function() end,
  try_update_metadata = function(_, metadata) updated = metadata.profile end,
  log = child.log
}
template.lifecycle_handlers.init(driver, legacy)
assert(updated == "ac-protocol")
print("AC UI capability, dry mode, temperature, swing and persistence tests passed")
