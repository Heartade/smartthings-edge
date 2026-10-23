-- Complete-state code table for ACs whose remote sends the entire setting.
local state = require "ac.state"
local M = { MAX_CODES = 64, MAX_CODE_LENGTH = 12000 }

local function valid_code(code)
  -- The IR capture module produces Base64, while this pure store also accepts
  -- short placeholders used by local unit callers. The Edge send boundary
  -- validates the format before building the Zosung payload.
  return type(code) == "string" and #code > 0 and #code <= M.MAX_CODE_LENGTH
end

local function key(s)
  return table.concat({s.power and "on" or "off", s.mode, s.temperature,
    s.fan, s.swing_vertical, s.swing_horizontal}, ":")
end
M.key = key

function M.parse_request(request)
  if type(request) ~= "string" then return nil, "missing request" end
  local token, power, mode, temperature, fan, vertical, horizontal =
    request:match("^([%w%-]+)|([%w%-]+)|([%w%-]+)|(%d+)|([%w%-]+)|([%w%-]+)|([%w%-]+)$")
  if not token or #token > 24 then
    if type(request) == "string" then
      local cancel_token = request:match("^([%w%-]+)|cancel$")
      if cancel_token and #cancel_token <= 24 then
        return { token = cancel_token, action = "cancel" }
      end
    end
    return nil, "expected token|on/off|mode|temperature|fan|vertical-swing|horizontal-swing"
  end

  if power ~= "on" and power ~= "off" then return nil, "power must be on or off" end
  local target = {
    power = power == "on",
    mode = mode,
    temperature = tonumber(temperature),
    fan = fan,
    swing_vertical = vertical,
    swing_horizontal = horizontal
  }
  local validated, err = state.apply(state.initial(), target)
  if not validated then return nil, err end
  return { token = token, target = validated }
end

function M.new(codes, limits)
  local store = { codes = {}, limits = limits or {} }
  local count = 0
  if type(codes) == "table" then
    for encoded_key, code in pairs(codes) do
      if type(encoded_key) == "string" and valid_code(code) and count < M.MAX_CODES then
        local power, mode, temperature, fan, vertical, horizontal =
          encoded_key:match("^([%w%-]+):([%w%-]+):(%d+):([%w%-]+):([%w%-]+):([%w%-]+)$")
        if power == "on" or power == "off" then
          local target = {
            power = power == "on", mode = mode, temperature = tonumber(temperature),
            fan = fan, swing_vertical = vertical, swing_horizontal = horizontal
          }
          local validated = state.apply(state.initial(), target, store.limits)
          if validated and key(validated) == encoded_key then
            store.codes[encoded_key] = code
            count = count + 1
          end
        end
      end
    end
  end

  function store:put(target, code)
    local valid, err = state.apply(state.initial(), target, self.limits)
    if not valid then return nil, err end
    if not valid_code(code) then return nil, "invalid or oversized captured code" end
    local encoded_key = key(valid)
    if not self.codes[encoded_key] then
      local existing = 0
      for _ in pairs(self.codes) do existing = existing + 1 end
      if existing >= M.MAX_CODES then return nil, "learned AC state limit reached" end
    end
    self.codes[encoded_key] = code
    return encoded_key
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
