import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_grid_button/flutter_grid_button.dart';

main() => runApp(ElephantEdgeApp());

enum labels { Resting, Walking, Running, Playing, Climbing, Descending }

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
  String cls;
  int counter;
  Timer timer;
  StreamController<int> counterStream;

  @override
  void initState() {
    super.initState();
    deviceState = BluetoothDeviceState.disconnected;
    counterStream = new BehaviorSubject<int>.seeded(30);
  }

  void startTimer(BuildContext context) {
    counter = 30;
    counterStream.add(counter);
    if (timer != null) {
      timer.cancel();
    }
    timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (counter > 0) {
        counter--;
      } else {
        timer.cancel();
        Navigator.of(context).pop();
      }
      counterStream.add(counter);
    });
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
            setState(() {
              connectionText = "Connected to ${targetDevice.name}";
            });
            print("Found Characteristics");
            await targetCharacteristic.setNotifyValue(true);
            targetCharacteristic.value.listen((data) {
              String str = new String.fromCharCodes(data);
              print('$cls: $str\n');
            });
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

  void recordingDialog(BuildContext context) {
    startTimer(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('$cls'),
          content: StreamBuilder<int>(
              stream: counterStream.stream,
              builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
                return SingleChildScrollView(
                    child: ListBody(
                  children: <Widget>[
                    Text('00:${snapshot.data.toString().padLeft(2, '0')}'),
                  ],
                ));
              }),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Stop'),
              onPressed: () {
                timer.cancel();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget scanButton = StreamBuilder(
        stream: flutterBlue.isScanning,
        initialData: false,
        builder: (BuildContext context, snapshot) {
          return new Center(
            child: CupertinoButton.filled(
              onPressed: snapshot.data ? null : () => startScan(),
              child: Text('Scan', style: TextStyle(fontSize: 20)),
            ),
          );
        });
    Widget gridButton = GridButton(
        textStyle: TextStyle(fontSize: 26),
        borderWidth: 3,
        onPressed: (dynamic val) {
          if (labels.values.contains(val)) {
            cls = val.toString().split('.')[1];
            recordingDialog(context);
          }
        },
        items: [
          [
            GridButtonItem(title: 'Walking', longPressValue: labels.Walking),
            GridButtonItem(title: 'Running', longPressValue: labels.Running),
          ],
          [
            GridButtonItem(title: 'Resting', longPressValue: labels.Resting),
            GridButtonItem(title: 'Playing', longPressValue: labels.Playing),
          ],
          [
            GridButtonItem(title: 'Climbing', longPressValue: labels.Climbing),
            GridButtonItem(
                title: 'Descending', longPressValue: labels.Descending),
          ]
        ]);

    return Scaffold(
        appBar: AppBar(
          title: Text(connectionText),
        ),
        body: Container(
            child: deviceState != BluetoothDeviceState.disconnected
                ? scanButton
                : gridButton));
  }
}
