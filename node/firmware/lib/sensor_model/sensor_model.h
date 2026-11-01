// Pure sensor logic shared by the firmware and the native unit tests.
// No Arduino headers here, so it compiles on the host with `pio test -e native`.
//
// The mock curves match node/rpi/mock_sensor.py: moisture drifts 20-80 % on a
// 300 s sine wave, water level drifts 20-70 % on a 240 s sine wave. They are
// synthetic values for running without probes, not measurements.
#pragma once

#include <math.h>

namespace sensor_model {

constexpr float kPi = 3.14159265358979f;

constexpr float kMoistureMean = 50.0f, kMoistureAmp = 30.0f, kMoisturePeriodS = 300.0f;
constexpr float kWaterMean    = 45.0f, kWaterAmp    = 25.0f, kWaterPeriodS    = 240.0f;
constexpr float kWaterPhase   = 1.0f;

// ADC calibration defaults, same as MOISTURE_DRY/WET and WATER_DRY/WET in
// node/rpi/config.py. Starting values, not calibrated against real probes.
constexpr int kMoistureDry = 2800, kMoistureWet = 1200;
constexpr int kWaterDry    = 3000, kWaterWet    = 500;

constexpr float kMoistureStressPct = 30.0f;
constexpr float kWaterStressPct    = 20.0f;

struct Reading {
  float moisturePct;
  float waterPct;
  int   moistureRaw;
  int   waterRaw;
  int   moistureStress;
  int   waterStress;
  float cs;
};

inline float clampPct(float v) { return v < 0.0f ? 0.0f : (v > 100.0f ? 100.0f : v); }

// Round to one decimal place, as sent over the wire.
inline float round1(float v) { return roundf(v * 10.0f) / 10.0f; }

inline float mockMoisturePct(float tSeconds) {
  return clampPct(kMoistureMean + kMoistureAmp * sinf(2.0f * kPi * tSeconds / kMoisturePeriodS));
}

inline float mockWaterPct(float tSeconds) {
  return clampPct(kWaterMean + kWaterAmp * sinf(2.0f * kPi * tSeconds / kWaterPeriodS + kWaterPhase));
}

// Map 0-100 % onto the ADC range, where `dry` is 0 % and `wet` is 100 %.
inline int pctToRaw(float pct, int dry, int wet) {
  return (int)lroundf(dry - (pct / 100.0f) * (dry - wet));
}

// Inverse of pctToRaw, for real probes. Clamped to 0-100 %.
inline float rawToPct(int raw, int dry, int wet) {
  if (dry == wet) return 0.0f;
  return clampPct(100.0f * (float)(dry - raw) / (float)(dry - wet));
}

inline int stressFlag(float pct, float threshold) { return pct < threshold ? 1 : 0; }

// Cs = 0.6 * moisture_stress + 0.4 * water_stress (same as node/rpi/fusion.py)
inline float soilStress(int moistureStress, int waterStress) {
  return 0.6f * moistureStress + 0.4f * waterStress;
}

inline Reading makeReading(float moisturePct, float waterPct) {
  Reading r;
  r.moisturePct    = round1(clampPct(moisturePct));
  r.waterPct       = round1(clampPct(waterPct));
  r.moistureRaw    = pctToRaw(r.moisturePct, kMoistureDry, kMoistureWet);
  r.waterRaw       = pctToRaw(r.waterPct, kWaterDry, kWaterWet);
  r.moistureStress = stressFlag(r.moisturePct, kMoistureStressPct);
  r.waterStress    = stressFlag(r.waterPct, kWaterStressPct);
  r.cs             = soilStress(r.moistureStress, r.waterStress);
  return r;
}

inline Reading mockReading(float tSeconds) {
  return makeReading(mockMoisturePct(tSeconds), mockWaterPct(tSeconds));
}

}  // namespace sensor_model
