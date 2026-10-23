-- Resolve the unified protocol/model selector and migrate older preferences.
local generated = require "ac.selection_index"

local M = { choices = {}, by_key = {}, by_protocol = {} }
for _, item in ipairs(generated) do
  M.choices[#M.choices + 1] = item
  M.by_key[item.key] = item
  if item.protocol_key:match("^irac_") then
    local family = item.protocol_key:sub(6)
    local variants = M.by_protocol[family] or {}
    variants[#variants + 1] = item
    M.by_protocol[family] = variants
  end
end

-- Previously selected handwritten protocols are migrated to their closest
-- supported IRremoteESP8266 catalog entry. These aliases are never shown in
-- the selector and their old encoders are no longer bundled.
local legacy_aliases = {
  lg_28 = "irac_lg_m1",
  lg2_28 = "irac_lg2_m2",
  lg2_akb74955603 = "irac_lg2_m3",
  toshiba_72_a = "irac_toshiba_ac_m0",
  toshiba_72_b = "irac_toshiba_ac_m1",
  mitsubishi_144 = "irac_mitsubishi_ac_m0",
  gree_yaw1f = "irac_gree_m1",
  gree_ybofb = "irac_gree_m2",
  gree_yx1fsf = "irac_gree_m3",
  kelvinator_128 = "irac_kelvinator_m0",
  electra_104 = "irac_electra_ac_m0",
  samsung_ac = "irac_samsung_ac_m0",
  haier_72 = "irac_haier_ac_m0",
  haier_yrw02 = "irac_haier_ac_yrw02_m0",
  haier_160 = "irac_haier_ac160_m0",
  haier_176_a = "irac_haier_ac176_m1",
  haier_176_b = "irac_haier_ac176_m2",
  carrier_64 = "irac_carrier_ac64_m0",
  tcl112_tac09chsd = "irac_tcl112ac_m1",
  tcl112_gz055be1 = "irac_tcl112ac_m2",
  midea_48 = "irac_midea_m0",
  daikin_152 = "irac_daikin152_m0",
}

function M.get(key)
  return M.by_key[key] or M.by_key[legacy_aliases[key]]
end

-- Old protocol preferences used a protocol key plus a separate integer model.
-- Convert that pair to the corresponding unified choice. Model 0 meant "the
-- first catalog model", which may itself have a nonzero upstream model ID.
function M.from_preferences(protocol_key, model)
  if type(protocol_key) ~= "string" then return nil end
  local direct = M.get(protocol_key)
  if direct then return direct end
  local family = protocol_key:match("^irac_(.+)$")
  if not family then return nil end
  local variants = M.by_protocol[family]
  if not variants then return nil end
  local requested = tonumber(model) or 0
  if requested == 0 then return variants[1] end
  for _, item in ipairs(variants) do
    if item.model == requested then return item end
  end
  return nil
end

function M.default(key)
  return M.get(key) or M.by_key.irac_lg_m1
end

return M
