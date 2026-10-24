import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _background = Color(0xFF0B1020);
const _panel = Color(0xFF171F33);
const _blue = Color(0xFF4F8CFF);

final _uuid = const Uuid();

SupabaseClient get db => Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (url.isEmpty || key.isEmpty) {
    runApp(const KulcskodApp(configured: false));
    return;
  }

  try {
    await Supabase.initialize(url: url, anonKey: key);
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
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (db.auth.currentUser == null) {
        await db.auth.signInAnonymously();
      }

      final user = db.auth.currentUser!;
      final existing = await db
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (existing == null) {
        final username = 'felhasznalo_${user.id.substring(0, 8)}';
        await db.from('profiles').upsert({
          'id': user.id,
          'username': username,
        });
      }
    } catch (e) {
      error = _friendly(e);
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return ErrorPage(
        message:
            'Nem sikerült elindítani az alkalmazást.\n\n$error\n\n'
            'Ellenőrizd a Supabase táblákat és az RLS-szabályokat.',
      );
    }

    return const HomePage();
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  bool _saving = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = db.auth.currentUser;
      if (user == null) {
        throw Exception('Nincs bejelentkezett felhasználó.');
      }

      final row = await db
          .from('profiles')
          .select('username')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      final username = row?['username']?.toString() ??
          'felhasznalo_${user.id.substring(0, 8)}';
      _usernameController.text = username;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _friendly(e);
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = db.auth.currentUser;
    if (user == null) {
      setState(() => _error = 'Nincs bejelentkezett felhasználó.');
      return;
    }

    final username = _usernameController.text.trim();
    final normalized = username.replaceAll(RegExp(r'\s+'), '_');

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await db.from('profiles').upsert({
        'id': user.id,
        'username': normalized,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A felhasználónév frissítve.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _error = _friendly(e));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Felhasználónév',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        hintText: 'pl. jani_42',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        final text = (value ?? '').trim();
                        if (text.isEmpty) {
                          return 'Adj meg egy felhasználónevet.';
                        }
                        if (text.length < 3) {
                          return 'Legalább 3 karakter hosszúnak kell lennie.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      SelectableText(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(_saving ? 'Mentés...' : 'Mentés'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class EmailVerificationGate extends StatefulWidget {
  final VoidCallback onVerified;

  const EmailVerificationGate({
    super.key,
    required this.onVerified,
  });

  @override
  State<EmailVerificationGate> createState() => _EmailVerificationGateState();
}

class _EmailVerificationGateState extends State<EmailVerificationGate> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkCurrentUser() async {
    try {
      final user = db.auth.currentUser;
      if (user != null && user.emailConfirmedAt != null) {
        widget.onVerified();
        return;
      }

      final result = await db.auth.getUser();
      if (result.user != null && result.user!.emailConfirmedAt != null) {
        widget.onVerified();
      }
    } catch (_) {
      // A frissítés ellenőrzése sikertelen lehet, de a felhasználó továbbra is
      // látni fogja a megerősítési felületet.
    }
  }

  Future<void> _requestVerification() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _message = 'Adj meg e-mail címet és jelszót.');
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final current = db.auth.currentUser;
      if (current != null &&
          current.appMetadata['provider'] == 'anonymous') {
        await db.auth.signOut();
      }

      await db.auth.signUp(
        email: email,
        password: password,
      );

      if (!mounted) return;

      setState(() {
        _sent = true;
        _message =
            'Megerősítő email elküldve. Kattints a levélben található linkre, majd nyomd meg a “Frissítés” gombot.';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _message = _friendly(e));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: _panel,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_user,
                      size: 52,
                      color: _blue,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Email megerősítés szükséges',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'A csoportok és a profil használata előtt igazolnod kell az email címedet.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Jelszó',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _requestVerification,
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: Text(_loading ? 'Küldés...' : 'Megerősítő email küldése'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _checkCurrentUser,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Frissítés'),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      SelectableText(
                        _message!,
                        style: TextStyle(
                          color: _sent ? Colors.lightGreen : Colors.orangeAccent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
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

class GroupCreatePage extends StatefulWidget {
  const GroupCreatePage({super.key});

  @override
  State<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends State<GroupCreatePage> {
  final _groupNameController = TextEditingController();
  final Set<String> _selectedUserIds = {};
  List<Map<String, dynamic>> _candidates = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _loadCandidates() async {
    try {
      final me = db.auth.currentUser!.id;
      final rows = await db
          .from('profiles')
          .select('id, username')
          .neq('id', me)
          .order('username', ascending: true);

      if (!mounted) return;

      setState(() {
        _candidates = List<Map<String, dynamic>>.from(rows);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _friendly(e);
        });
      }
    }
  }

  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      setState(() => _error = 'Adj meg egy csoportnevet.');
      return;
    }

    final me = db.auth.currentUser?.id;
    if (me == null) {
      setState(() => _error = 'Nincs bejelentkezett felhasználó.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final inserted = await db
          .from('groups')
          .insert({
            'name': groupName,
            'created_by': me,
          })
          .select();

      final groupId = inserted.first['id']?.toString();
      if (groupId == null || groupId.isEmpty) {
        throw Exception('A csoport azonosítója nem érkezett vissza.');
      }

      final members = <Map<String, dynamic>>[
        {'group_id': groupId, 'user_id': me},
        ..._selectedUserIds.map((userId) => {
          'group_id': groupId,
          'user_id': userId,
        }),
      ];

      await db.from('group_members').insert(members);

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = _friendly(e));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Csoport létrehozása')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _groupNameController,
                    decoration: const InputDecoration(
                      labelText: 'Csoport neve',
                      prefixIcon: Icon(Icons.group),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tagok kiválasztása',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _candidates.isEmpty
                        ? const Center(child: Text('Nincs más felhasználó.'))
                        : ListView(
                            children: _candidates.map((profile) {
                              final userId = profile['id']?.toString() ?? '';
                              final username =
                                  profile['username']?.toString() ?? 'Felhasználó';

                              return CheckboxListTile(
                                value: _selectedUserIds.contains(userId),
                                title: Text(username),
                                onChanged: (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _selectedUserIds.add(userId);
                                    } else {
                                      _selectedUserIds.remove(userId);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _createGroup,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_saving ? 'Létrehozás...' : 'Csoport létrehozása'),
                  ),
                ],
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

  bool get hasVerifiedEmail {
    final user = db.auth.currentUser;
    return user != null && user.emailConfirmedAt != null;
  }

  @override
  void initState() {
    super.initState();
    loadChats();
    loadGroups();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
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
      if (mounted) setState(() => error = _friendly(e));
    } finally {
      if (mounted) setState(() => searching = false);
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
      if (mounted) setState(() => error = _friendly(e));
    } finally {
      if (mounted) setState(() => loadingChats = false);
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
          .toList(growable: false);

      final rows = await db
          .from('groups')
          .select('id, name')
          .in_('id', groupIds)
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
      if (mounted) setState(() => error = _friendly(e));
    } finally {
      if (mounted) setState(() => loadingGroups = false);
    }
  }

  Future<void> openChat(Map<String, dynamic> profile) async {
    try {
      final response = await db.rpc(
        'get_or_create_direct_conversation',
        params: {'other_user': profile['id']},
      );

      final conversationId = response is Map
          ? response['id']?.toString() ??
              response['conversation_id']?.toString()
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
      }
    } catch (e) {
      if (mounted) setState(() => error = _friendly(e));
    }
  }

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
  }

  Future<void> _openGroupCreator() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GroupCreatePage()),
    );

    if (result == true) {
      await loadGroups();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!hasVerifiedEmail) {
      return EmailVerificationGate(
        onVerified: () {
          if (mounted) {
            setState(() {});
          }
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Kulcskód',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Profil',
            onPressed: _openProfile,
            icon: const Icon(Icons.person_outline),
          ),
          IconButton(
            tooltip: 'Csoport létrehozása',
            onPressed: _openGroupCreator,
            icon: const Icon(Icons.group_add),
          ),
          IconButton(
            tooltip: 'Frissítés',
            onPressed: () async {
              await loadChats();
              await loadGroups();
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Kijelentkezés',
            onPressed: signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Felhasználó keresése',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  onSubmitted: (_) => searchUsers(),
                  decoration: const InputDecoration(
                    hintText: 'Felhasználónév',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: searching ? null : searchUsers,
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          if (searching)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
          for (final profile in results)
            Card(
              color: _panel,
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.person),
                ),
                title: Text(profile['username']?.toString() ?? 'Felhasználó'),
                subtitle: const Text('Beszélgetés megnyitása'),
                trailing: const Icon(Icons.chat_bubble_outline),
                onTap: () => openChat(profile),
              ),
            ),
          if (error != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            'Csoportjaim',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (loadingGroups)
            const Center(child: CircularProgressIndicator())
          else if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Még nincs csoportod. Hozz létre egyet!'),
            )
          else
            for (final group in groups)
              Card(
                color: _panel,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: _blue,
                    child: Icon(Icons.group, color: Colors.white),
                  ),
                  title: Text(group['name'].toString()),
                  subtitle: Text(
                    '${group['member_count']} tag',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Csoport: ${group['name']}'),
                      ),
                    );
                  },
                ),
              ),
          const SizedBox(height: 24),
          const Text(
            'Beszélgetéseid',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (loadingChats)
            const Center(child: CircularProgressIndicator())
          else if (chats.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Még nincs beszélgetésed. Keress rá valakire fent!',
              ),
            )
          else
            for (final chat in chats)
              Card(
                color: _panel,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: _blue,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(chat['title'].toString()),
                  subtitle: Text(
                    chat['last'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatPage(
                          conversationId: chat['id'].toString(),
                          title: chat['title'].toString(),
                        ),
                      ),
                    );
                    await loadChats();
                  },
                ),
              ),
        ],
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String title;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.title,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final controller = TextEditingController();
  final scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  bool loading = true;
  bool sending = false;
  String? error;
  RealtimeChannel? channel;

  @override
  void initState() {
    super.initState();
    loadMessages();

    channel = db
        .channel('chat-${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (_) {
            loadMessages();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    if (channel != null) {
      db.removeChannel(channel!);
    }
    super.dispose();
  }

  Future<void> loadMessages() async {
    try {
      final rows = await db
          .from('messages')
          .select('id, sender_id, ciphertext, created_at')
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: true);

      if (!mounted) return;

      setState(() {
        messages = List<Map<String, dynamic>>.from(rows);
        loading = false;
        error = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(
            scrollController.position.maxScrollExtent,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = _friendly(e);
        });
      }
    }
  }

  Future<void> sendMessage() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;

    setState(() {
      sending = true;
      error = null;
    });

    try {
      final user = db.auth.currentUser;
      if (user == null) {
        throw Exception('Nincs bejelentkezett felhasználó.');
      }

      await db.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': user.id,
        'ciphertext': text,
        'client_message_id': _uuid.v4(),
      });

      controller.clear();
      await loadMessages();
    } catch (e) {
      if (mounted) setState(() => error = _friendly(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = db.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Text(
              'A prototípus üzenetei nincsenek végpontok között titkosítva.',
              style: TextStyle(fontSize: 11, color: Colors.orangeAccent),
              textAlign: TextAlign.center,
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const Center(child: Text('Küldd el az első üzenetet!'))
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final mine = message['sender_id'] == myId;
                          final text =
                              message['ciphertext']?.toString() ?? '';

                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.78,
                              ),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: mine ? _blue : _panel,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(text),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Üzenet írása…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: sending ? null : sendMessage,
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _friendly(Object error) {
  final text = error.toString();
  if (text.contains('permission denied') ||
      text.contains('42501') ||
      text.contains('row-level security')) {
    return 'Az adatbázis engedélye megtagadta a műveletet. '
        'Ellenőrizni kell a Supabase RLS-szabályait.';
  }
  if (text.contains('get_or_create_direct_conversation')) {
    return 'Hiányzik vagy nem megfelelő a beszélgetést létrehozó '
        'get_or_create_direct_conversation RPC.';
  }
  if (text.contains('groups') || text.contains('group_members')) {
    return 'A csoportokra vonatkozó tábla vagy mező hiányzik a Supabase adatbázisból. '
        'Hozd létre a public.groups és public.group_members táblákat.';
  }
  return text;
}






























































































































































































































































































































































































































































































































































































































































































































































































