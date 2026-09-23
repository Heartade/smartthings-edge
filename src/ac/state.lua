-- Pure desired-state model. No device I/O happens in this module.
local M = {}

local MODES = { cool = true, heat = true, dry = true, fan = true, auto = true }
local FANS = { auto = true, low = true, medium = true, high = true }
local SWING = { off = true, on = true, auto = true }
local KEYS = { power = true, mode = true, temperature = true, fan = true,
  swing_vertical = true, swing_horizontal = true }

function M.initial()
  return { power = false, mode = "cool", temperature = 24, fan = "auto",
    swing_vertical = "off", swing_horizontal = "off" }
end

local function valid(s, limits)
  if type(s.power) ~= "boolean" then return false, "power must be boolean" end
  if not MODES[s.mode] then return false, "unsupported mode" end
  if type(s.temperature) ~= "number" or s.temperature % 1 ~= 0 or
    s.temperature < (limits.min_temperature or 16) or
    s.temperature > (limits.max_temperature or 30) then
    return false, "temperature out of range"
  end
  if not FANS[s.fan] then return false, "unsupported fan" end
  if not SWING[s.swing_vertical] or not SWING[s.swing_horizontal] then
    return false, "unsupported swing"
  end
  if limits.supports and not limits.supports(s) then
    return false, "state unsupported by encoder"
  end
  return true
end

function M.apply(current, patch, limits)
  if type(current) ~= "table" or type(patch) ~= "table" then
    return nil, "state and patch must be tables"
  end
  limits = limits or {}
  local next_state = {}
  for key in pairs(KEYS) do next_state[key] = current[key] end
  for key, value in pairs(patch) do
    if not KEYS[key] then return nil, "unknown field: " .. tostring(key) end
    next_state[key] = value
  end
  local ok, err = valid(next_state, limits)
  if not ok then return nil, err end
  return next_state
end

return M
