package.path = "src/?.lua;src/?/init.lua;" .. package.path
local sdk = assert(os.getenv("SMARTTHINGS_LUA_LIBS"), "set SMARTTHINGS_LUA_LIBS")
package.path = sdk .. "/?.lua;" .. sdk .. "/?/init.lua;" .. package.path
local build_cap = require("st.capabilities").build_cap_from_json_string
package.loaded["st.capabilities"] = nil

local template
local now = 100
local sent, timers = {}, {}
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
package.preload["st.capabilities"] = function() return capability end
package.preload["socket"] = function()
  return { gettime = function() return now * 1000 end }
end
package.preload["ir.edge_zigbee"] = function()
  return {
    send = function(_, cluster, command, payload)
      sent[#sent + 1] = { cluster = cluster, command = command, payload = payload }
    end,
    received = function(message) return message.command, message.raw end
  }
end
driver_object.call_with_delay = function(_, delay, callback, label)
  local timer = { delay = delay, callback = callback, label = label }
  timers[#timers + 1] = timer
  return timer
end
driver_object.cancel_timer = function(_, timer) timer.cancelled = true end
dofile("src/init.lua")

local wire = require "ir.zosung_wire"
local zosung = require "ir.zosung"
local parent = {
  id = "blaster-1",
  get_field = function() end,
  log = { info = function() end, warn = function() end }
}

local function new_child(id, request, is_ac)
  local fields, events = {}, {}
  local child
  child = {
    id = id,
    preferences = { learnActionRequest = request },
    log = { info = function() end, warn = function() end },
    get_parent_device = function() return parent end,
    get_field = function(_, key) return fields[key] end,
    set_field = function(_, key, value, options)
      fields[key] = value
      if options and options.persist then child.last_persisted_field = key end
    end,
    supports_capability = function(_, supported)
      return is_ac and supported and supported.ID == "thermostatMode"
    end,
    emit_event = function(_, event) events[#events + 1] = event end
  }
  return child, fields, events
end

local function change_request(child, request)
  local old = child.preferences.learnActionRequest
  child.preferences.learnActionRequest = request
  template.lifecycle_handlers.infoChanged(driver_object, child, "infoChanged", {
    old_st_store = { preferences = { learnActionRequest = old } }
  })
end

local function receive(command, payload)
  template.zigbee_handlers.cluster[0xED00][command](driver_object, parent,
    { command = command, raw = payload })
end

local function capture(child, action, token, seq, bytes)
  change_request(child, token .. "|" .. action)
  assert(sent[#sent].cluster == 0xE004 and sent[#sent].payload == '{"study":0}')
  receive(0, wire.encode(0, { seq = seq, length = #bytes, unk1 = 0,
    unk2 = 0xE004, unk3 = 1, cmd = 2, unk4 = 0 }))
  receive(3, wire.encode(3, { zero = 0, seq = seq, position = 0,
    msgpart = bytes, msgpartcrc = zosung.checksum(bytes) }))
  receive(5, wire.encode(5, { seq = seq, zero = 0 }))
end

local child, fields, events = new_child("tv", "")
capture(child, "power_on", "learn-1", 12, "abc")
assert(fields.learned_ir_actions.power_on == "YWJj")
assert(child.last_persisted_field == "learned_ir_actions")

local duplicate_count = #sent
template.lifecycle_handlers.infoChanged(driver_object, child, "infoChanged", {
  old_st_store = { preferences = { learnActionRequest = "" } }
})
assert(#sent == duplicate_count)

template.capability_handlers.switch.on(driver_object, child, {})
local initial = sent[#sent]
assert(initial.cluster == 0xED00 and initial.command == 0)
local send_meta = wire.decode(0, initial.payload)
local ir_payload = '{"key_num":1,"delay":300,"key1":{"num":1,"freq":38000,"type":1,"key_code":"YWJj"}}'
assert(send_meta.length == #ir_payload) -- Command 00 carries metadata; command 03 carries JSON chunks.
local position = 0
while position < #ir_payload do
  receive(2, wire.encode(2, { seq = send_meta.seq, position = position, maxlen = 0x38 }))
  local part = wire.decode(3, sent[#sent].payload)
  local expected_part = ir_payload:sub(position + 1, position + 0x32)
  assert(part.msgpart == expected_part)
  assert(part.msgpartcrc == zosung.checksum(expected_part))
  assert(#events == 0) -- No switch state until all chunks finish.
  position = position + #part.msgpart
end
receive(4, wire.encode(4, { zero0 = 0, seq = send_meta.seq, zero1 = 0 }))
assert(events[#events] and events[#events].value == "on")

local missing_before = #sent
template.capability_handlers.switch.off(driver_object, child, {})
assert(#sent == missing_before)

local ac = new_child("ac", "", true)
ac:set_field("learned_ir_actions", { power_on = "YWJj" }, { persist = true })
local ac_before = #sent
template.capability_handlers.switch.on(driver_object, ac, {})
assert(#sent == ac_before)

local other, other_fields, other_events = new_child("fan", "")
capture(other, "power_off", "learn-2", 13, "xyz")
assert(other_fields.learned_ir_actions.power_off == "eHl6")
assert(fields.learned_ir_actions.power_off == nil)
template.capability_handlers.switch.off(driver_object, other, {})
local off_initial = sent[#sent]
assert(off_initial.command == 0)
local off_meta = wire.decode(0, off_initial.payload)
local off_payload = '{"key_num":1,"delay":300,"key1":{"num":1,"freq":38000,"type":1,"key_code":"eHl6"}}'
position = 0
while position < #off_payload do
  receive(2, wire.encode(2, { seq = off_meta.seq, position = position, maxlen = 0x38 }))
  local part = wire.decode(3, sent[#sent].payload)
  local expected_part = off_payload:sub(position + 1, position + 0x32)
  assert(part.msgpart == expected_part)
  position = position + #part.msgpart
end
receive(4, wire.encode(4, { zero0 = 0, seq = off_meta.seq, zero1 = 0 }))
assert(other_events[#other_events] and other_events[#other_events].value == "off")

change_request(child, "learn-3|power_off")
local active_timer = timers[#timers]
assert(active_timer.delay == 15)
local before_wrong_cancel = #sent
change_request(other, "learn-busy|power_on")
assert(#sent == before_wrong_cancel)
change_request(other, "cancel-1|cancel")
assert(#sent == before_wrong_cancel)
change_request(child, "cancel-2|cancel")
assert(sent[#sent].cluster == 0xE004 and sent[#sent].payload == '{"study":1}')

change_request(child, "learn-4|power_on")
active_timer = timers[#timers]
assert(active_timer.delay == 15)
now = now + 16
active_timer.callback()
assert(sent[#sent].cluster == 0xE004 and sent[#sent].payload == '{"study":1}')

change_request(child, "learn-5|power_on")
template.lifecycle_handlers.removed(driver_object, child, "removed", {})
assert(sent[#sent].cluster == 0xE004 and sent[#sent].payload == '{"study":1}')
change_request(other, "learn-3|power_on")
assert(sent[#sent].cluster == 0xE004 and sent[#sent].payload == '{"study":0}')

local failed_parent = {
  id = "blaster-no-timer",
  get_field = function() end,
  log = { info = function() end, warn = function() end }
}
local failed_child = new_child("no-timer", "")
failed_child.get_parent_device = function() return failed_parent end
local original_call_with_delay = driver_object.call_with_delay
driver_object.call_with_delay = function() return nil end
local result, err = driver_object:start_ir_learning(failed_parent, failed_child, "power_on")
assert(result == nil and err == "could not schedule IR transfer timeout")
assert(sent[#sent - 1].payload == '{"study":0}' and sent[#sent].payload == '{"study":1}')
driver_object.call_with_delay = original_call_with_delay
print("Edge child learn/send tests passed")
