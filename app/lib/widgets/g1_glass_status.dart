import 'dart:async';

import '../services/devices/g1/g1_bluetooth_manager.dart';
import 'package:flutter/material.dart';

class GlassStatus extends StatefulWidget {
  const GlassStatus({super.key});

  @override
  State<GlassStatus> createState() => GlassStatusState();
}

class GlassStatusState extends State<GlassStatus> {
  BluetoothManager bluetoothManager = BluetoothManager();

  bool isConnected = false;
  bool isScanning = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshData();
    });
  }

  @override
  void dispose() {
    if (_refreshTimer != null) {
      _refreshTimer!.cancel();
    }
    super.dispose();
  }

  void _refreshData() {
    setState(() {
      isConnected = bluetoothManager.isConnected;
      isScanning = bluetoothManager.isScanning;
    });
  }

  void _scanAndConnect() {
    try {
      bluetoothManager.startScanAndConnect(
        onUpdate: (_) => _refreshData(),
      );
    } catch (e) {
      debugPrint('Error in _scanAndConnect: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Card(
        color: Colors.black26,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              bluetoothManager.isConnected
                  ? Column(
                      children: [
                        const Text(
                          'Connected to G1 glasses',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () async {
                            // Disconnect and clear state
                            if (bluetoothManager.leftGlass != null) {
                              await bluetoothManager.leftGlass!.device.disconnect();
                              bluetoothManager.leftGlass = null;
                            }
                            if (bluetoothManager.rightGlass != null) {
                              await bluetoothManager.rightGlass!.device.disconnect();
                              bluetoothManager.rightGlass = null;
                            }
                            _refreshData();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Disconnect'),
                        ),
                      ],
                    )
                  : ElevatedButton(
                      onPressed: isScanning ? null : _scanAndConnect,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                      child: isScanning
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(width: 10),
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Scanning for G1 glasses',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            )
                          : const Text(
                              'Connect to G1',
                              style: TextStyle(color: Colors.white),
                            ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
