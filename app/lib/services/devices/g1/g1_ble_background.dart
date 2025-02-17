import 'dart:async';
import 'dart:developer';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'g1_bluetooth_manager.dart';

@pragma('vm:entry-point')
Future<void> g1BleBackgroundHandler(RemoteMessage message) async {
  final BluetoothManager managerInBg = BluetoothManager();
  var data = message.data;

  await managerInBg.initialize();
  await managerInBg.attemptReconnectFromStorage();

  if (data['text'] != null) {
    await managerInBg.display(data['text']);
  }
  log('G1 BLE background handler: messageId=${message.messageId}');
}