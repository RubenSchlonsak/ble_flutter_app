import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// Define Service and Characteristic UUIDs
const String SERVICE_UUID = "12345678-1234-1234-1234-123456789012";
const String CHARACTERISTIC_UUID = "abcdef12-3456-789a-bcde-123456789abc";

void main() {
  runApp(const BLEDemoApp());
}

class BLEDemoApp extends StatelessWidget {
  const BLEDemoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // MaterialApp is the root of your application.
    return MaterialApp(
      title: 'BLE Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const BLEHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BLEHomePage extends StatefulWidget {
  const BLEHomePage({Key? key}) : super(key: key);

  @override
  _BLEHomePageState createState() => _BLEHomePageState();
}

class _BLEHomePageState extends State<BLEHomePage> {
  final List<ScanResult> _scanResults = [];
  bool _isScanning = false;


  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  // Check and request necessary permissions
  Future<void> _checkPermissions() async {
    // Define the permissions you need
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetooth,
      Permission.location,
    ].request();

    // Check if all permissions are granted
    bool allGranted =
    statuses.values.every((status) => status.isGranted || status.isLimited);

    if (allGranted) {
      _startScan();
    } else {
      // Show a dialog informing the user that permissions are required
      _showPermissionsDeniedDialog();
    }
  }

  // Show dialog when permissions are denied
  void _showPermissionsDeniedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permissions Required'),
          content: const Text(
              'Bluetooth and Location permissions are required to use this app. Please grant them in the app settings.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Optionally, exit the app or disable functionality
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  // Start scanning for BLE devices
  void _startScan() {
    setState(() {
      _scanResults.clear();
      _isScanning = true;
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5)).catchError((e) {
      // Handle scan errors here
      setState(() {
        _isScanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e')),
      );
    });

    // Listen to scan results
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults.clear();
        _scanResults.addAll(results);
      });
    });

    // Stop scanning after the timeout
    FlutterBluePlus.isScanning.listen((isScanning) {
      if (!isScanning) {
        setState(() {
          _isScanning = false;
        });
      }
    });
  }

  // Stop scanning for BLE devices
  void _stopScan() {
    FlutterBluePlus.stopScan();
    setState(() {
      _isScanning = false;
    });
  }

  // Connect to a selected BLE device
  void _connectToDevice(BluetoothDevice device) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          title: Text('Connecting'),
          content: SizedBox(
            height: 100,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
      },
    );

    try {
      await device.connect();
      Navigator.of(context).pop(); // Close the connecting dialog

      // Navigate to the device screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DeviceScreen(device: device),
        ),
      );
    } catch (e) {
      Navigator.of(context).pop(); // Close the connecting dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: $e')),
      );
    }
  }

  // Build the list of scanned devices
  Widget _buildDeviceList() {
    return ListView.separated(
      itemCount: _scanResults.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final result = _scanResults[index];
        final device = result.device;
        final deviceName =
        device.name.isNotEmpty ? device.name : 'Unknown Device';

        return ListTile(
          leading: const Icon(Icons.bluetooth, color: Colors.blue),
          title: Text(deviceName),
          subtitle: Text(device.id.id),
          trailing: ElevatedButton(
            onPressed: () => _connectToDevice(device),
            child: const Text('Connect'),
          ),
        );
      },
    );
  }

  // Build the main UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Demo'),
        actions: [
          _isScanning
              ? IconButton(
            icon: const Icon(Icons.stop),
            onPressed: _stopScan,
          )
              : IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _startScan,
          ),
        ],
      ),
      body: _scanResults.isEmpty
          ? Center(
        child: _isScanning
            ? const CircularProgressIndicator()
            : const Text('No Devices Found'),
      )
          : _buildDeviceList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? _stopScan : _startScan,
        child: Icon(_isScanning ? Icons.stop : Icons.search),
      ),
    );
  }
}

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceScreen({Key? key, required this.device}) : super(key: key);

  @override
  _DeviceScreenState createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  List<BluetoothService> _services = [];
  bool _isDiscovering = false;
  final List<String> _receivedMessages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  BluetoothCharacteristic? _targetCharacteristic;

  @override
  void initState() {
    super.initState();
    _discoverServices();
  }

  // Discover services of the connected device
  Future<void> _discoverServices() async {
    setState(() {
      _isDiscovering = true;
    });

    try {
      _services = await widget.device.discoverServices();
      setState(() {
        _isDiscovering = false;
      });

      _addReceivedMessage("Discovered ${_services.length} services.");

      // Locate the desired service and characteristic
      _locateServiceAndCharacteristic();
    } catch (e) {
      setState(() {
        _isDiscovering = false;
      });
      _addReceivedMessage("Error discovering services: $e");
    }
  }

  // Locate the service and characteristic using the defined UUIDs
  void _locateServiceAndCharacteristic() {
    for (var service in _services) {
      if (service.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase()) {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString().toLowerCase() ==
              CHARACTERISTIC_UUID.toLowerCase()) {
            _targetCharacteristic = characteristic;
            _addReceivedMessage("Located Target Characteristic.");
            _setupCharacteristicNotifications();
            break;
          }
        }
      }
    }

    if (_targetCharacteristic == null) {
      _addReceivedMessage("Target Service or Characteristic not found.");
    }
  }

  // Set up notifications for the characteristic
  void _setupCharacteristicNotifications() async {
    if (_targetCharacteristic == null) return;

    try {
      await _targetCharacteristic!.setNotifyValue(true);
      _targetCharacteristic!.value.listen((value) {
        String received = _convertToString(value);
        _addReceivedMessage("Received: $received");
      });
      _addReceivedMessage("Subscribed to Characteristic Notifications.");
    } catch (e) {
      _addReceivedMessage("Error setting up notifications: $e");
    }
  }

  // Convert byte list to string
  String _convertToString(List<int> bytes) {
    try {
      return String.fromCharCodes(bytes);
    } catch (e) {
      return "Error decoding bytes";
    }
  }

  // Add a received message
  void _addReceivedMessage(String message) {
    setState(() {
      _receivedMessages.add(message);
    });

    // Schedule the scroll after the frame is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Send a message by writing to the characteristic
  void _sendMessage(String text) async {
    if (text.isEmpty || _targetCharacteristic == null) return;

    try {
      // Convert string to bytes
      List<int> bytes = text.codeUnits;

      await _targetCharacteristic!.write(bytes, withoutResponse: false);
      _addReceivedMessage("Sent: $text");
    } catch (e) {
      _addReceivedMessage("Error sending message: $e");
    }
  }

  // Disconnect from the device
  void _disconnect() {
    widget.device.disconnect();
    Navigator.of(context).pop();
  }

  // Build the data interface
  Widget _buildDataInterface() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8.0),
            itemCount: _receivedMessages.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(_receivedMessages[index]),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Enter message',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(20.0)),
                    ),
                  ),
                  onSubmitted: (text) {
                    _sendMessage(text);
                    _controller.clear();
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () {
                  String text = _controller.text;
                  _sendMessage(text);
                  _controller.clear();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Build the device screen UI
  @override
  Widget build(BuildContext context) {
    final deviceName =
    widget.device.name.isNotEmpty ? widget.device.name : widget.device.id.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(deviceName),
        actions: [
          IconButton(
            icon: const Icon(Icons.link_off),
            onPressed: _disconnect,
            tooltip: 'Disconnect',
          ),
        ],
      ),
      body: _isDiscovering
          ? const Center(child: CircularProgressIndicator())
          : _buildDataInterface(),
      // Uncomment the following line to display services list instead of data interface
      // body: _isDiscovering ? Center(child: CircularProgressIndicator()) : _buildServicesList(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _controller.dispose();
    widget.device.disconnect();
    super.dispose();
  }
}
