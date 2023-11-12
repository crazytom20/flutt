import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart'; 
import 'package:intl/intl.dart';


void main() => runApp(MyApp());

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
  List<BluetoothDiscoveryResultExtended> _devices = [];
  TextEditingController _dataReceived = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  void _startDiscovery() {
    _bluetooth.startDiscovery().listen((device) {
      setState(() {
        _devices.add(
            BluetoothDiscoveryResultExtended(device, false, false));
      });
    });
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

            // Enviar datos a la API
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
  final apiUrl = 'http://108.181.166.127/identiarbol/identiarbolbackend/public/api/datosregister';

  List<String> dataList = data.split('-');
  // Obtener ubicación
    Position position = await Geolocator.getCurrentPosition();
    String longitude = position.longitude.toString();
    String latitude = position.latitude.toString();

// Obtener fechas
DateTime now = DateTime.now();
String dateCreation = DateFormat.yMd().add_Hms().format(now);
String dateUpdate = DateFormat.yMd().add_Hms().format(now);
String dateDelete = DateFormat.yMd().add_Hms().format(now);

  for (int i = 0; i < dataList.length; i++) {
    final currentData = dataList[i];

    try {
      final response = await http.post(
        Uri.parse(apiUrl),

        body:{

            "par_int_id": (i + 1).toString(),
            "dat_txt_value": currentData,
            "dat_txt_longitude": longitude,
            "dat_txt_latitude": latitude,
            "dat_txt_status": "A",
            "nod_txt_code": "DATA",
            "dat_txt_datecreation": dateCreation,
            "dat_txt_dateupdate": dateUpdate,
            "dat_txt_datedelete": dateDelete,
        },
      );

      if (response.statusCode == 200) {
        print('Dato $currentData enviado exitosamente a la API con par_int_id ${(i + 1)}');
       
      } else {
        print('Error al enviar dato $currentData a la API. Código de estado: ${response.statusCode}');
       
      }
    } catch (e) {
      print('Error al enviar dato $currentData a la API: $e');
     
    }
  }
}

void _updateDataStatus(int index, String status) {
  if (index >= 0 && index < _devices.length) {
    setState(() {
      _devices[index].receivedData = status;
      _dataReceived.text = status;
    });
  }
}



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth Devices'),
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