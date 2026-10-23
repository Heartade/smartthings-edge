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
  for index, v in ipairs(timings) do
    -- A zero-length mark continues a long idle without adding an IR pulse.
    -- Only allow it between a full uint16 idle and its positive remainder.
    local continuation = v == 0 and index > 1 and index % 2 == 1 and
      timings[index - 1] == 65535 and type(timings[index + 1]) == "number" and
      timings[index + 1] > 0 and timings[index + 1] <= 65535
    assert(type(v) == "number" and v == math.floor(v) and
      ((v > 0 and v <= 65535) or continuation),
      "timing outside uint16 range or invalid idle continuation")
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

-- A session is private to one parent blaster; callers must reject or queue
-- other transmissions until command 04. Positions are zero-based byte offsets.
function M.new_session(encoded, seq)
  assert(type(encoded) == "string" and #encoded > 0, "empty IR code")
  assert(type(seq) == "number" and seq >= 0 and seq <= 65535 and seq % 1 == 0,
    "invalid sequence")
  local session = { code = encoded, seq = seq, complete = false, position = 0 }
  function session:start()
    return 0x00, { seq = self.seq, length = #self.code,
      unk1 = 0, unk2 = 0xE004, unk3 = 1, cmd = 2, unk4 = 0 }
  end
  function session:requested_part(request_seq, position)
    assert(not self.complete and request_seq == self.seq, "unexpected sequence")
    assert(type(position) == "number" and position >= 0 and position < #self.code
      and position % 1 == 0, "invalid part position")
    if self.last_position == position then
      return 0x03, { zero = 0, seq = self.seq, position = position,
        msgpart = self.last_part, msgpartcrc = M.checksum(self.last_part) }
    end
    assert(position == self.position, "unexpected part position")
    local part = self.code:sub(position + 1, position + 0x32)
    self.last_position, self.last_part = position, part
    self.position = position + #part
    return 0x03, { zero = 0, seq = self.seq, position = position,
      msgpart = part, msgpartcrc = M.checksum(part) }
  end
  function session:acknowledge(request_seq)
    assert(not self.complete and request_seq == self.seq, "unexpected sequence")
    assert(self.position == #self.code, "IR code transfer is incomplete")
    self.complete = true
    return 0x05, { seq = self.seq, zero = 0 }
  end
  return session
end

-- Receive the device's learned IR message. All chunks must arrive in order;
-- callers should abandon this object on a transport timeout.
function M.new_capture(max_bytes)
  local capture = { max_bytes = max_bytes or 8192 }
  function capture:begin(seq, length, metadata)
    assert(not self.seq and type(seq) == "number" and seq >= 0 and seq <= 65535,
      "capture already active or invalid sequence")
    assert(type(length) == "number" and length % 1 == 0 and length > 0
      and length <= self.max_bytes, "invalid capture length")
    self.seq, self.length, self.position, self.parts = seq, length, 0, {}
    metadata = metadata or {}
    return { { cmd = 0x01, payload = {
      zero = 0, seq = seq, length = length, unk1 = metadata.unk1 or 0,
      unk2 = metadata.unk2 or 0, unk3 = metadata.unk3 or 0,
      cmd = metadata.cmd or 0, unk4 = metadata.unk4 or 0
    } }, { cmd = 0x02, payload = { seq = seq, position = 0, maxlen = 0x38 } } }
  end
  function capture:part(seq, position, bytes, checksum)
    assert(self.seq == seq and self.position == position, "unexpected capture position or sequence")
    assert(type(bytes) == "string" and #bytes > 0 and
      position + #bytes <= self.length, "capture chunk out of bounds")
    assert(M.checksum(bytes) == checksum, "capture checksum mismatch")
    self.parts[#self.parts + 1] = bytes
    self.position = position + #bytes
    if self.position < self.length then
      return 0x02, { seq = seq, position = self.position, maxlen = 0x38 }
    end
    return 0x04, { zero0 = 0, seq = seq, zero1 = 0 }
  end
  function capture:finish(seq)
    assert(self.seq == seq and self.position == self.length, "incomplete capture")
    local code = base64(table.concat(self.parts))
    self.seq, self.parts = nil, nil
    return code
  end
  return capture
end

return M
