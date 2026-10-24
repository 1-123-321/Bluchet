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

  // Keep the generated auth email stable so repeated test registrations do not
  // trigger Supabase's email-send rate limit. For this mock auth flow you also
  // need to ensure email confirmation is disabled or the project is configured
  // to allow the number of signup attempts you are making in testing.
  return '$label@example.com';
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
