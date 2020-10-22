#include <ArduinoBLE.h>
#include <Arduino_LSM9DS1.h>

#define CONVERT_G_TO_MS2    9.80665f
#define SERVICE_UUID "61740001-8888-1000-8000-00805f666c79"
#define CHARACTERISTIC_UUID "61740002-8888-1000-8000-00805f666c79"

BLEService sensorService(SERVICE_UUID);

BLEStringCharacteristic sensorChar(CHARACTERISTIC_UUID, BLERead | BLENotify, 64);

long previousMillis = 0;  // last time the sensor was checked, in ms
char values[64];

void setup() {
  Serial.begin(115200);
  while (!Serial);

  // begin initialization
  if (!BLE.begin()) {
    Serial.println("starting BLE failed!");

    while (1);
  }

  BLE.setLocalName("ELEPHANTEDGE");
  BLE.setAdvertisedService(sensorService); // add the service UUID
  sensorService.addCharacteristic(sensorChar); // add the battery level characteristic
  BLE.addService(sensorService); // Add the battery service
  sensorChar.writeValue(""); // set initial value for this characteristic

  BLE.advertise();

  Serial.println("Bluetooth device active, waiting for connections...");

  if (!IMU.begin()) {
    Serial.println("Failed to initialize IMU!");
    while (1);
  }

  Serial.print("Accelerometer sample rate = ");
  Serial.print(IMU.accelerationSampleRate());
  Serial.println(" Hz");
  Serial.print("Gyroscope sample rate = ");
  Serial.print(IMU.gyroscopeSampleRate());
  Serial.println(" Hz");
  Serial.print("Magnetic field sample rate = ");
  Serial.print(IMU.magneticFieldSampleRate());
  Serial.println(" Hz");
}

void loop() {
  // wait for a BLE central
  BLEDevice central = BLE.central();

  // if a central is connected to the peripheral:
  if (central) {
    Serial.print("Connected to central: ");
    // print the central's BT address:
    Serial.println(central.address());

    while (central.connected()) {
      long currentMillis = millis();
      float ax, ay, az, gx, gy, gz, mx, my, mz;
      if (currentMillis - previousMillis >= 200) {
        previousMillis = currentMillis;
        if (IMU.accelerationAvailable()) {
          IMU.readAcceleration(ax, ay, az);
//          Serial.print(ax);
//          Serial.print('\t');
//          Serial.print(ay);
//          Serial.print('\t');
//          Serial.println(az);
        }

        if (IMU.gyroscopeAvailable()) {
          IMU.readGyroscope(gx, gy, gz);

//          Serial.print(gx);
//          Serial.print('\t');
//          Serial.print(gy);
//          Serial.print('\t');
//          Serial.println(gz);
        }

        if (IMU.magneticFieldAvailable()) {
          IMU.readMagneticField(mx, my, mz);
//
//          Serial.print(mx);
//          Serial.print('\t');
//          Serial.print(my);
//          Serial.print('\t');
//          Serial.println(mz);
        }

        sprintf(values, 
            "%0.2f,%0.2f,%0.2f,%0.2f,%0.2f,%0.2f,%0.2f,%0.2f,%0.2f", 
            ax * CONVERT_G_TO_MS2, ay * CONVERT_G_TO_MS2, az * CONVERT_G_TO_MS2, gx, gy, gz, mx, my, mz);
        Serial.println(values);
        sensorChar.writeValue(values);
      }
    }

    Serial.print("Disconnected from central: ");
    Serial.println(central.address());
  }
}
