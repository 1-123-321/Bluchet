import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _bluchetNotificationChannel =
    AndroidNotificationChannel(
  'bluchet_messages_calls',
  'Bluchet üzenetek és hívások',
  description: 'Bejövő KulcsKod-hívások értesítései.',
  importance: Importance.max,
);

Future<void> _initializeLocalNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
  const settings = InitializationSettings(android: androidSettings);
  await _localNotifications.initialize(settings);

  final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(_bluchetNotificationChannel);
}

Future<void> _requestNotificationPermission() async {
  if (!Platform.isAndroid) return;
  try {
    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final permissionGranted = await androidPlugin?.requestNotificationsPermission();
    debugPrint(
      'Bluchet notification permission: ${permissionGranted == null ? 'not applicable' : permissionGranted ? 'granted' : 'not granted'}',
    );
  } catch (error, stack) {
    debugPrint('Bluchet notification permission request failed: $error\n$stack');
  }
}

Future<void> _showLocalNotification({
  required int id,
  required String title,
  required String body,
}) async {
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'bluchet_messages_calls',
      'Bluchet üzenetek és hívások',
      channelDescription: 'Új üzenetek és bejövő hívások értesítései.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    ),
  );
  try {
    await _localNotifications.show(id, title, body, details);
  } catch (error) {
    debugPrint('Bluchet notification failed: $error');
  }
}

@pragma('vm:entry-point')
void kulcsKodForegroundTaskStart() {
  FlutterForegroundTask.setTaskHandler(_KulcsKodForegroundTaskHandler());
}

class _KulcsKodForegroundTaskHandler extends TaskHandler {
  SupabaseClient? _client;
  StreamSubscription<List<Map<String, dynamic>>>? _callsSubscription;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final Set<String> _seenCallIds = <String>{};
  String? _userId;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      final url = (await FlutterForegroundTask.getData(key: 'supabase_url'))
          ?.toString();
      final anonKey = (await FlutterForegroundTask.getData(key: 'supabase_anon_key'))
          ?.toString();
      _userId = (await FlutterForegroundTask.getData(key: 'call_user_id'))
          ?.toString();

      if (url == null || anonKey == null || _userId == null ||
          url.isEmpty || anonKey.isEmpty || _userId!.isEmpty) {
        debugPrint('KulcsKod call listener: missing service configuration.');
        return;
      }

      const secureStorage = FlutterSecureStorage();
      final accountsRaw = await secureStorage.read(
        key: 'bluchet_saved_accounts_v1',
      );
      if (accountsRaw == null || accountsRaw.isEmpty) {
        debugPrint('KulcsKod call listener: no saved account session.');
        return;
      }

      final decoded = jsonDecode(accountsRaw);
      if (decoded is! Map) return;
      final account = decoded[_userId];
      final refreshToken = account is Map
          ? account['refreshToken']?.toString()
          : null;
      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint('KulcsKod call listener: no refresh token for active account.');
        return;
      }

      final savedSeen = await FlutterForegroundTask.getData(
        key: 'kulcskod_seen_call_ids',
      );
      if (savedSeen is String && savedSeen.isNotEmpty) {
        try {
          final values = jsonDecode(savedSeen);
          if (values is List) {
            _seenCallIds.addAll(values.map((value) => value.toString()));
          }
        } catch (_) {}
      }

      await _notifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        ),
      );
      final androidNotifications = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidNotifications?.createNotificationChannel(
        const AndroidNotificationChannel(
          'kulcskod_incoming_calls',
          'KulcsKod bejövő hívások',
          description: 'Bejövő KulcsKod hanghívások értesítései.',
          importance: Importance.max,
        ),
      );

      // This client has its own auth session in the background isolate. The
      // refresh token comes from encrypted FlutterSecureStorage, not from the
      // foreground-task preferences.
      final client = SupabaseClient(
        url,
        anonKey,
        authOptions: const AuthClientOptions(),
      );
      _client = client;
      await client.auth.setSession(refreshToken);
      if (client.auth.currentUser?.id != _userId) {
        throw StateError('A háttérszolgáltatás felhasználója nem egyezik.');
      }

      _callsSubscription = client
          .from('voice_calls')
          .stream(primaryKey: ['id'])
          .eq('callee_id', _userId!)
          .listen(
        (rows) => unawaited(_processCallRows(rows)),
        onError: (Object error, StackTrace stack) {
          debugPrint('KulcsKod background call stream error: $error');
          FlutterForegroundTask.sendDataToMain(<String, dynamic>{
            'type': 'call_listener_error',
            'message': error.toString(),
          });
        },
      );
      FlutterForegroundTask.sendDataToMain(<String, dynamic>{
        'type': 'call_listener_started',
      });
    } catch (error, stack) {
      debugPrint('KulcsKod background call listener failed: $error\n$stack');
      FlutterForegroundTask.sendDataToMain(<String, dynamic>{
        'type': 'call_listener_error',
        'message': error.toString(),
      });
    }
  }

  Future<void> _processCallRows(List<Map<String, dynamic>> rows) async {
    final now = DateTime.now().toUtc();
    for (final row in rows) {
      if (row['status']?.toString() != 'ringing') continue;
      if (row['callee_id']?.toString() != _userId) continue;
      final callId = row['id']?.toString();
      if (callId == null || callId.isEmpty || _seenCallIds.contains(callId)) {
        continue;
      }

      // Avoid notifying about old ringing rows when the service first connects.
      final createdAtText = row['created_at']?.toString();
      if (createdAtText == null) continue;
      final createdAt = DateTime.tryParse(createdAtText)?.toUtc();
      if (createdAt == null) continue;
      final age = now.difference(createdAt);
      if (age > const Duration(minutes: 2) ||
          age < const Duration(seconds: -30)) {
        continue;
      }

      _seenCallIds.add(callId);
      if (_seenCallIds.length > 100) {
        _seenCallIds.remove(_seenCallIds.first);
      }
      await FlutterForegroundTask.saveData(
        key: 'kulcskod_seen_call_ids',
        value: jsonEncode(_seenCallIds.toList()),
      );

      final notificationId = callId.hashCode & 0x7fffffff;
      await _notifications.show(
        notificationId,
        'Bejövő KulcsKod-hívás',
        'Valaki hanghívást indított neked.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'kulcskod_incoming_calls',
            'KulcsKod bejövő hívások',
            channelDescription: 'Bejövő KulcsKod hanghívások értesítései.',
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: true,
            playSound: true,
          ),
        ),
        payload: callId,
      );
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _callsSubscription?.cancel();
    _callsSubscription = null;
    await _client?.dispose();
    _client = null;
  }

  @override
  void onReceiveData(Object data) async {
    if (data is! Map) return;
    final newUserId = data['userId']?.toString();
    if (newUserId != null && newUserId.isNotEmpty && newUserId != _userId) {
      // Account changes should restart the service through the UI isolate.
      await _callsSubscription?.cancel();
      await _client?.dispose();
      _callsSubscription = null;
      _client = null;
      _userId = newUserId;
    }
  }
}

void _initializeBackgroundService() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'kulcskod_background_service',
      channelName: 'KulcsKod háttérfigyelés',
      channelDescription: 'A KulcsKod aktív háttérfigyelésének állapota.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(15000),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

Future<void> _startBackgroundService(String userId) async {
  if (!Platform.isAndroid) return;
  final url = _readEnv('SUPABASE_URL');
  final anonKey = _readEnv('SUPABASE_ANON_KEY');
  if (url.isEmpty || anonKey.isEmpty) {
    debugPrint('KulcsKod call listener not started: Supabase config missing.');
    return;
  }

  // These are non-secret project settings and the active user ID. The refresh
  // token itself remains inside FlutterSecureStorage.
  await FlutterForegroundTask.saveData(key: 'supabase_url', value: url);
  await FlutterForegroundTask.saveData(key: 'supabase_anon_key', value: anonKey);
  await FlutterForegroundTask.saveData(key: 'call_user_id', value: userId);

  // Notification permission is requested once from the visible app UI after
  // the first frame. Avoid opening a second permission flow while starting
  // the foreground service.
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.restartService();
  } else {
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'KulcsKod hívásfigyelés',
      notificationText: 'Bejövő hívások figyelése aktív.',
      callback: kulcsKodForegroundTaskStart,
      notificationInitialRoute: '/',
      serviceTypes: [ForegroundServiceTypes.dataSync],
    );
  }
}

Future<void> _stopBackgroundService() async {
  if (!Platform.isAndroid) return;
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.stopService();
  }
  await FlutterForegroundTask.removeData(key: 'call_user_id');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  try {
    await _initializeLocalNotifications();
  } catch (error) {
    debugPrint('Bluchet notification initialization failed: $error');
  }

  try {
    _initializeBackgroundService();
  } catch (error) {
    debugPrint('KulcsKod background service initialization failed: $error');
  }

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Ignore a missing .env when values are supplied via --dart-define.
  }

  final url = _readEnv('SUPABASE_URL');
  final anonKey = _readEnv('SUPABASE_ANON_KEY');

  final isConfigured =
      url.startsWith('https://') && url.isNotEmpty && anonKey.isNotEmpty;

  if (!isConfigured) {
    runApp(
      const BluchetStartupApp(
        message: 'Missing SUPABASE_URL or SUPABASE_ANON_KEY',
      ),
    );
    return;
  }

  try {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      realtimeLifecycleOptions: const RealtimeLifecycleOptions.manual(),
    );
  } catch (error) {
    runApp(BluchetStartupApp(message: error.toString()));
    return;
  }

  runApp(const BluchetApp());
}

String _readEnv(String key) {
  const fromDartDefineValues = <String, String>{};
  final fromDartDefine = String.fromEnvironment(key, defaultValue: '');
  if (fromDartDefine.isNotEmpty) return fromDartDefine;
  return dotenv.env[key] ?? fromDartDefineValues[key] ?? '';
}

class AppSecurity {
  static bool isValidUsername(String value) =>
      RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(value.trim());

  static bool isValidPassword(String value) => value.length >= 6;

  static bool isValidMessage(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && trimmed.length <= 2000;
  }
}

class BluchetPalette {
  static const Color turquoise50 = Color(0xFFEAFDFB);
  static const Color turquoise100 = Color(0xFFD9FAF8);
  static const Color turquoise200 = Color(0xFFC3F5F4);
  static const Color turquoise300 = Color(0xFF9FEDE9);
  static const Color turquoise400 = Color(0xFF7BE6E0);
  static const Color turquoise500 = Color(0xFF5ADBD5);
  static const Color turquoise600 = Color(0xFF36C9C1);
  static const Color turquoise700 = Color(0xFF24A9A5);
  static const Color turquoise800 = Color(0xFF1A8A89);
  static const Color turquoise900 = Color(0xFF136E70);

  static const Color royalBlue50 = Color(0xFFEAF2FF);
  static const Color royalBlue100 = Color(0xFFDDEBFF);
  static const Color royalBlue200 = Color(0xFFD0E0FF);
  static const Color royalBlue300 = Color(0xFFB7D0FF);
  static const Color royalBlue400 = Color(0xFF95B5FF);
  static const Color royalBlue500 = Color(0xFF76A0FF);
  static const Color royalBlue600 = Color(0xFF5686F6);
  static const Color royalBlue700 = Color(0xFF3E6FEA);
  static const Color royalBlue800 = Color(0xFF315DC8);
  static const Color royalBlue900 = Color(0xFF2347A7);

  // Colors adapted from the latest Bluchet DB Console v4 HTML.
  static const Color primary = Color(0xFF4D8DFF);
  static const Color primaryDark = Color(0xFF244E9A);
  static const Color accent = Color(0xFF42D7D0);
  static const Color accentDark = Color(0xFF24A9A5);
  static const Color background = Color(0xFF07121B);
  static const Color card = Color(0xFF0D202B);
  static const Color surface = Color(0xFF123440);
  static const Color text = Color(0xFFE4F6FA);
  static const Color textMuted = Color(0xFF8EABB5);
  static const Color inputText = Color(0xFFE4F6FA);
  static const Color inputLabel = Color(0xFF8EABB5);
  static const Color success = Color(0xFF68E0A5);
  static const Color error = Color(0xFFFF737D);
  static const Color dangerSoft = Color(0xFF351A22);
}

class BluchetTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: BluchetPalette.background,
      colorScheme: const ColorScheme.dark(
        primary: BluchetPalette.primary,
        secondary: BluchetPalette.accent,
        surface: BluchetPalette.surface,
        error: BluchetPalette.error,
        onPrimary: Color(0xFFF4F7F7),
        onSecondary: Color(0xFFF4F7F7),
        onSurface: BluchetPalette.text,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: BluchetPalette.text,
            displayColor: BluchetPalette.text,
          ),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: BluchetPalette.card,
        foregroundColor: Color(0xFFF4F7F7),
        elevation: 0,
        toolbarHeight: 52,
        iconTheme: IconThemeData(size: 20),
        actionsIconTheme: IconThemeData(size: 20),
      ),
      cardTheme: CardThemeData(
        color: BluchetPalette.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF06131C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF244653)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF244653)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: BluchetPalette.accent, width: 2.5),
        ),
        hintStyle: const TextStyle(color: BluchetPalette.inputLabel),
        labelStyle: const TextStyle(color: BluchetPalette.inputLabel),
        floatingLabelStyle: const TextStyle(
          color: BluchetPalette.accentDark,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: const Color(0xFFF4F7F7),
          backgroundColor: BluchetPalette.accent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BluchetPalette.primaryDark,
        ),
      ),
    );
  }
}

class BluchetStartupApp extends StatelessWidget {
  final String message;

  const BluchetStartupApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: BluchetTheme.light(),
      home: Scaffold(
        backgroundColor: BluchetPalette.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              color: BluchetPalette.card,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: BluchetPalette.error,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Experimental client-side encryption for Bluchet.
///
/// Uses per-device X25519 static keys + HKDF-SHA256 + AES-256-GCM.
/// This is NOT the Signal Protocol: it does not provide forward secrecy or
/// authenticated identity-key verification. Do not market it as production-grade
/// Signal E2EE until those protocol features are implemented and audited.
class _BluchetE2ee {
  _BluchetE2ee(this.userId, this.storage);

  final String userId;
  final FlutterSecureStorage storage;
  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  String? _deviceId;
  SimpleKeyPair? _keyPair;
  String? _publicKey;
  Future<void>? _ready;

  String _b64(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');
  List<int> _unb64(String value) {
    final normalized = value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
    return base64Url.decode(normalized);
  }

  // A failed registration must be retryable; don't cache a failed Future forever.
  Future<void> ensureReady() async {
    try {
      await (_ready ??= _initialize());
    } catch (_) {
      _ready = null;
      rethrow;
    }
  }

  // Scope device identifiers and private seeds to the signed-in account.
  // This prevents two remembered accounts on one phone from sharing a key.
  String get _deviceIdStorageKey => 'bluchet_e2ee_device_id_$userId';
  String get _seedStorageKey => 'bluchet_e2ee_x25519_seed_$userId';

  Future<void> _initialize() async {
    _deviceId = await storage.read(key: _deviceIdStorageKey);
    _deviceId ??= const Uuid().v4();
    await storage.write(key: _deviceIdStorageKey, value: _deviceId);

    var seedText = await storage.read(key: _seedStorageKey);
    List<int> seed;
    if (seedText == null) {
      final generated = await _x25519.newKeyPair();
      seed = await generated.extractPrivateKeyBytes();
      await storage.write(key: _seedStorageKey, value: _b64(seed));
    } else {
      seed = _unb64(seedText);
    }
    _keyPair = await _x25519.newKeyPairFromSeed(seed);
    final publicKey = await _keyPair!.extractPublicKey();
    _publicKey = _b64(publicKey.bytes);

    // Register/update only this account + installation. Never delete first: a
    // failed insert must not leave the installation without its previous record.
    final db = Supabase.instance.client;
    await db.from('device_keys').upsert({
      'user_id': userId,
      'device_id': _deviceId,
      'identity_key': _publicKey,
      // Current schema requires these fields in some deployments. This marker
      // is explicitly NOT a cryptographic signature or a Signal signed prekey.
      'signed_prekey': _publicKey,
      'signed_prekey_signature': 'bluchet-static-x25519-v1-no-signature',
      'one_time_prekeys': <dynamic>[],
    }, onConflict: 'user_id,device_id');
  }

  Future<String> encryptForConversation({
    required String conversationId,
    required String plaintext,
    required List<String> memberIds,
  }) async {
    await ensureReady();
    final recipients = <String>{...memberIds, userId};
    final envelopes = <String, dynamic>{};

    for (final recipientId in recipients) {
      final dynamic result = await Supabase.instance.client.rpc(
        'get_e2ee_public_keys',
        params: {'target_user': recipientId},
      );
      if (result is! List || result.isEmpty) {
        throw Exception('E2EE: $recipientId felhasználónak nincs regisztrált titkosítási kulcsa.');
      }
      for (final rowValue in result) {
        final row = Map<String, dynamic>.from(rowValue as Map);
        final deviceId = row['device_id']?.toString();
        final publicText = row['identity_key']?.toString();
        if (deviceId == null || publicText == null || publicText.isEmpty) {
          throw Exception('E2EE: hibás eszközkulcs-válasz.');
        }
        final remotePublic = SimplePublicKey(_unb64(publicText), type: KeyPairType.x25519);
        final shared = await _x25519.sharedSecretKey(
          keyPair: _keyPair!,
          remotePublicKey: remotePublic,
        );
        final context = _keyContext(conversationId, userId, recipientId);
        final key = await _hkdf.deriveKey(
          secretKey: shared,
          nonce: utf8.encode(conversationId),
          info: utf8.encode(context),
        );
        final box = await _aes.encrypt(
          utf8.encode(plaintext),
          secretKey: key,
        );
        envelopes[deviceId] = {
          'recipient_user_id': recipientId,
          'sender_user_id': userId,
          'sender_public_key': _publicKey,
          'nonce': _b64(box.nonce),
          'cipher_text': _b64(box.cipherText),
          'mac': _b64(box.mac.bytes),
        };
      }
    }

    return 'bluchet-e2ee-v1:${jsonEncode({
      'version': 1,
      'conversation_id': conversationId,
      'devices': envelopes,
    })}';
  }

  Future<String> decryptMessage({
    required String conversationId,
    required String senderId,
    required String storedText,
  }) async {
    if (!storedText.startsWith('bluchet-e2ee-v1:')) {
      // Backwards compatibility: old plaintext rows are left untouched.
      return storedText;
    }
    await ensureReady();
    final decoded = jsonDecode(storedText.substring('bluchet-e2ee-v1:'.length));
    final root = Map<String, dynamic>.from(decoded as Map);
    if (root['conversation_id'] != conversationId) {
      throw Exception('E2EE: a titkosított üzenet másik beszélgetéshez tartozik.');
    }
    final devices = Map<String, dynamic>.from(root['devices'] as Map);
    final envelopeValue = devices[_deviceId];
    if (envelopeValue == null) {
      return '🔒 Ezt az üzenetet nem ehhez az eszközhöz titkosították.';
    }
    final envelope = Map<String, dynamic>.from(envelopeValue as Map);
    if (envelope['recipient_user_id'] != userId ||
        envelope['sender_user_id'] != senderId) {
      throw Exception('E2EE: az üzenet címzettje vagy feladója nem egyezik.');
    }
    final senderPublicText = envelope['sender_public_key']?.toString() ?? '';
    final senderPublic = SimplePublicKey(_unb64(senderPublicText), type: KeyPairType.x25519);
    final shared = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: senderPublic,
    );
    final key = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(conversationId),
      info: utf8.encode(_keyContext(conversationId, senderId, userId)),
    );
    final box = SecretBox(
      _unb64(envelope['cipher_text'].toString()),
      nonce: _unb64(envelope['nonce'].toString()),
      mac: Mac(_unb64(envelope['mac'].toString())),
    );
    return utf8.decode(await _aes.decrypt(box, secretKey: key));
  }

  String _keyContext(String conversationId, String a, String b) {
    final sorted = [a, b]..sort();
    return 'bluchet-e2ee-v1|$conversationId|${sorted[0]}|${sorted[1]}';
  }
}

class BluchetApp extends StatefulWidget {
  const BluchetApp({super.key});

  @override
  State<BluchetApp> createState() => _BluchetAppState();
}

class _BluchetAppState extends State<BluchetApp> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _loading = true;
  String? _currentUserId;
  StreamSubscription<dynamic>? _authStateSubscription;
  static const _accountsKey = 'bluchet_saved_accounts_v1';
  static const _lastAccountKey = 'bluchet_last_account_v1';

  Future<Map<String, dynamic>> _savedAccounts() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _rememberCurrentSession(String userId, {String? username}) async {
    final session = Supabase.instance.client.auth.currentSession;
    final refreshToken = session?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return;
    final accounts = await _savedAccounts();
    final old = accounts[userId] is Map ? Map<String, dynamic>.from(accounts[userId] as Map) : <String, dynamic>{};
    accounts[userId] = <String, dynamic>{
      'userId': userId,
      'username': username ?? old['username'] ?? Supabase.instance.client.auth.currentUser?.userMetadata?['username'] ?? 'Mentett fiók',
      'refreshToken': refreshToken,
    };
    await _storage.write(key: _accountsKey, value: jsonEncode(accounts));
    await _storage.write(key: _lastAccountKey, value: userId);
  }


  @override
  void initState() {
    super.initState();
    // Keep the encrypted refresh-token copy current as Supabase rotates it.
    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      final userId = state.session?.user.id;
      if (userId != null) unawaited(_rememberCurrentSession(userId));
    });
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      // Older builds stored a plain profile UUID without a Supabase Auth
      // session. That is not an authenticated identity, so discard it.
      await _storage.delete(key: 'bluchet_user_id');
      final client = Supabase.instance.client;
      var user = client.auth.currentUser;
      if (user != null) {
        await _rememberCurrentSession(user.id);
      } else {
        final accounts = await _savedAccounts();
        final lastId = await _storage.read(key: _lastAccountKey);
        final last = lastId == null ? null : accounts[lastId];
        final refreshToken = last is Map ? last['refreshToken'] as String? : null;
        if (refreshToken != null && refreshToken.isNotEmpty) {
          try {
            final response = await client.auth.setSession(refreshToken);
            user = response.user;
            if (user != null) await _rememberCurrentSession(user.id);
          } catch (error) {
            debugPrint('Could not restore last Bluchet account: $error');
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _currentUserId = user?.id;
        _loading = false;
      });
      if (user != null) {
        unawaited(_startBackgroundService(user.id));
      } else {
        unawaited(_stopBackgroundService());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentUserId = null;
        _loading = false;
      });
    }
  }

  // The user only sees a username. Supabase Auth still receives a
  // syntactically valid, non-deliverable internal address.
  String _internalEmail(String username) =>
      '${username.trim().toLowerCase()}@bluchet.invalid';

  Future<void> _login(String username, String password) async {
    if (!AppSecurity.isValidUsername(username)) {
      throw Exception(
        'Username must be 3-24 chars, letters/numbers/underscore only.',
      );
    }
    if (!AppSecurity.isValidPassword(password)) {
      throw Exception('Password must be at least 6 characters.');
    }

    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: _internalEmail(username),
      password: password,
    );
    final userId = response.user?.id;
    if (userId == null) {
      throw Exception('Login did not return a valid authenticated user.');
    }

    await _rememberCurrentSession(userId, username: username.trim().toLowerCase());
    if (!mounted) return;
    setState(() => _currentUserId = userId);
    unawaited(_startBackgroundService(userId));
  }

  Future<void> _register(String username, String password) async {
    if (!AppSecurity.isValidUsername(username)) {
      throw Exception(
        'Username must be 3-24 chars, letters/numbers/underscore only.',
      );
    }
    if (!AppSecurity.isValidPassword(password)) {
      throw Exception('Password must be at least 6 characters.');
    }

    final normalizedUsername = username.trim().toLowerCase();
    final response = await Supabase.instance.client.auth.signUp(
      email: _internalEmail(normalizedUsername),
      password: password,
      data: {'username': normalizedUsername},
    );

    final userId = response.user?.id;
    if (userId == null) {
      throw Exception('Registration did not return a valid user ID.');
    }
    if (response.session == null) {
      throw Exception(
        'Registration succeeded, but Supabase requires email confirmation. '
        'Disable Confirm email in Supabase Auth settings, then sign in.',
      );
    }

    await _rememberCurrentSession(userId, username: normalizedUsername);
    if (!mounted) return;
    setState(() => _currentUserId = userId);
    unawaited(_startBackgroundService(userId));
  }

  Future<void> _switchAccount() async {
    final accounts = await _savedAccounts();
    if (!mounted) return;
    final selectedId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fiókváltás'),
        content: SizedBox(
          width: double.maxFinite,
          child: accounts.isEmpty
              ? const Text('Még nincs mentett fiók.')
              : ListView(
                  shrinkWrap: true,
                  children: accounts.entries.map((entry) {
                    final data = entry.value is Map ? entry.value as Map : const {};
                    final name = data['username']?.toString() ?? 'Mentett fiók';
                    return ListTile(
                      leading: const Icon(Icons.account_circle_outlined),
                      title: Text(name),
                      subtitle: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(dialogContext, entry.key),
                    );
                  }).toList(),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Mégse'))],
      ),
    );
    if (selectedId == null || selectedId == _currentUserId) return;
    final data = accounts[selectedId];
    final refreshToken = data is Map ? data['refreshToken'] as String? : null;
    if (refreshToken == null || refreshToken.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ehhez a fiókhoz nincs mentett munkamenet. Jelentkezz be újra.'),
        ),
      );
      return;
    }
    try {
      // Preserve the current account before changing the single active Supabase session.
      if (_currentUserId != null) await _rememberCurrentSession(_currentUserId!);
      final response = await Supabase.instance.client.auth.setSession(refreshToken);
      final userId = response.user?.id;
      if (userId == null) throw Exception('A fiók munkamenete lejárt. Jelentkezz be újra.');
      await _rememberCurrentSession(userId);
      if (!mounted) return;
      setState(() => _currentUserId = userId);
      unawaited(_startBackgroundService(userId));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nem sikerült fiókot váltani: $error')));
    }
  }

  Future<void> _logout() async {
    if (_currentUserId != null) await _rememberCurrentSession(_currentUserId!);
    await _stopBackgroundService();
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    await _storage.delete(key: 'bluchet_user_id');
    if (!mounted) return;
    setState(() => _currentUserId = null);
  }

  Future<void> _onAccountDeleted() async {
    await _stopBackgroundService();
    try {
      if (_currentUserId != null) {
        final accounts = await _savedAccounts();
        accounts.remove(_currentUserId);
        await _storage.write(key: _accountsKey, value: jsonEncode(accounts));
        if (await _storage.read(key: _lastAccountKey) == _currentUserId) {
          await _storage.delete(key: _lastAccountKey);
        }
      }
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The account may already be deleted, so clear the local session anyway.
    }
    await _storage.delete(key: 'bluchet_user_id');
    if (!mounted) return;
    setState(() => _currentUserId = null);
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return MaterialApp(
        theme: BluchetTheme.light(),
        home: const Scaffold(
          backgroundColor: BluchetPalette.background,
          body: Center(child: _BluchetLoadingAnimation()),
        ),
      );
    }

    if (_currentUserId == null) {
      return MaterialApp(
        theme: BluchetTheme.light(),
        home: AuthScreen(onLogin: _login, onRegister: _register),
      );
    }

    return MaterialApp(
      theme: BluchetTheme.light(),
      home: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        builder: (context, opacity, child) => Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, (1 - opacity) * 8),
            child: child,
          ),
        ),
        child: ChatScreen(
          // Recreate all per-account state (E2EE keys, WebRTC controller,
          // listeners and conversation cache) when the signed-in user changes.
          key: ValueKey<String>(_currentUserId!),
          currentUserId: _currentUserId!,
          onSwitchAccount: _switchAccount,
          onLogout: _logout,
          onAccountDeleted: _onAccountDeleted,
        ),
      ),
    );
  }
}

class _BluchetLoadingAnimation extends StatelessWidget {
  const _BluchetLoadingAnimation();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.72, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.scale(scale: value, child: child),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/app_icon.png',
              width: 76,
              height: 76,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.chat_bubble_rounded,
                size: 64,
                color: BluchetPalette.primary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Bluchet',
            style: TextStyle(
              color: BluchetPalette.text,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: BluchetPalette.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  final Future<void> Function(String username, String password) onLogin;
  final Future<void> Function(String username, String password) onRegister;

  const AuthScreen({
    super.key,
    required this.onLogin,
    required this.onRegister,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isRegister = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Username and password are required.');
      return;
    }
    if (!AppSecurity.isValidUsername(username)) {
      setState(() {
        _error =
            'Username must be 3-24 chars, letters/numbers/underscore only.';
      });
      return;
    }
    if (!AppSecurity.isValidPassword(password)) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      if (_isRegister) {
        await widget.onRegister(username, password);
      } else {
        await widget.onLogin(username, password);
      }
      TextInput.finishAutofillContext(shouldSave: true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BluchetPalette.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: BluchetPalette.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BluchetPalette.primary.withOpacity(0.15),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/app_icon.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.image_not_supported_outlined,
                            size: 30,
                            color: BluchetPalette.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Bluchet',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: BluchetPalette.text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AutofillGroup(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _usernameController,
                            style: const TextStyle(color: BluchetPalette.inputText),
                            autofillHints: const [AutofillHints.username],
                            keyboardType: TextInputType.text,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.none,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Username'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _passwordController,
                            style: const TextStyle(color: BluchetPalette.inputText),
                            autofillHints: const [AutofillHints.password],
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(labelText: 'Password'),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(color: BluchetPalette.error),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: Text(_isSubmitting ? 'Please wait…' : 'Continue'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              setState(() {
                                _isRegister = !_isRegister;
                                _error = null;
                              });
                            },
                      child: Text(
                        _isRegister
                            ? 'Already have an account? Login'
                            : 'Need an account? Register',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Basic one-to-one WebRTC voice call. Supabase stores signaling only; audio is
/// sent over WebRTC. A TURN server may be needed on restrictive networks.
class _VoiceCallController {
  _VoiceCallController({required this.userId, required this.onIncoming});
  final String userId;
  final void Function(Map<String, dynamic> call) onIncoming;
  final SupabaseClient _db = Supabase.instance.client;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RealtimeChannel? _callChannel;
  RealtimeChannel? _candidateChannel;
  StreamSubscription<List<Map<String, dynamic>>>? _incomingSub;
  String? callId;
  bool muted = false;
  bool speaker = true;
  bool _handlingRemoteCandidates = false;
  bool _hasRemoteDescription = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  Future<void> listenForIncoming() async {
    _incomingSub?.cancel();
    _incomingSub = _db.from('voice_calls').stream(primaryKey: ['id']).listen((rows) {
      for (final row in rows) {
        if (row['callee_id'] == userId && row['status'] == 'ringing' && callId == null) {
          onIncoming(Map<String, dynamic>.from(row));
          break;
        }
      }
    }, onError: (Object e) => debugPrint('Incoming call listener: $e'));
  }

  Future<void> _preparePeer(String id) async {
    callId = id;
    _hasRemoteDescription = false;
    _pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
    } catch (error) {
      // Clean up the partially-created peer connection so another call can be
      // attempted after the user grants microphone access in Android settings.
      await _disposeMedia();
      final details = error.toString();
      if (details.contains('NotAllowedError') ||
          details.contains('Permission') ||
          details.contains('permission')) {
        throw Exception(
          'A mikrofon használatához engedély szükséges. '
          'Ellenőrizd az Android Beállítások > Alkalmazások > Bluchet > '
          'Engedélyek > Mikrofon részt, majd próbáld újra. '
          'Ritkán az AndroidManifest.xml RECORD_AUDIO engedélye is hiányozhat. '
          'Részlet: $details',
        );
      }
      throw Exception('Nem sikerült elindítani a mikrofont: $details');
    }
    for (final track in _localStream!.getAudioTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    _pc!.onIceCandidate = (candidate) async {
      if (candidate.candidate == null || callId != id) return;
      try {
        await _db.from('voice_call_candidates').insert({
          'call_id': id,
          'sender_id': userId,
          'candidate': candidate.candidate,
          'sdp_mid': candidate.sdpMid,
          'sdp_mline_index': candidate.sdpMLineIndex,
        });
      } catch (e) {
        debugPrint('ICE candidate send failed: $e');
      }
    };
    _candidateChannel = _db.channel('voice-candidates-$id-$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'voice_call_candidates',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'call_id', value: id),
        callback: (payload) async {
          final row = payload.newRecord;
          if (row['sender_id'] == userId) return;
          final candidate = RTCIceCandidate(
            row['candidate']?.toString(),
            row['sdp_mid']?.toString(),
            row['sdp_mline_index'] is int ? row['sdp_mline_index'] as int : int.tryParse('${row['sdp_mline_index']}'),
          );
          try {
            if (_hasRemoteDescription) {
              await _pc!.addCandidate(candidate);
            } else {
              _pendingCandidates.add(candidate);
            }
          } catch (e) { debugPrint('ICE candidate receive failed: $e'); }
        },
      )
      ..subscribe();
  }

  Future<void> _flushCandidates() async {
    final queued = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final c in queued) {
      try { await _pc?.addCandidate(c); } catch (_) {}
    }
  }

  Future<String> startCall({required String conversationId, required String calleeId}) async {
    if (callId != null) throw Exception('Már van aktív hívás.');
    final row = await _db.from('voice_calls').insert({
      'conversation_id': conversationId,
      'caller_id': userId,
      'callee_id': calleeId,
      'status': 'ringing',
    }).select('id').single();
    final id = row['id'].toString();
    try {
      await _preparePeer(id);
    } catch (error) {
      try {
        await _db.from('voice_calls').update({'status': 'ended'}).eq('id', id);
      } catch (cleanupError) {
        debugPrint('Failed to close unsuccessful call row: $cleanupError');
      }
      rethrow;
    }
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    await _db.from('voice_calls').update({'offer_sdp': offer.sdp}).eq('id', id);
    _watchCall(id);
    return id;
  }

  void _watchCall(String id) {
    _callChannel?.unsubscribe();
    _callChannel = _db.channel('voice-call-$id-$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'voice_calls',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
        callback: (payload) async {
          final row = payload.newRecord;
          if (row['status'] == 'ended' || row['status'] == 'declined' || row['status'] == 'missed') {
            await _disposeMedia();
          } else if (row['answer_sdp'] != null &&
              !_hasRemoteDescription &&
              row['caller_id'] == userId) {
            try {
              await _pc!.setRemoteDescription(
                RTCSessionDescription(row['answer_sdp'].toString(), 'answer'),
              );
              _hasRemoteDescription = true;
              await _flushCandidates();
            } catch (e) { debugPrint('Call answer failed: $e'); }
          }
        },
      )
      ..subscribe();
  }

  Future<void> acceptCall(Map<String, dynamic> row) async {
    final id = row['id'].toString();
    await _preparePeer(id);
    final offerText = row['offer_sdp']?.toString();
    if (offerText == null || offerText.isEmpty) throw Exception('A hívás ajánlata még nem érkezett meg.');
    await _pc!.setRemoteDescription(
      RTCSessionDescription(offerText, 'offer'),
    );
    _hasRemoteDescription = true;
    await _flushCandidates();
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await _db.from('voice_calls').update({'answer_sdp': answer.sdp, 'status': 'active'}).eq('id', id);
    _watchCall(id);
  }

  Future<void> declineCall(String id) async {
    await _db.from('voice_calls').update({'status': 'declined'}).eq('id', id);
  }

  Future<void> endCall() async {
    final id = callId;
    if (id != null) {
      try { await _db.from('voice_calls').update({'status': 'ended'}).eq('id', id); } catch (_) {}
    }
    await _disposeMedia();
  }

  Future<void> toggleMute() async {
    muted = !muted;
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await Helper.setSpeakerphoneOn(speaker);
  }

  Future<void> _disposeMedia() async {
    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) { await track.stop(); }
      await stream.dispose();
    }
    await _pc?.close();
    _pc = null;
    _hasRemoteDescription = false;
    await _candidateChannel?.unsubscribe();
    _candidateChannel = null;
    await _callChannel?.unsubscribe();
    _callChannel = null;
    callId = null;
    _pendingCandidates.clear();
    muted = false;
    speaker = true;
  }

  Future<void> dispose() async {
    await _incomingSub?.cancel();
    await endCall();
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final iconSize = large ? 34.0 : 30.0;
    final circleSize = large ? 82.0 : 68.0;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: circleSize,
                height: circleSize,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withOpacity(.18), blurRadius: 20, spreadRadius: 2)],
                ),
                child: Icon(icon, size: iconSize, color: const Color(0xFF07121B)),
              ),
              const SizedBox(height: 10),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(color: BluchetPalette.text, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final Future<void> Function() onLogout;
  final Future<void> Function() onSwitchAccount;
  final Future<void> Function() onAccountDeleted;

  const ChatScreen({
    super.key,
    required this.currentUserId,
    required this.onLogout,
    required this.onSwitchAccount,
    required this.onAccountDeleted,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final _BluchetE2ee _e2ee;
  late final _VoiceCallController _voiceCall;
  Map<String, dynamic>? _incomingCall;
  bool _callActive = false;
  bool _callStarting = false;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final Set<String> _groupInviteIds = <String>{};

  bool _loading = true;
  String? _error;
  bool _isAdmin = false;
  bool _checkingAdmin = true;
  bool _grantingAdmin = false;
  final TextEditingController _adminUsernameController = TextEditingController();
  List<_UserSearchResult> _searchResults = const [];
  int _searchRequestGeneration = 0;
  bool _searchingUsers = false;
  String? _searchError;
  List<_Conversation> _conversations = const [];
  final Map<String, int> _unreadCounts = <String, int>{};
  _Conversation? _selectedConversation;
  List<_Message> _messages = const [];
  final Map<String, String> _senderUsernames = <String, String>{};
  bool _showConversationScreen = false;
  int _messageLoadGeneration = 0;
  Timer? _messageRefreshTimer;
  bool _pollingMessages = false;
  int _activityRefreshTicks = 0;
  static const int _messagePageSize = 10;
  bool _loadingOlderMessages = false;
  bool _hasOlderMessages = true;
  String? _paginationConversationId;

  @override
  void initState() {
    super.initState();
    // Ask only after the signed-in chat screen is visible, not on the login screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_requestNotificationPermission());
    });
    _e2ee = _BluchetE2ee(widget.currentUserId, const FlutterSecureStorage());
    unawaited(_refreshAdminStatus());
    // Generate/load and register this account's E2EE key automatically.
    // Failures remain retryable and are surfaced instead of silently ignored.
    _e2ee.ensureReady().catchError((Object error) {
      if (mounted) _showError('Titkosítási kulcs regisztrációja sikertelen: $error');
    });
    _voiceCall = _VoiceCallController(userId: widget.currentUserId, onIncoming: (call) {
      if (!mounted || _incomingCall != null || _callActive) return;
      final callerId = call['caller_id']?.toString() ?? '';
      _loadUsernames(callerId.isEmpty ? <String>[] : <String>[callerId])
          .then((names) {
        final callerName = names[callerId] ?? 'Ismeretlen felhasználó';
        _showLocalNotification(
          id: 700001,
          title: 'Bejövő Bluchet-hívás',
          body: '$callerName hív téged.',
        );
      }).catchError((Object _) {
        _showLocalNotification(
          id: 700001,
          title: 'Bejövő Bluchet-hívás',
          body: 'Valaki hanghívást indított.',
        );
      });
      setState(() => _incomingCall = call);
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showIncomingCallDialog(call); });
    });
    _voiceCall.listenForIncoming();
    // E2EE initialization is already started above. Avoid starting a second
    // duplicate error handler for the same Future.
    _refreshConversations();

    // Poll only the currently open conversation. This makes incoming messages
    // appear even when Realtime is not configured for the messages table.
    _messageRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _activityRefreshTicks++;
      if (_activityRefreshTicks >= 10) {
        _activityRefreshTicks = 0;
        _refreshConversationActivity();
      }

      final conversationId = _selectedConversation?.id;
      if (conversationId == null || _pollingMessages) return;
      _pollingMessages = true;
      _loadMessages(conversationId, scrollToBottom: false).whenComplete(() {
        _pollingMessages = false;
      });
    });
  }


  @override
  void dispose() {
    _messageRefreshTimer?.cancel();
    _voiceCall.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _messageController.dispose();
    _groupNameController.dispose();
    _adminUsernameController.dispose();
    super.dispose();
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error.toString().replaceFirst('Exception: ', '');
    });
  }

  Future<Map<String, String>> _loadUsernames(List<String> userIds) async {
    if (userIds.isEmpty) return <String, String>{};
    final response = await Supabase.instance.client.rpc(
      'get_usernames_for_current_user',
      params: {'p_user_ids': userIds},
    );
    if (response is! List) {
      throw Exception('Username lookup returned an unexpected response.');
    }
    final names = <String, String>{};
    for (final item in response) {
      final row = Map<String, dynamic>.from(item as Map);
      final id = row['id']?.toString();
      final username = row['username']?.toString().trim();
      if (id != null && username != null && username.isNotEmpty) {
        names[id] = username;
      }
    }
    return names;
  }

  Future<void> _searchUsers(String term) async {
    // Every keystroke invalidates earlier requests. A slow response for an
    // older term must never replace results for the latest term.
    final requestGeneration = ++_searchRequestGeneration;
    final cleaned = term.trim();

    if (cleaned.length < 2) {
      if (!mounted) return;
      setState(() {
        _searchResults = const [];
        _searchingUsers = false;
        _searchError = cleaned.isEmpty ? null : 'Type at least 2 characters.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _searchingUsers = true;
      _searchError = null;
      _searchResults = const [];
    });

    try {
      final response = await Supabase.instance.client.rpc(
        'search_profiles',
        params: {'search_term': cleaned.toLowerCase()},
      );

      if (!mounted || requestGeneration != _searchRequestGeneration) return;
      if (response is! List) {
        throw const FormatException('Unexpected search response.');
      }

      final results = <_UserSearchResult>[];
      final seenIds = <String>{};
      for (final item in response) {
        if (item is! Map) continue;
        final userId = item['id']?.toString();
        final username = item['username']?.toString().trim();
        if (userId == null ||
            username == null ||
            username.isEmpty ||
            userId == widget.currentUserId ||
            !seenIds.add(userId)) {
          continue;
        }
        results.add(_UserSearchResult(userId: userId, username: username));
      }

      if (!mounted || requestGeneration != _searchRequestGeneration) return;
      setState(() {
        _searchResults = results;
        _searchingUsers = false;
        _searchError = null;
      });
    } catch (error) {
      if (!mounted || requestGeneration != _searchRequestGeneration) return;
      setState(() {
        _searchResults = const [];
        _searchingUsers = false;
        _searchError = 'User search failed. Check your connection and try again.';
      });
      // Keep the raw error available for debugging without exposing database
      // details in the UI.
      debugPrint('Bluchet user search failed: $error');
    }
  }

  void _toggleGroupInvite(String userId) {
    setState(() {
      if (_groupInviteIds.contains(userId)) {
        _groupInviteIds.remove(userId);
      } else {
        _groupInviteIds.add(userId);
      }
    });
  }

  Future<void> _createGroupConversation() async {
    if (_groupInviteIds.isEmpty) {
      setState(() => _error = 'At least one other member is required.');
      return;
    }

    final groupTitle = _groupNameController.text.trim();
    final memberIds = <String>{..._groupInviteIds, widget.currentUserId}.toList();

    try {
      final response = await Supabase.instance.client.rpc(
        'create_group_conversation_for_current_user',
        params: {
          'p_member_ids': memberIds,
          'p_title': groupTitle.isEmpty ? 'Group chat' : groupTitle,
        },
      );
      final conversationId = response.toString();
      if (conversationId.isEmpty || conversationId == 'null') {
        throw Exception('Group creation did not return a conversation ID.');
      }

      _groupNameController.clear();
      _groupInviteIds.clear();
      await _refreshConversations();

      if (!mounted) return;
      final title = groupTitle.isEmpty ? 'Group chat' : groupTitle;
      setState(() {
        _showConversationScreen = true;
        _selectedConversation = _Conversation(
          id: conversationId,
          otherUserId: widget.currentUserId,
          otherUsername: 'Group',
          isGroup: true,
          title: title,
          createdBy: widget.currentUserId,
          memberIds: memberIds,
        );
        _messages = const [];
        _error = null;
      });
      await _loadMessages(conversationId);
    } catch (error) {
      _showError(error);
    }
  }

  Future<List<_UserSearchResult>> _loadGroupMembers(String conversationId) async {
    final List<dynamic> rows = await Supabase.instance.client
        .from('conversation_participants')
        .select('user_id')
        .eq('conversation_id', conversationId);

    final memberIds = rows
        .map((item) => (item as Map<String, dynamic>)['user_id'] as String)
        .toList();
    if (memberIds.isEmpty) return const [];

    // Resolve names through a narrowly scoped SECURITY DEFINER RPC.
    final usernameById = await _loadUsernames(memberIds);

    return memberIds
        .map((id) => _UserSearchResult(
              userId: id,
              username: usernameById[id] ?? 'Unknown user',
            ))
        .toList();
  }

  Future<void> _inviteUsersToGroup(_Conversation group) async {
    final inviteIds = <String>{};
    _searchController.clear();
    _searchResults = const [];
    _searchError = null;
    _searchingUsers = false;
    _searchRequestGeneration++;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setDialogState) => AlertDialog(
          title: const Text('Invite members'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: BluchetPalette.inputText),
                  decoration: const InputDecoration(
                    hintText: 'Search user...',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) async {
                    await _searchUsers(value);
                    setDialogState(() {});
                  },
                ),
                if (_searchingUsers)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_searchError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _searchError!,
                      style: const TextStyle(color: BluchetPalette.error),
                    ),
                  ),
                if (!_searchingUsers &&
                    _searchError == null &&
                    _searchController.text.trim().length >= 2 &&
                    _searchResults.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No users found.'),
                  ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final result = _searchResults[index];
                      if (result.userId == widget.currentUserId ||
                          group.memberIds.contains(result.userId)) {
                        return const SizedBox.shrink();
                      }
                      final selected = inviteIds.contains(result.userId);
                      return ListTile(
                        title: Text(result.username),
                        trailing: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.add_circle_outline,
                          color: selected
                              ? BluchetPalette.primary
                              : BluchetPalette.accent,
                        ),
                        onTap: () {
                          setDialogState(() {
                            if (selected) {
                              inviteIds.remove(result.userId);
                            } else {
                              inviteIds.add(result.userId);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final idsToInvite = inviteIds.toList();
                if (idsToInvite.isEmpty) {
                  Navigator.pop(dialogContext);
                  return;
                }

                try {
                  await Supabase.instance.client.rpc(
                    'invite_users_to_group_for_current_user',
                    params: {
                      'p_conversation_id': group.id,
                      'p_user_ids': idsToInvite,
                    },
                  );
                  await _refreshConversations();
                  if (!mounted) return;
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  setState(() => _selectedConversation = group);
                } catch (error) {
                  _showError(error);
                }
              },
              child: const Text('Invite'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshConversations() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<dynamic> participantRows = await Supabase.instance.client
          .from('conversation_participants')
          .select('conversation_id, user_id')
          .eq('user_id', widget.currentUserId);

      // A conversation may appear more than once in the participant query.
      // Build a stable, unique list before fetching conversation metadata.
      final conversationIds = participantRows
          .map((item) =>
              (item as Map<String, dynamic>)['conversation_id'] as String)
          .toSet()
          .toList();

      if (conversationIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _conversations = const [];
          _selectedConversation = null;
          _messages = const [];
          _loading = false;
        });
        return;
      }

      // Fetch unread counts independently so a missing/unapplied unread SQL
      // migration cannot prevent the conversation list itself from loading.
      try {
        final unreadResponse = await Supabase.instance.client.rpc(
          'get_unread_counts_for_current_user',
        );
        if (unreadResponse is List) {
          _unreadCounts
            ..clear()
            ..addEntries(unreadResponse.map((item) {
              final row = Map<String, dynamic>.from(item as Map);
              return MapEntry(
                row['conversation_id'].toString(),
                int.tryParse(row['unread_count'].toString()) ?? 0,
              );
            }));
        }
      } catch (_) {
        // Unread badges stay hidden until the SQL migration is installed.
      }

      final List<dynamic> conversationRows = await Supabase.instance.client
          .from('conversations')
          .select('id, title, is_direct, created_by')
          .inFilter('id', conversationIds);

      final conversationMap = <String, Map<String, dynamic>>{
        for (final row in conversationRows)
          (row as Map<String, dynamic>)['id'] as String: row,
      };

      final conversations = <_Conversation>[];
      for (final item in participantRows) {
        final map = item as Map<String, dynamic>;
        final conversationId = map['conversation_id'] as String;
        final meta = conversationMap[conversationId];
        final title = meta?['title'] as String?;
        // Group/direct classification comes from the database flag, never
        // from the title: direct chats can also have custom titles.
        final isGroup = meta?['is_direct'] == false;

        if (isGroup) {
          final members = await _loadGroupMembers(conversationId);
          conversations.add(
            _Conversation(
              id: conversationId,
              otherUserId: widget.currentUserId,
              otherUsername: 'Group',
              isGroup: true,
              title: title ?? 'Group chat',
              createdBy: meta?['created_by']?.toString(),
              memberIds: members.map((member) => member.userId).toList(),
            ),
          );
          continue;
        }

        final List<dynamic> participants = await Supabase.instance.client
            .from('conversation_participants')
            .select('conversation_id, user_id')
            .eq('conversation_id', conversationId);

        Map<String, dynamic>? otherParticipant;
        for (final element in participants) {
          final candidate = element as Map<String, dynamic>;
          if (candidate['user_id'] != widget.currentUserId) {
            otherParticipant = candidate;
            break;
          }
        }
        if (otherParticipant == null) continue;

        final otherUserId = otherParticipant['user_id'] as String;
        final usernameById = await _loadUsernames([otherUserId]);
        final username = usernameById[otherUserId] ?? 'Unknown user';

        conversations.add(
          _Conversation(
            id: conversationId,
            otherUserId: otherUserId,
            otherUsername: username,
          ),
        );
      }

      if (!mounted) return;
      // Defensive de-duplication prevents repeated participant rows from
      // creating duplicate entries in the chat list.
      final uniqueConversations = <String, _Conversation>{
        for (final conversation in conversations)
          conversation.id: conversation,
      }.values.toList();
      // Sort using the timestamp of each conversation's newest message.
      // The timestamp is read from Supabase (not guessed from local send time),
      // and conversations with no messages remain at the bottom.
      final activityByConversation = <String, DateTime>{};
      for (final conversation in uniqueConversations) {
        try {
          final latestMessage = await Supabase.instance.client
              .from('messages')
              .select('created_at')
              .eq('conversation_id', conversation.id)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          final createdAt = latestMessage?['created_at'];
          if (createdAt != null) {
            final parsed = DateTime.tryParse(createdAt.toString());
            if (parsed != null) {
              activityByConversation[conversation.id] = parsed;
            }
          }
        } catch (_) {
          // Keep the list usable if message timestamps are not readable.
        }
      }
      final conversationsWithActivity = uniqueConversations.map((conversation) {
        return _Conversation(
          id: conversation.id,
          otherUserId: conversation.otherUserId,
          otherUsername: conversation.otherUsername,
          isGroup: conversation.isGroup,
          title: conversation.title,
          createdBy: conversation.createdBy,
          memberIds: conversation.memberIds,
          lastActivityAt: activityByConversation[conversation.id],
        );
      }).toList();
      conversationsWithActivity.sort((a, b) {
        final aTime = a.lastActivityAt;
        final bTime = b.lastActivityAt;
        if (aTime == null && bTime != null) return 1;
        if (aTime != null && bTime == null) return -1;
        if (aTime != null && bTime != null) {
          final byActivity = bTime.compareTo(aTime);
          if (byActivity != 0) return byActivity;
        }
        return a.id.compareTo(b.id);
      });

      final previousSelectedId = _selectedConversation?.id;
      final selectedStillExists = conversationsWithActivity.any(
        (conversation) => conversation.id == previousSelectedId,
      );
      final nextSelected = selectedStillExists
          ? conversationsWithActivity.firstWhere(
              (conversation) => conversation.id == previousSelectedId,
            )
          : (conversationsWithActivity.isNotEmpty ? conversationsWithActivity.first : null);
      final selectionChanged = nextSelected?.id != previousSelectedId;
      setState(() {
        _conversations = conversationsWithActivity;
        _selectedConversation = nextSelected;
        if (selectionChanged) _messages = const [];
        _loading = false;
      });
      if (selectionChanged) {
        // Invalidate any pending response for the previous chat.
        _messageLoadGeneration++;
      }

      if (_selectedConversation != null) {
        await _loadMessages(_selectedConversation!.id);
      } else if (mounted) {
        setState(() => _messages = const []);
      }
    } catch (error) {
      _showError(error);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshConversationActivity() async {
    final current = List<_Conversation>.from(_conversations);
    if (!mounted || current.isEmpty) return;

    final activityByConversation = <String, DateTime>{};
    for (final conversation in current) {
      try {
        final latestMessage = await Supabase.instance.client
            .from('messages')
            .select('created_at')
            .eq('conversation_id', conversation.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        final createdAt = latestMessage?['created_at'];
        if (createdAt != null) {
          final parsed = DateTime.tryParse(createdAt.toString());
          if (parsed != null) activityByConversation[conversation.id] = parsed;
        }
      } catch (_) {
        // Preserve the current order if activity cannot be read.
      }
    }

    if (!mounted) return;
    final updated = current.map((conversation) {
      return _Conversation(
        id: conversation.id,
        otherUserId: conversation.otherUserId,
        otherUsername: conversation.otherUsername,
        isGroup: conversation.isGroup,
        title: conversation.title,
        createdBy: conversation.createdBy,
        memberIds: conversation.memberIds,
        lastActivityAt: activityByConversation[conversation.id],
      );
    }).toList();
    updated.sort((a, b) {
      final aTime = a.lastActivityAt;
      final bTime = b.lastActivityAt;
      if (aTime == null && bTime != null) return 1;
      if (aTime != null && bTime == null) return -1;
      if (aTime != null && bTime != null) {
        final byActivity = bTime.compareTo(aTime);
        if (byActivity != 0) return byActivity;
      }
      return a.id.compareTo(b.id);
    });

    setState(() {
      _conversations = updated;
      final selectedId = _selectedConversation?.id;
      if (selectedId != null) {
        for (final conversation in updated) {
          if (conversation.id == selectedId) {
            _selectedConversation = conversation;
            break;
          }
        }
      }
    });
  }

  Future<void> _openConversation({
    required String userId,
    required String username,
  }) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_or_create_direct_conversation_for_current_user',
        params: {'other_user': userId},
      );
      final conversationId = response.toString();

      await _refreshConversations();
      if (!mounted) return;
      setState(() {
        _showConversationScreen = true;
        _selectedConversation = _Conversation(
          id: conversationId,
          otherUserId: userId,
          otherUsername: username,
        );
        _messages = const [];
        _error = null;
        _searchController.clear();
        _searchResults = const [];
        _searchError = null;
        _searchingUsers = false;
        _searchRequestGeneration++;
      });
      await _loadMessages(conversationId);
    } catch (error) {
      _showError(error);
    }
  }

  Future<List<_Message>> _decodeMessageRows(
    String conversationId,
    List<dynamic> rows,
  ) async {
    final decoded = <_Message>[];
    for (final item in rows) {
      final map = Map<String, dynamic>.from(item as Map);
      decoded.add(
        _Message(
          id: map['id'].toString(),
          senderId: map['sender_id'].toString(),
          text: await _e2ee.decryptMessage(
            conversationId: conversationId,
            senderId: map['sender_id'].toString(),
            storedText: (map['ciphertext'] ?? '').toString(),
          ),
          createdAt: DateTime.tryParse(
                (map['created_at'] ?? '').toString(),
              ) ??
              DateTime.now(),
        ),
      );
    }
    decoded.sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
    return decoded;
  }

  Future<void> _loadMessages(
    String conversationId, {
    bool scrollToBottom = true,
  }) async {
    // First load only the newest page. Polling refreshes that page and merges
    // it with older pages already loaded by scrolling upward.
    if (_paginationConversationId != conversationId) {
      _paginationConversationId = conversationId;
      _hasOlderMessages = true;
      _loadingOlderMessages = false;
    }
    final requestGeneration = ++_messageLoadGeneration;
    try {
      final response = await Supabase.instance.client.rpc(
        'get_messages_page_for_current_user',
        params: {
          'p_conversation_id': conversationId,
          'p_before_created_at': null,
          'p_before_id': null,
          'p_page_size': _messagePageSize,
        },
      );
      if (response is! List) {
        throw Exception('The message query returned an unexpected response.');
      }
      final pageMessages = await _decodeMessageRows(conversationId, response);

      final senderIds = pageMessages.map((message) => message.senderId).toSet().toList();
      final resolvedNames = <String, String>{};
      if (senderIds.isNotEmpty) {
        try {
          resolvedNames.addAll(await _loadUsernames(senderIds));
        } catch (_) {
          // Messages remain readable if username lookup is temporarily unavailable.
        }
      }

      if (!mounted ||
          requestGeneration != _messageLoadGeneration ||
          _selectedConversation?.id != conversationId) {
        return;
      }

      final previousMessages = _messages;
      final previousIds = previousMessages.map((message) => message.id).toSet();
      if (!scrollToBottom && previousMessages.isNotEmpty) {
        final incoming = pageMessages.where((message) =>
            !previousIds.contains(message.id) &&
            message.senderId != widget.currentUserId).toList();
        for (final message in incoming) {
          final sender = resolvedNames[message.senderId] ?? 'Új üzenet';
          final preview = message.text.length > 120
              ? '${message.text.substring(0, 120)}…'
              : message.text;
          await _showLocalNotification(
            id: message.id.hashCode & 0x7fffffff,
            title: sender,
            body: preview,
          );
        }
      }

      final mergedById = <String, _Message>{
        for (final message in previousMessages) message.id: message,
        for (final message in pageMessages) message.id: message,
      };
      final mergedMessages = mergedById.values.toList()
        ..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          if (byTime != 0) return byTime;
          return a.id.compareTo(b.id);
        });

      setState(() {
        _messages = mergedMessages;
        _senderUsernames.addAll(resolvedNames);
        // On the first page, fewer than 10 rows means the history is complete.
        if (previousMessages.isEmpty) {
          _hasOlderMessages = pageMessages.length >= _messagePageSize;
        }
        _error = null;
        _unreadCounts[conversationId] = 0;
      });

      try {
        await Supabase.instance.client.rpc(
          'mark_conversation_read_for_current_user',
          params: {'p_conversation_id': conversationId},
        );
      } catch (_) {
        // The read marker is optional and must not hide messages.
      }

      if (scrollToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                !_scrollController.hasClients ||
                requestGeneration != _messageLoadGeneration ||
                _selectedConversation?.id != conversationId) {
              return;
            }
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          });
        });
      }
    } catch (error) {
      if (mounted &&
          requestGeneration == _messageLoadGeneration &&
          _selectedConversation?.id == conversationId) {
        _showError(error);
      }
    }
  }

  Future<void> _loadOlderMessages() async {
    final conversationId = _selectedConversation?.id;
    if (conversationId == null ||
        _loadingOlderMessages ||
        !_hasOlderMessages ||
        _messages.isEmpty) {
      return;
    }

    final oldest = _messages.first;
    setState(() => _loadingOlderMessages = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'get_messages_page_for_current_user',
        params: {
          'p_conversation_id': conversationId,
          'p_before_created_at': oldest.createdAt.toUtc().toIso8601String(),
          'p_before_id': oldest.id,
          'p_page_size': _messagePageSize,
        },
      );
      if (response is! List) {
        throw Exception('The older-message query returned an unexpected response.');
      }
      final olderMessages = await _decodeMessageRows(conversationId, response);
      final senderIds = olderMessages.map((message) => message.senderId).toSet().toList();
      final resolvedNames = <String, String>{};
      if (senderIds.isNotEmpty) {
        try {
          resolvedNames.addAll(await _loadUsernames(senderIds));
        } catch (_) {}
      }
      if (!mounted || _selectedConversation?.id != conversationId) return;

      // Keep the same visible message on screen after adding rows above it.
      final oldPixels = _scrollController.hasClients
          ? _scrollController.position.pixels
          : 0.0;
      final oldMaxExtent = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;
      final mergedById = <String, _Message>{
        for (final message in _messages) message.id: message,
        for (final message in olderMessages) message.id: message,
      };
      final mergedMessages = mergedById.values.toList()
        ..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          if (byTime != 0) return byTime;
          return a.id.compareTo(b.id);
        });
      setState(() {
        _messages = mergedMessages;
        _senderUsernames.addAll(resolvedNames);
        _hasOlderMessages = olderMessages.length >= _messagePageSize;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_scrollController.hasClients ||
            _selectedConversation?.id != conversationId) return;
        final addedExtent = _scrollController.position.maxScrollExtent - oldMaxExtent;
        final target = (oldPixels + addedExtent).clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(target.toDouble());
      });
    } catch (error) {
      if (mounted && _selectedConversation?.id == conversationId) {
        _showError(error);
      }
    } finally {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

  Future<void> _showIncomingCallDialog(Map<String, dynamic> call) async {
    if (!mounted) return;
    final callerId = call['caller_id']?.toString() ?? '';
    String callerName = 'Bejövő hívás';
    try { callerName = (await _loadUsernames([callerId]))[callerId] ?? callerName; } catch (_) {}
    if (!mounted || _incomingCall?['id'] != call['id']) return;
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: BluchetPalette.background,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                children: [
                  const Align(alignment: Alignment.topLeft, child: Icon(Icons.graphic_eq, color: BluchetPalette.accent, size: 30)),
                  const Spacer(),
                  Container(
                    width: 156, height: 156,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF103743),
                      border: Border.all(color: BluchetPalette.accent.withOpacity(.7), width: 2),
                      boxShadow: [BoxShadow(color: BluchetPalette.accent.withOpacity(.14), blurRadius: 34, spreadRadius: 8)],
                    ),
                    child: const Icon(Icons.person_rounded, size: 86, color: BluchetPalette.accent),
                  ),
                  const SizedBox(height: 28),
                  Text(callerName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: BluchetPalette.text)),
                  const SizedBox(height: 10),
                  const Text('Bejövő hanghívás', style: TextStyle(fontSize: 16, color: BluchetPalette.textMuted)),
                  const SizedBox(height: 8),
                  const Text('BLUCHET  /  HÍVÁS', style: TextStyle(fontSize: 11, letterSpacing: 2.2, fontWeight: FontWeight.w700, color: BluchetPalette.accent)),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallActionButton(icon: Icons.call_end_rounded, label: 'Elutasítás', color: const Color(0xFFFF737D), onTap: () => Navigator.pop(ctx, false)),
                      _CallActionButton(icon: Icons.call_rounded, label: 'Fogadás', color: const Color(0xFF68E0A5), onTap: () => Navigator.pop(ctx, true)),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _incomingCall = null);
    if (accept != true) {
      try { await _voiceCall.declineCall(call['id'].toString()); } catch (e) { _showError(e); }
      return;
    }
    try {
      setState(() { _callStarting = true; _callActive = true; });
      await _voiceCall.acceptCall(call);
      if (mounted) setState(() => _callStarting = false);
      if (mounted) _showCallControls(callerName);
    } catch (e) {
      await _voiceCall.endCall();
      if (mounted) setState(() { _callActive = false; _callStarting = false; });
      _showError(e);
    }
  }

  Future<void> _startVoiceCall() async {
    final conversation = _selectedConversation;
    if (conversation == null || conversation.isGroup) {
      _showError('Hanghívás jelenleg csak négyszemközti beszélgetésben érhető el.');
      return;
    }
    if (_callStarting || _callActive) return;
    try {
      setState(() => _callStarting = true);
      await _voiceCall.startCall(conversationId: conversation.id, calleeId: conversation.otherUserId);
      if (!mounted) return;
      setState(() { _callStarting = false; _callActive = true; });
      _showCallControls(conversation.otherUsername);
    } catch (e) {
      await _voiceCall.endCall();
      if (mounted) setState(() { _callStarting = false; _callActive = false; });
      _showError(e);
    }
  }

  Future<void> _showCallControls(String peerName) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => Scaffold(
            backgroundColor: BluchetPalette.background,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  children: [
                    const Align(alignment: Alignment.topLeft, child: Icon(Icons.graphic_eq, color: BluchetPalette.accent, size: 30)),
                    const Spacer(),
                    Container(
                      width: 142, height: 142,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF103743),
                        border: Border.all(color: BluchetPalette.accent.withOpacity(.55), width: 2),
                      ),
                      child: const Icon(Icons.person_rounded, size: 78, color: BluchetPalette.accent),
                    ),
                    const SizedBox(height: 24),
                    Text(peerName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: BluchetPalette.text)),
                    const SizedBox(height: 10),
                    Text(
                      _voiceCall.callId == null ? 'Hívás befejezve' : (_callStarting ? 'Kapcsolódás…' : 'Hanghívás folyamatban'),
                      style: const TextStyle(fontSize: 15, color: BluchetPalette.textMuted),
                    ),
                    const SizedBox(height: 8),
                    const Text('BLUCHET  /  HÍVÁS', style: TextStyle(fontSize: 11, letterSpacing: 2.2, fontWeight: FontWeight.w700, color: BluchetPalette.accent)),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CallActionButton(
                          icon: _voiceCall.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          label: _voiceCall.muted ? 'Mikrofon be' : 'Némítás',
                          color: _voiceCall.muted ? BluchetPalette.accent : const Color(0xFF204451),
                          onTap: () async { await _voiceCall.toggleMute(); setDialogState(() {}); },
                        ),
                        _CallActionButton(
                          icon: _voiceCall.speaker ? Icons.volume_up_rounded : Icons.hearing_rounded,
                          label: _voiceCall.speaker ? 'Hangszóró' : 'Fülhallgató',
                          color: _voiceCall.speaker ? BluchetPalette.accent : const Color(0xFF204451),
                          onTap: () async { await _voiceCall.toggleSpeaker(); setDialogState(() {}); },
                        ),
                      ],
                    ),
                    const SizedBox(height: 34),
                    _CallActionButton(
                      icon: Icons.call_end_rounded,
                      label: 'Hívás befejezése',
                      color: const Color(0xFFFF737D),
                      large: true,
                      onTap: () async {
                        await _voiceCall.endCall();
                        if (mounted) setState(() { _callActive = false; _callStarting = false; });
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() { _callActive = false; _callStarting = false; });
  }

  Future<void> _deleteGroup(_Conversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(
          'This permanently deletes “${conversation.title}” and its messages for every member.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: BluchetPalette.error),
            child: const Text('Delete group'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.rpc(
        'delete_group_for_current_user',
        params: {'p_conversation_id': conversation.id},
      );
      if (!mounted) return;
      setState(() {
        _conversations = _conversations
            .where((item) => item.id != conversation.id)
            .toList();
        if (_selectedConversation?.id == conversation.id) {
          _selectedConversation = null;
          _messages = const [];
          _showConversationScreen = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group deleted.')),
      );
      await _refreshConversations();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account permanently?'),
        content: const Text(
          'Your account will be permanently deleted. Your profile and data linked to it may also be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: BluchetPalette.error),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.rpc('delete_my_account');
      await widget.onAccountDeleted();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _refreshAdminStatus() async {
    try {
      final result = await Supabase.instance.client.rpc('is_bluchet_admin');
      if (!mounted) return;
      setState(() {
        _isAdmin = result == true;
        _checkingAdmin = false;
      });
    } catch (error) {
      // Missing admin migration or denied access must never grant admin UI.
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
        _checkingAdmin = false;
      });
      debugPrint('Bluchet admin status unavailable: $error');
    }
  }

  Future<void> _showAdminManagementDialog() async {
    if (!_isAdmin || !mounted) return;
    _adminUsernameController.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Admin hozzáadása'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add meg a már regisztrált Bluchet-felhasználónevét.'),
                const SizedBox(height: 12),
                TextField(
                  controller: _adminUsernameController,
                  autofocus: true,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Felhasználónév',
                    hintText: 'pl. sea',
                  ),
                  onSubmitted: (_) async {
                    if (_grantingAdmin) return;
                    setDialogState(() => _grantingAdmin = true);
                    try {
                      await Supabase.instance.client.rpc(
                        'grant_bluchet_admin_by_username',
                        params: {
                          'p_username': _adminUsernameController.text.trim(),
                        },
                      );
                      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Az adminjogot sikeresen megadtuk.')),
                        );
                      }
                    } catch (error) {
                      if (dialogContext.mounted) {
                        setDialogState(() => _grantingAdmin = false);
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text('Nem sikerült adminná tenni: $error')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _grantingAdmin ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Mégse'),
            ),
            FilledButton.icon(
              onPressed: _grantingAdmin
                  ? null
                  : () async {
                      setDialogState(() => _grantingAdmin = true);
                      try {
                        await Supabase.instance.client.rpc(
                          'grant_bluchet_admin_by_username',
                          params: {
                            'p_username': _adminUsernameController.text.trim(),
                          },
                        );
                        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Az adminjogot sikeresen megadtuk.')),
                          );
                        }
                      } catch (error) {
                        if (dialogContext.mounted) setDialogState(() => _grantingAdmin = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Nem sikerült adminná tenni: $error')),
                          );
                        }
                      }
                    },
              icon: _grantingAdmin
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.admin_panel_settings),
              label: const Text('Admin hozzáadása'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMessage(_Message message) async {
    if (message.senderId != widget.currentUserId) {
      _showError('Csak a saját üzenetedet törölheted.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Üzenet törlése'),
        content: const Text('Biztosan törlöd ezt az üzenetet? Ez a művelet nem vonható vissza.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Mégse'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Törlés'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      // RLS must allow users to delete their own message rows only.
      final deletedRows = await Supabase.instance.client
          .from('messages')
          .delete()
          .eq('id', message.id)
          .eq('sender_id', widget.currentUserId)
          .select('id');
      if (deletedRows.isEmpty) {
        throw Exception('A szerver nem engedte a törlést (RLS), vagy az üzenet már nem létezik.');
      }
      final conversationId = _selectedConversation?.id;
      if (conversationId != null) await _loadMessages(conversationId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Üzenet törölve.')),
        );
      }
    } catch (error) {
      _showError('Nem sikerült törölni az üzenetet. Ellenőrizd a messages DELETE RLS-szabályát. $error');
    }
  }

  Future<void> _sendMessage() async {
    final conversation = _selectedConversation;
    final text = _messageController.text.trim();
    if (conversation == null || text.isEmpty) return;

    if (!AppSecurity.isValidMessage(text)) {
      setState(() => _error = 'Message is empty or too long.');
      return;
    }

    try {
      await _e2ee.ensureReady();
      final participantRows = await Supabase.instance.client
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', conversation.id);
      final memberIds = participantRows
          .map((row) => (row as Map<String, dynamic>)['user_id'].toString())
          .toSet()
          .toList();
      final encryptedPayload = await _e2ee.encryptForConversation(
        conversationId: conversation.id,
        plaintext: text,
        memberIds: memberIds,
      );
      await Supabase.instance.client.rpc(
        'insert_message_for_current_user',
        params: {
          'p_conversation_id': conversation.id,
          'p_ciphertext': encryptedPayload,
        },
      );

      _messageController.clear();
      await _loadMessages(conversation.id);
      await _refreshConversations();
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BluchetPalette.background,
      appBar: AppBar(
        leading: _showConversationScreen
            ? IconButton(
                tooltip: 'Back to conversations',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showConversationScreen = false),
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _showConversationScreen && _selectedConversation != null
                  ? (_selectedConversation!.isGroup
                      ? _selectedConversation!.title
                      : _selectedConversation!.otherUsername)
                  : 'Bluchet',
            ),
            if (_showConversationScreen)
              const _BluchetPulseIndicator(),
          ],
        ),
        actions: [
          if (_showConversationScreen &&
              _selectedConversation?.isGroup == true &&
              (_selectedConversation!.createdBy == widget.currentUserId ||
                  _selectedConversation!.createdBy == null))
            IconButton(
              tooltip: 'Delete group',
              icon: const Icon(Icons.delete_outline),
              color: BluchetPalette.error,
              onPressed: () => _deleteGroup(_selectedConversation!),
            ),
          if (_showConversationScreen && _selectedConversation?.isGroup == true)
            IconButton(
              onPressed: () async {
                final selected = _selectedConversation;
                if (selected == null) return;
                try {
                  final members = await _loadGroupMembers(selected.id);
                  if (!mounted) return;
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Group members'),
                      content: SizedBox(
                        width: 320,
                        child: members.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'No members found. Check Supabase access to conversation_participants and profiles.',
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: members.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) => ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: BluchetPalette.turquoise100,
                                    foregroundColor: BluchetPalette.primaryDark,
                                    child: Text(members[index].username.isEmpty
                                        ? '?'
                                        : members[index].username[0].toUpperCase()),
                                  ),
                                  title: Text(members[index].username),
                                  subtitle: members[index].userId == widget.currentUserId
                                      ? const Text('You')
                                      : null,
                                ),
                              ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                } catch (error) {
                  _showError(error);
                }
              },
              icon: const Icon(Icons.group),
            ),
          if (_showConversationScreen && _selectedConversation != null && !_selectedConversation!.isGroup)
            IconButton(
              tooltip: 'Hanghívás',
              onPressed: (_callStarting || _callActive) ? null : _startVoiceCall,
              icon: Icon(_callStarting ? Icons.hourglass_top : Icons.call),
              color: BluchetPalette.turquoise300,
            ),
          if (!_checkingAdmin && _isAdmin)
            IconButton(
              tooltip: 'Admin hozzáadása',
              onPressed: _showAdminManagementDialog,
              icon: const Icon(Icons.admin_panel_settings),
              color: BluchetPalette.turquoise300,
            ),
          IconButton(
            tooltip: 'Fiókváltás',
            onPressed: widget.onSwitchAccount,
            icon: const Icon(Icons.switch_account),
          ),
          IconButton(
            tooltip: 'Delete account',
            onPressed: _deleteAccount,
            icon: const Icon(Icons.person_remove_alt_1),
            color: BluchetPalette.error,
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _showConversationScreen && _selectedConversation != null
          ? PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && mounted) {
                  setState(() => _showConversationScreen = false);
                }
              },
              child: _ConversationDetailView(
                conversation: _selectedConversation!,
                currentUserId: widget.currentUserId,
                scrollController: _scrollController,
                messageController: _messageController,
                messages: _messages,
                senderUsernames: _senderUsernames,
                error: _error,
                onSend: _sendMessage,
                onDeleteMessage: _deleteMessage,
                onLoadOlderMessages: _loadOlderMessages,
                loadingOlderMessages: _loadingOlderMessages,
                hasOlderMessages: _hasOlderMessages,
              ),
            )
          : _loading
          ? const Center(
              child: CircularProgressIndicator(color: BluchetPalette.primary),
            )
          : Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/app_icon.png'),
                  fit: BoxFit.contain,
                  opacity: 0.035,
                ),
              ),
              child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _groupNameController,
                          style: const TextStyle(color: BluchetPalette.inputText),
                          decoration: const InputDecoration(
                            hintText: 'Group name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _createGroupConversation,
                        child: const Text('Create group'),
                      ),
                    ],
                  ),
                ),
                if (_groupInviteIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final userId in _groupInviteIds)
                            Chip(
                              backgroundColor: BluchetPalette.turquoise800,
                              side: const BorderSide(color: BluchetPalette.turquoise600),
                              label: Text(
                                _searchResults
                                    .firstWhere(
                                      (result) => result.userId == userId,
                                      orElse: () => const _UserSearchResult(
                                        userId: '',
                                        username: 'Member',
                                      ),
                                    )
                                    .username,
                                style: const TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onDeleted: () => _toggleGroupInvite(userId),
                            ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: BluchetPalette.inputText),
                          onChanged: _searchUsers,
                          decoration: const InputDecoration(
                            hintText: 'Search user',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _searchUsers(_searchController.text),
                        icon: const Icon(Icons.search),
                        color: BluchetPalette.primaryDark,
                      ),
                    ],
                  ),
                ),
                if (_searchingUsers)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_searchError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text(
                      _searchError!,
                      style: const TextStyle(color: BluchetPalette.error),
                    ),
                  ),
                if (!_searchingUsers &&
                    _searchError == null &&
                    _searchController.text.trim().length >= 2 &&
                    _searchResults.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text('No users found.'),
                  ),
                if (_searchResults.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        final isSelected =
                            _groupInviteIds.contains(result.userId);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: BluchetPalette.royalBlue100,
                            foregroundColor: BluchetPalette.primaryDark,
                            child: Text(result.username.isEmpty
                                ? '?'
                                : result.username[0].toUpperCase()),
                          ),
                          title: Text(result.username),
                          subtitle: const Text('Private chat or add to group'),
                          trailing: Wrap(
                            spacing: 2,
                            children: [
                              IconButton(
                                tooltip: 'Open private chat',
                                icon: const Icon(Icons.chat_bubble_outline),
                                color: BluchetPalette.primary,
                                onPressed: () => _openConversation(
                                  userId: result.userId,
                                  username: result.username,
                                ),
                              ),
                              IconButton(
                                tooltip: isSelected ? 'Remove from group' : 'Add to group',
                                icon: Icon(isSelected
                                    ? Icons.check_circle
                                    : Icons.group_add_outlined),
                                color: isSelected
                                    ? BluchetPalette.primary
                                    : BluchetPalette.accentDark,
                                onPressed: () => _toggleGroupInvite(result.userId),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: BluchetPalette.dangerSoft,
                      border: Border.all(color: BluchetPalette.error.withOpacity(0.7)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: BluchetPalette.error),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = _conversations[index];
                      final isSelected =
                          _selectedConversation?.id == conversation.id;
                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: const Color(0xFF303E40),
                        title: Text(
                          conversation.isGroup
                              ? conversation.title
                              : conversation.otherUsername,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFFE8F0EF)
                                : BluchetPalette.text,
                          ),
                        ),
                        subtitle: Text(
                          conversation.isGroup
                              ? 'Group • ${conversation.memberIds.length} members'
                              : 'Direct chat',
                          style:
                              const TextStyle(color: BluchetPalette.textMuted),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((_unreadCounts[conversation.id] ?? 0) > 0)
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: const BoxDecoration(
                                  color: BluchetPalette.turquoise500,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            if (conversation.isGroup)
                              IconButton(
                                tooltip: 'Invite members',
                                icon: const Icon(Icons.person_add_alt_1),
                                color: BluchetPalette.primaryDark,
                                onPressed: () =>
                                    _inviteUsersToGroup(conversation),
                              ),
                          ],
                        ),
                        onTap: () async {
                          setState(() {
                            _showConversationScreen = true;
                            _selectedConversation = conversation;
                            _messages = const [];
                            _error = null;
                          });
                          await _loadMessages(conversation.id);
                        },
                      );
                    },
                  ),
                ),
              ],
              ),
            ),
    );
  }
}

class _ConversationDetailView extends StatelessWidget {
  final _Conversation conversation;
  final String currentUserId;
  final ScrollController scrollController;
  final TextEditingController messageController;
  final List<_Message> messages;
  final Map<String, String> senderUsernames;
  final String? error;
  final Future<void> Function() onSend;
  final Future<void> Function(_Message message) onDeleteMessage;
  final Future<void> Function() onLoadOlderMessages;
  final bool loadingOlderMessages;
  final bool hasOlderMessages;

  const _ConversationDetailView({
    required this.conversation,
    required this.currentUserId,
    required this.scrollController,
    required this.messageController,
    required this.messages,
    required this.senderUsernames,
    required this.error,
    required this.onSend,
    required this.onDeleteMessage,
    required this.onLoadOlderMessages,
    required this.loadingOlderMessages,
    required this.hasOlderMessages,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF102C30)),
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: 0.075,
                child: Image.asset(
                  'assets/app_icon.png',
                  width: 300,
                  height: 300,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Column(
            children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              conversation.isGroup
                  ? conversation.title
                  : conversation.otherUsername,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: BluchetPalette.text,
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              error!,
              style: const TextStyle(color: BluchetPalette.error),
            ),
          ),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_outlined,
                            size: 34, color: BluchetPalette.primary),
                        const SizedBox(height: 10),
                        const Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: BluchetPalette.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Send the first message below. If old messages should appear, check SELECT permissions on the Supabase messages table.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: BluchetPalette.textMuted),
                        ),
                      ],
                    ),
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is UserScrollNotification &&
                        notification.direction == ScrollDirection.forward &&
                        notification.metrics.pixels <=
                            notification.metrics.minScrollExtent + 90 &&
                        hasOlderMessages &&
                        !loadingOlderMessages) {
                      onLoadOlderMessages();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    // Keep a fixed-height header so loading older rows does not
                    // move the current viewport just because the spinner appears.
                    itemCount: messages.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return SizedBox(
                          height: 28,
                          child: loadingOlderMessages
                              ? const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        );
                      }
                      final message = messages[index - 1];
                    final isMine = message.senderId == currentUserId;
                    final localTime = message.createdAt.toLocal();
                    final time = '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
                    final senderName = senderUsernames[message.senderId];
                    return Align(
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: isMine
                            ? () => onDeleteMessage(message)
                            : null,
                        child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(maxWidth: 620),
                        decoration: BoxDecoration(
                          color: isMine
                              ? const Color(0xFF293545)
                              : const Color(0xFF293B3A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (conversation.isGroup && senderName != null) ...[
                              Text(
                                senderName,
                                style: const TextStyle(
                                  color: BluchetPalette.turquoise300,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            Text(
                              message.text,
                              style: const TextStyle(
                                color: Color(0xFFF0F5F4),
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              time,
                              style: const TextStyle(
                                color: Color(0xFFB2C0BE),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        ),
                      ),
                    );
                  },
                  ),
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    style: const TextStyle(color: BluchetPalette.inputText),
                    minLines: 1,
                    maxLines: 5,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      hintText: 'Type a message',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    onPressed: onSend,
                    icon: const Icon(Icons.send),
                    color: BluchetPalette.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BluchetPulseIndicator extends StatefulWidget {
  const _BluchetPulseIndicator();

  @override
  State<_BluchetPulseIndicator> createState() => _BluchetPulseIndicatorState();
}

class _BluchetPulseIndicatorState extends State<_BluchetPulseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: Color.lerp(const Color(0xFF247E78), const Color(0xFF42D7D0), _controller.value),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF42D7D0).withOpacity(0.15 + 0.45 * _controller.value),
                  blurRadius: 4 + 5 * _controller.value,
                  spreadRadius: _controller.value,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 5),
        const Text(
          'BLUCHET PULSE · élő frissítés',
          style: TextStyle(
            color: Color(0xFF42D7D0),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.35,
          ),
        ),
      ],
    );
  }
}

class _UserSearchResult {
  final String userId;
  final String username;

  const _UserSearchResult({
    required this.userId,
    required this.username,
  });
}

class _Conversation {
  final String id;
  final String otherUserId;
  final String otherUsername;
  final bool isGroup;
  final String title;
  final String? createdBy;
  final List<String> memberIds;
  final DateTime? lastActivityAt;

  const _Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    this.isGroup = false,
    this.title = '',
    this.createdBy,
    this.memberIds = const [],
    this.lastActivityAt,
  });
}

class _Message {
  final String id;
  final String senderId;
  final String text;
  final DateTime createdAt;

  const _Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
  });
}
