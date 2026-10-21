-- Register explicit protocol implementations. Experimental encoders remain
-- opt-in and candidate models are metadata, never an implicit fallback.
local state = require "ac.state"
local zosung = require "ir.zosung"
local M = {}
local encoders = {}

function M.register(id, encoder)
  assert(type(id) == "string" and id:match("^[%w_.%-]+$"), "invalid protocol id")
  assert(not encoders[id], "duplicate protocol id")
  assert(type(encoder) == "table" and type(encoder.supports) == "function"
    and type(encoder.encode) == "function", "encoder requires supports and encode")
  encoders[id] = encoder
end

function M.available()
  local ids = {}
  for id in pairs(encoders) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

function M.describe(id)
  local encoder = encoders[id]
  if not encoder then return nil end
  return {
    min_temperature = encoder.min_temperature or 16,
    max_temperature = encoder.max_temperature or 30,
    swing_modes = encoder.swing_modes or { "off" },
    modes = encoder.modes or { "auto", "cool", "heat", "dry", "fan" }
  }
end

function M.encode(id, current, patch, model)
  local encoder = encoders[id]
  if not encoder then return nil, "protocol not implemented: " .. tostring(id) end
  if type(patch) ~= "table" then return nil, "state patch must be a table" end
  local defaults = encoder.mode_defaults and encoder.mode_defaults[patch.mode]
  if defaults then
    local adjusted = {}
    for key, value in pairs(patch) do adjusted[key] = value end
    for key, value in pairs(defaults) do
      if adjusted[key] == nil then adjusted[key] = value end
    end
    patch = adjusted
  end
  local next_state, err = state.apply(current, patch, {
    min_temperature = encoder.min_temperature,
    max_temperature = encoder.max_temperature,
    supports = function(s) return encoder.supports(s, model) end
  })
  if not next_state then return nil, err end
  local frames = encoder.encode(next_state, model, current)
  if type(frames) ~= "table" or #frames == 0 then
    return nil, "encoder returned no frames"
  end
  for _, frame in ipairs(frames) do
    if type(frame) ~= "table" or type(frame.timings) ~= "table" or
      #frame.timings == 0 or type(frame.carrier_hz) ~= "number" then
      return nil, "encoder returned invalid frame"
    end
  end
  return next_state, frames
end

function M.to_payload(frames)
  if type(frames) ~= "table" or #frames == 0 then
    return nil, "encoder returned no frames"
  end
  if #frames > 8 then return nil, "encoder returned too many frames" end

  local keys = {}
  for index, frame in ipairs(frames) do
    if type(frame) ~= "table" or type(frame.timings) ~= "table" or
      #frame.timings == 0 or type(frame.carrier_hz) ~= "number" or
      frame.carrier_hz % 1 ~= 0 or frame.carrier_hz < 10000 or frame.carrier_hz > 100000 then
      return nil, "encoder returned invalid frame"
    end
    local ok, code = pcall(zosung.encode_timings, frame.timings)
    if not ok then return nil, "encoder returned invalid timings: " .. tostring(code) end
    keys[#keys + 1] = string.format(
      '"key%d":{"num":1,"freq":%d,"type":1,"key_code":"%s"}',
      index, frame.carrier_hz, code)
  end
  return string.format('{"key_num":%d,"delay":300,%s}', #frames, table.concat(keys, ","))
end

return M
