-- Send-side Lua adaptations of IRremoteESP8266, revision
-- 1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f. Original sources:
-- ir_Samsung, ir_Haier, ir_Carrier, ir_Tcl, ir_Midea and ir_Daikin.
-- Copyright 2017-2022 David Conran; 2016-2017 sillyfrog; 2019 pasna;
-- and IRremoteESP8266 contributors.
-- SPDX-License-Identifier: LGPL-2.1-only
-- See licenses/IRremoteESP8266-LGPL-2.1.txt and docs/expanded-ac-protocols.md.
local M = { encoders = {} }
local function pair(t, mark, space) t[#t + 1], t[#t + 2] = mark, space end
local function bits(t, value, count, mark, one, zero, msb)
  for bit = 0, count - 1 do
    local shift = msb and count - bit - 1 or bit
    pair(t, mark, ((value >> shift) & 1) == 1 and one or zero)
  end
end
local function bytes(t, data, first, last, mark, one, zero, msb)
  for i = first, last do bits(t, data[i], 8, mark, one, zero, msb) end
end
local function sum(data, first, last)
  local total = 0
  for i = first, last do total = total + data[i] end
  return total & 255
end
local function zeros(length)
  local data = {}
  for i = 1, length do data[i] = 0 end
  return data
end
local function enabled(value) return value ~= "off" end
local function packet(data, header, mark, one, zero, gap, msb)
  local t = {}
  pair(t, header[1], header[2])
  bytes(t, data, 1, #data, mark, one, zero, msb)
  pair(t, mark, gap)
  return t
end
local function register(id, minimum, maximum, swing, build, supports)
  M.encoders[id] = {
    min_temperature = minimum, max_temperature = maximum, swing_modes = swing,
    supports = function(s)
      local v, h = enabled(s.swing_vertical), enabled(s.swing_horizontal)
      if #swing == 1 and (v or h) then return false, id .. " has no absolute swing control" end
      if #swing == 2 and h then return false, id .. " does not support horizontal swing" end
      if supports then return supports(s) end
      return true
    end,
    encode = function(s)
      return { { carrier_hz = 38000, timings = build(s) } }
    end
  }
  return M.encoders[id]
end
local all_swing = { "off", "vertical", "horizontal", "all" }
local vertical = { "off", "vertical" }
local no_swing = { "off" }
local fans = { auto = 0, low = 1, medium = 2, high = 3 }

-- Samsung: always send the complete extended state. This avoids relying on a
-- remembered previous power state when the physical remote is also in use.
local function popcount(value)
  local n = 0
  for _ = 1, 8 do n = n + (value & 1); value = value >> 1 end
  return n
end
local function samsung_checksum(data, offset)
  local count = popcount(data[offset]) + popcount(data[offset + 1] & 15) +
    popcount(data[offset + 2] & 240)
  for i = offset + 3, offset + 6 do count = count + popcount(data[i]) end
  local checksum = count ~ 255
  data[offset + 1] = (data[offset + 1] & 15) | ((checksum & 15) << 4)
  data[offset + 2] = (data[offset + 2] & 240) | (checksum >> 4)
end
local samsung = register("samsung-ac", 16, 30, all_swing, function(s)
  local mode = ({ auto = 0, cool = 1, dry = 2, fan = 3, heat = 4 })[s.mode]
  local fan = s.mode == "auto" and 6 or ({ auto = 0, low = 2, medium = 4, high = 5 })[s.fan]
  local v, h = enabled(s.swing_vertical), enabled(s.swing_horizontal)
  local swing = v and (h and 4 or 2) or (h and 3 or 7)
  local power = s.power and 0xF0 or 0xC0
  local data = { 2, 2, 0, 0, 0, 0, power,
    1, 2, 0, 0, 0, 0, 0,
    1, 2, 0x80 | (swing << 4), 0x71, (s.temperature - 16) << 4,
    1 | (fan << 1) | (mode << 4), power }
  for offset = 1, 15, 7 do samsung_checksum(data, offset) end
  local t = {}
  pair(t, 690, 17844)
  for offset = 1, 15, 7 do
    pair(t, 3086, 8864)
    bytes(t, data, offset, offset + 6, 586, 1432, 436, false)
    -- Only the last trailing idle is bounded to the TS1201 uint16 format.
    pair(t, 586, offset == 15 and 65535 or 2886)
  end
  return t
end, function(s)
  if s.mode == "auto" and s.fan ~= "auto" then return false, "Samsung auto mode requires automatic fan" end
  return true
end)
samsung.mode_defaults = { auto = { fan = "auto" } }

-- Carrier/Surrey 64-bit state. This variant has no native Auto or Dry mode.
local carrier = register("carrier-64", 16, 30, vertical, function(s)
  local mode = ({ heat = 1, cool = 2, fan = 3 })[s.mode]
  local data = { 0x84, 0x55, (mode << 4) | (fans[s.fan] << 6),
    (s.temperature - 16) | (enabled(s.swing_vertical) and 32 or 0),
    s.power and 16 or 0, 0, 0x90, 0x10 }
  local checksum = 0
  -- Checksum covers nibbles 5..15 of the little-endian uint64 state.
  checksum = data[3] >> 4
  for i = 4, 8 do checksum = checksum + (data[i] & 15) + (data[i] >> 4) end
  data[3] = data[3] | (checksum & 15)
  return packet(data, {8940, 4556}, 503, 1736, 615, 65535, false)
end, function(s)
  if s.mode ~= "cool" and s.mode ~= "heat" and s.mode ~= "fan" then
    return false, "Carrier 64-bit supports cool, heat and fan only"
  end
  return true
end)
carrier.modes = { "cool", "heat", "fan" }

-- Haier HSU07-HEA03 (72-bit): MSB-first payload and an extra leader pair.
local function haier_packet(data)
  local t = { 3000, 3000 }
  pair(t, 3000, 4300)
  bytes(t, data, 1, #data, 520, 1650, 650, true)
  pair(t, 520, 65535) -- Upstream's guessed 150ms final idle is bounded.
  return t
end
register("haier-72", 16, 30, vertical, function(s)
  local mode = ({ auto = 0, cool = 1, dry = 2, heat = 3, fan = 4 })[s.mode]
  local fan = ({ auto = 0, low = 3, medium = 2, high = 1 })[s.fan]
  local data = { 0xA5, ((s.temperature - 16) << 4) | (s.power and 1 or 0),
    0x20 | (enabled(s.swing_vertical) and 0xC0 or 0), 0, 12, fan << 6, mode << 5, 0, 0 }
  data[9] = sum(data, 1, 8)
  return haier_packet(data)
end)

-- YR-W02 uses the first 14 bytes of the same representation as Haier176.
-- Native Power-button messages carry the complete state; optional timers,
-- sensor reports, health and cleaning are deliberately disabled.
local function haier_long(s, length, model)
  local data = zeros(length)
  local fan = ({ auto = 5, low = 3, medium = 2, high = 1 })[s.fan]
  local mode = ({ auto = 0, cool = 1, dry = 2, heat = 4, fan = 6 })[s.mode]
  data[1] = model
  data[2] = ((s.temperature - 16) << 4) | (enabled(s.swing_vertical) and 12 or 0)
  data[3] = length ~= 20 and enabled(s.swing_horizontal) and 0xE0 or 0
  data[5] = (s.power and 0x40 or 0) | (length == 20 and s.mode == "heat" and 0x80 or 0)
  data[6], data[8], data[13] = fan << 5, mode << 5, 5
  data[14] = sum(data, 1, 13)
  if length > 14 then
    data[15] = length == 20 and 0xB5 or 0xB7
    data[17] = (fan == 5 and 0 or fan) << (length == 20 and 5 or 6)
    data[length] = sum(data, 15, length - 1)
  end
  return haier_packet(data)
end
register("haier-yrw02", 16, 30, all_swing, function(s) return haier_long(s, 14, 0xA6) end)
register("haier-160", 16, 30, vertical, function(s) return haier_long(s, 20, 0xA6) end)
register("haier-176-a", 16, 30, all_swing, function(s) return haier_long(s, 22, 0xA6) end)
register("haier-176-b", 16, 30, all_swing, function(s) return haier_long(s, 22, 0x59) end)

-- TCL112AC, including the documented Daewoo GYKQ-52E family.
local function tcl(s, native_model)
  local mode = ({ heat = 1, dry = 2, cool = 3, fan = 7, auto = 8 })[s.mode]
  local fan = ({ auto = 0, low = 2, medium = 3, high = 5 })[s.fan]
  local data = { 0x23, 0xCB, 0x26, 1, 0, 0x60 | (s.power and 4 or 0),
    mode, 31 - s.temperature, 0x40 | fan | (enabled(s.swing_vertical) and 56 or 0),
    0, 0, 0, (native_model and 128 or 0) | (enabled(s.swing_horizontal) and 8 or 0), 0 }
  data[14] = sum(data, 1, 13)
  return packet(data, {3000, 1650}, 500, 1050, 325, 65535, false)
end
register("tcl112-tac09chsd", 16, 31, all_swing, function(s) return tcl(s, true) end)
register("tcl112-gz055be1", 16, 31, all_swing, function(s) return tcl(s, false) end)

-- Midea's normal state plus its fully inverted copy. Swing uses toggle-only
-- auxiliary messages upstream, so no absolute swing selector is advertised.
local function reverse8(value)
  local reversed = 0
  for _ = 1, 8 do reversed = (reversed << 1) | (value & 1); value = value >> 1 end
  return reversed
end
register("midea-48", 17, 30, no_swing, function(s)
  local mode = ({ cool = 0, dry = 1, auto = 2, heat = 3, fan = 4 })[s.mode]
  local data = { 0xA1, (s.power and 128 or 0) | (fans[s.fan] << 3) | mode,
    0x40 | (s.temperature - 17), 0xFF, 0xFF, 0 }
  local checksum = 0
  for i = 1, 5 do checksum = checksum + reverse8(data[i]) end
  data[6] = reverse8((-checksum) & 255)
  local t = {}
  for phase = 1, 2 do
    pair(t, 4480, 4480)
    for i = 1, 6 do bits(t, phase == 1 and data[i] or (data[i] ~ 255), 8, 560, 1680, 560, true) end
    pair(t, 560, phase == 1 and 5600 or 65535)
  end
  return t
end)

-- Daikin ARC480A5 / 152-bit family. Implements the common IRac Celsius state
-- subset (setMode followed by setTemp), not separate comfort/sensor commands.
register("daikin-152", 18, 32, vertical, function(s)
  local mode = ({ auto = 0, dry = 2, cool = 3, heat = 4, fan = 6 })[s.mode]
  local fan = ({ auto = 10, low = 3, medium = 5, high = 6 })[s.fan]
  local data = zeros(19)
  data[1], data[2], data[3], data[16] = 0x11, 0xDA, 0x27, 0xC5
  data[6], data[7] = (s.power and 1 or 0) | (mode << 4), s.temperature << 1
  data[9] = (fan << 4) | (enabled(s.swing_vertical) and 15 or 0)
  data[19] = sum(data, 1, 18)
  local t = {}
  bits(t, 0, 5, 433, 1529, 433, false)
  pair(t, 433, 25182)
  pair(t, 3492, 1718)
  bytes(t, data, 1, 19, 433, 1529, 433, false)
  pair(t, 433, 25182)
  return t
end)
return M
