import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:path_provider/path_provider.dart';

main() {
  runApp(ElephantEdgeApp());
}

class ElephantEdgeApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elephant Edge',
      debugShowCheckedModeBanner: false,
      home: ElephantEdge(),
      theme: ThemeData.dark(),
    );
  }
}

class ElephantEdge extends StatefulWidget {
  @override
  _ElephantEdgeState createState() => _ElephantEdgeState();
}

class _ElephantEdgeState extends State<ElephantEdge> {
  final String serviceUUID = "61740001-8888-1000-8000-00805f666c79";
  final String charUUID = "61740002-8888-1000-8000-00805f666c79";
  final String deviceName = "Arduino";

  FlutterBlue flutterBlue = FlutterBlue.instance;
  StreamSubscription<List<ScanResult>> scanSubScription;
  StreamSubscription<BluetoothDeviceState> stateSubscription;
  BluetoothDevice targetDevice;
  BluetoothCharacteristic targetCharacteristic;
  BluetoothDeviceState deviceState;

  String connectionText = "Elephant Edge";

  @override
  void initState() {
    super.initState();
    deviceState = BluetoothDeviceState.disconnected;
    //startScan();
  }

  startScan() {
    setState(() {
      connectionText = "Scanning...";
    });

    flutterBlue.startScan(timeout: Duration(seconds: 4));

    var found = false;

    scanSubScription = flutterBlue.scanResults.listen((scanResults) {
      if (scanResults.length > 0) {
        scanResults.forEach((result) {
          if (result.device.name == deviceName) {
            print('DEVICE found');
            found = true;
            stopScan();
            setState(() {
              connectionText = "Found Target Device";
            });

            targetDevice = result.device;
            stateSubscription = targetDevice.state.listen((s) {
              setState(() {
                deviceState = s;
                if (deviceState == BluetoothDeviceState.disconnected) {
                  connectToDevice();
                }
              });
            });
            connectToDevice();
          }
        });

        if (!found) {
          setState(() {
            connectionText = "No Device Found";
          });
        }
      }
    }, onDone: () {
      stopScan();
    });
  }

  stopScan() async {
    await FlutterBlue.instance.stopScan();
    scanSubScription?.cancel();
    scanSubScription = null;
    print("stop scan");
  }

  connectToDevice() async {
    if (targetDevice == null) return;

    setState(() {
      connectionText = "Device Connecting";
    });

    await targetDevice.connect();
    print('DEVICE CONNECTED');
    setState(() {
      connectionText = "Device Connected";
    });

    discoverServices();
  }

  disconnectFromDevice() {
    print('DEVICE disconnecting');
    if (targetDevice == null) return;

    targetDevice.disconnect();
    stateSubscription.cancel();
    setState(() {
      connectionText = "Device Disconnected";
      targetDevice = null;
    });
    print('DEVICE disconnected');
  }

  discoverServices() async {
    if (targetDevice == null) return;

    List<BluetoothService> services = await targetDevice.discoverServices();
    for (BluetoothService service in services) {
      if (service.uuid.toString() == serviceUUID) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid.toString() == charUUID) {
            targetCharacteristic = characteristic;
            await targetCharacteristic.setNotifyValue(true);
            setState(() {
              connectionText = "Connected to ${targetDevice.name}";
            });
            print("Found Characteristics");
          }
        }
      }
    }
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/data.csv');
  }

  Future<File> writeData(String data) async {
    final file = await _localFile;
    return file.writeAsString('$data\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(connectionText),
      ),
      body: Container(
          child: deviceState == BluetoothDeviceState.disconnected
              ? StreamBuilder(
                  stream: flutterBlue.isScanning,
                  initialData: false,
                  builder: (BuildContext context, snapshot) {
                    return new Center(
                      child: CupertinoButton.filled(
                        onPressed: snapshot.data ? null : () => startScan(),
                        child: Text('Scan', style: TextStyle(fontSize: 20)),
                      ),
                    );
                  })
              : targetCharacteristic == null
                  ? Center(child: CircularProgressIndicator())
                  : StreamBuilder(
                      stream: targetCharacteristic.value,
                      initialData: "",
                      builder: (BuildContext context, snapshot) {
                        if (snapshot.hasData && snapshot.data.length > 0) {
                          String data = new String.fromCharCodes(snapshot.data);
                          writeData(data);
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: <Widget>[
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: <Widget>[
                                    Text(data, style: TextStyle(fontSize: 16)),
                                  ]),
                            ],
                          );
                        }
                        return CircularProgressIndicator();
                      })),
    );
  }
}
