#include <WiFi.h>
#include <PubSubClient.h>
#include <ESP32Servo.h>
#include <OpenExhibitProtocol.h>
#include "settings.h"
// Classic ESP32 DevKit. GPIO25 drives only a current-limited indicator LED.
// GPIO26 carries a hobby servo control signal. Use a separate rated supply.
WiFiClient network;
PubSubClient mqtt(network);
Servo servo;
int targetAngle=90, actualAngle=90;
uint32_t lastStep=0;
void publishLine(const char *line) { mqtt.publish("oes/esp32/up",line,false); }
void safeOutputs() {
  digitalWrite(25,LOW);
  if (servo.attached()) servo.detach();
}
bool setChannel(const char *ch,long val) {
  if (!strcmp(ch,"light") && val>=0 && val<=1) {
    digitalWrite(25,val ? HIGH : LOW); return true;
  }
  if (!strcmp(ch,"servo") && val>=30 && val<=150) {
    targetAngle=(int)val;
    if (!servo.attached()) { servo.attach(26,1000,2000); servo.write(actualAngle); }
    return true;
  }
  return false;
}
ExhibitEndpoint endpoint("esp32","button,light,servo",publishLine,safeOutputs,setChannel);
void message(char *topic, byte *payload, unsigned int size) {
  if (size>=96 || strcmp(topic,"oes/esp32/down")) return;
  char buf[96]; memcpy(buf,payload,size); buf[size]=0;
  endpoint.receive(buf,millis());
}
void setup() {
  pinMode(25,OUTPUT); pinMode(27,INPUT_PULLUP);
  endpoint.begin(esp_random());
  WiFi.mode(WIFI_STA);
  if (WIFI_SSID[0]) WiFi.begin(WIFI_SSID,WIFI_PASS);
  mqtt.setServer(MQTT_HOST,MQTT_PORT); mqtt.setCallback(message);
  mqtt.setSocketTimeout(1); mqtt.setKeepAlive(5);
}
void loop() {
  uint32_t now=millis();
  endpoint.tick(now);
  static bool wasOnline=false;
  static uint32_t lastTry=0;
  if (WiFi.status()!=WL_CONNECTED || !mqtt.connected()) {
    if (wasOnline) { endpoint.begin(esp_random()); wasOnline=false; }
    if (WiFi.status()==WL_CONNECTED && now-lastTry>=2500) {
      lastTry=now;
      if (mqtt.connect(MQTT_CLIENT_ID,MQTT_USER,MQTT_PASS)) {
        endpoint.begin(esp_random());
        mqtt.subscribe("oes/esp32/down"); wasOnline=true;
      }
    }
    return;
  }
  mqtt.loop();
  if (servo.attached() && now-lastStep>=25 && actualAngle!=targetAngle) {
    lastStep=now; actualAngle += targetAngle>actualAngle ? 1 : -1;
    servo.write(actualAngle);
  }
  static int state=HIGH, previous=HIGH;
  static uint32_t changed=0;
  int raw=digitalRead(27);
  if (raw!=previous) { previous=raw; changed=now; }
  if (raw!=state && now-changed>=30) { state=raw; endpoint.input("button",state==LOW); }
}
