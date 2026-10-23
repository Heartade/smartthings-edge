-- Raw payloads for Zosung cluster-specific ZCL commands. The outer ZCL
-- header/addressing belongs to the SmartThings Zigbee adapter.
local M = {}

local function uint(v, width)
  assert(type(v) == "number" and v % 1 == 0 and v >= 0 and v < 256 ^ width,
    "integer out of range")
  local out = {}
  for _ = 1, width do
    out[#out + 1] = string.char(v % 256)
    v = math.floor(v / 256)
  end
  return table.concat(out)
end

local function read(data, offset, width)
  assert(offset + width - 1 <= #data, "truncated Zosung payload")
  local n = 0
  for i = width - 1, 0, -1 do n = n * 256 + data:byte(offset + i) end
  return n, offset + width
end

function M.encode(cmd, p)
  if cmd == 0x00 then
    return uint(p.seq, 2) .. uint(p.length, 4) .. uint(p.unk1, 4) ..
      uint(p.unk2, 2) .. uint(p.unk3, 1) .. uint(p.cmd, 1) .. uint(p.unk4, 2)
  elseif cmd == 0x01 then
    return uint(p.zero, 1) .. M.encode(0x00, p)
  elseif cmd == 0x02 then
    return uint(p.seq, 2) .. uint(p.position, 4) .. uint(p.maxlen, 1)
  elseif cmd == 0x03 then
    assert(type(p.msgpart) == "string" and #p.msgpart <= 255, "invalid chunk")
    return uint(p.zero, 1) .. uint(p.seq, 2) .. uint(p.position, 4) ..
      uint(#p.msgpart, 1) .. p.msgpart .. uint(p.msgpartcrc, 1)
  elseif cmd == 0x04 then
    return uint(p.zero0, 1) .. uint(p.seq, 2) .. uint(p.zero1, 2)
  elseif cmd == 0x05 then
    return uint(p.seq, 2) .. uint(p.zero, 2)
  end
  error("unknown Zosung command")
end

function M.decode(cmd, data)
  assert(type(data) == "string", "payload must be bytes")
  local pos, p = 1, {}
  local function take(name, width)
    p[name], pos = read(data, pos, width)
  end
  if cmd == 0x00 or cmd == 0x01 then
    if cmd == 0x01 then take("zero", 1) end
    take("seq", 2); take("length", 4); take("unk1", 4)
    take("unk2", 2); take("unk3", 1); take("cmd", 1); take("unk4", 2)
  elseif cmd == 0x02 then
    take("seq", 2); take("position", 4); take("maxlen", 1)
  elseif cmd == 0x03 then
    take("zero", 1); take("seq", 2); take("position", 4)
    local len; len, pos = read(data, pos, 1)
    assert(pos + len <= #data, "truncated Zosung chunk")
    p.msgpart = data:sub(pos, pos + len - 1)
    pos = pos + len
    take("msgpartcrc", 1)
  elseif cmd == 0x04 then
    take("zero0", 1); take("seq", 2); take("zero1", 2)
  elseif cmd == 0x05 then
    take("seq", 2); take("zero", 2)
  else
    error("unknown Zosung command")
  end
  assert(pos == #data + 1, "trailing Zosung payload bytes")
  return p
end

function M.learning(enable)
  return enable and '{"study":0}' or '{"study":1}'
end

return M
