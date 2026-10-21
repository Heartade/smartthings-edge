-- LG and LG2 28-bit AC state encoders. Field layout and timings are based on
-- the public protocol descriptions in IRremoteESP8266's ir_LG.cpp / ir_LG.h.
-- SPDX-License-Identifier: LGPL-2.1-only
-- See THIRD_PARTY_NOTICES.md and licenses/IRremoteESP8266-LGPL-2.1.txt.
-- No upstream C++ source is bundled here. Keep unsupported swing variants
-- fail-closed until their required auxiliary frames are implemented.
local M = { encoders = {} }

local LG_MODE = { cool = 0, dry = 1, fan = 2, auto = 3, heat = 4 }
local LG_FAN = { low = 1, medium = 2, high = 4, auto = 5 }

local function checksum(raw_without_sum)
  local data = math.floor(raw_without_sum / 16)
  local sum = 0
  for _ = 1, 4 do
    sum = sum + (data % 16)
    data = math.floor(data / 16)
  end
  return sum % 16
end

local function timings_for(raw, protocol)
  local header_mark, header_space, bit_mark
  if protocol == "lg2" then
    header_mark, header_space, bit_mark = 3200, 9900, 480
  else
    header_mark, header_space, bit_mark = 8500, 4250, 550
  end

  local timings = { header_mark, header_space }
  for bit = 27, 0, -1 do
    timings[#timings + 1] = bit_mark
    local value = math.floor(raw / (2 ^ bit)) % 2
    timings[#timings + 1] = value == 1 and 1600 or 550
  end
  timings[#timings + 1] = bit_mark
  timings[#timings + 1] = 39750
  return timings
end

local function make_encoder(protocol, source_models, fan_codes, swing_vertical)
  fan_codes = fan_codes or LG_FAN
  return {
    min_temperature = 16,
    max_temperature = 30,
    swing_modes = swing_vertical and { "off", "vertical" } or { "off" },
    source_models = source_models,
    supports = function(s)
      return LG_MODE[s.mode] ~= nil and fan_codes[s.fan] ~= nil and
        (swing_vertical or s.swing_vertical == "off") and s.swing_horizontal == "off"
    end,
    encode = function(s)
      local raw
      if not s.power then
        -- LG AC power-off uses its dedicated fixed command.
        raw = 0x088C0051
      else
        local power = 0 -- LG's normal state represents power on as 00.
        local temperature = s.temperature - 15
        local without_sum = 0x08800000 + power * 0x40000 +
          LG_MODE[s.mode] * 0x1000 + temperature * 0x100 + fan_codes[s.fan] * 0x10
        raw = without_sum + checksum(without_sum)
      end
      local frames = { {
        carrier_hz = 38000,
        timings = timings_for(raw, protocol)
      } }
      if swing_vertical and s.power then
        local swing = timings_for(s.swing_vertical == "off" and 0x0881315A or 0x08813149, protocol)
        for _, duration in ipairs(swing) do
          frames[1].timings[#frames[1].timings + 1] = duration
        end
      end
      return frames
    end
  }
end

-- These remote/model identifiers are listed by IRremoteESP8266 for the
-- corresponding LG or LG2 family. Their extra swing/light-only frames are
-- intentionally excluded by supports() above.
local lg_models = {
  "GE6711AR2853M", "LG6711A20083V", "TS-H122ERM1", "AG1BH09AW101"
}
local lg2_models = {
  "AKB74395308", "S4-W12JA3AA", "AKB75215403", "AKB74955603",
  "A4UW30GFA2", "AMNW09GSJA0", "AMNW24GTPA1", "AKB73757604",
  "AKB73315611", "MS05SQ NW0"
}

M.encoders["lg-28"] = make_encoder("lg", lg_models)
M.encoders["lg2-28"] = make_encoder("lg2", lg2_models)
M.encoders["lg2-akb74955603"] = make_encoder("lg2", { "AKB74955603", "AMNW09GSJA0" }, {
  low = 9, medium = 2, high = 10, auto = 5
}, true)

return M
