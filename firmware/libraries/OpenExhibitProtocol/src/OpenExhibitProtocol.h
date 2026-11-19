#pragma once
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

class ExhibitEndpoint {
public:
  using Send = void (*)(const char *);
  using Safe = void (*)();
  using Set = bool (*)(const char *, long);
  ExhibitEndpoint(const char *id, const char *caps, Send send, Safe safe, Set set)
      : id_(id), caps_(caps), send_(send), safe_(safe), set_(set) {}
  void begin(uint32_t boot) {
    safe_(); armed_ = false; live_ = false; seq_ = 0; token_[0] = 0;
    snprintf(boot_, sizeof(boot_), "%08lx", (unsigned long)boot);
  }
  void tick(uint32_t now) {
    if (live_ && now - beat_ > 1200) {
      begin(strtoul(boot_, nullptr, 16) + 1);
    }
  }
  void input(const char *channel, long value) {
    if (!live_) return;
    char line[86];
    snprintf(line, sizeof(line), "IN %s %s %ld", token_, channel, value);
    send_(line);
  }
  void receive(char *line, uint32_t now) {
    tick(now);
    char *ctx = nullptr;
    const char *op = strtok_r(line, " \r\n", &ctx);
    if (!op) return;
    if (!strcmp(op, "OFF")) { armed_ = false; safe_(); return; }
    char out[96];
    if (!strcmp(op, "PROBE")) {
      snprintf(out, sizeof(out), "BOOT %s", boot_); send_(out); return;
    }
    char *arg = strtok_r(nullptr, " \r\n", &ctx);
    if (!arg) return;
    if (!strcmp(op, "OPEN")) {
      char *session = strtok_r(nullptr, " \r\n", &ctx);
      char *boot = strtok_r(nullptr, " \r\n", &ctx);
      if (strcmp(arg, "1") || !session || strlen(session) != 12 || !boot || strcmp(boot,boot_)) return;
      for (int i=0; i<12; ++i) if (!isxdigit((unsigned char)session[i])) return;
      safe_(); armed_ = false; live_ = true; seq_ = 0; beat_ = now;
      memcpy(token_, session, 13);
      snprintf(out, sizeof(out), "HELLO 1 %s %s 0.1 %s", id_, token_, caps_);
      send_(out); return;
    }
    if (!live_ || strcmp(arg, token_)) return;
    if (!strcmp(op, "HB")) {
      beat_ = now;
      snprintf(out, sizeof(out), "ALIVE %s", token_); send_(out); return;
    }
    if (!strcmp(op, "ARM")) {
      armed_ = true;
      snprintf(out, sizeof(out), "ARMED %s", token_); send_(out); return;
    }
    if (strcmp(op, "OUT") || !armed_) return;
    char *number = strtok_r(nullptr, " \r\n", &ctx);
    char *channel = strtok_r(nullptr, " \r\n", &ctx);
    char *val = strtok_r(nullptr, " \r\n", &ctx);
    if (!number || !channel || !val || strlen(number)>9 || strlen(val)>8) return;
    char *end;
    unsigned long n = strtoul(number, &end, 10);
    if (*end || n==0 || number[0]=='-') return;
    long value = strtol(val, &end, 10);
    if (*end) return;
    if (n > seq_) {
      if (!set_(channel, value)) {
        armed_ = false; safe_();
        snprintf(out, sizeof(out), "ERR %s range_or_channel", token_); send_(out); return;
      }
      seq_ = n;
    }
    snprintf(out, sizeof(out), "ACK %s %lu", token_, n); send_(out);
  }
private:
  const char *id_, *caps_;
  Send send_; Safe safe_; Set set_;
  char token_[13] = {}, boot_[9] = {};
  bool live_ = false, armed_ = false;
  uint32_t beat_ = 0, seq_ = 0;
};
