package.path = "src/?.lua;src/?/init.lua;" .. package.path
local controller = require "ir.controller"
local wire = require "ir.zosung_wire"
local sent, clock = {}, 0
local c = controller.new(function(cluster, cmd, raw)
  sent[#sent + 1] = { cluster = cluster, cmd = cmd, raw = raw }
end, function() return clock end, 10)
local seq = assert(c:send_code("ABC"))
assert(sent[1].cmd == 0 and seq == 0)
assert(c:start_learning() == nil)
assert(c:receive(2, wire.encode(2, {seq = seq, position = 0, maxlen = 56})) == "in progress")
assert(sent[2].cmd == 3 and wire.decode(3, sent[2].raw).msgpart == "ABC")
assert(c:receive(4, wire.encode(4, {zero0 = 0, seq = seq, zero1 = 0})) == "sent")
assert(sent[3].cmd == 5 and c.active == nil)
assert(c:start_learning())
assert(sent[4].raw == '{"study":0}')
assert(c:receive(0, wire.encode(0, {seq = 9, length = 3, unk1 = 0,
  unk2 = 0xE004, unk3 = 1, cmd = 1, unk4 = 0})) == "in progress")
assert(sent[5].cmd == 1 and sent[6].cmd == 2)
assert(c:receive(3, wire.encode(3, {zero = 0, seq = 9, position = 0,
  msgpart = "abc", msgpartcrc = 38})) == "in progress")
assert(sent[7].cmd == 4)
local status, code = c:receive(5, wire.encode(5, {seq = 9, zero = 0}))
assert(status == "learned" and code == "YWJj")
assert(sent[8].raw == '{"study":1}')
c:send_code("ABC")
clock = 11
assert(c:expire() and c.active == nil)
assert(c:send_code("XYZ"))
assert(c:cancel_learning() == nil)
assert(c:receive(2, wire.encode(2, {seq = 2, position = 0, maxlen = 56})) == "in progress")
assert(c:receive(4, wire.encode(4, {zero0 = 0, seq = 2, zero1 = 0})) == "sent")
assert(c:start_learning())
clock = 22
assert(c:expire() and sent[#sent].raw == '{"study":1}')
assert(c:start_learning())
assert(c:cancel_learning() and sent[#sent].raw == '{"study":1}')
print("IR controller tests passed")
