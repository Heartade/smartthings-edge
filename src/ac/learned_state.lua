-- Complete-state code table for ACs whose remote sends the entire setting.
local state = require "ac.state"
local M = {}

local function key(s)
  return table.concat({s.power and "on" or "off", s.mode, s.temperature,
    s.fan, s.swing_vertical, s.swing_horizontal}, ":")
end
M.key = key

function M.new(codes, limits)
  local store = { codes = codes or {}, limits = limits or {} }
  function store:put(target, code)
    local valid, err = state.apply(state.initial(), target, self.limits)
    if not valid then return nil, err end
    if type(code) ~= "string" or #code == 0 then return nil, "empty code" end
    self.codes[key(valid)] = code
    return key(valid)
  end
  function store:resolve(current, patch)
    local next_state, err = state.apply(current, patch, self.limits)
    if not next_state then return nil, err end
    local code = self.codes[key(next_state)]
    if not code then return nil, "state not learned: " .. key(next_state) end
    return next_state, code
  end
  function store:remove(target)
    local valid, err = state.apply(state.initial(), target, self.limits)
    if not valid then return nil, err end
    self.codes[key(valid)] = nil
    return true
  end
  return store
end

return M
