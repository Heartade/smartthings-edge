-- Decode the Zosung IR code and render its signed mark/space timings for UI.
-- The wire format is base64(LZSS blocks of little-endian uint16 durations).
local M = {}

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local decode = {}
for index = 1, #alphabet do decode[alphabet:sub(index, index)] = index - 1 end

local function from_base64(value)
  if type(value) ~= "string" or #value == 0 or #value % 4 ~= 0 or
      value:find("[^A-Za-z0-9+/=]") then return nil, "invalid base64 capture" end
  local out = {}
  for i = 1, #value, 4 do
    local a, b, c, d = value:byte(i, i + 3)
    a, b = decode[string.char(a)], decode[string.char(b)]
    c = c == 61 and nil or decode[string.char(c)]
    d = d == 61 and nil or decode[string.char(d)]
    if a == nil or b == nil or (c == nil and d ~= nil) then
      return nil, "invalid base64 capture"
    end
    local n = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
    out[#out + 1] = string.char(math.floor(n / 65536) % 256)
    if c ~= nil then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
    if d ~= nil then out[#out + 1] = string.char(n % 256) end
  end
  return table.concat(out)
end

local function decompress(compressed)
  local output, position = {}, 1
  while position <= #compressed do
    local header = compressed:byte(position)
    position = position + 1
    local block_type = math.floor(header / 32)
    if block_type == 0 then
      local length = header % 32 + 1
      if position + length - 1 > #compressed then return nil, "truncated literal block" end
      for i = position, position + length - 1 do output[#output + 1] = compressed:byte(i) end
      position = position + length
    else
      local length = block_type + 2
      if length == 9 then
        while position <= #compressed and compressed:byte(position) == 255 do
          length = length + 255
          position = position + 1
        end
        if position > #compressed then return nil, "truncated extended block" end
        length = length + compressed:byte(position)
        position = position + 1
      end
      if position > #compressed then return nil, "truncated reference block" end
      local distance = (header % 32) * 256 + compressed:byte(position) + 1
      position = position + 1
      if distance > #output then return nil, "invalid reference distance" end
      for _ = 1, length do output[#output + 1] = output[#output - distance + 1] end
    end
  end
  if #output == 0 or #output % 2 ~= 0 then return nil, "invalid timing byte count" end
  local timings = {}
  for i = 1, #output, 2 do
    local duration = output[i] + output[i + 1] * 256
    local timing_index = #timings + 1
    timings[timing_index] = timing_index % 2 == 1 and duration or -duration
  end
  return timings
end

function M.decode(code)
  local compressed, err = from_base64(code)
  if not compressed then return nil, err end
  return decompress(compressed)
end

function M.report(code, carrier_hz)
  local timings, err = M.decode(code)
  if not timings then return nil, err end
  local total_us, marks, spaces = 0, 0, 0
  for _, value in ipairs(timings) do
    total_us = total_us + math.abs(value)
    if value > 0 then marks = marks + 1 else spaces = spaces + 1 end
  end

  local lines = {
    string.format("Captured IR signal | carrier ~%d Hz (default)", carrier_hz or 38000),
    "Protocol: not decoded; raw timings shown",
    string.format("%d timings (%d marks, %d spaces) | %.2f ms total", #timings, marks, spaces, total_us / 1000),
    "Durations in microseconds: + mark, - space"
  }
  local row = {}
  for index, value in ipairs(timings) do
    row[#row + 1] = string.format("%+d", value)
    if #row == 8 or index == #timings then
      lines[#lines + 1] = table.concat(row, "  ")
      row = {}
    end
  end
  local result = table.concat(lines, "\n")
  local max_length = 3000
  if #result > max_length then
    result = result:sub(1, max_length - 44) .. "\n… timing list shortened"
  end
  return result, timings
end

return M
