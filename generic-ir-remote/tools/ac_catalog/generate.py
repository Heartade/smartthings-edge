#!/usr/bin/env python3
"""Compile the pinned upstream common AC API into finite-domain Lua encoders.

All state setters/checksums/Manchester coding/repeats remain upstream code at
build time. The hub evaluates reduced decision graphs; it does not run C++.
Requires Python/numpy and a C++11 compiler. See docs/ac-catalog.md.
"""
import argparse, hashlib, json, os, re, shutil, struct, subprocess, sys
from pathlib import Path
import numpy as np
from selection_artifacts import generate as generate_selection_artifacts

REVISION = '1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f'
SOURCE_SHA256 = 'cb35fa7a0e96e4b045edcb1701f8a9270f14a93fa6a12beeb0098667157bc8d9'
MODEL_ENUMS = {
 'ARGO':'argo_ac_remote_model_t', 'FUJITSU_AC':'fujitsu_ac_remote_model_t',
 'GREE':'gree_ac_remote_model_t', 'HAIER_AC176':'haier_ac176_remote_model_t',
 'HITACHI_AC1':'hitachi_ac1_remote_model_t', 'MIRAGE':'mirage_ac_remote_model_t',
 'PANASONIC_AC':'panasonic_ac_remote_model_t', 'SHARP_AC':'sharp_ac_remote_model_t',
 'TCL112AC':'tcl_ac_remote_model_t', 'TEKNOPOINT':'tcl_ac_remote_model_t',
 'VOLTAS':'voltas_ac_remote_model_t', 'WHIRLPOOL_AC':'whirlpool_ac_remote_model_t',
 'LG':'lg_ac_remote_model_t', 'LG2':'lg_ac_remote_model_t', 'TOSHIBA_AC':'toshiba_ac_remote_model_t'
}
PREV_POWER = {'AIRWELL','DAIKIN64','DAIKIN128','PANASONIC_AC32','WHIRLPOOL_AC',
 'KELON','PANASONIC_AC','HITACHI_AC1','SHARP_AC','SAMSUNG_AC'}
PREV_SWING = {'COOLIX','TRANSCOLD','CORONA_AC','HITACHI_AC344','HITACHI_AC424',
 'KELON','MIDEA','LG','LG2','SHARP_AC','HITACHI_AC1'}

def catalog(src):
    text = (src/'IRac.cpp').read_text(encoding='utf-8')
    section = text.split('bool IRac::isProtocolSupported(',1)[1].split('return true;',1)[0]
    protocols = sorted(set(re.findall(r'case decode_type_t::(\w+):',section)))
    macros = sorted(set(re.findall(r'#if (SEND_\w+)',section)))
    header = (src/'IRsend.h').read_text(encoding='utf-8')
    models = {}
    for protocol in protocols:
        enum = MODEL_ENUMS.get(protocol)
        if not enum:
            models[protocol] = [(0,'default')]; continue
        body = re.search(r'enum '+enum+r'\s*\{(.*?)\};',header,re.S)[1]
        body = re.sub(r'//[^\n]*','',body)
        value, result = -1, []
        for part in body.split(','):
            m = re.match(r'\s*(\w+)(?:\s*=\s*(\d+))?',part)
            if not m: continue
            value = int(m[2]) if m[2] else value+1
            result.append((value,m[1]))
        # LG/LG2 are selected by the model in upstream IRac. Avoid cross-family aliases.
        if protocol == 'LG': result = [x for x in result if x[0] in (1,5)]
        if protocol == 'LG2': result = [x for x in result if x[0] in (2,3,4)]
        if protocol == 'PANASONIC_AC': result = [x for x in result if x[0] != 0]
        if protocol == 'TEKNOPOINT': result = [x for x in result if x[0] == 2]
        models[protocol] = result
    return protocols, macros, models

def verify_source(upstream):
    paths=sorted([*upstream.joinpath('src').glob('*.cpp'),*upstream.joinpath('src').glob('*.h'),
      upstream/'test/IRsend_test.h'],key=lambda p:p.relative_to(upstream).as_posix())
    digest=hashlib.sha256()
    for path in paths:
        digest.update(path.relative_to(upstream).as_posix().encode()+b'\0'+path.read_bytes()+b'\0')
    if digest.hexdigest()!=SOURCE_SHA256:
        raise RuntimeError('Upstream sources differ from the pinned revision; use an unmodified source archive')

def build(upstream, work, compiler):
    src = upstream/'src'; protocols, macros, models = catalog(src)
    work.mkdir(parents=True,exist_ok=True)
    # Only capture instrumentation is changed in this temporary test header.
    header = (upstream/'test/IRsend_test.h').read_text(encoding='utf-8')
    header = header.replace('#define OUTPUT_BUF 10000U','#define OUTPUT_BUF 4096U').replace('#define RAW_BUF 10000U','#define RAW_BUF 4096U')
    header = header.replace('class IRsendTest : public IRsend {','extern void catalog_pulse(bool, uint32_t, uint32_t);\nclass IRsendTest : public IRsend {')
    header = header.replace('uint16_t mark(uint16_t usec) {','uint16_t mark(uint16_t usec) {\n    catalog_pulse(true, usec, _freq_unittest);')
    header = header.replace('void space(uint32_t time) {','void space(uint32_t time) {\n    catalog_pulse(false, time, _freq_unittest);')
    (work/'IRsend_test.h').write_text(header,encoding='utf-8',newline='\n')
    # Snapshot normalized mode/temp/fan after the actual common-API helper sends.
    original = (src/'IRac.cpp').read_text(encoding='utf-8')
    start = original.index('bool IRac::sendAc(const stdAc::state_t desired')
    end = original.index('}  // NOLINT(readability/fn_size)',start)
    body = original[start:end]
    body,n = re.subn(r'(^\s+\w+\(&ac,[^;]+;)',r'\1\n      catalog_common(ac, 0);',body,flags=re.M)
    patched = original[:start]+body+original[end:]
    hook = '''\nextern stdAc::state_t catalog_normalized;\nextern bool catalog_has_normalized;
template<class T> auto catalog_common(T &ac, int) -> decltype(ac.toCommon(), void()) {
 catalog_normalized = ac.toCommon(); catalog_has_normalized = true;
}
template<class T> void catalog_common(T &, long) {}
'''
    patched = patched.replace('/// Class constructor',hook+'\n/// Class constructor',1)
    (work/'IRac.cpp').write_text(patched,encoding='utf-8',newline='\n')
    wrapper = (Path(__file__).parent/'capture.cpp').read_text(encoding='utf-8')
    items = ',\n'.join('{"'+p+'", decode_type_t::'+p+'}' for p in protocols)
    wrapper = wrapper.replace('/* PROTOCOL_ITEMS */',items)
    (work/'capture.cpp').write_text(wrapper,encoding='utf-8',newline='\n')
    sources = [src/n for n in ['IRsend.cpp','IRrecv.cpp','IRtimer.cpp','IRutils.cpp','IRtext.cpp']]
    sources += sorted(src.glob('ir_*.cpp'))
    sources += [work/'capture.cpp',work/'IRac.cpp']
    exe = work/('capture.exe' if os.name == 'nt' else 'capture')
    flags = ['-std=c++11','-O1','-w','-ffunction-sections','-fdata-sections',
      '-DUNIT_TEST','-D_IR_ENABLE_DEFAULT_=false']
    flags += ['-D'+m+'=true' for m in sorted(set(macros + ['SEND_COOLIX48', 'DECODE_MIRAGE']))]
    flags += ['-I'+str(work),'-I'+str(src),'-I'+str(upstream/'test')]
    print('Compiling native catalog capture ('+str(n)+' normalized-state hooks)',flush=True)
    objects=work/'objects'; objects.mkdir(exist_ok=True)
    stamp=hashlib.sha256((' '.join(flags)+header).encode()).hexdigest()
    def compile_one(path):
        key=hashlib.sha256(path.read_bytes()+stamp.encode()).hexdigest()[:16]
        obj=objects/(path.stem+'_'+key+'.o')
        if not obj.exists():
            result=subprocess.run([compiler]+flags+['-c',str(path),'-o',str(obj)],capture_output=True,text=True)
            if result.returncode:
                print(result.stderr,flush=True)
                raise RuntimeError('Compile failed: '+str(path))
        return obj
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=4) as pool:
        object_paths=list(pool.map(compile_one,sources))
    subprocess.run([compiler]+[str(p) for p in object_paths]+['-Wl,--gc-sections','-o',str(exe)],check=True)
    return exe,protocols,models

class Graph:
    def __init__(self,dims):
        self.dims=dims; self.nodes=[]; self.intern={}; self.memo={}
    def build(self,v,depth=0):
        first=int(v[0])
        if np.all(v==first): return -first-1
        key=(depth,v.tobytes())
        if key in self.memo: return self.memo[key]
        children=tuple(self.build(child,depth+1) for child in v.reshape(self.dims[depth],-1))
        if len(set(children))==1: result=children[0]
        else:
            node=(depth+1,)+children
            result=self.intern.get(node)
            if result is None:
                self.nodes.append(node); result=len(self.nodes); self.intern[node]=result
        self.memo[key]=result
        return result
    def evaluate(self,root,inputs):
        while root>0:
            node=self.nodes[root-1]; root=node[1+inputs[node[0]-1]]
        return -root-1

def lua_array(values): return '{'+','.join(map(str,values))+'}'
def base36(value):
    """Encode graph integers compactly while keeping generated files plain Lua."""
    digits='0123456789abcdefghijklmnopqrstuvwxyz'
    sign='-' if value<0 else ''
    value=abs(int(value)); result=''
    while value:
        value,remainder=divmod(value,36)
        result=digits[remainder]+result
    return sign+(result or '0')

def lua_graph_data(dims,roots,nodes):
    # Literal numeric table constructors make the hub compile over 100,000
    # constants across this catalog. Store a compact base-36 stream instead;
    # the runtime expands only the selected model's graph on first use.
    values=roots+[value for node in nodes for value in node]
    encoded=','.join(base36(value) for value in values)
    return ('return {dims='+lua_array(dims)+',root_count='+str(len(roots))+
      ',node_count='+str(len(nodes))+',values="'+encoded+'"}\n')

def lua_value(value):
    if isinstance(value,bool): return 'true' if value else 'false'
    if isinstance(value,str): return json.dumps(value)
    if isinstance(value,list): return '{'+','.join(lua_value(v) for v in value)+'}'
    if isinstance(value,dict): return '{'+','.join(k+'='+lua_value(v) for k,v in value.items())+'}'
    return str(value)

def finalize(manifest,output):
    index=[{'protocol':e['protocol'],'models':[{k:v for k,v in m.items() if k in
      ('value','name','module','min','max','modes','vertical','horizontal')} for m in e['models']]} for e in manifest]
    (output.parent/'catalog_index.lua').write_text('-- Generated by tools/ac_catalog/generate.py; LGPL-2.1-only.\nreturn '+lua_value(index)+'\n',encoding='utf-8',newline='\n')
    Path('tools/ac_catalog/manifest.json').write_text(json.dumps({'revision':REVISION,'source_sha256':SOURCE_SHA256,'protocols':manifest},indent=2)+'\n',encoding='utf-8',newline='\n')
    model_doc='# Generated AC protocol models\n\nGenerated by `tools/ac_catalog/generate.py`. Choose a protocol/model entry directly from the AC detail screen. The selector shows model identifiers when a protocol has multiple variants.\n\n| Protocol | Model numbers | Celsius range |\n| --- | --- | --- |\n'
    for entry in manifest:
        model_doc+='| `'+entry['protocol']+'` | '+ '; '.join(str(m['value'])+' = '+m['name'] for m in entry['models'])+' | '+ '; '.join(str(m['value'])+': '+str(m['min'])+'–'+str(m['max']) for m in entry['models'])+' |\n'
    Path('docs/ac-catalog-models.md').write_text(model_doc,encoding='utf-8',newline='\n')
    generate_selection_artifacts()
def capture(exe,index,model,dims,path):
    subprocess.run([str(exe),str(index),str(model),str(dims[6]),str(dims[7]),str(dims[8]),str(path)],check=True)
    data=path.read_bytes(); count=struct.unpack_from('<I',data)[0]; pos=4; rows=[]; maxlen=0
    for _ in range(count):
        carrier,length,mode,temp,fan,normalized=struct.unpack_from('<6I',data,pos); pos+=24
        durations=np.frombuffer(data,dtype='<u4',count=length,offset=pos).copy(); pos+=length*4
        rows.append((carrier,length,mode,temp,fan,normalized,durations)); maxlen=max(maxlen,length)
    assert pos==len(data) and count==int(np.prod(dims)),(pos,len(data),count,dims)
    matrix=np.zeros((count,maxlen+6),dtype=np.uint32)
    for i,row in enumerate(rows):
        matrix[i,:6]=row[:6]; matrix[i,6:6+row[1]]=row[-1]
    return matrix

def generate(exe,protocols,models,work,output,only=None,resume=False):
    output.mkdir(parents=True,exist_ok=True); manifest=[]
    for index,protocol in enumerate(protocols):
        if only and protocol not in only: continue
        entry={'protocol':protocol,'models':[]}
        for model,name in models[protocol]:
            info_path=work/(protocol+'_'+str(model)+'.info.json')
            if resume and info_path.exists():
                info=json.loads(info_path.read_text(encoding='utf-8'))
                if (output/(info['module']+'.lua')).exists():
                    entry['models'].append(info)
                    print(protocol,model,'resumed',flush=True)
                    continue
            dims=[5,23,4,2,2,2,2 if protocol in PREV_POWER else 1,2 if protocol in PREV_SWING else 1,2 if protocol == 'HITACHI_AC1' else 1]
            path=work/(protocol+'_'+str(model)+'.bin')
            matrix=capture(exe,index,model,dims,path)
            if not np.any(matrix[:,1]): raise RuntimeError('No captured waveform for '+protocol)
            if np.any(matrix[:,0]==0): raise RuntimeError('No carrier for '+protocol)
            graph=Graph(dims); roots=[graph.build(matrix[:,i]) for i in range(matrix.shape[1])]
            # Compare all generated graph outputs to every upstream matrix column.
            coordinates=np.indices(dims).reshape(len(dims),-1).T
            evaluated = {}
            for col,root in enumerate(roots):
                if root<0:
                    assert np.all(matrix[:,col]==-root-1); continue
                if root not in evaluated:
                    evaluated[root]=np.array([graph.evaluate(root,inputs) for inputs in coordinates],dtype=np.uint32)
                restored=evaluated[root]
                if not np.array_equal(restored,matrix[:,col]):
                    raise AssertionError('Graph mismatch '+protocol+' '+str(model)+' column '+str(col))
            normalized=matrix[:,5].astype(bool)
            on=coordinates[:,3]==1
            real_modes=sorted(set(int(x)-1 for x in matrix[on & normalized,2] if int(x)>0)) or list(range(5))
            temps=matrix[on & normalized,3]
            temps=temps[(temps>=10)&(temps<=32)]
            lo,hi=(int(temps.min()),int(temps.max())) if len(temps) else (16,30)
            # Does the source actually respond to the axis? If not, omit its control.
            reshaped=matrix.reshape(tuple(dims)+(matrix.shape[1],))
            vertical=not np.array_equal(np.take(reshaped,0,axis=4),np.take(reshaped,1,axis=4))
            horizontal=not np.array_equal(np.take(reshaped,0,axis=5),np.take(reshaped,1,axis=5))
            key=protocol.lower()+'_'+str(model)
            text='-- Generated from IRremoteESP8266 '+REVISION+'; LGPL-2.1-only.\n'
            text+=lua_graph_data(dims,roots,graph.nodes)
            (output/(key+'.lua')).write_bytes(text.encode('utf-8'))
            info={'value':model,'name':name,'module':key,'min':lo,'max':hi,'modes':real_modes,
              'vertical':vertical,'horizontal':horizontal,'rows':len(matrix),'nodes':len(graph.nodes),
              'bytes':len(text),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
            info_path.write_text(json.dumps(info,indent=2),encoding='utf-8',newline='\n')
            entry['models'].append(info)
            print(protocol,model,name,'rows',len(matrix),'nodes',len(graph.nodes),'Lua bytes',len(text),flush=True)
        manifest.append(entry)
        (work/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8',newline='\n')
    return manifest

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--upstream',type=Path,required=True)
    ap.add_argument('--work',type=Path,required=True); ap.add_argument('--compiler',default='g++')
    ap.add_argument('--output',type=Path,default=Path('src/ac/catalog_data'))
    ap.add_argument('--only',nargs='*'); ap.add_argument('--skip-build',action='store_true'); ap.add_argument('--resume',action='store_true')
    args=ap.parse_args()
    verify_source(args.upstream)
    if args.skip_build:
        protocols,_,models=catalog(args.upstream/'src'); exe=args.work/('capture.exe' if os.name=='nt' else 'capture')
    else: exe,protocols,models=build(args.upstream,args.work,args.compiler)
    manifest=generate(exe,protocols,models,args.work,args.output,set(args.only) if args.only else None,args.resume)
    if not args.only: finalize(manifest,args.output)
if __name__=='__main__': main()
