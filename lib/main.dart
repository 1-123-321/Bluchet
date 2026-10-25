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
