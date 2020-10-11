import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
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

  StreamController<int> counterController;
  StreamController<Map> uploadController;
  String connectionText = "Elephant Edge";
  String cls;
  int counter;
  Timer timer;
  List sensorValues = new List();
  bool recording = false;

  @override
  void initState() {
    super.initState();
    deviceState = BluetoothDeviceState.disconnected;
    counterController = new BehaviorSubject<int>.seeded(30);
    uploadController =
        new BehaviorSubject<Map>.seeded({'file': '', 'value': 0.0});
  }

  void startTimer(BuildContext context) {
    counter = 30;
    counterController.add(counter);
    if (timer != null) {
      timer.cancel();
    }
    recording = true;
    timer = Timer.periodic(Duration(seconds: 1), (timer) {
      (counter > 0) ? counter-- : stopTimer(true);
      counterController.add(counter);
    });
  }

  void stopTimer(bool save) {
    timer.cancel();
    recording = false;
    Navigator.of(context).pop();
    if (save) {
      saveToFile();
    }
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
              if (recording) {
                sensorValues.add(new String.fromCharCodes(data));
                print('append data');
              }
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

  Future<File> saveToFile() async {
    final path = await _localPath;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('$path/$cls.$timestamp.csv');
    String data = sensorValues.join('\n');
    sensorValues.clear();
    return file.writeAsString(data);
  }

  void recordingDialog(BuildContext context) {
    startTimer(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text('$cls', style: TextStyle(fontSize: 26)),
          content: StreamBuilder<int>(
              stream: counterController.stream,
              builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
                return SingleChildScrollView(
                    child: ListBody(
                  children: <Widget>[
                    Text('00:${snapshot.data.toString().padLeft(2, '0')}',
                        style: TextStyle(fontSize: 22)),
                  ],
                ));
              }),
          actions: <Widget>[
            CupertinoDialogAction(
              child: Text('Cancel'),
              onPressed: () {
                stopTimer(false);
              },
            ),
            CupertinoDialogAction(
              child: Text('Stop'),
              onPressed: () {
                stopTimer(true);
              },
            ),
          ],
        );
      },
    );
  }

  void uploadingDialog(BuildContext context) {
    startUpload();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text('Upload to Edge Impulse', style: TextStyle(fontSize: 20)),
          content: StreamBuilder<Map>(
              stream: uploadController.stream,
              builder: (BuildContext context, AsyncSnapshot<Map> snapshot) {
                if (snapshot.data != null) {
                  return SingleChildScrollView(
                      child: ListBody(
                    children: <Widget>[
                      LinearProgressIndicator(value: snapshot.data['value']),
                      Text(snapshot.data['file'],
                          style: TextStyle(fontSize: 16)),
                    ],
                  ));
                } else {
                  return CircularProgressIndicator();
                }
              }),
        );
      },
    );
  }

  startUpload() async {
    final path = await _localPath;
    var files = Directory(path)
        .listSync()
        .where((file) => file.path.endsWith('.csv'))
        .toList();

    int count = files.length;

    try {
      for (var i = 0; i < count; i++) {
        // Read the file.
        var filename = p.basename(files[i].path);
        print(filename);
        String contents = await File(files[i].path).readAsString();
        print(contents);
        if (contents.length > 0) {
          var values = contents
              .split('\n')
              .map((line) =>
                  line.split(',').map((str) => double.parse(str)).toList())
              .toList();
          print(values);
          uploadController.add({'file': filename, 'value': i / count});
          //await Future.delayed(const Duration(seconds: 5), () {});
          uploadToEdgeImpulse(filename, values);
        }
      }
    } catch (e) {
      print(e.toString());
      return 0;
    }

    Navigator.of(context).pop();
  }

  uploadToEdgeImpulse(filename, values) async {
    final hmacKey = '1fd9c37d114b9cb9ae658905e2f5888d';
    final apiKey =
        'ei_0244e827c85da58ff46cc06ac7d5159d1dc9431d8cafc51be687d3d4e8205928';

    var data = {
      'protected': {
        'ver': 'v1',
        'alg': 'HS256',
        'iat': (DateTime.now().millisecondsSinceEpoch / 1000).floor()
      },
      'signature': '0' * 64,
      'payload': {
        'device_name': '8F:27:A2:90:30:76',
        'device_type': 'ARDUINO_NANO33BLE',
        'interval_ms': 100,
        'sensors': [
          {'name': 'accX', 'units': 'm/s2'},
          {'name': 'accY', 'units': 'm/s2'},
          {'name': 'accZ', 'units': 'm/s2'},
          {'name': 'gyrX', 'units': 'dps'},
          {'name': 'gyrY', 'units': 'dps'},
          {'name': 'gyrZ', 'units': 'dps'},
          {'name': 'magX', 'units': 'uT'},
          {'name': 'magY', 'units': 'uT'},
          {'name': 'magZ', 'units': 'uT'},
        ],
        'values': values
      }
    };

    var encoded = jsonEncode(data);
    var hmac = new Hmac(sha256, utf8.encode(hmacKey)); // HMAC-SHA256
    data['signature'] = hmac.convert(utf8.encode(encoded)).toString();

    encoded = jsonEncode(data);
    print(encoded);

    final String url = 'https://ingestion.edgeimpulse.com/api/training/data';

    try {
      final httpClient = HttpClient();
      final request = await httpClient.postUrl(Uri.parse(url));
      request.headers.add('x-api-key', apiKey);
      request.headers.add('x-file-name', filename);
      request.headers.add('content-type', 'application/json');
      request.add(utf8.encode(encoded));

      //request.headers.contentType = new ContentType("application", "json");
      final response = await request.close();
      if (response.statusCode == 200) {
        print("Uploaded successfully.");
      } else {
        print("Failed to upload.");
        print(response);
      }
    } on TimeoutException catch (_) {
      //print
    } on SocketException catch (_) {
      //print
    }
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
        textStyle: TextStyle(fontSize: 26, color: Colors.black),
        borderWidth: 3,
        onPressed: (dynamic val) {
          if (labels.values.contains(val)) {
            cls = val.toString().split('.')[1];
            recordingDialog(context);
          }
        },
        items: [
          [
            GridButtonItem(
                title: 'Walking',
                color: Colors.blueAccent,
                longPressValue: labels.Walking),
            GridButtonItem(
                title: 'Running',
                color: Colors.deepOrangeAccent,
                longPressValue: labels.Running),
          ],
          [
            GridButtonItem(
                title: 'Resting',
                color: Colors.yellowAccent,
                longPressValue: labels.Resting),
            GridButtonItem(
                title: 'Playing',
                color: Colors.pinkAccent,
                longPressValue: labels.Playing),
          ],
          [
            GridButtonItem(
                title: 'Climbing',
                color: Colors.green,
                longPressValue: labels.Climbing),
            GridButtonItem(
                title: 'Descending',
                color: Colors.deepPurpleAccent,
                longPressValue: labels.Descending),
          ]
        ]);

    return Scaffold(
        appBar: AppBar(
          title: Text(connectionText),
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.upload_file),
              onPressed: () {
                uploadingDialog(context);
              },
            ),
          ],
        ),
        body: Container(
            child: deviceState == BluetoothDeviceState.disconnected
                ? scanButton
                : gridButton));
  }
}
