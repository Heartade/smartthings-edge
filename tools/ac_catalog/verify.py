#!/usr/bin/env python3
"""Compare the shipped Lua runtime against every native capture (Lua 5.3)."""
import argparse, hashlib, json
from pathlib import Path
from lupa.lua53 import LuaRuntime

ap=argparse.ArgumentParser()
ap.add_argument('--work',type=Path,required=True)
args=ap.parse_args()
lua=LuaRuntime(unpack_returned_tuples=True)
verify=lua.eval('''function(path, id, model)
  package.path = "src/?.lua;" .. package.path
  local encoder = require("ac.protocol_catalog").encoders[id]
  local f=assert(io.open(path,"rb")); local binary=f:read("*a"); f:close()
  local rows,pos=string.unpack("<I4",binary)
  local data=require("ac.catalog_data." .. model.module)
  local dims=data.dims
  local modes={"auto","cool","heat","dry","fan"}
  local fans={"auto","low","medium","high"}
  local total=0
  for row=0,rows-1 do
    local coordinate={}
    local remaining=row
    for d=#dims,1,-1 do coordinate[d]=remaining % dims[d]; remaining=math.floor(remaining/dims[d]) end
    local carrier,count,mode,temp,fan,normalized
    carrier,count,mode,temp,fan,normalized,pos=string.unpack("<I4I4I4I4I4I4",binary,pos)
    local s={mode=modes[coordinate[1]+1],temperature=coordinate[2]+10,
      fan=fans[coordinate[3]+1],power=coordinate[4]==1,
      swing_vertical=coordinate[5]==1 and "auto" or "off",
      swing_horizontal=coordinate[6]==1 and "auto" or "off"}
    local previous={power=coordinate[7]==1,
      swing_vertical=coordinate[8]==1 and "auto" or "off",
      swing_horizontal=coordinate[9]==1 and "auto" or "off"}
    local frames=encoder.encode(s,model.value,previous)
    if count==0 then assert(#frames==0)
    else
      assert(#frames==1 and frames[1].carrier_hz==carrier)
      assert(#frames[1].timings==count)
      for i=1,count do
        local expected; expected,pos=string.unpack("<I4",binary,pos)
        assert(frames[1].timings[i]==expected,id.." row "..row.." pulse "..i)
      end
      total=total+count
    end
  end
  assert(pos==#binary+1)
  return rows,total
end''')
manifest=json.loads(Path('tools/ac_catalog/manifest.json').read_text(encoding='utf-8'))
rows=pulses=0
for entry in manifest['protocols']:
    for model in entry['models']:
        path=args.work/(entry['protocol']+'_'+str(model['value'])+'.bin')
        assert hashlib.sha256(path.read_bytes()).hexdigest()==model['sha256'], 'Capture checksum mismatch: '+str(path)
        r,p=verify(str(path),'irac-'+entry['protocol'].lower().replace('_','-'),lua.table_from(model))
        assert r==model['rows']
        rows+=r; pulses+=p
        print(entry['protocol'],model['value'],r,'states matched',flush=True)
print('TOTAL',rows,'states,',pulses,'timings matched')
