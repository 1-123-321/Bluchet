import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _background = Color(0xFF0B1020);
const _panel = Color(0xFF171F33);
const _blue = Color(0xFF4F8CFF);

SupabaseClient get db => Supabase.instance.client;

String _friendly(Object error) {
  final text = error.toString();
  return text.startsWith('Exception: ')
      ? text.replaceFirst('Exception: ', '')
      : text;
}

String _normalizeUsername(String value) {
  final cleaned = value.trim().replaceAll(RegExp(r'\s+'), '_');
  return cleaned;
}

String _buildInternalEmail(String username) {
  final safe = username
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '.');

  final label = safe.isEmpty ? 'user' : safe;
  return '$label@test.com';
}

class KulcskodApp extends StatelessWidget {
  final bool configured;
  final String? startupError;

  const KulcskodApp({
    super.key,
    this.configured = false,
    this.startupError,
  });

  @override
  Widget build(BuildContext context) {
    final title = 'Kulcskód';
    final bodyText = !configured
        ? 'A backend még nincs konfigurálva'
        : startupError != null
            ? 'A backend inicializálása sikertelen:\n${_friendly(startupError!)}'
            : 'A backend készen áll.';

    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _blue,
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      bodyText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (url.isEmpty || key.isEmpty) {
    runApp(const KulcskodApp(configured: false));
    return;
  }

  try {
    await Supabase.initialize(
      url: url,
      anonKey: key,
    );
    runApp(const KulcskodApp(configured: true));
  } catch (e) {
    runApp(KulcskodApp(startupError: e.toString()));
  }
}
