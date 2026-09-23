-- Zosung TS1201 send-side protocol primitives. Zigbee I/O is supplied by the
-- driver; this module is intentionally usable in a plain Lua test runner.
local M = { TRANSMIT_CLUSTER = 0xED00, CONTROL_CLUSTER = 0xE004 }

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    out[#out + 1] = alphabet:sub(math.floor(n / 262144) + 1, math.floor(n / 262144) + 1)
    out[#out + 1] = alphabet:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
    out[#out + 1] = b and alphabet:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
    out[#out + 1] = c and alphabet:sub(n % 64 + 1, n % 64 + 1) or "="
  end
  return table.concat(out)
end

function M.encode_timings(timings)
  assert(type(timings) == "table" and #timings > 0 and #timings % 2 == 0,
    "timings must be alternating mark/space pairs")
  local bytes = {}
  for _, v in ipairs(timings) do
    assert(type(v) == "number" and v == math.floor(v) and v > 0 and v <= 65535,
      "timing outside 1..65535 microseconds")
    bytes[#bytes + 1] = v % 256
    bytes[#bytes + 1] = math.floor(v / 256)
  end
  -- Literal blocks in the LZ format accepted by the Zosung device.
  local compressed = {}
  for i = 1, #bytes, 32 do
    local len = math.min(32, #bytes - i + 1)
    compressed[#compressed + 1] = string.char(len - 1)
    for j = i, i + len - 1 do compressed[#compressed + 1] = string.char(bytes[j]) end
  end
  return base64(table.concat(compressed))
end

function M.checksum(s)
  local sum = 0
  for i = 1, #s do sum = (sum + s:byte(i)) % 256 end
  return sum
end

-- A session is private to one parent blaster; queue other transmissions until
-- the device acknowledges command 04. Positions are zero-based byte offsets.
function M.new_session(encoded, seq)
  assert(type(encoded) == "string" and #encoded > 0, "empty IR code")
  assert(type(seq) == "number" and seq >= 0 and seq <= 65535 and seq % 1 == 0,
    "invalid sequence")
  local session = { code = encoded, seq = seq, complete = false }
  function session:start()
    return 0x00, { seq = self.seq, length = #self.code,
      unk1 = 0, unk2 = 0xE004, unk3 = 1, cmd = 2, unk4 = 0 }
  end
  function session:requested_part(request_seq, position)
    assert(not self.complete and request_seq == self.seq, "unexpected sequence")
    assert(type(position) == "number" and position >= 0 and position < #self.code
      and position % 1 == 0, "invalid part position")
    local part = self.code:sub(position + 1, position + 0x32)
    return 0x03, { zero = 0, seq = self.seq, position = position,
      msgpart = part, msgpartcrc = M.checksum(part) }
  end
  function session:acknowledge(request_seq)
    assert(not self.complete and request_seq == self.seq, "unexpected sequence")
    self.complete = true
    return 0x05, { seq = self.seq, zero = 0 }
  end
  return session
end

return M
