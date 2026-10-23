package.path = "src/?.lua;src/?/init.lua;" .. package.path
local state = require "ac.state"
local learned = require "ac.learned_state"
local store = learned.new()
local current = state.initial()
assert(store:resolve(current, {power = true}) == nil)
local target = assert(state.apply(current, {power = true, temperature = 25}))
assert(store:put(target, "captured-base64") == "on:cool:25:auto:off:off")
local next_state, code = store:resolve(current, {power = true, temperature = 25})
assert(next_state.temperature == 25 and code == "captured-base64")
assert(current.temperature == 24)
assert(store:resolve(current, {power = true, temperature = 26}) == nil)
assert(store:remove(target))
assert(store:resolve(current, {power = true, temperature = 25}) == nil)
print("Learned-state tests passed")
