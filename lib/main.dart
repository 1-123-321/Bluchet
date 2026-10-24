import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _background = Color(0xFF0B1020);
const _panel = Color(0xFF171F33);
const _blue = Color(0xFF4F8CFF);

final _uuid = const Uuid();

SupabaseClient get db => Supabase.instance.client;

String _friendly(Object error) {
  final text = error.toString();
  return text.startsWith('Exception: ')
      ? text.replaceFirst('Exception: ', '')
      : text;
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

class KulcskodApp extends StatelessWidget {
  final bool configured;
  final String? startupError;

  const KulcskodApp({
    super.key,
    this.configured = true,
    this.startupError,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluchet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _blue,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _background,
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: startupError != null
          ? ErrorPage(message: 'Indítási hiba:\n$startupError')
          : !configured
              ? const ErrorPage(
                  message:
                      'Hiányzik a Supabase URL vagy az anon kulcs. '
                      'Ellenőrizd a GitHub Actions buildbeállításait.',
                )
              : const StartPage(),
    );
  }
}

class ErrorPage extends StatelessWidget {
  final String message;

  const ErrorPage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(message),
        ),
      ),
    );
  }
}

class StartPage extends StatefulWidget {
  const StartPage({super.key});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _codeController = TextEditingController();

  bool _loading = true;
  bool _verificationSent = false;
  bool _submitting = false;
  bool _verifying = false;
  String? _registeredUserId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    try {
      final user = db.auth.currentUser;

      if (user == null) {
        if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }

      final row = await db
          .from('profiles')
          .select('email_verified')
          .eq('id', user.id)
          .maybeSingle();

      final verified = row?['email_verified'] == true;

      if (verified) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        }
        return;
      }

      _registeredUserId = user.id;
      _emailController.text = user.email ?? '';

      if (mounted) {
        setState(() {
          _verificationSent = true;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _friendly(e));
      }
    } finally {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _restartRegistration() async {
    try {
      await db.auth.signOut();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      _registeredUserId = null;
      _verificationSent = false;
      _emailController.clear();
      _passwordController.clear();
      _usernameController.clear();
      _codeController.clear();
      _error = null;
    });
  }

  Future<void> _sendVerificationEmail(String email, String code) async {
    try {
      await db.functions.invoke(
        'send-email-verification',
        body: {
          'email': email,
          'code': code,
        },
      );
    } catch (_) {
      debugPrint('EMAIL VERIFICATION TEST CODE: $code');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email ellenőrző kód: $code')),
        );
      }
    }
  }

  Future<void> _register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final username = _usernameController.text.trim();

    if (email.isEmpty || password.isEmpty || username.isEmpty) {
      setState(() => _error = 'Minden mező kitöltése kötelező.');
      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Érvényes e-mail címet adj meg.');
      return;
    }

    if (password.length < 6) {
      setState(() => _error = 'A jelszónak legalább 6 karakter hosszúnak kell lennie.');
      return;
    }

    final normalizedUsername = username.replaceAll(RegExp(r'\s+'), '_');
    if (normalizedUsername.length < 3) {
      setState(() => _error = 'A felhasználónévnek legalább 3 karakter hosszúnak kell lennie.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final authResponse = await db.auth.signUp(
        email: email,
        password: password,
      );

      final userId = authResponse.user?.id ?? db.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('A felhasználó létrehozása nem sikerült.');
      }

      final code = _uuid.v4().substring(0, 6).toUpperCase();
      _registeredUserId = userId;

      await db.from('profiles').upsert({
        'id': userId,
        'email': email,
        'username': normalizedUsername,
        'email_verified': false,
        'email_verification_code': code,
      });

      await _sendVerificationEmail(email, code);

      if (mounted) {
        setState(() {
          _verificationSent = true;
          _submitting = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _friendly(e);
        });
      }
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim().toUpperCase();
    final userId = _registeredUserId ?? db.auth.currentUser?.id;

    if (userId == null) {
      setState(() => _error = 'Nincs aktív felhasználó a hitelesítéshez.');
      return;
    }

    if (code.isEmpty) {
      setState(() => _error = 'Add meg az ellenőrző kódot.');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      final row = await db
          .from('profiles')
          .select('email_verification_code')
          .eq('id', userId)
          .maybeSingle();

      final expectedCode = (row?['email_verification_code'] ?? '').toString();
      if (expectedCode.isEmpty || expectedCode != code) {
        throw Exception('A kód helytelen vagy lejárt. Kezdje újra a regisztrációval.');
      }

      await db.from('profiles').update({
        'email_verified': true,
        'email_verification_code': null,
      }).eq('id', userId);

      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (email.isNotEmpty && password.isNotEmpty) {
        try {
          await db.auth.signInWithPassword(
            email: email,
            password: password,
          );
        } catch (_) {
          // ha már be van jelentkezve, ez nem fontos
        }
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } catch (e) {
      if (mounted) {
        await _restartRegistration();
        setState(() => _error = _friendly(e));
      }
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }

  Widget _buildRegisterForm() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Regisztráció',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'E-mail cím',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Jelszó',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Felhasználónév',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
            ),
          ElevatedButton(
            onPressed: _submitting ? null : _register,
            child: Text(_submitting ? 'Regisztráció...' : 'Regisztráció'),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationForm() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'E-mail ellenőrzés',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'Küldtünk egy ellenőrző kódot a(z) ${_emailController.text.trim()} címre.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _codeController,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Ellenőrző kód',
              prefixIcon: Icon(Icons.verified_user_outlined),
            ),
          ),
          const SizedBox(height: 24),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
            ),
          ElevatedButton(
            onPressed: _verifying ? null : _verifyCode,
            child: Text(_verifying ? 'Ellenőrzés...' : 'Ellenőrzés'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _restartRegistration,
            child: const Text('Újra kezdem'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            color: _panel,
            child: _verificationSent
                ? _buildVerificationForm()
                : _buildRegisterForm(),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final searchController = TextEditingController();
  List<Map<String, dynamic>> results = [];
  List<Map<String, dynamic>> chats = [];
  List<Map<String, dynamic>> groups = [];
  bool searching = false;
  bool loadingChats = true;
  bool loadingGroups = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      loadChats(),
      loadGroups(),
    ]);
  }

  Future<void> searchUsers() async {
    final query = searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      searching = true;
      error = null;
      results = [];
    });

    try {
      final me = db.auth.currentUser!.id;
      final rows = await db
          .from('profiles')
          .select('id, username')
          .ilike('username', '%$query%')
          .neq('id', me)
          .limit(30);

      if (mounted) {
        setState(() {
          results = List<Map<String, dynamic>>.from(rows);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = _friendly(e));
      }
    } finally {
      if (mounted) {
        setState(() => searching = false);
      }
    }
  }

  Future<void> loadChats() async {
    setState(() => loadingChats = true);

    try {
      final me = db.auth.currentUser!.id;

      final memberships = await db
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', me);

      final loaded = <Map<String, dynamic>>[];

      for (final membership in memberships) {
        final conversationId = membership['conversation_id'].toString();

        final people = await db
            .from('conversation_participants')
            .select('user_id')
            .eq('conversation_id', conversationId);

        String title = 'Beszélgetés';
        for (final person in people) {
          final id = person['user_id'].toString();
          if (id == me) continue;

          final profile = await db
              .from('profiles')
              .select('username')
              .eq('id', id)
              .maybeSingle();

          if (profile != null) {
            title = profile['username']?.toString() ?? title;
          }
        }

        final latest = await db
            .from('messages')
            .select('ciphertext, created_at')
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false)
            .limit(1);

        loaded.add({
          'id': conversationId,
          'title': title,
          'last': latest.isEmpty
              ? 'Még nincs üzenet'
              : latest.first['ciphertext']?.toString() ?? '',
        });
      }

      if (mounted) {
        setState(() {
          chats = loaded;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = _friendly(e));
      }
    } finally {
      if (mounted) {
        setState(() => loadingChats = false);
      }
    }
  }

  Future<void> loadGroups() async {
    setState(() => loadingGroups = true);

    try {
      final me = db.auth.currentUser!.id;

      final memberships = await db
          .from('group_members')
          .select('group_id')
          .eq('user_id', me);

      if (memberships.isEmpty) {
        if (mounted) {
          setState(() {
            groups = [];
            error = null;
          });
        }
        return;
      }

      final groupIds = memberships
          .map((e) => e['group_id'].toString())
          .toList();

      final rows = await db
          .from('groups')
          .select('id, name')
          .inFilter('id', groupIds)
          .order('name', ascending: true);

      final loaded = <Map<String, dynamic>>[];

      for (final row in rows) {
        final groupId = row['id'].toString();
        final members = await db
            .from('group_members')
            .select('user_id')
            .eq('group_id', groupId);

        loaded.add({
          'id': groupId,
          'name': row['name']?.toString() ?? 'Csoport',
          'member_count': members.length,
        });
      }

      if (mounted) {
        setState(() {
          groups = loaded;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = _friendly(e));
      }
    } finally {
      if (mounted) {
        setState(() => loadingGroups = false);
      }
    }
  }

  Future<void> openChat(Map<String, dynamic> profile) async {
    try {
      final response = await db.rpc(
        'get_or_create_direct_conversation',
        params: {'other_user': profile['id']},
      );

      final conversationId = response is Map
          ? response['id']?.toString() ?? response['conversation_id']?.toString()
          : response.toString();

      if (conversationId == null ||
          conversationId.isEmpty ||
          conversationId == 'null') {
        throw Exception('A beszélgetés azonosítója nem érkezett meg.');
      }

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: conversationId,
            title: profile['username']?.toString() ?? 'Beszélgetés',
          ),
        ),
      );

      await loadChats();
    } catch (e) {
      if (mounted) {
        setState(() => error = _friendly(e));
      }
    }
  }

  Future<void> signOut() async {
    try {
      await db.auth.signOut();

      if (mounted) {
        setState(() {
          chats = [];
          results = [];
          groups = [];
        });

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const StartPage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = _friendly(e));
      }
    }
  }

  Future<void> openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
  }

  Future<void> openGroupCreator() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GroupCreatePage()),
    );

    if (created == true) {
      await loadGroups();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Kulcskód',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        
