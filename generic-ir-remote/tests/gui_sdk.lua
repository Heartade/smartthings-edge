-- GUI commands using the checked-in custom schemas and real SDK events.
local sdk = assert(os.getenv("SMARTTHINGS_LUA_LIBS"), "set SMARTTHINGS_LUA_LIBS")
package.path = "src/?.lua;src/?/init.lua;" .. sdk .. "/?.lua;" .. sdk .. "/?/init.lua;" .. package.path
local json = require "st.json"
local standard = require "st.capabilities"
local custom = setmetatable({}, { __index = standard })
local function read(path)
  local file = assert(io.open(path)); local text = file:read("*a"); file:close(); return json.decode(text)
end
local ids = {}
for _, item in ipairs(read("capabilities/manifest.json").capabilities) do
  local definition = read("capabilities/" .. item.definition)
  definition.id, definition.version = item.registeredId, item.registeredVersion
  custom[definition.id] = standard.build_cap_from_json_string(json.encode(definition), false)
  ids[item.key] = item.registeredId
end
package.loaded["st.capabilities"] = custom
local clock, template = 0
local sent, timers, created, existing = {}, {}, {}, {}
local driver = { run = function() end }
driver.call_with_delay = function(_, delay, callback, label)
  local timer = { delay = delay, callback = callback, label = label }
  timers[#timers + 1] = timer; return timer
end
driver.cancel_timer = function(_, timer) timer.cancelled = true end
driver.try_create_device = function(_, metadata) created[#created + 1] = metadata end
package.preload["st.zigbee"] = function() return function(_, value) template = value; return driver end end
package.preload["socket"] = function() return { gettime = function() return clock end } end
package.preload["ir.edge_zigbee"] = function()
  return { send = function(_, cluster, command, payload)
    sent[#sent + 1] = { cluster = cluster, command = command, payload = payload }
  end, received = function(message) return message.command, message.raw end }
end
dofile("src/init.lua")
local function device(id, model, caps)
  local d = { id = id, model = model, fields = {}, events = {}, warnings = {}, preferences = {} }
  d.get_field = function(_, key) return d.fields[key] end
  d.set_field = function(_, key, value) d.fields[key] = value end
  d.supports_capability = function(_, cap) return caps[cap.ID] == true end
  d.emit_event = function(_, event)
    assert(caps[event.capability.ID], "event emitted for unsupported capability")
    d.events[event.capability.ID .. "." .. event.attribute.NAME] = event.value.value
  end
  d.log = { warn = function(text) d.warnings[#d.warnings + 1] = text end, info = function() end }
  return d
end
local parent = device("parent", "TS1201", { [ids.remoteCreation] = true, refresh = true })
parent.device_network_id = "ieee"
parent.get_short_address = function() return 0x1234 end
parent.get_child_by_parent_assigned_key = function(_, key) return existing[key] end
local function child(id, ac)
  local caps = { [ids.irLearning] = true, switch = true, refresh = true }
  if ac then
    for _, key in ipairs({ ids.acSelection, ids.acLearningSetup, "airConditionerMode", "temperatureSetpoint", "fanMode", "fanOscillationMode" }) do caps[key] = true end
  end
  local d = device(id, ac and "ac-protocol" or "remote-tv", caps)
  d.get_parent_device = function() return parent end
  d.preferences.acProtocol = ac and "learned_state" or nil
  return d
end
local function command(d, capability, name, args)
  template.capability_handlers[capability][name](driver, d, { args = args or {} })
end
local function status(d) return d.events[ids.irLearning .. ".learningStatus"] end
local wire, zosung = require "ir.zosung_wire", require "ir.zosung"
local function receive(command_id, fields)
  template.zigbee_handlers.cluster[0xED00][command_id](driver, parent,
    { command = command_id, raw = wire.encode(command_id, fields) })
end
local function complete_capture(seq, bytes)
  receive(0, {seq = seq, length = #bytes, unk1 = 0, unk2 = 0xE004, unk3 = 1, cmd = 2, unk4 = 0})
  receive(3, {zero = 0, seq = seq, position = 0, msgpart = bytes, msgpartcrc = zosung.checksum(bytes)})
  receive(5, {seq = seq, zero = 0})
end

template.lifecycle_handlers.init(driver, parent)
command(parent, ids.remoteCreation, "setRemoteName", {name = "거실 에어컨"})
command(parent, ids.remoteCreation, "setRemoteType", {remoteType = "ac-protocol"})
command(parent, ids.remoteCreation, "createRemote")
command(parent, ids.remoteCreation, "createRemote")
assert(#created == 1 and created[1].label == "거실 에어컨")
assert(parent.events[ids.remoteCreation .. ".creationStatus"] == "creating")
local ac = child("ac", true)
ac.parent_assigned_child_key = created[1].parent_assigned_child_key
existing[ac.parent_assigned_child_key] = ac
template.lifecycle_handlers.added(driver, ac)
assert(parent.events[ids.remoteCreation .. ".creationStatus"] == "created")
assert(parent.fields.gui_creation_pending == nil and #sent == 0)

-- A timed-out creation retry retains its key, including across initialization.
command(parent, ids.remoteCreation, "createRemote")
local pending_key = created[2].parent_assigned_child_key
local pending_timer = timers[#timers]
clock = 31; pending_timer.callback()
assert(parent.events[ids.remoteCreation .. ".creationStatus"] == "error")
parent.fields.gui_initialized = nil
template.lifecycle_handlers.init(driver, parent)
command(parent, ids.remoteCreation, "createRemote")
assert(#created == 3 and created[3].parent_assigned_child_key == pending_key)

local tv, other = child("tv"), child("other")
template.lifecycle_handlers.init(driver, tv)
template.lifecycle_handlers.init(driver, other)
command(tv, ids.irLearning, "learn")
assert(status(tv) == "learning" and sent[#sent].payload == '{"study":0}')
command(other, ids.irLearning, "learn")
assert(status(other) == "busy")
command(other, ids.irLearning, "cancel")
assert(status(tv) == "learning")
command(tv, ids.irLearning, "selectAction", {action = "power_off"})
assert(tv.fields.gui_selected_action == nil) -- Target is frozen during capture.
complete_capture(99, "abc")
assert(status(tv) == "learned" and tv.fields.learned_ir_actions.power_on == "YWJj")
assert(tv.events[ids.irLearning .. ".signalStatus"] == "saved")
command(tv, ids.irLearning, "test")
assert(status(tv) == "testing")
command(tv, ids.irLearning, "deleteSignal")
assert(status(tv) == "busy" and tv.fields.learned_ir_actions.power_on == "YWJj")
local meta = wire.decode(0, sent[#sent].payload)
local position = 0
while position < meta.length do
  receive(2, {seq = meta.seq, position = position, maxlen = 56})
  position = position + #wire.decode(3, sent[#sent].payload).msgpart
end
receive(4, {zero0 = 0, seq = meta.seq, zero1 = 0})
assert(status(tv) == "sent" and tv.events["switch.switch"] == "off")
command(tv, ids.irLearning, "learn")
command(tv, ids.irLearning, "cancel")
assert(status(tv) == "cancelled" and tv.fields.learned_ir_actions.power_on == "YWJj")
command(tv, ids.irLearning, "learn")
clock = clock + 16; timers[#timers].callback()
assert(status(tv) == "timeout" and tv.fields.learned_ir_actions.power_on == "YWJj")
command(tv, ids.irLearning, "deleteSignal")
assert(tv.fields.learned_ir_actions.power_on == nil and status(tv) == "deleted")

-- Standard controls edit a capture draft without IR or desired-state changes.
local before = #sent
command(ac, ids.acLearningSetup, "setSetupMode", {mode = "on"})
command(ac, "switch", "on")
command(ac, "airConditionerMode", "setAirConditionerMode", {mode = "dry"})
command(ac, "temperatureSetpoint", "setTemperatureSetpoint", {setpoint = 25})
command(ac, "fanMode", "setFanMode", {fanMode = "high"})
command(ac, "fanOscillationMode", "setFanOscillationMode", {fanOscillationMode = "all"})
assert(#sent == before and ac.fields.ac_desired_state.power == false)
assert(ac.fields.ac_desired_state.temperature == 24 and ac.fields.gui_ac_draft.mode == "dry")
command(ac, ids.irLearning, "learn")
command(ac, "temperatureSetpoint", "setTemperatureSetpoint", {setpoint = 26})
assert(ac.fields.gui_ac_draft.temperature == 25)
complete_capture(100, "xyz")
assert(status(ac) == "learned")
local key = require("ac.learned_state").key(ac.fields.gui_ac_draft)
assert(ac.fields.learned_ac_states[key] == "eHl6")
command(ac, ids.irLearning, "test")
assert(status(ac) == "testing")
meta = wire.decode(0, sent[#sent].payload)
position = 0
while position < meta.length do
  receive(2, {seq = meta.seq, position = position, maxlen = 56})
  position = position + #wire.decode(3, sent[#sent].payload).msgpart
end
receive(4, {zero0 = 0, seq = meta.seq, zero1 = 0})
assert(status(ac) == "sent" and ac.fields.ac_desired_state.power == false)
assert(ac.events["switch.switch"] == "on" and ac.fields.gui_ac_draft.temperature == 25)
before = #sent
command(ac, ids.acLearningSetup, "setSetupMode", {mode = "off"})
assert(#sent == before and ac.fields.gui_ac_draft == nil)
assert(ac.events["switch.switch"] == "off" and ac.events["temperatureSetpoint.temperatureSetpoint"] == 24)
command(ac, ids.irLearning, "learn")
assert(#sent == before and status(ac) == "error")
command(ac, ids.acLearningSetup, "setSetupMode", {mode = "on"})
command(ac, ids.irLearning, "learn")
command(ac, ids.acLearningSetup, "setSetupMode", {mode = "off"})
assert(status(ac) == "cancelled" and ac.fields.gui_ac_draft == nil)
assert(sent[#sent].payload == '{"study":1}' and ac.fields.ac_desired_state.power == false)
command(ac, ids.acLearningSetup, "setSetupMode", {mode = "on"})
before = #sent
ac.fields.gui_initialized = nil
template.lifecycle_handlers.init(driver, ac)
assert(ac.fields.gui_ac_draft == nil and status(ac) == "idle" and #sent == before)
command(tv, ids.irLearning, "learn")
complete_capture(101, "abc")
command(tv, ids.irLearning, "learn")
receive(3, {zero = 0, seq = 102, position = 0, msgpart = "bad", msgpartcrc = zosung.checksum("bad")})
assert(status(tv) == "error" and tv.fields.learned_ir_actions.power_on == "YWJj")

-- Toggle protocols advance their previous-state baseline only after transfer
-- completion. A timeout preserves the baseline for a correct retry.
local protocol_ac = child("protocol-ac", true)
protocol_ac.preferences.acProtocol = "irac_whirlpool_ac"
protocol_ac.preferences.acModel = 1
template.lifecycle_handlers.init(driver, protocol_ac)
assert(protocol_ac.fields.ac_protocol_selection == "irac_whirlpool_ac_m1")
assert(protocol_ac.events[ids.acSelection .. ".selection"] == "irac_whirlpool_ac_m1")
local before_protocol = #sent
command(protocol_ac, ids.irLearning, "learn")
assert(#sent == before_protocol) -- A selected protocol disables learning.
command(protocol_ac, "switch", "on")
assert(protocol_ac.fields.ac_last_sent_state == nil)
local protocol_meta = wire.decode(0, sent[#sent].payload)
local protocol_position = 0
while protocol_position < protocol_meta.length do
  receive(2, {seq = protocol_meta.seq, position = protocol_position, maxlen = 56})
  protocol_position = protocol_position + #wire.decode(3, sent[#sent].payload).msgpart
end
receive(4, {zero0 = 0, seq = protocol_meta.seq, zero1 = 0})
assert(protocol_ac.fields.ac_last_sent_state.power == true)
assert(protocol_ac.fields.ac_last_sent_protocol == "irac-whirlpool-ac")
assert(protocol_ac.fields.ac_last_sent_model == 1)
command(protocol_ac, "switch", "off")
clock = clock + 16; timers[#timers].callback()
assert(protocol_ac.fields.ac_last_sent_state.power == true)
assert(protocol_ac.fields.ac_desired_state.power == false)

-- Catalog preference keys with the irac_ prefix resolve to their registered
-- encoder IDs even when the generated profile lookup is stale or incomplete.
local lg2_ac = child("lg2-ac", true)
lg2_ac.preferences.acProtocol = "irac_lg2"
lg2_ac.preferences.acModel = 2
template.lifecycle_handlers.init(driver, lg2_ac)
assert(lg2_ac.fields.ac_protocol_selection == "irac_lg2_m2")
local selector_sends = #sent
command(lg2_ac, ids.acSelection, "setSelection", {selection = "irac_lg2_m3"})
assert(lg2_ac.fields.ac_protocol_selection == "irac_lg2_m3")
assert(lg2_ac.events[ids.acSelection .. ".selection"] == "irac_lg2_m3")
assert(#sent == selector_sends) -- Changing the protocol/model never transmits IR.
command(lg2_ac, ids.acSelection, "setSelection", {selection = "irac_lg2_m2"})
local before_lg2 = #sent
command(lg2_ac, "switch", "on")
assert(#sent == before_lg2 + 1)
local lg2_meta = wire.decode(0, sent[#sent].payload)
assert(lg2_meta.length > 0)
local lg2_position = 0
while lg2_position < lg2_meta.length do
  receive(2, {seq = lg2_meta.seq, position = lg2_position, maxlen = 56})
  lg2_position = lg2_position + #wire.decode(3, sent[#sent].payload).msgpart
end
receive(4, {zero0 = 0, seq = lg2_meta.seq, zero1 = 0})
assert(lg2_ac.fields.ac_last_sent_protocol == "irac-lg2")

-- Choosing a complete protocol from a learned-state child requests the clean
-- profile while retaining the selection locally and without transmitting IR.
local selector_ac = child("selector-ac", true)
local selection_profiles = {}
selector_ac.try_update_metadata = function(_, metadata) selection_profiles[#selection_profiles + 1] = metadata.profile end
template.lifecycle_handlers.init(driver, selector_ac)
local before_selection = #sent
command(selector_ac, ids.acSelection, "setSelection", {selection = "irac_lg2_m2"})
assert(selection_profiles[#selection_profiles] == "ac-protocol")
assert(selector_ac.fields.ac_protocol_selection == "irac_lg2_m2")
assert(#sent == before_selection)

-- Existing children with handwritten protocol preferences migrate to the
-- closest generated catalog entry; the old choice is never re-published.
local old_protocol_ac = child("old-protocol-ac", true)
old_protocol_ac.preferences.acProtocol = "lg2_akb74955603"
template.lifecycle_handlers.init(driver, old_protocol_ac)
assert(old_protocol_ac.fields.ac_protocol_selection == "irac_lg2_m3")
assert(old_protocol_ac.events[ids.acSelection .. ".selection"] == "irac_lg2_m3")
old_protocol_ac.fields.ac_protocol_selection = "lg_28"
template.lifecycle_handlers.init(driver, old_protocol_ac)
assert(old_protocol_ac.fields.ac_protocol_selection == "irac_lg_m1")
assert(old_protocol_ac.events[ids.acSelection .. ".selection"] == "irac_lg_m1")

-- Parent and child upgrades request their original profile with the new caps.
local migrated = {}
local legacy_parent = device("legacy-parent", "TS1201", { refresh = true })
legacy_parent.get_short_address = parent.get_short_address
legacy_parent.try_update_metadata = function(_, value) migrated[#migrated + 1] = value.profile end
template.lifecycle_handlers.init(driver, legacy_parent)
assert(migrated[1] == "ir-blaster")
template.lifecycle_handlers.init(driver, legacy_parent)
assert(#migrated == 1)
local legacy_tv = device("legacy-tv", "remote-tv", { switch = true, refresh = true })
legacy_tv.get_parent_device = function() return parent end
legacy_tv.try_update_metadata = legacy_parent.try_update_metadata
template.lifecycle_handlers.init(driver, legacy_tv)
assert(migrated[2] == "remote-tv")
print("GUI creation, learning, ownership, timeout, test/delete, AC draft and restart tests passed")
