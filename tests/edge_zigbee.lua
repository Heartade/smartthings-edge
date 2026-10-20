package.path = "src/?.lua;src/?/init.lua;" .. package.path

local function callable(constructor)
  return setmetatable(constructor, { __call = function(_, ...) return constructor.new(...) end })
end

local FrameCtrl = {}
FrameCtrl.__index = FrameCtrl
function FrameCtrl.new(value)
  return setmetatable({ value = value or 0 }, FrameCtrl)
end
function FrameCtrl:set_cluster_specific()
  self.value = self.value | 0x01
end
function FrameCtrl:set_disable_default_response()
  self.value = self.value | 0x10
end

local function value_type(value)
  return { value = value }
end

local messages = {
  AddressHeader = function(src_addr, src_endpoint, dest_addr, dest_endpoint, profile, cluster)
    return { src_addr = src_addr, src_endpoint = src_endpoint, dest_addr = dest_addr,
      dest_endpoint = dest_endpoint, profile = profile, cluster = cluster }
  end,
  ZigbeeMessageTx = function(fields) return fields end
}
local zcl = {
  ZclHeader = function(fields) return fields end,
  ZclMessageBody = function(fields) return fields end
}
package.preload["st.zigbee.messages"] = function() return messages end
package.preload["st.zigbee.zcl.frame_ctrl"] = function() return callable(FrameCtrl) end
package.preload["st.zigbee.generic_body"] = function()
  return { GenericBody = function(bytes)
    return { body_bytes = bytes, _serialize = function(self) return self.body_bytes end,
      get_length = function(self) return #self.body_bytes end }
  end }
end
package.preload["st.zigbee.zcl"] = function() return zcl end
package.preload["st.zigbee.data_types"] = function()
  return { Uint8 = value_type, ZCLCommandId = value_type }
end
package.preload["st.zigbee.constants"] = function()
  return { HUB = { ADDR = 0, ENDPOINT = 1 }, HA_PROFILE_ID = 0x0104 }
end

local adapter = require "ir.edge_zigbee"
local endpoints = { [0xED00] = 3, [0xE004] = 3 }
local device = {
  sent = {},
  get_short_address = function() return 0x1234 end,
  get_endpoint = function(_, cluster) return endpoints[cluster] end,
  get_profile_id = function() return 0x0104 end,
  send = function(self, message) self.sent[#self.sent + 1] = message end
}

local raw = string.char(0x01, 0x02, 0x00, 0xFF)
adapter.send(device, 0xED00, 0x03, raw)
local tx = device.sent[1]
assert(tx.address_header.src_addr == 0 and tx.address_header.src_endpoint == 1)
assert(tx.address_header.dest_addr == 0x1234 and tx.address_header.dest_endpoint == 3)
assert(tx.address_header.profile == 0x0104 and tx.address_header.cluster == 0xED00)
assert(tx.body.zcl_header.cmd.value == 0x03 and tx.body.zcl_header.seqno.value == 0)
assert(tx.body.zcl_header.frame_ctrl.value == 0x11)
assert(tx.body.zcl_body:_serialize() == raw and tx.body.zcl_body:get_length() == #raw)

adapter.send(device, 0xE004, 0x00, '{"study":0}')
assert(device.sent[2].address_header.cluster == 0xE004)
assert(device.sent[2].body.zcl_header.seqno.value == 1)
assert(device.sent[2].body.zcl_body:_serialize() == '{"study":0}')

local command, payload = adapter.received({ body = {
  zcl_header = { cmd = { value = 0x03 } },
  zcl_body = { body_bytes = raw }
} })
assert(command == 0x03 and payload == raw)

command, payload = adapter.received({ body = {
  zcl_header = { cmd = { value = 0x00 } },
  zcl_body = raw
} })
assert(command == 0x00 and payload == raw)

local invalid, err = adapter.received({ body = { zcl_header = {}, zcl_body = {} } })
assert(invalid == nil and type(err) == "string")
print("Edge Zigbee adapter tests passed")
