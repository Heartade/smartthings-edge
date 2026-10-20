-- SmartThings Edge adapter for raw Zosung ZCL command bodies.
local messages = require "st.zigbee.messages"
local zcl = require "st.zigbee.zcl"
local data_types = require "st.zigbee.data_types"
local constants = require "st.zigbee.constants"

local M = {}
local zcl_sequence = 0

local RawBody = {}
RawBody.__index = RawBody

function RawBody.new(bytes)
  return setmetatable({ bytes = bytes }, RawBody)
end

function RawBody:serialize()
  return self.bytes
end

function RawBody:get_length()
  return #self.bytes
end

function RawBody:get_fields()
  return { self.bytes }
end

function RawBody:pretty_print()
  return string.format("ZosungRawBody: %d bytes", #self.bytes)
end

local function next_zcl_sequence()
  local seq = zcl_sequence
  zcl_sequence = (zcl_sequence + 1) % 256
  return seq
end

function M.send(device, cluster, command, payload)
  assert(device ~= nil, "device is required")
  assert(type(cluster) == "number" and cluster % 1 == 0, "invalid cluster")
  assert(type(command) == "number" and command % 1 == 0, "invalid command")
  assert(type(payload) == "string", "Zosung payload must be bytes")

  local frame_ctrl = zcl.FrameCtrl(0)
  frame_ctrl:set_cluster_specific()
  frame_ctrl:set_disable_default_response()

  local zcl_header = zcl.ZclHeader({
    frame_ctrl = frame_ctrl,
    seqno = data_types.Uint8(next_zcl_sequence()),
    cmd = data_types.ZCLCommandId(command)
  })
  local address_header = messages.AddressHeader(
    constants.HUB.ADDR,
    constants.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(cluster),
    device:get_profile_id() or constants.HA_PROFILE_ID,
    cluster
  )
  local body = zcl.ZclMessageBody({
    zcl_header = zcl_header,
    zcl_body = RawBody.new(payload)
  })
  device:send(messages.ZigbeeMessageTx({
    address_header = address_header,
    body = body
  }))
end

local function byte_string(value)
  if type(value) == "string" then return value end
  if type(value) == "table" and type(value.value) == "string" then
    return value.value
  end
  return nil
end

function M.received(zb_rx)
  local body = zb_rx and zb_rx.body
  local header = body and body.zcl_header
  local zcl_body = body and body.zcl_body
  local command = header and header.cmd and header.cmd.value
  local payload = zcl_body and byte_string(zcl_body.body_bytes)

  if payload == nil and zcl_body then
    payload = byte_string(zcl_body)
  end
  if type(command) ~= "number" or payload == nil then
    return nil, "message has no raw Zosung ZCL command body"
  end
  return command, payload
end

return M
