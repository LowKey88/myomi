import 'dart:io';

import 'package:android_package_manager/android_package_manager.dart';
import '/models/g1/bmp.dart';
import '/models/g1/commands.dart';
import '/models/g1/crc.dart';
import '/models/g1/dashboard.dart';
import '/models/g1/setup.dart';
import '/services/dashboard_controller.dart';
import '/models/g1/note.dart';
import '/models/g1/notification.dart';
import 'g1_notifications_listener.dart';
import '/utils/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/models/g1/text.dart';

import 'dart:async';
import 'dart:convert';
import '../../../utils/constants.dart';
import '../../../models/g1/glass.dart';

/* Bluetooth Magnager is the heart of the application
  * It is responsible for scanning for the glasses and connecting to them
  * It also handles the connection state of the glasses
  * It allows for sending commands to the glasses
  */

typedef OnUpdate = void Function(String message);

class BluetoothManager {
  static final BluetoothManager singleton = BluetoothManager._internal();

  // Add mic status property with default false.
  bool isMicActive = false;

  // Add a flag to control auto-reconnect behavior.
  bool _isDisconnecting = false;

  factory BluetoothManager() {
    return singleton;
  }

  BluetoothManager._internal() {
    // Optionally, initialize isMicActive from SharedPreferences
    _loadMicState();
    notificationListener = AndroidNotificationsListener(
      onData: _handleAndroidNotification,
    );

    notificationListener!.startListening();
  }

  Future<void> _loadMicState() async {
    final prefs = await SharedPreferences.getInstance();
    isMicActive = prefs.getBool('mic_active') ?? false;
  }

  DashboardController dashboardController = DashboardController();

  Timer? _syncTimer;

  Glass? leftGlass;
  Glass? rightGlass;

  AndroidNotificationsListener? notificationListener;

  get isConnected =>
      leftGlass?.isConnected == true && rightGlass?.isConnected == true;
  get isScanning => _isScanning;

  Timer? _scanTimer;
  bool _isScanning = false;
  int _retryCount = 0;
  static const int maxRetries = 3;

  Future<String?> _getLastG1UsedUid(GlassSide side) async {
    final pref = await SharedPreferences.getInstance();
    return pref.getString(side == GlassSide.left ? 'left' : 'right');
  }

  Future<String?> _getLastG1UsedName(GlassSide side) async {
    final pref = await SharedPreferences.getInstance();
    return pref.getString(side == GlassSide.left ? 'leftName' : 'rightName');
  }

  Future<void> _saveLastG1Used(GlassSide side, String name, String uid) async {
    final pref = await SharedPreferences.getInstance();
    await pref.setString(side == GlassSide.left ? 'left' : 'right', uid);
    await pref.setString(
        side == GlassSide.left ? 'leftName' : 'rightName', name);
  }

  Future<void> initialize() async {
    FlutterBluePlus.setLogLevel(LogLevel.none);
  
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    Map<Permission, PermissionStatus> statuses = await [
      //Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.any((status) => status.isDenied)) {
      throw Exception(
          'All permissions are required to use Bluetooth. Please enable them in the app settings.');
    }

    if (statuses.values.any((status) => status.isPermanentlyDenied)) {
      await openAppSettings();
      throw Exception(
          'All permissions are required to use Bluetooth. Please enable them in the app settings.');
    }
  }

  Future<void> attemptReconnectFromStorage() async {
    await initialize();

    final leftUid = await _getLastG1UsedUid(GlassSide.left);
    final rightUid = await _getLastG1UsedUid(GlassSide.right);

    if (leftUid != null) {
      leftGlass = Glass(
        name: await _getLastG1UsedName(GlassSide.left) ?? 'Left Glass',
        device: BluetoothDevice(remoteId: DeviceIdentifier(leftUid)),
        side: GlassSide.left,
      );
      await leftGlass!.connect();
      _setReconnect(leftGlass!);
    }

    if (rightUid != null) {
      rightGlass = Glass(
        name: await _getLastG1UsedName(GlassSide.right) ?? 'Right Glass',
        device: BluetoothDevice(remoteId: DeviceIdentifier(rightUid)),
        side: GlassSide.right,
      );
      await rightGlass!.connect();
      _setReconnect(rightGlass!);
    }
  }

  Future<void> startScanAndConnect({
    required OnUpdate onUpdate,
  }) async {
    try {
      // this will fail in backround mode
      await _requestPermissions();
    } catch (e) {
      onUpdate(e.toString());
    }

    if (!await FlutterBluePlus.isAvailable) {
      onUpdate('Bluetooth is not available');
      throw Exception('Bluetooth is not available');
    }

    if (!await FlutterBluePlus.isOn) {
      onUpdate('Bluetooth is turned off');
      throw Exception('Bluetooth is turned off');
    }

    // Reset state
    _isScanning = true;
    _retryCount = 0;
    leftGlass = null;
    rightGlass = null;

    await _startScan(onUpdate);
  }

  Future<void> _startScan(OnUpdate onUpdate) async {
    await FlutterBluePlus.stopScan();
    debugPrint('Starting new scan attempt ${_retryCount + 1}/$maxRetries');

    // Set scan timeout
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(seconds: 30), () {
      if (_isScanning) {
        _handleScanTimeout(onUpdate);
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 30),
      androidUsesFineLocation: true,
    );

    // Listen for scan results
    FlutterBluePlus.scanResults.listen(
      (results) {
        for (ScanResult result in results) {
          String deviceName = result.device.name;
          String deviceId = result.device.id.id;
          debugPrint('Found device: $deviceName ($deviceId)');

          if (deviceName.isNotEmpty) {
            _handleDeviceFound(result, onUpdate);
          }
        }
      },
      onError: (error) {
        debugPrint('Scan results error: $error');
        onUpdate(error.toString());
      },
    );

    // Monitor scanning state
    FlutterBluePlus.isScanning.listen((isScanning) {
      debugPrint('Scanning state changed: $isScanning');
      if (!isScanning && _isScanning) {
        _handleScanComplete(onUpdate);
      }
    });
  }

  void _handleDeviceFound(ScanResult result, OnUpdate onUpdate) async {
    String deviceName = result.device.name;
    Glass? glass;
    if (deviceName.contains('_L_') && leftGlass == null) {
      debugPrint('Found left glass: $deviceName');
      glass = Glass(
        name: deviceName,
        device: result.device,
        side: GlassSide.left,
      );
      leftGlass = glass;
      onUpdate("Left glass found: ${glass.name}");
      await _saveLastG1Used(GlassSide.left, glass.name, glass.device.id.id);
    } else if (deviceName.contains('_R_') && rightGlass == null) {
      debugPrint('Found right glass: $deviceName');
      glass = Glass(
        name: deviceName,
        device: result.device,
        side: GlassSide.right,
      );
      rightGlass = glass;
      onUpdate("Right glass found: ${glass.name}");
      await _saveLastG1Used(GlassSide.right, glass.name, glass.device.id.id);
    }
    if (glass != null) {
      await glass.connect();

      _setReconnect(glass);
    }

    // Stop scanning if both glasses are found
    if (leftGlass != null && rightGlass != null) {
      _isScanning = false;
      stopScanning();
      _sync();
    }
  }

  void _setReconnect(Glass glass) {
    glass.device.connectionState.listen((BluetoothConnectionState state) {
      debugPrint('[${glass.side} Glass] Connection state: $state');
      // Only auto-reconnect if not in the process of disconnecting.
      if (!_isDisconnecting && state == BluetoothConnectionState.disconnected) {
        debugPrint('[${glass.side} Glass] Disconnected, attempting to reconnect...');
        glass.connect();
      }
    });
  }

  void _handleScanTimeout(OnUpdate onUpdate) async {
    debugPrint('Scan timeout occurred');

    if (_retryCount < maxRetries && (leftGlass == null || rightGlass == null)) {
      _retryCount++;
      debugPrint('Retrying scan (Attempt $_retryCount/$maxRetries)');
      await _startScan(onUpdate);
    } else {
      _isScanning = false;
      stopScanning();
      onUpdate(leftGlass == null && rightGlass == null
          ? 'No glasses found'
          : 'Scan completed');
    }
  }

  void _handleScanComplete(OnUpdate onUpdate) {
    if (_isScanning && (leftGlass == null || rightGlass == null)) {
      _handleScanTimeout(onUpdate);
    }
  }

  Future<void> connectToDevice(BluetoothDevice device,
      {required String side}) async {
    try {
      debugPrint('Attempting to connect to $side glass: ${device.name}');
      await device.connect(timeout: const Duration(seconds: 15));
      debugPrint('Connected to $side glass: ${device.name}');

      List<BluetoothService> services = await device.discoverServices();
      debugPrint('Discovered ${services.length} services for $side glass');

      for (BluetoothService service in services) {
        if (service.uuid.toString().toUpperCase() ==
            BluetoothConstants.UART_SERVICE_UUID) {
          debugPrint('Found UART service for $side glass');
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() ==
                BluetoothConstants.UART_TX_CHAR_UUID) {
              debugPrint('Found TX characteristic for $side glass');
            } else if (characteristic.uuid.toString().toUpperCase() ==
                BluetoothConstants.UART_RX_CHAR_UUID) {
              debugPrint('Found RX characteristic for $side glass');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error connecting to $side glass: $e');
      await device.disconnect();
      rethrow;
    }
  }

  void stopScanning() {
    _scanTimer?.cancel();
    FlutterBluePlus.stopScan().then((_) {
      debugPrint('Stopped scanning');
      _isScanning = false;
    }).catchError((error) {
      debugPrint('Error stopping scan: $error');
    });
  }

  Future<void> sendCommandToGlasses(List<int> command) async {
    if (leftGlass != null) {
      await leftGlass!.sendData(command);
      await Future.delayed(Duration(milliseconds: 100));
    }
    if (rightGlass != null) {
      await rightGlass!.sendData(command);
      await Future.delayed(Duration(milliseconds: 100));
    }
  }



static const int TEXT_COMMAND = 0x4E;
static const int DISPLAYING_COMPLETE = 0x40;
static const int DISPLAY_WIDTH = 360;
static const int DISPLAY_USE_WIDTH = 360;
static const double FONT_SIZE = 21;
static const double FONT_DIVIDER = 2.0;
static const int LINES_PER_SCREEN = 5;
static const int MAX_CHUNK_SIZE = 176;
static const List<int> EXIT_COMMAND = [0x18];

int textSeqNum = 0;

/// Splits a string into lines based on length or display parameters.
List<String> splitIntoLines(String text) {
  // Replace specific symbols
  text = text.replaceAll("⬆", "^").replaceAll("⟶", "-");

  // Handle the specific case of " " (single space)
  if (text == " ") {
    return [" "];
  }

  final lines = <String>[];
  final rawLines = text.split("\n"); // Split by newlines first
  final charsPerLine = ((DISPLAY_USE_WIDTH / (FONT_SIZE / FONT_DIVIDER) * 1.45)).round(); // Rough estimate

  for (String rawLine in rawLines) {
    if (rawLine.isEmpty) {
      // Add an empty line for \n
      lines.add("");
      continue;
    }

    // Wrap text using our rough charsPerLine
    String current = rawLine.trim();
    while (current.isNotEmpty) {
      // If shorter than max length, just add
      if (current.length <= charsPerLine) {
        lines.add(current);
        break;
      }

      // Otherwise, find the best split position
      int splitIndex = charsPerLine;

      // Move splitIndex left until we find a space
      while (splitIndex > 0 && current[splitIndex] != ' ') {
        splitIndex--;
      }

      // If no space was found, force the split at charsPerLine
      if (splitIndex == 0) {
        splitIndex = charsPerLine;
      }

      // Extract the chunk, trim it, and add to result lines
      String chunk = current.substring(0, splitIndex).trim();
      lines.add(chunk);

      // Remove that chunk (plus leading/trailing spaces) from current
      current = current.substring(splitIndex).trim();
    }
  }

  return lines;
}

List<List<int>> createTextWallChunks(String text, {int screenStatus = 0x71}) {
  // Split text into lines based on display width and font size
  final lines = splitIntoLines(text);

  // Add indentation to each line
  final unusedWidth = DISPLAY_WIDTH - DISPLAY_USE_WIDTH;
  final indentChars = (unusedWidth / (FONT_SIZE / FONT_DIVIDER) / 2).round();
  final indentedLines = lines.map((line) => ' ' * indentChars + line).toList();

  // Calculate total pages (hard set to 1 since we only do 1 page)
  final totalPages = 1;

  final allChunks = <List<int>>[];

  // Process each page
  for (int page = 0; page < totalPages; page++) {
    // Get lines for current page
    final startLine = page * LINES_PER_SCREEN;
    final endLine = (startLine + LINES_PER_SCREEN > indentedLines.length)
        ? indentedLines.length
        : startLine + LINES_PER_SCREEN;
    final pageLines = indentedLines.sublist(startLine, endLine);

    // Combine lines for this page
    final pageText = pageLines.join('\n') + '\n';

    // Encode the text to UTF-8
    final textBytes = utf8.encode(pageText);

    // Calculate the total number of chunks
    final totalChunks = (textBytes.length / MAX_CHUNK_SIZE).ceil();

    // Create chunks for this page
    for (int i = 0; i < totalChunks; i++) {
      final start = i * MAX_CHUNK_SIZE;
      final end = (start + MAX_CHUNK_SIZE > textBytes.length)
          ? textBytes.length
          : start + MAX_CHUNK_SIZE;

      // Create a copy of the range of bytes for the payload chunk
      final payloadChunk = textBytes.sublist(start, end);

      // Create header with protocol specifications
      final header = <int>[
        TEXT_COMMAND, // Command type
        textSeqNum & 0xFF, // Sequence number
        totalChunks & 0xFF, // Total packages
        i & 0xFF, // Current package number
        screenStatus & 0xFF, // Screen status
        0x00, // new_char_pos0 (high)
        0x00, // new_char_pos1 (low)
        page & 0xFF, // Current page number
        totalPages & 0xFF // Max page number
      ];

      // Combine header and payload
      final chunk = Uint8List(header.length + payloadChunk.length);
      chunk.setAll(0, header);
      chunk.setAll(header.length, payloadChunk);

      allChunks.add(chunk.toList());
    }

    // Increment sequence number for next page
    textSeqNum = (textSeqNum + 1) % 256;
    break; //hard set to 1  - 1PAGECHANGE
  }

  return allChunks;
}


List<List<int>> createDoubleTextWallChunks(String text1, String text2, {int screenStatus = 0x71}) {
  // Split both texts into lines
  List<String> lines1 = splitIntoLines(text1);
  List<String> lines2 = splitIntoLines(text2);

  // Ensure we only take up to 5 lines per screen
  while (lines1.length < LINES_PER_SCREEN) lines1.add("");
  while (lines2.length < LINES_PER_SCREEN) lines2.add("");

  lines1 = lines1.sublist(0, LINES_PER_SCREEN);
  lines2 = lines2.sublist(0, LINES_PER_SCREEN);

  // Get space width (each space is 2 pixels + 1 extra padding pixel, so 3 total)
  // Assuming fontLoader.getGlyph(' ').width + 1 is a constant or can be approximated
  const spaceWidth = 3; // Approximate space width

  // Calculate where the right column should start
  final rightColumnStart = (DISPLAY_USE_WIDTH * 0.6).round();

  // Construct the text output by merging the lines
  final pageText = StringBuffer();
  for (int i = 0; i < LINES_PER_SCREEN; i++) {
    String leftText = lines1[i].replaceAll('\u2002', ''); // Drop enspaces
    String rightText = lines2[i].replaceAll('\u2002', '');

    // Calculate width of left text
    int leftTextWidth = calculateTextWidth(leftText);

    // Calculate spacing needed
    int neededSpacingPixels = rightColumnStart - leftTextWidth;
    // Base spaces (at least 3)
    int baseSpaces = neededSpacingPixels ~/ spaceWidth;
    baseSpaces = baseSpaces > 3 ? baseSpaces : 3;
    // Check remainder to see if we should add one extra space
    int remainder = neededSpacingPixels % spaceWidth;
    bool addExtraSpace = (neededSpacingPixels >= 0) && (remainder == 1 || remainder == 2);
    // Cap at 60 spaces
    int safeSpaces = baseSpaces + (addExtraSpace ? 1 : 0);
    safeSpaces = safeSpaces < 60 ? safeSpaces : 60;

    // Log compressed info
    debugPrint("L: '$leftText' (W=$leftTextWidth) | Spaces=$safeSpaces${addExtraSpace ? " + extra space" : ""} | R: '$rightText'");

    // Construct the full line
    pageText.write(leftText);
    pageText.write(' ' * safeSpaces);
    pageText.write(rightText);
    pageText.write('\n');
  }

  // Convert **everything**, including debug line, into bytes and chunk it
  final textBytes = utf8.encode(pageText.toString());
  final totalChunks = (textBytes.length / MAX_CHUNK_SIZE).ceil();

  final allChunks = <List<int>>[];
  for (int i = 0; i < totalChunks; i++) {
    final start = i * MAX_CHUNK_SIZE;
    final end = (start + MAX_CHUNK_SIZE > textBytes.length) ? textBytes.length : start + MAX_CHUNK_SIZE;
    final payloadChunk = textBytes.sublist(start, end);

    // Create header with protocol specifications
    final header = <int>[
      TEXT_COMMAND, // Command type
      textSeqNum & 0xFF, // Sequence number
      totalChunks & 0xFF, // Total packages
      i & 0xFF, // Current package number
      screenStatus & 0xFF, // Screen status
      0x00, // new_char_pos0 (high)
      0x00, // new_char_pos1 (low)
      0x00, // Current page number (always 0 for now)
      0x01 // Max page number (always 1)
    ];

    // Combine header and payload
    final chunk = Uint8List(header.length + payloadChunk.length);
    chunk.setAll(0, header);
    chunk.setAll(header.length, payloadChunk);

    allChunks.add(chunk.toList());
  }

  // **Ensure BLE packet limit is respected**
  if (allChunks.length > totalChunks) {
    debugPrint("Chunking error: Exceeded totalChunks!");
  }

  // Increment sequence number for next page
  textSeqNum = (textSeqNum + 1) % 256;

  return allChunks;
}

// Placeholder for calculateTextWidth function
int calculateTextWidth(String text) {
  // Implement your text width calculation logic here
  // This is a placeholder, replace with actual implementation
  return text.length * 10; // Example: 10 pixels per character
}


Future<void> sendText(String text, { 
  Duration delay = const Duration(milliseconds: 70),
}) async {
  final chunks = createTextWallChunks(text);
  for (final chunk in chunks) {
    await sendCommandToGlasses(chunk);
    await Future.delayed(delay);
  }

}

  List<String> createSentencesFromWords(List<String> words) {
    String text = words.join(" ");
    List<String> sentences = createSentences(text);
    return sentences;
  }
   List<String> createSentences(String text) {
    // sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    List<String> sentences  = text.split(RegExp(r'(?<=[.!?])\s+'));
    return sentences;
  }

  Future<void> displaySentences(
  List<String> sentences, {
  int sentenceCount = 1, // New parameter: number of sentences to display at once
  int durationMultiplier = 40,
}) async {
  // Process sentences in batches of [sentenceCount]
  for (int i = 0; i < sentences.length; i += sentenceCount) {
    // Get a group of sentences (batch)
    final batch = sentences.sublist(
      i,
      (i + sentenceCount > sentences.length) ? sentences.length : i + sentenceCount,
    );
    // Combine the batch into a single text block (each on a new line)
    final batchText = batch.join('\n');
    await sendText(batchText);
    int duration = batchText.length * durationMultiplier;
    await Future.delayed(Duration(milliseconds: duration));
  }
  await Future.delayed(Duration(microseconds: 16));
  await clearScreen();
}

Future<void> display(String text) async {
  final pref = await SharedPreferences.getInstance();
  await pref.setString('last_received_message', text);

  List<String> sentences = createSentences(text);
  await displaySentences(sentences);
}



Future<void> clearScreen() async {
  // await sendTextAiLegacy(".");
  // just right glass
  await rightGlass!.sendData(EXIT_COMMAND);
}


 Future<void> sendTextAi (String text, {Duration delay = const Duration(seconds: 5)}) async {
    final textMsg = TextMessage(text);
    List<List<int>> packets = textMsg.constructSendText();

    for (int i = 0; i < packets.length; i++) {
      await sendCommandToGlasses(packets[i]);
      await Future.delayed(delay);
    }
  }

  Future<void> setDashboardLayout(List<int> option) async {
    // concat the command with the option
    List<int> command = DashboardLayout.DASHBOARD_CHANGE_COMMAND.toList();
    command.addAll(option);

    await sendCommandToGlasses(command);
  }

  Future<void> sendNote(Note note) async {
    List<int> noteBytes = note.buildAddCommand();
    await sendCommandToGlasses(noteBytes);
  }

  Future<void> sendBitmap(Uint8List bitmap) async {
    List<Uint8List> textBytes = Utils.divideUint8List(bitmap, 194);

    List<List<int>?> sentPackets = [];

    debugPrint("Transmitting BMP");
    for (int i = 0; i < textBytes.length; i++) {
      sentPackets.add(await _sendBmpPacket(dataChunk: textBytes[i], seq: i));
      await Future.delayed(Duration(milliseconds: 100));
    }

    debugPrint("Send end packet");
    await _sendPacketEndPacket();
    await Future.delayed(Duration(milliseconds: 500));

    List<int> concatenatedList = [];
    for (var packet in sentPackets) {
      if (packet != null) {
        concatenatedList.addAll(packet);
      }
    }
    Uint8List concatenatedPackets = Uint8List.fromList(concatenatedList);

    debugPrint("Sending CRC for mitmap");
    // Send CRC
    await _sendCRCPacket(packets: concatenatedPackets);
  }

  // Send a notification to the glasses
  Future<void> sendNotification(NCSNotification notification) async {
    G1Notification notif = G1Notification(ncsNotification: notification);
    List<Uint8List> notificationChunks = await notif.constructNotification();

    for (Uint8List chunk in notificationChunks) {
      await sendCommandToGlasses(chunk);
      await Future.delayed(
          Duration(milliseconds: 50)); // Small delay between chunks
    }
  }

  Future<String> _getAppDisplayName(String packageName) async {
    final pm = AndroidPackageManager();
    final name = await pm.getApplicationLabel(packageName: packageName);

    return name ?? packageName;
  }

  void _handleAndroidNotification(ServiceNotificationEvent notification) async {
    debugPrint(
        'Received notification: ${notification.toString()} from ${notification.packageName}');
    if (isConnected) {
      NCSNotification ncsNotification = NCSNotification(
        msgId: (notification.id ?? 1) + DateTime.now().millisecondsSinceEpoch,
        action: 0,
        type: 0,
        appIdentifier: notification.packageName ?? 'dev.visionlink.coreos',
        title: notification.title ?? '',
        subtitle: '',
        message: notification.content ?? '',
        displayName: await _getAppDisplayName(notification.packageName ?? ''),
      );

      sendNotification(ncsNotification);
    }
  }

  Future<List<int>?> _sendBmpPacket({
    required Uint8List dataChunk,
    int seq = 0,
  }) async {
    BmpPacket result = BmpPacket(
      seq: seq,
      data: dataChunk,
    );

    List<int> bmpCommand = result.build();

    if (seq == 0) {
      // Insert the 4 required bytes
      bmpCommand.insertAll(2, [0x00, 0x1c, 0x00, 0x00]);
    }

    try {
      sendCommandToGlasses(bmpCommand);
      return bmpCommand;
    } catch (e) {
      return null;
    }
  }

  int _crc32(Uint8List data) {
    var crc = Crc32();
    crc.add(data);
    return crc.close();
  }

  Future<List<int>?> _sendCRCPacket({
    required Uint8List packets,
  }) async {
    Uint8List crcData = Uint8List.fromList([...packets]);

    int crc32Checksum = _crc32(crcData) & 0xFFFFFFFF;
    Uint8List crc32Bytes = Uint8List(4);
    crc32Bytes[0] = (crc32Checksum >> 24) & 0xFF;
    crc32Bytes[1] = (crc32Checksum >> 16) & 0xFF;
    crc32Bytes[2] = (crc32Checksum >> 8) & 0xFF;
    crc32Bytes[3] = crc32Checksum & 0xFF;

    CrcPacket result = CrcPacket(
      data: crc32Bytes,
    );

    List<int> crcCommand = result.build();

    try {
      await leftGlass!.sendData(crcCommand);
      // wait for a reply to be sent over the crcReplies stream
      //await leftGlass!.replies.stream.firstWhere((d) => d[0] == Commands.CRC);
      debugPrint('CRC reply received from left glass');

      await rightGlass!.sendData(crcCommand);
      //await rightGlass!.replies.stream.firstWhere((d) => d[0] == Commands.CRC);
      debugPrint('CRC reply received from right glass');

      return crcCommand;
    } catch (e) {
      return null;
    }
  }

  Future<bool?> _sendPacketEndPacket() async {
    try {
      await leftGlass!.sendData([0x20, 0x0d, 0x0e]);
      //await leftGlass!.replies.stream.firstWhere((d) => d[0] == 0x20);
      await rightGlass!.sendData([0x20, 0x0d, 0x0e]);
      //await rightGlass!.replies.stream.firstWhere((d) => d[0] == 0x20);
    } catch (e) {
      debugPrint('Error in sendTextPacket: $e');
      return false;
    }
    return null;
  }

  Future<void> sync() async {
    await _sync();
  }

  Future<void> _sync() async {
    if (!isConnected) {
      return;
    }

  

    
    final dash = await dashboardController.updateDashboardCommand();
    for (var command in dash) {
      await sendCommandToGlasses(command);
    }

    // every 10 minutes sync G1Setup
    if (DateTime.now().minute % 10 == 0) {
      final setup = await G1Setup.generateSetup().constructSetup();
      for (var command in setup) {
        await sendCommandToGlasses(command);
      }
    }
  }

  bool _manualMicOverride = false;
  bool get manualMicOverride => _manualMicOverride;
  
  Future<void> setMicrophone(bool open, {bool manual = false}) async {
    final subCommand = open ? 0x01 : 0x00;
    isMicActive = open;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mic_active', open);
    // For an unknown issue the microphone will not close when sent to the left side,
    // to work around this we send the command to the right side only.
    await rightGlass!.sendData([Commands.OPEN_MIC, subCommand]);
    if(manual) {
      _manualMicOverride = open;
    }
  }

  Future<void> disconnectGlasses() async {
    // Set the flag to disable reconnect attempts.
    _isDisconnecting = true;
    // Clear stored UIDs from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('left');
    await prefs.remove('right');
    await prefs.remove('leftName');
    await prefs.remove('rightName');

    try {
      // Safely disconnect left glass
      if (leftGlass != null) {
        if (leftGlass!.isConnected) {
          await leftGlass!.device.disconnect();
        }
        leftGlass = null;
      }

      // Safely disconnect right glass
      if (rightGlass != null) {
        if (rightGlass!.isConnected) {
          await rightGlass!.device.disconnect();
        }
        rightGlass = null;
      }

      // Cancel any pending timers
      _scanTimer?.cancel();
      _syncTimer?.cancel();
      
      // Reset scanning state
      _isScanning = false;
      _retryCount = 0;

      debugPrint('Successfully disconnected both glasses');
    } catch (e) {
      debugPrint('Error during disconnect: $e');
      // Still null out the glasses even if disconnect fails
      leftGlass = null;
      rightGlass = null;
      rethrow;
    }
  }

    Future<void> queryBatteryStatus() async {
    List<int> batteryQueryPacket = constructBatteryLevelQuery();
    // Log.d(TAG, "Sending battery status query: " + bytesToHex(batteryQueryPacket));

    await  sendCommandToGlasses(batteryQueryPacket);
  }

  List<int> constructBatteryLevelQuery() {
    // Command 0x2C to query battery level
    // 0x01 for Android, 0x02 for iOS 
    return [0x2C, 0x01]; 
  }

}

