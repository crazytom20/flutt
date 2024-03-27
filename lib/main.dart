import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:connectivity/connectivity.dart';
import 'package:background_fetch/background_fetch.dart';

void main() {
  BackgroundFetch.configure(BackgroundFetchConfig(
    minimumFetchInterval: 15, // Intervalo mínimo en minutos
    stopOnTerminate: false, // Mantener ejecución después de cerrar la aplicación
    enableHeadless: true, // Permitir ejecución en segundo plano
    startOnBoot: true, // Iniciar automáticamente después del reinicio del dispositivo
  ), (String taskId) async {
    // Función para manejar la ejecución en segundo plano
    await sendDataInBackground();
    BackgroundFetch.finish(taskId);
  });

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BluetoothDeviceList(),
    );
  }
}

class BluetoothDiscoveryResultExtended {
  final BluetoothDiscoveryResult result;
  bool isConnecting;
  bool isConnected;
  BluetoothConnection? connection;
  String receivedData = "";

  BluetoothDiscoveryResultExtended(
      this.result, this.isConnecting, this.isConnected);
}

class BluetoothDeviceList extends StatefulWidget {
  @override
  _BluetoothDeviceListState createState() => _BluetoothDeviceListState();
}

class _BluetoothDeviceListState extends State<BluetoothDeviceList> {
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  Set<String> _deviceAddresses = Set<String>();
  List<BluetoothDiscoveryResultExtended> _devices = [];
  TextEditingController _dataReceived = TextEditingController();
  bool _showOfflineDataButton = false;
  bool _isSendingOfflineData = false;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
    _checkInternetConnection();
  }

  void _startDiscovery() {
    _bluetooth.startDiscovery().listen((device) {
      if (!_deviceAddresses.contains(device.device.address)) {
        setState(() {
          _deviceAddresses.add(device.device.address);
          _devices.add(
              BluetoothDiscoveryResultExtended(device, false, false));
        });
      }
    });
  }

  void _refreshDevices() {
    setState(() {
      _deviceAddresses.clear();
      _devices.clear();
    });
    _startDiscovery();
  }

  Future<void> _connectToDevice(
      BluetoothDiscoveryResultExtended extendedDevice) async {
    final device = extendedDevice.result.device;

    setState(() {
      extendedDevice.isConnecting = true;
    });

    try {
      final connection = await BluetoothConnection.toAddress(device.address);
      setState(() {
        extendedDevice.connection = connection;
        extendedDevice.isConnecting = false;
        extendedDevice.isConnected = true;
        _devices = [_devices.firstWhere((d) => d == extendedDevice)];
      });

      String accumulatedData = '';

      if (connection.input != null) {
        connection.input!.asBroadcastStream().listen((data) {
          String message = String.fromCharCodes(data);
          accumulatedData += message;

          if (accumulatedData.contains('\n')) {
            accumulatedData = accumulatedData.replaceAll('\n', '');
            print(accumulatedData);
            setState(() {
              extendedDevice.receivedData = accumulatedData;
              _dataReceived.text = accumulatedData;
            });

            _sendDataToApi(accumulatedData);

            accumulatedData = '';
          }
        });
      }
    } catch (e) {
      setState(() {
        extendedDevice.isConnecting = false;
      });
      print('Error al conectar: $e');
    }
  }

  Future<void> _sendDataToApi(String data) async {
    final apiUrl =
        'https://identiarbol.org/identiarbolbackend/public/api/datosregister';

    List<String> dataList = data.split('-');
    Position position = await Geolocator.getCurrentPosition();
    String longitude = position.longitude.toString();
    String latitude = position.latitude.toString();
    DateTime now = DateTime.now();
    String dateCreation = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    String dateUpdate = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

    for (int i = 0; i < dataList.length - 1; i++) {
      final currentData = dataList[i];
      final currentDatanodo = dataList[5];

      try {
        print('Enviando dato $currentData a la API...');
        final response = await http.post(
          Uri.parse(apiUrl),
          body: {
            "par_int_id": (i + 1).toString(),
            "dat_txt_value": currentData,
            "dat_txt_longitude": longitude,
            "dat_txt_latitude": latitude,
            "dat_txt_status": "A",
            "dat_txt_datecreation": dateCreation,
            "dat_txt_dateupdate": dateUpdate,
            "nod_int_id": currentDatanodo,
          },
        );

        if (response.statusCode == 200) {
          print('Dato $currentData enviado exitosamente a la API con par_int_id ${(i + 1)}');
        } else {
          print('Error al enviar dato $currentData a la API. Código de estado: ${response.statusCode}');
          await _saveDataToFile(data);
        }
      } catch (e) {
        print('Error al enviar dato $currentData a la API: $e');
        await _saveDataToFile(data);
      }
    }

    _showSnackBar('Datos enviados exitosamente a la API');
    setState(() {
      _isSendingOfflineData = false;
    });
  }

  Future<void> _saveDataToFile(String data) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/offline_data.txt');

      if (!await file.exists()) {
        await file.create();
      }

      await file.writeAsString('$data\n', mode: FileMode.append);

      print('Datos guardados localmente en el archivo.');
    } catch (e) {
      print('Error al guardar datos localmente: $e');
    }
  }

  Future<void> _sendOfflineData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/offline_data.txt');

      if (await file.exists()) {
        final contents = await file.readAsString();

        if (contents.isNotEmpty) {
          setState(() {
            _isSendingOfflineData = true;
          });
          print('Enviando datos almacenados localmente...');
          await _sendDataToApi(contents);
          await file.writeAsString('');
          _showSnackBar('Datos enviados exitosamente a la API');
        }
      }
    } catch (e) {
      print('Error al enviar datos almacenados localmente: $e');
      _showSnackBar('Error al enviar datos almacenados');
    }
  }

  void _showSnackBar(String message) {
    final snackBar = SnackBar(content: Text(message));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  void _checkInternetConnection() async {
    var connectivityResult = await Connectivity().checkConnectivity();

    if (connectivityResult == ConnectivityResult.mobile ||
        connectivityResult == ConnectivityResult.wifi) {
      print('Conexión a Internet disponible.');
      setState(() {
        _showOfflineDataButton = false;
      });
      if (!_isSendingOfflineData) {
        await _sendOfflineData();
      }
    } else {
      print('No hay conexión a Internet.');
      setState(() {
        _showOfflineDataButton = true;
      });
      print('Guardando datos localmente...');
      await _saveDataToFileLocally(_dataReceived.text);
    }
  }

  Future<void> _saveDataToFileLocally(String data) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/offline_data_local.txt');

      if (!await file.exists()) {
        await file.create();
      }

      await file.writeAsString('$data\n', mode: FileMode.append);

      print('Datos guardados localmente en el archivo local.');
    } catch (e) {
      print('Error al guardar datos localmente: $e');
    }
  }

  void _showOfflineData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/offline_data_local.txt');

      if (await file.exists()) {
        final contents = await file.readAsString();

        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Datos almacenados localmente'),
              content: Text(contents),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('Cerrar'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      print('Error al leer datos almacenados localmente: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Monitoreo Ambiental'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshDevices,
          ),
          if (_showOfflineDataButton)
            IconButton(
              icon: Icon(Icons.offline_bolt),
              onPressed: _showOfflineData,
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: EdgeInsets.only(top: 10.0),
            child: Text("Datos recibidos:"),
          ),
          TextFormField(
            controller: _dataReceived,
            readOnly: true,
            maxLines: 1,
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final extendedDevice = _devices[index];
                final device = extendedDevice.result.device;

                return ListTile(
                  title: Text(
                    extendedDevice.isConnected
                        ? '${device.name} - Conectado y preparado para recibir datos'
                        : extendedDevice.isConnecting
                            ? 'Conectando...'
                            : device.name.toString(),
                  ),
                  subtitle: Text(device.address),
                  onTap: () {
                    if (!extendedDevice.isConnected &&
                        !extendedDevice.isConnecting) {
                      _connectToDevice(extendedDevice);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> sendDataInBackground() async {
  // Implementa el código para enviar datos en segundo plano
  // Asegúrate de manejar adecuadamente la conexión Bluetooth y los datos a enviar
}
