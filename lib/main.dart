
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final searchController = TextEditingController();
  List<Map<String, dynamic>> results = [];
  List<Map<String, dynamic>> chats = [];
  bool searching = false;
  bool loadingChats = true;
  String? error;

  @override
  void initState() {
    super.initState();
    loadChats();
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
      await db.auth.signInAnonymously();
      if (mounted) {
        setState(() {
          chats = [];
          results = [];
        });
        await loadChats();
      }
    } catch (e) {
      if (mounted) setState(() => error = _friendly(e));
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
        actions: [
          IconButton(
            tooltip: 'Frissítés',
            onPressed: loadChats,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Új névtelen munkamenet',
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
        // Prototípus: itt a szöveg olvasható formában kerül tárolásra.
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
  return text;
}

