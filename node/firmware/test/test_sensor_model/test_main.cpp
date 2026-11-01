// Host-side unit tests for lib/sensor_model. Run with: pio test -e native
#include <unity.h>
#include <math.h>

#include "sensor_model.h"

using namespace sensor_model;

void setUp() {}
void tearDown() {}

static void test_mock_curve_at_start() {
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 50.0f, mockMoisturePct(0));
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 45.0f + 25.0f * sinf(1.0f), mockWaterPct(0));
}

static void test_mock_moisture_peak_and_trough() {
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 80.0f, mockMoisturePct(75));
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 20.0f, mockMoisturePct(225));
}

static void test_mock_ranges_over_full_sweep() {
  for (int t = 0; t < 1200; t += 3) {
    float m = mockMoisturePct((float)t);
    float w = mockWaterPct((float)t);
    TEST_ASSERT_TRUE(m >= 19.99f && m <= 80.01f);
    TEST_ASSERT_TRUE(w >= 19.99f && w <= 70.01f);
  }
}

static void test_pct_raw_round_trip() {
  TEST_ASSERT_EQUAL_INT(kMoistureDry, pctToRaw(0, kMoistureDry, kMoistureWet));
  TEST_ASSERT_EQUAL_INT(kMoistureWet, pctToRaw(100, kMoistureDry, kMoistureWet));
  TEST_ASSERT_EQUAL_INT(1750, pctToRaw(50, kWaterDry, kWaterWet));
  TEST_ASSERT_FLOAT_WITHIN(0.1f, 42.0f,
      rawToPct(pctToRaw(42.0f, kMoistureDry, kMoistureWet), kMoistureDry, kMoistureWet));
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 100.0f, rawToPct(0, kMoistureDry, kMoistureWet));
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 0.0f, rawToPct(4095, kMoistureDry, kMoistureWet));
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 0.0f, rawToPct(100, 500, 500));
}

static void test_stress_thresholds_are_strict() {
  TEST_ASSERT_EQUAL_INT(1, stressFlag(29.9f, kMoistureStressPct));
  TEST_ASSERT_EQUAL_INT(0, stressFlag(30.0f, kMoistureStressPct));
  TEST_ASSERT_EQUAL_INT(1, stressFlag(19.9f, kWaterStressPct));
  TEST_ASSERT_EQUAL_INT(0, stressFlag(20.0f, kWaterStressPct));
}

static void test_soil_stress_weights() {
  TEST_ASSERT_FLOAT_WITHIN(1e-6f, 0.0f, soilStress(0, 0));
  TEST_ASSERT_FLOAT_WITHIN(1e-6f, 0.6f, soilStress(1, 0));
  TEST_ASSERT_FLOAT_WITHIN(1e-6f, 0.4f, soilStress(0, 1));
  TEST_ASSERT_FLOAT_WITHIN(1e-6f, 1.0f, soilStress(1, 1));
}

static void test_make_reading_rounds_and_clamps() {
  Reading r = makeReading(25.04f, 150.0f);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 25.0f, r.moisturePct);
  TEST_ASSERT_FLOAT_WITHIN(0.001f, 100.0f, r.waterPct);
  TEST_ASSERT_EQUAL_INT(1, r.moistureStress);
  TEST_ASSERT_EQUAL_INT(0, r.waterStress);
  TEST_ASSERT_FLOAT_WITHIN(1e-6f, 0.6f, r.cs);
  TEST_ASSERT_EQUAL_INT(kWaterWet, r.waterRaw);
}

int main(int, char**) {
  UNITY_BEGIN();
  RUN_TEST(test_mock_curve_at_start);
  RUN_TEST(test_mock_moisture_peak_and_trough);
  RUN_TEST(test_mock_ranges_over_full_sweep);
  RUN_TEST(test_pct_raw_round_trip);
  RUN_TEST(test_stress_thresholds_are_strict);
  RUN_TEST(test_soil_stress_weights);
  RUN_TEST(test_make_reading_rounds_and_clamps);
  return UNITY_END();
}
