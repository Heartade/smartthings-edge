-- Run with SMARTTHINGS_LUA_LIBS pointing to an extracted official Edge SDK.
local sdk = assert(os.getenv("SMARTTHINGS_LUA_LIBS"), "set SMARTTHINGS_LUA_LIBS")
package.path = "src/?.lua;src/?/init.lua;" .. sdk .. "/?.lua;" ..
  sdk .. "/?/init.lua;" .. package.path

local adapter = require "ir.edge_zigbee"
local sent = {}
local device = {
  get_short_address = function() return 0x1234 end,
  get_endpoint = function() return 1 end,
  get_profile_id = function() return 0x0104 end,
  send = function(_, tx)
    -- Exercise the SDK's complete recursive serializer, not mocked tables.
    local bytes = tx:_serialize()
    assert(type(bytes) == "string" and #bytes > 0)
    sent[#sent + 1] = tx
  end
}

local raw = string.char(1, 2, 0, 255)
adapter.send(device, 0xED00, 0x03, raw)
local expected = string.char(0x11, 0, 3) .. raw
assert(sent[1].body:_serialize() == expected)
assert(sent[1]:_serialize():sub(-#expected) == expected)
adapter.send(device, 0xE004, 0, '{"study":0}')
assert(sent[2].body:_serialize() == string.char(0x11, 1, 0) .. '{"study":0}')

local registry = require "ac.registry"
local state = require "ac.state"
local catalog = require "ac.protocol_catalog"
local controller = require "ir.controller"
local wire = require "ir.zosung_wire"
local cases = {}
for id, encoder in pairs(catalog.encoders) do registry.register(id, encoder) end
for _, entry in ipairs(catalog.index) do
  for _, model in ipairs(entry.models) do
    cases[#cases + 1] = { id = "irac-" .. entry.protocol:lower():gsub("_", "-"), model = model.value }
  end
end
for _, case in ipairs(cases) do
local id = case.id
for _, power in ipairs({ true, false }) do
  local features = registry.describe(id, case.model)
  local mode = features.modes[1]
  for _, value in ipairs(features.modes) do if value == "cool" then mode = value end end
  local desired, frames = registry.encode(id, state.initial(), { power = power, mode = mode,
    temperature = math.max(features.min_temperature, math.min(24, features.max_temperature)) }, case.model, state.initial())
  assert(desired, id .. ": " .. tostring(frames))
  if #frames > 0 then
  local payload = assert(registry.to_payload(frames))
  local c = controller.new(function(cluster, command, body)
    adapter.send(device, cluster, command, body)
  end, function() return 0 end)
  assert(c:send_code(payload))
  assert(sent[#sent].address_header.cluster.value == 0xED00)
  assert(sent[#sent].body.zcl_header.cmd.value == 0)
  local seq = wire.decode(0, sent[#sent].body.zcl_body.body_bytes).seq
  local position = 0
  local received = {}
  while position < #payload do
    assert(c:receive(2, wire.encode(2, { seq = seq, position = position, maxlen = 0x38 })))
    local part = wire.decode(3, sent[#sent].body.zcl_body.body_bytes)
    received[#received + 1] = part.msgpart
    position = position + #part.msgpart
  end
  assert(table.concat(received) == payload)
  assert(c:receive(4, wire.encode(4, { zero0 = 0, seq = seq, zero1 = 0 })) == "sent")
  end
end
end
print("Official SDK serialization and complete chunk transfers passed for " .. #cases .. " AC protocol/model choices")
