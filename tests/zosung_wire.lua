package.path = "src/?.lua;src/?/init.lua;" .. package.path
local wire = require "ir.zosung_wire"
local examples = {
  [0] = {seq = 0x1234, length = 50, unk1 = 0, unk2 = 0xE004, unk3 = 1, cmd = 2, unk4 = 0},
  [1] = {zero = 0, seq = 0x1234, length = 50, unk1 = 0, unk2 = 0xE004, unk3 = 1, cmd = 2, unk4 = 0},
  [2] = {seq = 0x1234, position = 50, maxlen = 56},
  [3] = {zero = 0, seq = 0x1234, position = 0, msgpart = "ABC", msgpartcrc = 198},
  [4] = {zero0 = 0, seq = 0x1234, zero1 = 0},
  [5] = {seq = 0x1234, zero = 0}
}
for cmd, payload in pairs(examples) do
  local encoded = wire.encode(cmd, payload)
  local decoded = wire.decode(cmd, encoded)
  for key, value in pairs(payload) do assert(decoded[key] == value, key) end
  assert(not pcall(function() wire.decode(cmd, encoded .. "x") end))
  assert(not pcall(function() wire.decode(cmd, encoded:sub(1, -2)) end))
end
assert(wire.encode(2, examples[2]) == string.char(0x34, 0x12, 50, 0, 0, 0, 56))
assert(wire.learning(true) == '{"study":0}' and wire.learning(false) == '{"study":1}')
print("Zosung payload tests passed")
