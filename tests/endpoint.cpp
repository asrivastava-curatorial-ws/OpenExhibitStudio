#include "OpenExhibitProtocol.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>

static std::string message;
static int powered = 0, count = 0;
void emit(const char *s) { message=s; }
void safe() { powered=0; }
bool output(const char *ch,long value) {
  if (std::strcmp(ch,"lamp") || value<0 || value>1) return false;
  powered=(int)value;++count;return true;
}
int main() {
  ExhibitEndpoint e("uno","lamp",emit,safe,output);
  auto send=[&](const char *cmd,uint32_t now){char buf[100];std::snprintf(buf,sizeof(buf),"%s",cmd);e.receive(buf,now);};
  e.begin(42);assert(powered==0);
  send("PROBE",0);assert(message=="BOOT 0000002a");
  send("OPEN 1 abcdef012345 0000002a",5);assert(message=="HELLO 1 uno abcdef012345 0.1 lamp");
  send("OUT abcdef012345 1 lamp 1",7);assert(powered==0);
  send("ARM abcdef012345",8);send("OUT abcdef012345 1 lamp 1",9);assert(powered==1 && count==1);
  send("OUT abcdef012345 1 lamp 1",10);assert(count==1 && message=="ACK abcdef012345 1");
  e.tick(1300);assert(powered==0);
  send("ARM abcdef012345",1301);send("OUT abcdef012345 2 lamp 1",1302);assert(count==1);
  send("PROBE",1400);assert(message=="BOOT 0000002b");
  send("OPEN 1 001122334455 0000002b",1500);send("ARM 001122334455",1510);
  send("OUT 001122334455 1 lamp 27",1520);assert(powered==0 && message=="ERR 001122334455 range_or_channel");
  std::puts("PASS native firmware protocol: handshake, arming, duplicate, watchdog, stale session, out-of-range.");
}
