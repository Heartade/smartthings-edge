// Capture only: protocol setters and transmitters are the pinned upstream code.
// SPDX-License-Identifier: LGPL-2.1-only
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include "IRac.h"
#include "ir_York.h"
struct Protocol { const char* name; decode_type_t value; };
const Protocol protocols[] = { /* PROTOCOL_ITEMS */ };
struct Pulse { bool mark; uint32_t duration; uint32_t carrier; };
std::vector<Pulse> pulses;
stdAc::state_t catalog_normalized;
bool catalog_has_normalized = false;
void catalog_pulse(bool mark, uint32_t duration, uint32_t carrier) {
  if (!duration) return;
  if (!pulses.empty() && pulses.back().mark == mark && pulses.back().carrier == carrier)
    pulses.back().duration += duration;
  else pulses.push_back({mark,duration,carrier});
}
void u32(std::ostream &out, uint32_t n) {
  for (int i=0;i<4;i++) { out.put(static_cast<char>(n & 255)); n >>= 8; }
}
void york(const stdAc::state_t &s) {
  // Upstream advertises YORK in isProtocolSupported but has no sendAc case.
  // Its public raw union documents absolute power/swing bits; the declared
  // setPowerToggle method is unimplemented in this revision.
  IRYorkAc ac(0);
  ac.setMode(ac.convertMode(s.mode)); ac.setTemp(s.degrees);
  ac.setFan(ac.convertFan(s.fanspeed));
  ac._.Power = s.power; ac._.SwingV = s.swingv != stdAc::swingv_t::kOff;
  ac.send(); catalog_normalized=ac.toCommon(); catalog_has_normalized=true;
}
int main(int argc,char**argv) {
  try {
    if (argc!=7) throw std::runtime_error("expected protocol-index model prev-power-count prev-swing-count prev-horizontal-count output");
    int index=std::stoi(argv[1]), model=std::stoi(argv[2]);
    int ppCount=std::stoi(argv[3]), pvCount=std::stoi(argv[4]);
    int phCount=std::stoi(argv[5]);
    std::ofstream out(argv[6],std::ios::binary);
    if (!out) throw std::runtime_error("cannot open capture output");
    u32(out,5*23*4*2*2*2*ppCount*pvCount*phCount);
    int fans[]={0,2,3,4};
    IRac ac(0);
    for(int mode=0;mode<5;mode++) for(int temp=10;temp<=32;temp++)
    for(int fan=0;fan<4;fan++) for(int power=0;power<2;power++)
    for(int sv=0;sv<2;sv++) for(int sh=0;sh<2;sh++)
    for(int pp=0;pp<ppCount;pp++) for(int pv=0;pv<pvCount;pv++) for(int ph=0;ph<phCount;ph++) {
      stdAc::state_t desired;
      desired.protocol=protocols[index].value; desired.model=model;
      desired.power=power; desired.mode=static_cast<stdAc::opmode_t>(mode);
      desired.degrees=temp; desired.fanspeed=static_cast<stdAc::fanspeed_t>(fans[fan]);
      desired.swingv=sv?stdAc::swingv_t::kAuto:stdAc::swingv_t::kOff;
      desired.swingh=sh?stdAc::swingh_t::kAuto:stdAc::swingh_t::kOff;
      auto prev=desired; prev.power=pp; prev.swingv=pv?stdAc::swingv_t::kAuto:stdAc::swingv_t::kOff;
      prev.swingh=ph?stdAc::swingh_t::kAuto:stdAc::swingh_t::kOff;
      pulses.clear(); catalog_has_normalized=false;
      if (desired.protocol==decode_type_t::YORK) york(desired);
      else if (!ac.sendAc(desired,&prev)) throw std::runtime_error(std::string("sendAc failed for ")+protocols[index].name);
      uint32_t carrier=pulses.empty()?38000:pulses.front().carrier;
      if (!pulses.empty() && !pulses.front().mark) throw std::runtime_error("leading space");
      std::vector<uint32_t> durations;
      for (auto &pulse:pulses) {
        if (pulse.carrier!=carrier) throw std::runtime_error("mixed carrier frequencies");
        if (pulse.mark && pulse.duration>65535) throw std::runtime_error("mark exceeds uint16");
        if (!pulse.mark) {
          // Preserve long idle periods exactly with zero-mark continuations.
          while (pulse.duration>65535) {
            durations.push_back(65535); durations.push_back(0); pulse.duration-=65535;
          }
        }
        durations.push_back(pulse.duration);
      }
      if (durations.size()%2) durations.push_back(1);
      const auto &norm=catalog_has_normalized?catalog_normalized:desired;
      u32(out,carrier); u32(out,durations.size());
      u32(out,static_cast<int>(norm.mode)+1);
      u32(out,std::max(0,static_cast<int>(std::round(norm.celsius ? norm.degrees : (norm.degrees - 32) * 5 / 9))));
      u32(out,static_cast<int>(norm.fanspeed)); u32(out,catalog_has_normalized);
      for (auto duration:durations) u32(out,duration);
    }
    return 0;
  } catch(const std::exception &e) { std::cerr<<e.what()<<std::endl; return 1; }
}
