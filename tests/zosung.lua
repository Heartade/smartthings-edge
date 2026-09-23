package.path = "src/?.lua;src/?/init.lua;" .. package.path
local z = require "ir.zosung"
-- Literal LZ block: 03 84 03 A8 61; base64 = A4QDqGE=
assert(z.encode_timings({900, 25000}) == "A4QDqGE=")
assert(z.checksum("ABC") == 198)
local s = z.new_session(string.rep("A", 101), 42)
local cmd, initial = s:start()
assert(cmd == 0 and initial.length == 101 and initial.unk2 == 0xE004)
local part_cmd, part = s:requested_part(42, 50)
assert(part_cmd == 3 and part.position == 50 and #part.msgpart == 50)
assert(part.msgpartcrc == (50 * 65) % 256)
assert(not pcall(function() s:requested_part(43, 0) end))
assert(not pcall(function() s:requested_part(42, 101) end))
local done_cmd = s:acknowledge(42)
assert(done_cmd == 5 and s.complete)
assert(not pcall(function() s:requested_part(42, 0) end))
assert(not pcall(function() z.encode_timings({70000, 500}) end))
print("Zosung send-side tests passed")
