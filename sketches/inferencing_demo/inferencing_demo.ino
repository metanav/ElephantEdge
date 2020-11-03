
/* Includes ---------------------------------------------------------------- */
#include <elephant_edge_v3_inference.h>
#include <Arduino_LSM9DS1.h>
#include <ArduinoBLE.h>

/* Constant defines -------------------------------------------------------- */
#define CONVERT_G_TO_MS2    9.80665f
#define SERVICE_UUID "61740001-8888-1000-8000-00805f666c79"
#define CHARACTERISTIC_UUID "61740002-8888-1000-8000-00805f666c79"
#define DATA_SIZE 115
/* Private variables ------------------------------------------------------- */
static bool debug_nn = false; // Set this to true to see e.g. features generated from the raw signal
static uint32_t run_inference_every_ms = 200;

// inference buffer requires 6 (axes) * 200 (frame size) * 4 (float size) = 4800 bytes.
// Mbed thread has 4096 bytes default maximum memory limit so passing 8192 as maximum memory size 
static rtos::Thread inference_thread(osPriorityLow, 8192);
static rtos::Thread ble_thread(osPriorityLow);
static float buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE] = { 0 };
ei_impulse_result_t result = { 0 };

/**
  @brief      Arduino setup function
*/
void setup()
{
  delay(5000);

  // put your setup code here, to run once:
  Serial.begin(115200);
  Serial.println("Edge Impulse Inferencing Demo");

  if (!IMU.begin()) {
    ei_printf("Failed to initialize IMU!\r\n");
  }
  else {
    ei_printf("IMU initialized\r\n");
  }

  if (!BLE.begin()) {
    Serial.println("starting BLE failed!");
    while (1);
  }

  if (EI_CLASSIFIER_RAW_SAMPLES_PER_FRAME != 6) {
    ei_printf("ERR: EI_CLASSIFIER_RAW_SAMPLES_PER_FRAME should be equal to 6 (3 acc axes + 3 gyro axes)\n");
    return;
  }

  ble_thread.start(&ble_send_message);
  inference_thread.start(&run_inference);
}

/**
  @brief      Printf function uses vsnprintf and output using Arduino Serial

  @param[in]  format     Variable argument list
*/
void ei_printf(const char *format, ...) {
  static char print_buf[1024] = { 0 };

  va_list args;
  va_start(args, format);
  int r = vsnprintf(print_buf, sizeof(print_buf), format, args);
  va_end(args);

  if (r > 0) {
    Serial.write(print_buf);
  }
}

/**
   @brief      Run inferencing in the background.
               You probably want to implement some averaging here, e.g.
               look at the last 10 inference results and only do something
               when 70% of the last inferences are the same.
*/
void run_inference()
{
  // wait until we have a full buffer
  delay((EI_CLASSIFIER_INTERVAL_MS * EI_CLASSIFIER_RAW_SAMPLE_COUNT) + 100);

  while (1) {

    // copy the buffer
    float inference_buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE];
    memcpy(inference_buffer, buffer, EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE * sizeof(float));
    // Turn the raw buffer in a signal which we can the classify
    signal_t signal;
    int err = numpy::signal_from_buffer(inference_buffer, EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE, &signal);

    if (err != 0) {
      ei_printf("Failed to create signal from buffer (%d)\n", err);
      return;
    }

    // Run the classifier
    //ei_impulse_result_t result = { 0 };
    err = run_classifier(&signal, &result, debug_nn);
    if (err != EI_IMPULSE_OK) {
      ei_printf("ERR: Failed to run classifier (%d)\n", err);
      return;
    }
    // print the predictions
    //    ei_printf("Predictions (DSP: %d ms., Classification: %d ms., Anomaly: %d ms.): \n",
    //              result.timing.dsp, result.timing.classification, result.timing.anomaly);
    //    for (size_t ix = 0; ix < EI_CLASSIFIER_LABEL_COUNT; ix++) {
    //      ei_printf("    %s: %.5f\n", result.classification[ix].label, result.classification[ix].value);
    //    }
#if EI_CLASSIFIER_HAS_ANOMALY == 1
    ei_printf("    anomaly score: %.3f\n", result.anomaly);
#endif

    delay(run_inference_every_ms);
  }
}


void ble_send_message()
{
  BLEService sensorService(SERVICE_UUID);
  BLEStringCharacteristic sensorChar(CHARACTERISTIC_UUID, BLERead | BLENotify, DATA_SIZE);
  BLE.setLocalName("Arduino");
  BLE.setAdvertisedService(sensorService); // add the service UUID
  sensorService.addCharacteristic(sensorChar); // add the characteristic
  BLE.addService(sensorService); // Add the  service
  sensorChar.writeValue("{\"status\": \"init\" }"); // set initial value for this characteristic

  BLE.advertise();

  ei_printf("Bluetooth device active, waiting for connections...");

  // if a central is connected to the peripheral:
  while (1) {
    // wait for a BLE central
    BLEDevice central = BLE.central();
    if (central) {
      ei_printf("Connected");

      while (central.connected()) {
        char values[DATA_SIZE];
        sprintf(values,
                "{\"status\": \"result\", \"pred\": {\"%s\": %.2f,\"%s\": %.2f,\"%s\": %.2f,\"%s\": %.2f,\"%s\": %.2f}}",
                result.classification[0].label,
                result.classification[0].value,
                result.classification[1].label,
                result.classification[1].value,
                result.classification[2].label,
                result.classification[2].value,
                result.classification[3].label,
                result.classification[3].value,
                result.classification[4].label,
                result.classification[4].value
               );

        ei_printf("%s\n", values);
        sensorChar.writeValue(values);

      }
    }
  }
}

/**
  @brief      Get data and run inferencing

  @param[in]  debug  Get debug info if true
*/
void loop()
{
  while (1) {
    // Determine the next tick (and then sleep later)
    uint64_t next_tick = micros() + (EI_CLASSIFIER_INTERVAL_MS * 1000);

    // roll the buffer -6 points so we can overwrite the last one
    numpy::roll(buffer, EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE, -6);

    // read to the end of the buffer
    IMU.readAcceleration(
      buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE - 6],
      buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE - 5],
      buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE - 4]
    );

    IMU.readGyroscope(
      buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE - 3],
      buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE - 2],
      buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE - 1]
    );

    buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE - 6] *= CONVERT_G_TO_MS2;
    buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE - 5] *= CONVERT_G_TO_MS2;
    buffer[EI_CLASSIFIER_DSP_INPUT_FRAME_SIZE - 4] *= CONVERT_G_TO_MS2;

    // and wait for next tick
    uint64_t time_to_wait = next_tick - micros();
    delay((int)floor((float)time_to_wait / 1000.0f));
    delayMicroseconds(time_to_wait % 1000);
  }
}

#if !defined(EI_CLASSIFIER_SENSOR) || EI_CLASSIFIER_SENSOR != EI_CLASSIFIER_SENSOR_ACCELEROMETER
#error "Invalid model for current sensor"
#endif
