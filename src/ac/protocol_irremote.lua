-- Lua adaptations of IRremoteESP8266's Toshiba, Mitsubishi, Gree, Kelvinator
-- and Electra AC encoders. Copyright 2009 Ken Shirriff; 2016-2022 David Conran;
-- 2019 Mark Kuchel and IRremoteESP8266 contributors. Lua adaptation: 2026.
-- Distributed under LGPL-2.1; see licenses/IRremoteESP8266-LGPL-2.1.txt and
-- docs/protocol-sources.md for upstream sources, scope and validation.
-- SPDX-License-Identifier: LGPL-2.1-only
local M = { encoders = {} }

local function append(t, mark, space)
  t[#t + 1], t[#t + 2] = mark, space
end

local function bits(t, value, count, mark, one, zero, msb)
  for i = 0, count - 1 do
    local shift = msb and count - 1 - i or i
    append(t, mark, ((value >> shift) & 1) == 1 and one or zero)
  end
end

local function bytes(t, data, first, last, mark, one, zero, msb)
  for i = first, last do bits(t, data[i], 8, mark, one, zero, msb) end
end

local function packet(t, data, header, mark, one, zero, footer, gap, msb)
  append(t, header[1], header[2])
  bytes(t, data, 1, #data, mark, one, zero, msb)
  append(t, footer, gap)
end

local function sum(data, first, last)
  local total = 0
  for i = first, last do total = total + data[i] end
  return total & 0xFF
end

local function block_checksum(data, offset)
  local total = 10
  for i = 1, 4 do total = total + (data[offset + i] & 15) end
  for i = 5, 7 do total = total + (data[offset + i] >> 4) end
  return (total & 15) << 4
end

local function enabled(swing) return swing ~= "off" end
local function frame(t) return { { carrier_hz = 38000, timings = t } } end
local common_modes = { auto = 0, cool = 1, dry = 2, fan = 3, heat = 4 }
local common_fans = { auto = 0, low = 1, medium = 2, high = 3 }

local function encoder(minimum, maximum, build, supports)
  return {
    min_temperature = minimum, max_temperature = maximum,
    swing_modes = { "off", "vertical", "horizontal", "all" },
    supports = supports or function() return true end,
    encode = function(s) return frame(build(s)) end
  }
end

local function toshiba(s, model)
  local mode = ({ auto = 0, cool = 1, dry = 2, heat = 3, fan = 4 })[s.mode]
  local fan = ({ auto = 0, low = 2, medium = 4, high = 6 })[s.fan]
  local length = 3 | (model << 4)
  local data = { 0xF2, 0x0D, length, length ~ 0xFF, 1,
    (s.temperature - 17) << 4, (s.power and mode or 7) | (fan << 5), 0, 0 }
  for i = 1, 8 do data[9] = data[9] ~ data[i] end
  local t = {}
  -- Toshiba repeats each message once, then sends a separate 56-bit swing state.
  for _ = 1, 2 do packet(t, data, {4400, 4300}, 580, 1600, 490, 580, 7400, true) end
  length = 1 | (model << 4)
  data = { 0xF2, 0x0D, length, length ~ 0xFF, 0x21,
    enabled(s.swing_vertical) and 1 or 2, 0 }
  for i = 1, 6 do data[7] = data[7] ~ data[i] end
  for _ = 1, 2 do packet(t, data, {4400, 4300}, 580, 1600, 490, 580, 7400, true) end
  return t
end

for model = 0, 1 do
  local remote = model
  M.encoders[remote == 0 and "toshiba-72-a" or "toshiba-72-b"] = encoder(17, 30,
    function(s) return toshiba(s, remote) end,
    function(s)
      if s.swing_horizontal ~= "off" then return false, "Toshiba does not support horizontal swing" end
      return true
    end)
end

M.encoders["toshiba-72-a"].swing_modes = { "off", "vertical" }
M.encoders["toshiba-72-b"].swing_modes = { "off", "vertical" }

M.encoders["mitsubishi-144"] = encoder(16, 31, function(s)
  local mode = ({ auto = 4, cool = 3, dry = 2, heat = 1, fan = 7 })[s.mode]
  local fan = ({ auto = 0, low = 1, medium = 2, high = 4 })[s.fan]
  local vane = enabled(s.swing_vertical) and 7 or 1
  local wide = enabled(s.swing_horizontal) and 8 or 3
  local data = { 0x23, 0xCB, 0x26, 1, 0, s.power and 0x20 or 0,
    mode << 3, s.temperature - 16,
    (wide << 4) | (({ cool = 6, dry = 2, fan = 7 })[s.mode] or 0),
    fan | (vane << 3) | 0x40 | (fan == 0 and 0x80 or 0),
    0x67, 0, 0, 0, 0, 0, vane << 3, 0 }
  data[18] = sum(data, 1, 17)
  local t = {}
  for _ = 1, 2 do packet(t, data, {3400, 1750}, 450, 1300, 420, 440, 15500, false) end
  return t
end)

local function split_block(t, data, offset, kelvinator)
  local mark, one, zero = 620, 1600, 540
  local header, gap = {9000, 4500}, 19980
  if kelvinator then mark, one, zero, header, gap = 680, 1530, 510, {9010, 4505}, 19975 end
  append(t, header[1], header[2])
  bytes(t, data, offset + 1, offset + 4, mark, one, zero, false)
  bits(t, 2, 3, mark, one, zero, false)
  append(t, mark, gap)
  bytes(t, data, offset + 5, offset + 8, mark, one, zero, false)
  append(t, mark, kelvinator and gap * 2 or gap)
end

local function gree_supports(s)
  if s.mode == "auto" and s.temperature ~= 25 then
    return false, "Gree auto mode requires a 25 C setpoint"
  end
  if s.mode == "dry" and s.fan ~= "low" then
    return false, "Gree dry mode requires low fan"
  end
  return true
end

for _, model in ipairs({ "yaw1f", "ybofb", "yx1fsf" }) do
  local remote = model
  M.encoders["gree-" .. remote] = encoder(16, 30, function(s)
    local data = { common_modes[s.mode] | (s.power and 8 or 0) |
        (common_fans[s.fan] << 4) | (enabled(s.swing_vertical) and 64 or 0),
      s.temperature - 16, 0x20 | (s.power and remote == "yaw1f" and 0x40 or 0),
      0x50, (enabled(s.swing_vertical) and 1 or 0) |
        (enabled(s.swing_horizontal) and 0x10 or 0), 0x20, 0, 0 }
    data[8] = block_checksum(data, 0)
    local t = {}
    split_block(t, data, 0, false)
    return t
  end, gree_supports)
  M.encoders["gree-" .. remote].mode_defaults = {
    auto = { temperature = 25 }, dry = { fan = "low" }
  }
end

M.encoders["kelvinator-128"] = encoder(16, 30, function(s)
  local fan = ({ auto = 0, low = 1, medium = 3, high = 5 })[s.fan]
  local swing = enabled(s.swing_vertical) or enabled(s.swing_horizontal)
  local data = { common_modes[s.mode] | (s.power and 8 or 0) |
      (math.min(fan, 3) << 4) | (swing and 64 or 0), s.temperature - 16,
    0, 0x50, (enabled(s.swing_vertical) and 1 or 0) |
      (enabled(s.swing_horizontal) and 16 or 0), 0, 0, 0,
    0, 0, 0, 0x70, 0, 0, fan << 4, 0 }
  for i = 1, 3 do data[i + 8] = data[i] end
  data[8], data[16] = block_checksum(data, 0), block_checksum(data, 8)
  local t = {}
  split_block(t, data, 0, true)
  split_block(t, data, 8, true)
  return t
end, function(s)
  if (s.mode == "auto" or s.mode == "dry") and s.temperature ~= 25 then
    return false, "Kelvinator auto/dry mode requires a 25 C setpoint"
  end
  return true
end)
M.encoders["kelvinator-128"].mode_defaults = {
  auto = { temperature = 25 }, dry = { temperature = 25 }
}

M.encoders["electra-104"] = encoder(16, 32, function(s)
  local mode = ({ auto = 0, cool = 1, dry = 2, heat = 4, fan = 6 })[s.mode]
  local fan = ({ auto = 5, low = 3, medium = 2, high = 1 })[s.fan]
  local data = { 0xC3, ((s.temperature - 8) << 3) |
      (enabled(s.swing_vertical) and 0 or 7),
    enabled(s.swing_horizontal) and 0 or 0xE0, 0, fan << 5, 0, mode << 5,
    0, 0, s.power and 0x20 or 0, 0, 8, 0 }
  data[13] = sum(data, 1, 12)
  local t = {}
  -- Upstream's arbitrary 100ms trailing idle exceeds TS1201's uint16 timing.
  -- Bound only the final idle; all data pulses remain identical to upstream.
  packet(t, data, {9166, 4470}, 646, 1647, 547, 646, 65535, false)
  return t
end)

return M
