-- Bounded per-child table of captured remote button signals.
local M = { MAX_CODE_LENGTH = 12000, MAX_ACTIONS = #require("ir.tv_buttons").actions }
local valid_actions = require("ir.tv_buttons").valid
local valid_requests = setmetatable({ cancel = true }, { __index = valid_actions })

local function valid_code(code)
  return type(code) == "string" and #code > 0 and
    #code <= M.MAX_CODE_LENGTH and #code % 4 == 0 and
    code:match("^[A-Za-z0-9+/]*=?=?$") ~= nil
end

function M.parse_request(request)
  if type(request) ~= "string" then return nil, "missing request" end
  local token, action = request:match("^([%w%-]+)|([%w_%-]+)$")
  if not token or #token > 24 or not valid_requests[action] then
    return nil, "expected token|action (a supported remote button) or token|cancel"
  end
  return { token = token, action = action }
end

function M.to_payload(code)
  assert(valid_code(code), "invalid captured code")
  return '{"key_num":1,"delay":300,"key1":{"num":1,"freq":38000,"type":1,"key_code":"' .. code .. '"}}'
end

function M.new(codes)
  local store = { codes = {} }
  if type(codes) == "table" then
    for action, code in pairs(codes) do
      if valid_actions[action] and valid_code(code) then
        store.codes[action] = code
      end
    end
  end

  function store:get(action)
    if not valid_actions[action] then return nil, "unsupported action" end
    return self.codes[action]
  end

  function store:put(action, code)
    if not valid_actions[action] then return nil, "unsupported action" end
    if not valid_code(code) then return nil, "invalid or oversized captured code" end
    if not self.codes[action] then
      local count = 0
      for _ in pairs(self.codes) do count = count + 1 end
      if count >= M.MAX_ACTIONS then return nil, "learned action limit reached" end
    end
    self.codes[action] = code
    return action
  end

  function store:remove(action)
    if not valid_actions[action] then return nil, "unsupported action" end
    self.codes[action] = nil
    return true
  end

  return store
end

return M
