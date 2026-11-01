// =============================================================================
// FarmLens firmware: ESP32 sensor bridge
// Board: ESP32 Dev Module (esp32dev). Framework: Arduino / PlatformIO.
//
// Every 5 seconds: build a sensor reading and POST it as JSON to the
// Raspberry Pi node at http://RPI_HOST:RPI_PORT/api/sensor.
//
// By default the reading comes from the same simulated curves the Pi uses in
// SENSOR_MODE=mock. Build with -D USE_ANALOG_PROBES to read two analog probes
// instead. That path compiles but has not been tested on real probes.
// =============================================================================

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

#include "sensor_model.h"

#if __has_include("secrets.h")
#include "secrets.h"
#else
#warning "include/secrets.h not found: building with placeholder settings. Copy secrets.h.example to secrets.h."
#define WIFI_SSID "YOUR_WIFI_SSID"
#define WIFI_PASS "YOUR_WIFI_PASSWORD"
#define RPI_HOST  "YOUR_RPI_IP"
#define RPI_PORT  8000
#define NODE_ID   "FL-001"
#define API_KEY   ""
#endif

#ifndef API_KEY
#define API_KEY ""
#endif

const int LED_PIN = 2;                       // ESP32 Dev Module built-in LED
const unsigned long SEND_INTERVAL_MS = 5000;

#ifdef USE_ANALOG_PROBES
const int MOISTURE_PIN = 34;                 // ADC1 pins, usable while WiFi is on
const int WATER_PIN    = 35;
#endif

// ─── LED HELPERS ─────────────────────────────────────────────────────────────
void blinkLED(int times, int ms) {
  for (int i = 0; i < times; i++) {
    digitalWrite(LED_PIN, LOW);  delay(ms);
    digitalWrite(LED_PIN, HIGH); delay(ms);
  }
}

// ─── READ SENSORS ────────────────────────────────────────────────────────────
sensor_model::Reading readSensors() {
#ifdef USE_ANALOG_PROBES
  using namespace sensor_model;
  float m = rawToPct(analogRead(MOISTURE_PIN), kMoistureDry, kMoistureWet);
  float w = rawToPct(analogRead(WATER_PIN), kWaterDry, kWaterWet);
  return makeReading(m, w);
#else
  return sensor_model::mockReading(millis() / 1000.0f);
#endif
}

// ─── SEND SENSOR DATA TO THE PI ──────────────────────────────────────────────
bool sendSensorData() {
  sensor_model::Reading r = readSensors();

  JsonDocument doc;
  doc["node_id"]      = NODE_ID;
  doc["moisture_raw"] = r.moistureRaw;
  doc["moisture_pct"] = r.moisturePct;
  doc["water_raw"]    = r.waterRaw;
  doc["water_pct"]    = r.waterPct;
  doc["ts"]           = (int)(millis() / 1000);
  doc["fault"]        = 0;

  String body;
  serializeJson(doc, body);

  String url = String("http://") + RPI_HOST + ":" + String(RPI_PORT) + "/api/sensor";

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  if (strlen(API_KEY) > 0) {
    http.addHeader("X-API-Key", API_KEY);
  }
  http.setTimeout(4000);
  int code = http.POST(body);
  http.end();

  if (code == 200) {
    Serial.printf("[FL] POST OK   m=%.1f%% w=%.1f%% cs=%.2f\n", r.moisturePct, r.waterPct, r.cs);
    return true;
  }
  Serial.printf("[FL] POST FAIL HTTP %d (is the Pi running? is API_KEY right?)\n", code);
  return false;
}

// ─── SETUP ───────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println("\n[FL] FarmLens ESP32 sensor bridge");
  Serial.printf("[FL] Node: %s\n", NODE_ID);
#ifdef USE_ANALOG_PROBES
  Serial.println("[FL] Sensor source: analog probes");
#else
  Serial.println("[FL] Sensor source: simulated curves");
#endif

  pinMode(LED_PIN, OUTPUT);
  blinkLED(2, 300);   // 2 slow blinks = booting

  Serial.printf("[FL] Connecting to WiFi: %s\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    digitalWrite(LED_PIN, !digitalRead(LED_PIN));
    Serial.print(".");
    attempts++;
  }
  Serial.println();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[FL] WiFi failed, restarting");
    delay(3000);
    ESP.restart();
  }

  digitalWrite(LED_PIN, HIGH);  // solid = connected
  Serial.printf("[FL] WiFi connected, ESP32 IP: %s\n", WiFi.localIP().toString().c_str());

  if (MDNS.begin("farmlens-esp32")) {
    Serial.println("[FL] mDNS: farmlens-esp32.local");
  }
  Serial.printf("[FL] Posting to http://%s:%d/api/sensor every %lus\n",
                RPI_HOST, RPI_PORT, SEND_INTERVAL_MS / 1000);
}

// ─── LOOP ────────────────────────────────────────────────────────────────────
void loop() {
  static unsigned long lastSend = 0;

  if (millis() - lastSend >= SEND_INTERVAL_MS) {
    bool ok = sendSensorData();
    // LED feedback: 1 quick blink = OK, 3 rapid = failed
    if (ok) {
      digitalWrite(LED_PIN, LOW); delay(60); digitalWrite(LED_PIN, HIGH);
    } else {
      blinkLED(3, 80);
      digitalWrite(LED_PIN, HIGH);
    }
    lastSend = millis();
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[FL] WiFi lost, reconnecting");
    WiFi.reconnect();
    delay(2000);
  }
}
