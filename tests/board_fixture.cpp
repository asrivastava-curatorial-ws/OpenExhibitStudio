// Native transport fixture. Runs the same endpoint header as both sketches.
#include "OpenExhibitProtocol.h"
#include <chrono>
#include <cstring>
#include <iostream>
#include <string>
static int lamp=0;
void transmit(const char *str) { std::cout<<str<<'\n'<<std::flush; }
void safe() {lamp=0;}
bool setOutput(const char *channel,long value) {
  if (std::strcmp(channel,"lamp") || value<0 || value>1) return false;
  lamp=value; return true;
}
int main() {
  ExhibitEndpoint board("uno","dial,lamp,lamp_echo",transmit,safe,setOutput);
  board.begin(12345);
  std::string command;
  while (std::getline(std::cin,command)) {
    if (command.size()>95) continue;
    char line[96];std::strcpy(line,command.c_str());
    uint32_t now=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
    board.receive(line,now);
    if (command.find("HB ")==0)board.input("dial",72);
    if (command.find("OUT ")==0)board.input("lamp_echo",lamp);
  }
}
