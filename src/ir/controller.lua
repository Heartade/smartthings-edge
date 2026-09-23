-- Per-parent TS1201 transfer coordinator. The caller supplies Zigbee send and
-- a monotonic clock. Its sessions remain transient across driver restarts.
local zosung = require "ir.zosung"
local wire = require "ir.zosung_wire"
local M = {}

function M.new(send, now, timeout_seconds)
  assert(type(send) == "function" and type(now) == "function")
  local c = { send = send, now = now, timeout = timeout_seconds or 15,
    seq = -1, active = nil }

  local function emit(cluster, cmd, payload)
    c.send(cluster, cmd, cluster == zosung.CONTROL_CLUSTER and payload or wire.encode(cmd, payload))
  end

  function c:expire()
    if self.active and self.now() >= self.active.deadline then
      if self.active.kind == "learn" then
        emit(zosung.CONTROL_CLUSTER, 0x00, wire.learning(false))
      end
      self.active = nil
      return true
    end
    return false
  end

  function c:send_code(code)
    self:expire()
    if self.active then return nil, "IR blaster busy" end
    self.seq = (self.seq + 1) % 65536
    local session = zosung.new_session(code, self.seq)
    local cmd, payload = session:start()
    self.active = { kind = "send", session = session, deadline = self.now() + self.timeout }
    emit(zosung.TRANSMIT_CLUSTER, cmd, payload)
    return self.seq
  end

  function c:start_learning()
    self:expire()
    if self.active then return nil, "IR blaster busy" end
    self.active = { kind = "learn", session = zosung.new_capture(),
      deadline = self.now() + self.timeout }
    emit(zosung.CONTROL_CLUSTER, 0x00, wire.learning(true))
    return true
  end

  function c:cancel_learning()
    if not self.active or self.active.kind ~= "learn" then
      return nil, "no learning in progress"
    end
    emit(zosung.CONTROL_CLUSTER, 0x00, wire.learning(false))
    self.active = nil
    return true
  end

  function c:receive(cmd, raw)
    self:expire()
    if not self.active then return nil, "no active transfer" end
    local active = self.active
    local p = wire.decode(cmd, raw)
    if active.kind == "send" then
      if cmd == 0x02 then
        local response, part = active.session:requested_part(p.seq, p.position)
        emit(zosung.TRANSMIT_CLUSTER, response, part)
      elseif cmd == 0x04 then
        local response, ack = active.session:acknowledge(p.seq)
        emit(zosung.TRANSMIT_CLUSTER, response, ack)
        self.active = nil
        return "sent"
      else
        return nil, "unexpected send command"
      end
    elseif active.kind == "learn" then
      if cmd == 0x00 then
        local requests = active.session:begin(p.seq, p.length, p)
        for _, request in ipairs(requests) do
          emit(zosung.TRANSMIT_CLUSTER, request.cmd, request.payload)
        end
      elseif cmd == 0x03 then
        local response, payload = active.session:part(p.seq, p.position, p.msgpart, p.msgpartcrc)
        emit(zosung.TRANSMIT_CLUSTER, response, payload)
      elseif cmd == 0x05 then
        local code = active.session:finish(p.seq)
        emit(zosung.CONTROL_CLUSTER, 0x00, wire.learning(false))
        self.active = nil
        return "learned", code
      else
        return nil, "unexpected learning command"
      end
    end
    active.deadline = self.now() + self.timeout
    return "in progress"
  end
  return c
end

return M
