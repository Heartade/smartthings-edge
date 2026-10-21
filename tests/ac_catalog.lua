package.path = "src/?.lua;" .. package.path
local catalog = require "ac.protocol_catalog"
local registry = require "ac.registry"
local state = require "ac.state"
local zosung = require "ir.zosung"
for id, encoder in pairs(catalog.encoders) do registry.register(id, encoder) end
local models, count = 0, 0
for _, entry in ipairs(catalog.index) do
  local id = "irac-" .. entry.protocol:lower():gsub("_", "-")
  assert(not registry.encode(id, state.initial(), {}, 999))
  for _, model in ipairs(entry.models) do
    models = models + 1
    local features = registry.describe(id, model.value)
    for _, mode in ipairs(features.modes) do
      for _, fan in ipairs({"auto", "low", "medium", "high"}) do
        for _, power in ipairs({true, false}) do
          local current = state.initial()
          local desired, frames = registry.encode(id, current, {
            power = power, mode = mode, fan = fan,
            temperature = math.max(features.min_temperature, math.min(24, features.max_temperature)),
            swing_vertical = model.vertical and "auto" or "off",
            swing_horizontal = model.horizontal and "auto" or "off"
          }, model.value, current)
          assert(desired, id .. "/" .. model.value .. ": " .. tostring(frames))
          if #frames > 0 then assert(registry.to_payload(frames)) end
          count = count + 1
        end
      end
    end
  end
end
-- Long idle continuations are accepted only after a full uint16 idle.
assert(zosung.encode_timings({500,65535,0,40000}))
assert(not pcall(zosung.encode_timings,{0,500}))
assert(not pcall(zosung.encode_timings,{500,100,0,100}))
print("AC catalog registry/payload checks passed: " .. models .. " models, " .. count .. " commands")
