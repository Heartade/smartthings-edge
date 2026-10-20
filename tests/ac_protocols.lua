package.path = "src/?.lua;src/?/init.lua;" .. package.path
local registry = require "ac.registry"
local state = require "ac.state"
local encoders = require("ac.protocol_irremote").encoders
for id, encoder in pairs(encoders) do registry.register(id, encoder) end
local vectors = dofile("tests/reference/ac_waveforms.lua")

for index, vector in ipairs(vectors) do
  local desired, frames = registry.encode(vector.id, state.initial(), {
    power = vector.power, mode = vector.mode, temperature = vector.temperature,
    fan = vector.fan, swing_vertical = vector.swing_vertical,
    swing_horizontal = vector.swing_horizontal
  })
  assert(desired, tostring(index) .. ": " .. tostring(frames))
  assert(#frames == 1 and frames[1].carrier_hz == 38000)
  local timings = frames[1].timings
  local hash = 2166136261
  for _, duration in ipairs(timings) do
    assert(duration > 0 and duration <= 65535)
    for _ = 1, 4 do
      hash = ((hash ~ (duration & 255)) * 16777619) & 0xFFFFFFFF
      duration = duration >> 8
    end
  end
  assert(#timings == vector.count and hash == vector.hash,
    "upstream waveform mismatch: " .. index .. " " .. vector.id)
  assert(registry.to_payload(frames))
end

for id in pairs(encoders) do
  local limits = assert(registry.describe(id))
  assert(registry.encode(id, state.initial(), { temperature = limits.min_temperature - 1 }) == nil)
  assert(registry.encode(id, state.initial(), { temperature = limits.max_temperature + 1 }) == nil)
  local _, on = registry.encode(id, state.initial(), { swing_vertical = "on" })
  local _, auto = registry.encode(id, state.initial(), { swing_vertical = "auto" })
  assert(table.concat(on[1].timings, ",") == table.concat(auto[1].timings, ","))
end
assert(registry.encode("toshiba-72-a", state.initial(), { swing_horizontal = "on" }) == nil)
local _, reason = registry.encode("gree-yaw1f", state.initial(), { mode = "dry", fan = "high" })
assert(reason:find("low fan", 1, true))
assert(registry.encode("gree-yaw1f", state.initial(), { mode = "dry" }).fan == "low")
assert(registry.encode("kelvinator-128", state.initial(), { mode = "auto" }).temperature == 25)
assert(registry.encode("kelvinator-128", state.initial(), { mode = "auto", temperature = 24 }) == nil)
print("AC protocol tests passed: " .. #vectors .. " upstream waveform vectors across 8 variants")
