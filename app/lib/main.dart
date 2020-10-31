import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
      .then((value) => runApp(ElephantEdgeApp()));
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
  List sensorValues = new List();
  final List<double> values = [];

  @override
  void initState() {
    super.initState();
    deviceState = BluetoothDeviceState.disconnected;
  }

  void startScan() {
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
  }

  connectToDevice() async {
    if (targetDevice == null) return;

    setState(() {
      connectionText = "Device Connecting";
    });

    await targetDevice.connect();
    setState(() {
      connectionText = "Device Connected";
    });

    discoverServices();
  }

  disconnectFromDevice() {
    if (targetDevice == null) return;

    targetDevice.disconnect();
    stateSubscription.cancel();
    setState(() {
      connectionText = "Device Disconnected";
      targetDevice = null;
    });
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
            setState(() {
              connectionText = "Connected to ${targetDevice.name}";
              print("here");
            });
            await targetCharacteristic.setNotifyValue(true);

            // targetCharacteristic.value.listen((data) {
            //   sensorValues.add(new String.fromCharCodes(data));
            // });
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text(connectionText)),
        body: Container(
            child: deviceState == BluetoothDeviceState.disconnected
                ? StreamBuilder(
                    stream: flutterBlue.isScanning,
                    initialData: false,
                    builder: (BuildContext context, snapshot) {
                      return CupertinoTheme(
                          data: CupertinoThemeData(
                              primaryColor: Colors.pink,
                              primaryContrastingColor: Colors.white),
                          child: Center(
                            child: CupertinoButton.filled(
                              onPressed:
                                  snapshot.data ? null : () => startScan(),
                              child:
                                  Text('Scan', style: TextStyle(fontSize: 20)),
                            ),
                          ));
                    })
                : targetCharacteristic == null
                    ? Center(child: CupertinoActivityIndicator())
                    : StreamBuilder<List<int>>(
                        stream: targetCharacteristic.value,
                        initialData: [],
                        builder: (BuildContext context, snapshot) {
                          if (snapshot != null && snapshot.data.length > 0) {
                            print(snapshot.data);
                            try {
                              var payload = jsonDecode(
                                  new String.fromCharCodes(snapshot.data));

                              if (payload['status'] == 'result') {
                                final Map<String, dynamic> pred =
                                    new Map<String, dynamic>.from(
                                        payload['pred']);

                                var sortedKeys = pred.keys.toList(
                                    growable: false)
                                  ..sort(
                                      (k1, k2) => pred[k2].compareTo(pred[k1]));
                                var sortedPred = new LinkedHashMap.fromIterable(
                                    sortedKeys,
                                    key: (k) => k,
                                    value: (k) => pred[k]);
                                List<Widget> widgets = [];
                                var i = 0;
                                sortedPred.forEach((k, v) {
                                  i++;
                                  widgets.add(ListTile(
                                      selected: i == 1,
                                      title: Text(
                                          '${k[0].toUpperCase()}${k.substring(1)}',
                                          style: TextStyle(
                                              fontSize: 24,
                                              color: Colors.white)),
                                      trailing: Text('$v',
                                          style: TextStyle(fontSize: 24))));
                                });

                                return ListTileTheme(
                                    selectedTileColor: Colors.pink,
                                    child: ListView(children: widgets));
                              } else {
                                return Center(
                                    child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                      Text('Loading',
                                          style: TextStyle(fontSize: 30)),
                                      SizedBox(height: 10),
                                      CupertinoActivityIndicator(radius: 30.0)
                                    ]));
                              }
                            } catch (e) {
                              return Text("");
                            }
                          } else {
                            return CupertinoActivityIndicator(radius: 20.0);
                          }
                        })));
  }
}
