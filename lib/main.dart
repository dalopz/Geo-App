import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:io';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'geoApp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 0, 144, 101),
        ),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'GeoApp'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String ubicacion = '...';
  late String latitud;
  late String longitud;
  Timer? _timer;
  bool actualizando = false;
  bool viajeIniciado = false;
  File? _localFile;
  String? _identificadorViaje;
  int puntoConsecutivo = 1;
  String? _nombreUsuario; 
  String? _medioTransporte;

  @override
  void initState() {
    super.initState();
    _initFile();
    WakelockPlus.enable();
    _pedirNombreUsuario();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _initFile() async {
    final directory = await getExternalStorageDirectory();
    _localFile = File('${directory!.path}/ubicaciones.txt');

    if (!await _localFile!.exists()) {
      await _localFile!.create();
      await _localFile!.writeAsString('id viaje, id punto, latitud, longitud, fecha, hora, usuario, medio de transporte\n');
    }
  }

  Future<void> _pedirNombreUsuario() async {
    if (_nombreUsuario == null) {
      TextEditingController usuarioController = TextEditingController();

      final result = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Información del usuario'),
            content: TextField(
              controller: usuarioController,
              decoration: const InputDecoration(labelText: 'Nombre de usuario'),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  if (usuarioController.text.isNotEmpty) {
                    setState(() {
                      _nombreUsuario = usuarioController.text;
                    });
                    Navigator.of(context).pop('success');
                  }
                },
                child: const Text('Aceptar'),
              ),
            ],
          );
        },
      );
    }
  }

Future<void> _pedirDatosViaje() async {

  String? medioTransporteSeleccionado = _medioTransporte;

  final result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Información de la ruta'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  hint: const Text('Medio de transporte'),
                  value: medioTransporteSeleccionado, 
                  onChanged: (String? newValue) {
                    setState(() {
                      medioTransporteSeleccionado = newValue; 
                    });
                  },
                  items: <String>['Ruta empresarial', 'Carro', 'Moto', 'Caminata']
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); 
            },
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              if (medioTransporteSeleccionado != null) {
                _medioTransporte = medioTransporteSeleccionado;
                Navigator.of(context).pop('success');
              }
            },
            child: const Text('Aceptar'),
          ),
        ],
      );
    },
  );

  if (result == 'success') {
    iniciarViaje();
  }
}




void iniciarViaje() {
  if (_medioTransporte == null) {
    return;
  }

  setState(() {
    viajeIniciado = true;
    _identificadorViaje = DateTime.now().millisecondsSinceEpoch.toString();
    puntoConsecutivo = 1;
  });

  int segundosIntervalo;
  switch (_medioTransporte) {
    case 'Caminata':
      segundosIntervalo = 5;
      break;
    case 'Carro':
    case 'Moto':
    case 'Ruta empresarial':
      segundosIntervalo = 10;
      break;
    default:
      segundosIntervalo = 10;
      break;
  }

  _timer = Timer.periodic(Duration(seconds: segundosIntervalo), (timer) {
    obtenerUbicacionPeriodica();
  });

  obtenerUbicacionPeriodica();
}

  void detenerViaje() {
    setState(() {
      viajeIniciado = false;
    });
    _timer?.cancel();
  }

  Future<void> obtenerUbicacionPeriodica() async {
    if (!viajeIniciado) return;

    setState(() {
      actualizando = true;
    });

    try {
      Position position = await getUbicacionActual();
      latitud = position.latitude.toString();
      longitud = position.longitude.toString();

      setState(() {
        ubicacion = '$latitud,$longitud';
      });

      print(ubicacion);
      await _guardarUbicacion(ubicacion);
      puntoConsecutivo++;
    } catch (e) {
      print('Error al obtener ubicación: $e');
    }

    setState(() {
      actualizando = false;
    });
  }

  Future<Position> getUbicacionActual() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Servicio de ubicación desactivado');
    }

    LocationPermission permisoDeUbicacion = await Geolocator.checkPermission();
    if (permisoDeUbicacion == LocationPermission.denied) {
      permisoDeUbicacion = await Geolocator.requestPermission();
      if (permisoDeUbicacion == LocationPermission.deniedForever) {
        return Future.error('Permiso de ubicación denegado permanentemente');
      }

      if (permisoDeUbicacion == LocationPermission.denied) {
        return Future.error('Permiso de ubicación denegado');
      }
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> _guardarUbicacion(String ubicacion) async {
    try {
      if (_localFile != null && _identificadorViaje != null) {
        String fecha = DateFormat('yyyy-MM-dd').format(DateTime.now());
        String hora = DateFormat('HH:mm:ss').format(DateTime.now());
        await _localFile!.writeAsString(
            '$_identificadorViaje, $puntoConsecutivo, $ubicacion, $fecha, $hora, $_nombreUsuario, $_medioTransporte\n',
            mode: FileMode.append);
      }
    } catch (e) {
      print('Error al guardar la ubicación: $e');
    }
  }

  Future<void> _leerUbicaciones() async {
    try {
      if (_localFile != null && await _localFile!.exists()) {
        String contenido = await _localFile!.readAsString();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Contenido del archivo'),
            content: SingleChildScrollView(
              child: Text(contenido),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cerrar'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      } else {
        print('El archivo no existe');
      }
    } catch (e) {
      print('Error al leer el archivo: $e');
    }
  }

  Future<void> _compartirArchivo() async {
    if (_localFile != null && await _localFile!.exists()) {
      try {
        final XFile xfile = XFile(_localFile!.path);
        await Share.shareXFiles([xfile], text: 'Envio archivo de ubicaciones');
      } catch (e) {
        print('Error al compartir el archivo: $e');
      }
    } else {
      print('No se encontró el archivo para compartir');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('${widget.title} - Bienvenido, $_nombreUsuario'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Ubicación actual:',
            ),
            Text(
              ubicacion,
              style: const TextStyle(fontSize: 10),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: viajeIniciado ? null : () => _pedirDatosViaje(),
              child: const Text('Iniciar viaje'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: viajeIniciado ? () => detenerViaje() : null,
              child: const Text('Detener viaje'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: viajeIniciado ? null : () => _leerUbicaciones(),
              child: const Text('Leer ubicaciones guardadas'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _compartirArchivo(),
              child: const Text('Compartir archivo'),
            ),
          ],
        ),
      ),
    );
  }
}
