package.path = "src/?.lua;src/?/init.lua;" .. package.path
local state = require "ac.state"
local registry = require "ac.registry"
assert(#registry.available() == 0)
assert(registry.encode("samsung_ac", state.initial(), { power = true }) == nil)
registry.register("fixture", {
  min_temperature = 18, max_temperature = 30,
  supports = function(s, model) return model == "example" and s.fan == "auto" end,
  encode = function(s) return { { carrier_hz = 38000, timings = {900, s.temperature * 100} } } end
})
assert(registry.available()[1] == "fixture")
assert(registry.encode("fixture", state.initial(), {fan = "high"}, "example") == nil)
local next_state, frames = registry.encode("fixture", state.initial(),
  {power = true, temperature = 25}, "example")
assert(next_state.power and next_state.temperature == 25)
assert(frames[1].timings[2] == 2500)
assert(state.initial().power == false)
print("AC registry tests passed")
