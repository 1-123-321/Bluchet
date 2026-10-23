import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const _navy = Color(0xFF071526);
const _panel = Color(0xFF10263D);
const _blue = Color(0xFF278BFF);
const _cyan = Color(0xFF35D5D0);
bool _backendConfigured = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(url: url, anonKey: key);
    _backendConfigured = true;
  }

  runApp(const KulcskodApp());
}

SupabaseClient get supa => Supabase.instance.client;

class KulcskodApp extends StatelessWidget {
  const KulcskodApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Kulcskód',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _navy,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _blue,
        brightness: Brightness.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
    ),
    home: _backendConfigured ? const AuthGate() : const SetupRequired(),
  );
}

class SetupRequired extends StatelessWidget {
  const SetupRequired({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.key_rounded, size: 64, color: _cyan),
            SizedBox(height: 16),
            Text(
              'Kulcskód',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'A backend még nincs konfigurálva. Állítsd be a Supabase URL-t és a publikus klienskulcsot a README szerint; az alkalmazás nem színlel működő kapcsolatot.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    ),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: supa.auth.onAuthStateChange,
    builder: (context, _) =>
        supa.auth.currentUser == null ? const AuthScreen() : const HomeScreen(),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final username = TextEditingController();

  bool register = false;
  bool busy = false;
  String? error;
  String? notice;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    username.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });

    try {
      if (register) {
        final name = username.text.trim().toLowerCase();
        if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(name)) {
          throw const FormatException(
            'A felhasználónév 3–24 karakter, csak a–z, 0–9 és _ lehet.',
          );
        }

        final res = await supa.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          data: {'username': name},
        );

        if (res.user != null && res.session == null) {
          notice = 'Ellenőrizd az e-mail-fiókodat a megerősítéshez.';
        }
      } else {
        await supa.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on FormatException catch (e) {
      error = e.message;
    } catch (e) {
      error = _friendly(e);
    }

    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    try {
      await supa.auth.resetPasswordForEmail(email.text.trim());
      setState(() => notice = 'Ha a cím regisztrálva van, érkezik visszaállító e-mail.');
    } catch (e) {
      setState(() => error = _friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.key_rounded, color: _cyan, size: 64),
                const SizedBox(height: 10),
                const Text(
                  'Kulcskód',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  register ? 'Hozz létre fiókot' : 'Jelentkezz be biztonságosan',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 28),
                if (register)
                  ...[
                    TextField(
                      controller: username,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Felhasználónév',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'E-mail-cím',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Jelszó',
                    prefixIcon: const Icon(Icons.lock_outline),
                    helperText: register
                        ? 'Legalább 8 karaktert használj.'
                        : 'A jelszavad bizalmas és titkos.',
                  ),
                ),
                const SizedBox(height: 16),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                if (notice != null)
                  Text(
                    notice!,
                    style: const TextStyle(color: _cyan),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      busy ? 'Folyamatban…' : register ? 'Regisztráció' : 'Bejelentkezés',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    register = !register;
                    error = null;
                    notice = null;
                  }),
                  child: Text(
                    register ? 'Már van fiókod? Bejelentkezés' : 'Új vagy itt? Regisztráció',
                  ),
                ),
                if (!register)
                  TextButton(
                    onPressed: resetPassword,
                    child: const Text('Elfelejtett jelszó'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        children: [
          Icon(Icons.key_rounded, color: _cyan),
          SizedBox(width: 8),
          Text('Kulcskód'),
        ],
      ),
      actions: const [
        IconButton(icon: Icon(Icons.logout), onPressed: null),
      ],
    ),
    body: IndexedStack(
      index: tab,
      children: const [
        ConversationList(),
        SearchUsers(),
        ProfileScreen(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          label: 'Beszélgetések',
        ),
        NavigationDestination(
          icon: Icon(Icons.search),
          label: 'Keresés',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profil',
        ),
      ],
    ),
  );
}

class ConversationList extends StatefulWidget {
  const ConversationList({super.key});

  @override
  State<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<ConversationList> {
  Future<List<Map<String, dynamic>>> load() async {
    final rows = await supa
        .from('conversation_participants')
        .select('conversation_id, conversations(id, updated_at)')
        .eq('user_id', supa.auth.currentUser!.id)
        .order('created_at');

    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final conv = row['conversations'];
      if (conv == null) continue;

      final others = await supa
          .from('conversation_participants')
          .select('user_id, profiles(username)')
          .eq('conversation_id', conv['id'])
          .neq('user_id', supa.auth.currentUser!.id);

      final user = others.isEmpty
          ? 'Beszélgetés'
          : (others.first['profiles']?['username'] ?? 'Felhasználó').toString();

      final messages = await supa
          .from('messages')
          .select('created_at')
          .eq('conversation_id', conv['id'])
          .order('created_at', ascending: false)
          .limit(1);

      result.add({
        'id': conv['id'],
        'username': user,
        'updated_at': messages.isNotEmpty
            ? messages.first['created_at']
            : conv['updated_at'],
      });
    }

    result.sort((a, b) => (b['updated_at'] ?? '').toString().compareTo(
        (a['updated_at'] ?? '').toString()));
    return result;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: load(),
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snap.hasError) {
        return Center(
          child: Text('Nem sikerült betölteni: ${_friendly(snap.error!)}'),
        );
      }

      final items = snap.data ?? [];
      if (items.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(30),
            child: Text(
              'Még nincs beszélgetésed. Keress felhasználókat a Keresés lapon.',
            ),
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
          itemBuilder: (context, index) {
            final item = items[index];
            final date = item['updated_at'] != null
                ? DateFormat('yyyy. MM. dd. HH:mm').format(
                    DateTime.parse(item['updated_at'].toString()),
                  )
                : 'Most';
            return ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.person_outline),
              ),
              title: Text(item['username'].toString()),
              subtitle: Text(date),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      conversationId: item['id'].toString(),
                      username: item['username'].toString(),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    },
  );
}

class SearchUsers extends StatefulWidget {
  const SearchUsers({super.key});

  @override
  State<SearchUsers> createState() => _SearchUsersState();
}

class _SearchUsersState extends State<SearchUsers> {
  final query = TextEditingController();
  bool busy = false;
  String? error;
  List<Map<String, dynamic>> results = [];

  Future<void> search() async {
    setState(() {
      busy = true;
      error = null;
    });

    try {
      final q = query.text.trim().toLowerCase();
      if (q.length < 2) {
        throw const FormatException('Legalább 2 karaktert írj be.');
      }

      final rows = await supa
          .from('profiles')
          .select('id, username')
          .ilike('username', '%$q%')
          .limit(20);

      setState(() => results = List<Map<String, dynamic>>.from(rows));
    } on FormatException catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = _friendly(e));
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> openUser(Map<String, dynamic> user) async {
    try {
      final id = await supa.rpc(
        'get_or_create_direct_conversation',
        params: {'other_user': user['id']},
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: id.toString(),
            username: user['username'].toString(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => error = _friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: query,
                onSubmitted: (_) => search(),
                decoration: const InputDecoration(
                  labelText: 'Felhasználó keresése',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: busy ? null : search,
              child: const Text('Keresés'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (error != null)
          Text(
            error!,
            style: const TextStyle(color: Colors.redAccent),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: results.isEmpty
              ? const Center(
                  child: Text('Nincs találat. Próbáld meg a felhasználónevet.'),
                )
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = results[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(user['username'].toString()),
                      onTap: () => openUser(user),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String username;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.username,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final controller = TextEditingController();
  final uuid = const Uuid();
  List<Map<String, dynamic>> messages = [];
  bool loading = true;
  String? error;
  RealtimeChannel? channel;

  @override
  void initState() {
    super.initState();
    load();
    channel = supa.channel('messages-${widget.conversationId}').onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: Filter.or(
        Filter('conversation_id', 'eq', widget.conversationId),
      ),
      callback: (payload) async {
        await load();
      },
    );
    supa.realtime.setAuth();
  }

  Future<void> load() async {
    try {
      final rows = await supa
          .from('messages')
          .select('id,sender_id,ciphertext,created_at,delivery_status,client_message_id')
          .eq('conversation_id', widget.conversationId)
          .order('created_at');

      setState(() {
        messages = List<Map<String, dynamic>>.from(rows);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _friendly(e);
          loading = false;
        });
      }
    }
  }

  Future<void> send() async {
    if (controller.text.trim().isEmpty) return;

    setState(() => error = 'Küldés letiltva: a Signal Protocol-alapú E2EE kliens és tartós kulcstárolás nincs még integrálva.');
  }

  @override
  void dispose() {
    if (channel != null) {
      supa.removeChannel(channel!);
    }
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('@${widget.username}')),
    body: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: _panel,
          child: Text(
            'E2EE: még nem aktív, ez csak UI prototípus.',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : messages.isEmpty
                  ? const Center(child: Text('Még nincs üzenet.'))
                  : ListView.builder(
                      itemCount: messages.length,
                      itemBuilder: (_, index) {
                        final msg = messages[index];
                        final mine = msg['sender_id'] == supa.auth.currentUser!.id;
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: mine ? _blue : _panel,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(msg['ciphertext']?.toString() ?? '…'),
                          ),
                        );
                      },
                    ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Üzenet…',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: send,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = supa.auth.currentUser;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const CircleAvatar(
          radius: 34,
          child: Icon(Icons.person, size: 34),
        ),
        const SizedBox(height: 12),
        Text(
          user?.email ?? 'Vendég',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () async {
            await supa.auth.signOut();
          },
          icon: const Icon(Icons.logout),
          label: const Text('Kijelentkezés'),
        ),
      ],
    );
  }
}

String _friendly(Object error) {
  final s = error.toString();
  if (s.contains('Invalid login credentials')) {
    return 'Hibás e-mail-cím vagy jelszó.';
  }
  if (s.contains('User already registered')) {
    return 'Ez a felhasználó már regisztrálva van.';
  }
  if (s.contains('weak password')) {
    return 'A jelszó túl gyenge.';
  }
  return s;
}
