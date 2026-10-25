import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  final isConfigured = supabaseUrl.startsWith('https://') &&
      supabaseAnonKey.startsWith('sb_') &&
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty;

  String? startupError;

  if (!isConfigured) {
    startupError = supabaseUrl.isEmpty || supabaseAnonKey.isEmpty
        ? 'Missing SUPABASE_URL or SUPABASE_ANON_KEY'
        : 'SUPABASE_URL or SUPABASE_ANON_KEY has an unexpected format';
  } else {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
    } catch (error) {
      startupError = error.toString();
    }
  }

  runApp(KulcskodApp(
    configured: isConfigured,
    startupError: startupError,
  ));
}

const _background = Color(0xFF0B1020);
const _panel = Color(0xFF171F33);
const _blue = Color(0xFF4F8CFF);
const _muted = Color(0xFFB2C2D4);
const _success = Color(0xFF7AE4B1);

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

class KulcskodApp extends StatefulWidget {
  final bool configured;
  final String? startupError;

  const KulcskodApp({
    super.key,
    this.configured = false,
    this.startupError,
  });

  @override
  State<KulcskodApp> createState() => _KulcskodAppState();
}

class _KulcskodAppState extends State<KulcskodApp> {
  @override
  Widget build(BuildContext context) {
    final hasStartupIssue = !widget.configured || widget.startupError != null;

    return MaterialApp(
      title: 'Bluchet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _blue,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: _background,
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: _background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _blue.withOpacity(0.35),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bluchet',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (hasStartupIssue) ...[
                        Text(
                          widget.startupError ?? 'Application is not configured.',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: _muted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Set SUPABASE_URL and SUPABASE_ANON_KEY in your build configuration to continue.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: _muted,
                            ),
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Supabase is configured and the app is ready.',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: _success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
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
