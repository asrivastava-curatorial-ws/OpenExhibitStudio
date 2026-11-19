#include <OpenExhibitProtocol.h>
// Classic Uno/Nano/Mega. The only physical output is the built-in indicator LED.
static void sendLine(const char *line) { Serial.println(line); }
static void safeOutputs() { digitalWrite(LED_BUILTIN, LOW); }
static bool setChannel(const char *name, long v) {
  if (strcmp(name, "lamp") || v < 0 || v > 1) return false;
  digitalWrite(LED_BUILTIN, v ? HIGH : LOW);
  return true;
}
ExhibitEndpoint endpoint("uno", "dial,button,encoder,lamp", sendLine, safeOutputs, setChannel);
volatile long encoder = 0;
void encoderA() { encoder += digitalRead(4) ? -1 : 1; }
char inputLine[96];
uint8_t used = 0;
bool overflowed = false;
void setup() {
  pinMode(LED_BUILTIN, OUTPUT); safeOutputs();
  pinMode(2, INPUT_PULLUP); pinMode(3, INPUT_PULLUP); pinMode(4, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(3), encoderA, RISING);
  Serial.begin(115200);
  endpoint.begin(micros());
}
void loop() {
  uint32_t now = millis();
  endpoint.tick(now);
  for (int budget=32; budget && Serial.available(); --budget) {
    char c = Serial.read();
    if (c == '\n') {
      if (!overflowed) { inputLine[used]=0; endpoint.receive(inputLine,now); }
      used=0; overflowed=false;
    } else if (used < sizeof(inputLine)-1) inputLine[used++]=c;
    else overflowed=true;
  }
  static uint32_t nextSample=0, changed=0;
  static int stable=HIGH, lastRaw=HIGH;
  int raw=digitalRead(2);
  if (raw != lastRaw) { lastRaw=raw; changed=now; }
  if (raw != stable && now-changed >= 25) {
    stable=raw; endpoint.input("button", stable==LOW);
  }
  if (now-nextSample>=100) {
    nextSample=now;
    endpoint.input("dial", (long)analogRead(A0)*100/1023);
    noInterrupts(); long value=encoder; interrupts();
    static long last=0;
    if (value!=last) { endpoint.input("encoder",value); last=value; }
  }
}
