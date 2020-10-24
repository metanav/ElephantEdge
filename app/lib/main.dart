import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_grid_button/flutter_grid_button.dart';
import 'package:flutter_compass/flutter_compass.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
      .then((value) => runApp(ElephantEdgeApp()));
}

enum Activity { Walking, Running, Resting, Standing }
enum Orientation { Up, Left, Right }

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
  String clsActivity;
  String clsOrientation;
  int counter;
  Timer timer;
  List sensorValues = new List();
  List directions = new List();
  String direction = '';
  bool recording = false;

  @override
  void initState() {
    super.initState();
    deviceState = BluetoothDeviceState.disconnected;
    counterController = new BehaviorSubject<int>.seeded(30);
    uploadController =
        new BehaviorSubject<Map>.seeded({'file': '', 'value': 0.0});

    FlutterCompass.events.listen((compass) {
      if (recording) {
        direction = getDirection(compass);
        directions.add(direction);
      }
    });
  }

  String getDirection(CompassEvent compass) {
    String direction;
    if ((compass.heading >= 0 && compass.heading < 45) ||
        (compass.heading >= 315 && compass.heading <= 360)) {
      direction = 'North';
    } else if (compass.heading >= 45 && compass.heading < 135) {
      direction = 'South';
    } else if (compass.heading >= 135 && compass.heading < 225) {
      direction = 'East';
    } else if (compass.heading >= 225 && compass.heading < 315) {
      direction = 'West';
    }
    return direction;
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
    } else {
      sensorValues.clear();
      direction = '';
      directions.clear();
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
            });
            await targetCharacteristic.setNotifyValue(true);

            targetCharacteristic.value.listen((data) {
              if (recording) {
                sensorValues.add(new String.fromCharCodes(data));
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

  String calculateHeading() {
    if (directions.length == 0) {
      throw new Exception('Direction not captured');
    }

    var heading = {'North': 0, 'South': 0, 'East': 0, 'West': 0};

    directions.forEach((direction) {
      heading[direction]++;
    });

    var maxValue = 0;
    var maxValueKey;
    var sum = 0;

    heading.forEach((key, value) {
      if (value > maxValue) {
        maxValue = value;
        maxValueKey = key;
      }
      sum += value;
    });

    if (maxValueKey == null) {
      throw new Exception('Direction not captured');
    }

    var perMaxValue = maxValue * 100 / sum;
    if (perMaxValue < 95) {
      throw new Exception('Direction is not consistent');
    }

    return maxValueKey;
  }

  void saveToFile() async {
    final path = await _localPath;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    try {
      final clsHeading = calculateHeading();
      final label = '${clsActivity}_${clsOrientation}_$clsHeading';
      final file = File('$path/$label.$timestamp.csv');
      file.writeAsString(sensorValues.join('\n'));
    } catch (e) {
      fileNotSavedDialog();
    }

    sensorValues.clear();
    direction = '';
    directions.clear();
  }

  Future<void> fileNotSavedDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text('Save Error'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                    'Inconsistent direction: data will not be saved, please try again.',
                    style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
          actions: <Widget>[
            CupertinoDialogAction(
              child: Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void recordingDialog(BuildContext context) {
    startTimer(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text('$clsActivity', style: TextStyle(fontSize: 26)),
          content: StreamBuilder<int>(
              stream: counterController.stream,
              builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
                return SingleChildScrollView(
                    child: ListBody(
                  children: <Widget>[
                    Text('Direction: $direction',
                        style: TextStyle(fontSize: 22)),
                    Text('Orientation: $clsOrientation',
                        style: TextStyle(fontSize: 22)),
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

  void uploadingDialog(BuildContext context, String datasetType) {
    startUpload(datasetType);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title:
              Text('Uploading to Edge Impulse', style: TextStyle(fontSize: 20)),
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

  startUpload(String datasetType) async {
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
          final endpoint =
              'https://ingestion.edgeimpulse.com/api/$datasetType/data';
          uploadToEdgeImpulse(endpoint, filename, values);
        }
      }
    } catch (e) {
      print(e.toString());
      return 0;
    }

    await Future.delayed(Duration(seconds: 5), () {
      Navigator.of(context).pop();
    });
  }

  uploadToEdgeImpulse(endpoint, filename, values) async {
    final hmacKey = '1dbddc4c372fb95c3845481afaf53026';
    final apiKey =
        'ei_a3718f368123649639fc29db6f0067a9a3aa66119bb8914e1db47338ce1c7ca5';

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
          {'name': 'pressure', 'units': 'kPa'},
        ],
        'values': values
      }
    };

    var encoded = jsonEncode(data);
    var hmac = new Hmac(sha256, utf8.encode(hmacKey)); // HMAC-SHA256
    data['signature'] = hmac.convert(utf8.encode(encoded)).toString();

    encoded = jsonEncode(data);
    print(encoded);

    try {
      final httpClient = HttpClient();
      final request = await httpClient.postUrl(Uri.parse(endpoint));
      request.headers.add('x-api-key', apiKey);
      request.headers.add('x-file-name', filename);
      request.headers.add('content-type', 'application/json');
      request.add(utf8.encode(encoded));

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

  Future<Orientation> getOrientation() async {
    return showCupertinoModalPopup<Orientation>(
      context: context,
      builder: (BuildContext context) {
        return CupertinoActionSheet(
          title: Text(
            'Collar Orientation',
            style: TextStyle(fontSize: 18.0),
          ),
          actions: <Widget>[
            CupertinoActionSheetAction(
              child: Text('Up'),
              onPressed: () {
                Navigator.of(context).pop(Orientation.Up);
              },
            ),
            CupertinoActionSheetAction(
              child: Text('Left'),
              onPressed: () {
                Navigator.of(context).pop(Orientation.Left);
              },
            ),
            CupertinoActionSheetAction(
              child: Text('Right'),
              onPressed: () {
                Navigator.of(context).pop(Orientation.Right);
              },
            )
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            child: Text('Cancel'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
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
        textStyle: TextStyle(fontSize: 24, color: Colors.black),
        borderWidth: 3,
        onPressed: (dynamic valActivity) async {
          if (Activity.values.contains(valActivity)) {
            clsActivity = valActivity.toString().split('.')[1];
            var valOrientation = await getOrientation();
            if (Orientation.values.contains(valOrientation)) {
              clsOrientation = valOrientation.toString().split('.')[1];
              print(clsOrientation);
              final CompassEvent compass = await FlutterCompass.events.first;
              direction = getDirection(compass);
              directions.add(direction);
              recordingDialog(context);
            }
          }
        },
        items: [
          [
            GridButtonItem(
                title: 'Walking',
                color: Colors.blueAccent,
                longPressValue: Activity.Walking),
            GridButtonItem(
                title: 'Running',
                color: Colors.deepOrangeAccent,
                longPressValue: Activity.Running),
          ],
          [
            GridButtonItem(
                title: 'Resting',
                color: Colors.yellowAccent,
                longPressValue: Activity.Resting),
            GridButtonItem(
                title: 'Standing',
                color: Colors.pinkAccent,
                longPressValue: Activity.Standing),
          ]
        ]);

    return Scaffold(
        appBar: AppBar(title: Text(connectionText)),
        body: Container(
            child: deviceState == BluetoothDeviceState.disconnected
                ? scanButton
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 96.0),
                    child: gridButton)),
        drawer: Drawer(
            child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            DrawerHeader(
              child: Text('Upload data to Edge Impulse',
                  style: TextStyle(fontSize: 26)),
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
            ),
            ListTile(
              title:
                  Text('Upload Training Data', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.pop(context);
                uploadingDialog(context, 'training');
              },
            ),
            ListTile(
              title:
                  Text('Upload Testing Data', style: TextStyle(fontSize: 18)),
              onTap: () {
                uploadingDialog(context, 'testing');
                Navigator.pop(context);
              },
            )
          ],
        )));
  }
}
