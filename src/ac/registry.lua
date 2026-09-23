-- Register only encoders whose output has fixture coverage. A candidate model
-- is metadata, never an implicit fallback to another protocol.
local state = require "ac.state"
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

function M.encode(id, current, patch, model)
  local encoder = encoders[id]
  if not encoder then return nil, "protocol not implemented: " .. tostring(id) end
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

return M
