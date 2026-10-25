import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Ignore missing .env when values are provided via --dart-define.
  }

  final url = _readEnv('SUPABASE_URL');
  final anonKey = _readEnv('SUPABASE_ANON_KEY');

  final isConfigured = url.startsWith('https://') &&
      anonKey.startsWith('sb_') &&
      url.isNotEmpty &&
      anonKey.isNotEmpty;

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
    );
  } catch (error) {
    runApp(
      BluchetStartupApp(
        message: error.toString(),
      ),
    );
    return;
  }

  runApp(const BluchetApp());
}

String _readEnv(String key) {
  final fromDartDefine = String.fromEnvironment(key, defaultValue: '');
  if (fromDartDefine.isNotEmpty) {
    return fromDartDefine;
  }

  return dotenv.env[key] ?? '';
}

class AppSecurity {
  static bool isValidUsername(String value) {
    final normalized = value.trim();
    return RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(normalized);
  }

  static bool isValidPassword(String value) {
    return value.trim().length >= 6;
  }

  static bool isValidMessage(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && trimmed.length <= 2000;
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

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final userId = await _storage.read(key: 'bluchet_user_id');
    if (!mounted) return;

    setState(() {
      _currentUserId = userId;
      _loading = false;
    });
  }

  Future<void> _login(String username, String password) async {
    if (!AppSecurity.isValidUsername(username)) {
      throw Exception('Username must be 3-24 chars, letters/numbers/underscore only.');
    }

    if (!AppSecurity.isValidPassword(password)) {
      throw Exception('Password must be at least 6 characters.');
    }

    final response = await Supabase.instance.client.rpc(
      'login_user',
      params: {
        'p_username': username,
        'p_password': password,
      },
    );

    final userId = response.toString();
    await _storage.write(key: 'bluchet_user_id', value: userId);

    if (!mounted) return;
    setState(() {
      _currentUserId = userId;
    });
  }

  Future<void> _register(String username, String password) async {
    if (!AppSecurity.isValidUsername(username)) {
      throw Exception('Username must be 3-24 chars, letters/numbers/underscore only.');
    }

    if (!AppSecurity.isValidPassword(password)) {
      throw Exception('Password must be at least 6 characters.');
    }

    final response = await Supabase.instance.client.rpc(
      'register_user',
      params: {
        'p_username': username,
        'p_password': password,
      },
    );

    final userId = response.toString();
    await _storage.write(key: 'bluchet_user_id', value: userId);

    if (!mounted) return;
    setState(() {
      _currentUserId = userId;
    });
  }

  Future<void> _logout() async {
    await _storage.delete(key: 'bluchet_user_id');
    if (!mounted) return;
    setState(() {
      _currentUserId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_currentUserId == null) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: AuthScreen(
          onLogin: _login,
          onRegister: _register,
        ),
      );
    }

    return MaterialApp(
      theme: ThemeData.dark(),
      home: ChatScreen(
        currentUserId: _currentUserId!,
        onLogout: _logout,
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

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Username and password are required.';
      });
      return;
    }

    if (!AppSecurity.isValidUsername(username)) {
      setState(() {
        _error = 'Username must be 3-24 chars, letters/numbers/underscore only.';
      });
      return;
    }

    if (!AppSecurity.isValidPassword(password)) {
      setState(() {
        _error = 'Password must be at least 6 characters.';
      });
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
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              color: const Color(0xFF171F33),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Bluchet',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: Text(
                          _isRegister ? 'Create account' : 'Login',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
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

class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final Future<void> Function() onLogout;

  const ChatScreen({
    super.key,
    required this.currentUserId,
    required this.onLogout,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  bool _loading = true;
  String? _error;

  List<_UserSearchResult> _searchResults = const [];
  List<_Conversation> _conversations = const [];
  _Conversation? _selectedConversation;
  List<_Message> _messages = const [];

  @override
  void initState() {
    super.initState();
    _refreshConversations();
  }

  Future<void> _searchUsers(String term) async {
    final cleaned = term.trim();
    if (cleaned.isEmpty) {
      setState(() {
        _searchResults = const [];
      });
      return;
    }

    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('profiles')
          .select()
          .ilike('username', '%$cleaned%')
          .limit(10);

      final results = <_UserSearchResult>[];
      for (final item in rows) {
        final map = item as Map<String, dynamic>;
        final userId = map['id'] as String;
        final username = map['username'] as String;
        if (userId != widget.currentUserId) {
          results.add(
            _UserSearchResult(
              userId: userId,
              username: username,
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _searchResults = results;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _refreshConversations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('conversation_participants')
          .select()
          .eq('user_id', widget.currentUserId);

      final conversations = <_Conversation>[];

      for (final item in rows) {
        final map = item as Map<String, dynamic>;
        final conversationId = map['conversation_id'] as String;

        final List<dynamic> participants = await Supabase.instance.client
            .from('conversation_participants')
            .select()
            .eq('conversation_id', conversationId);

        Map<String, dynamic>? otherParticipant;
        for (final p in participants) {
          final candidate = p as Map<String, dynamic>;
          if (candidate['user_id'] != widget.currentUserId) {
            otherParticipant = candidate;
            break;
          }
        }

        if (otherParticipant == null) {
          continue;
        }

        final otherUserId = otherParticipant['user_id'] as String;

        final profile = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', otherUserId)
            .maybeSingle();

        final username = profile?['username'] ?? 'Unknown user';

        conversations.add(
          _Conversation(
            id: conversationId,
            otherUserId: otherUserId,
            otherUsername: username,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        if (_selectedConversation == null && conversations.isNotEmpty) {
          _selectedConversation = conversations.first;
        }
        _loading = false;
      });

      if (_selectedConversation != null) {
        await _loadMessages(_selectedConversation!.id);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openConversation({
    required String userId,
    required String username,
  }) async {
    try {
      final conversationId = await Supabase.instance.client.rpc(
        'get_or_create_direct_conversation_for_user',
        params: {
          'actor_id': widget.currentUserId,
          'other_user': userId,
        },
      ) as String;

      final conv = _Conversation(
        id: conversationId,
        otherUserId: userId,
        otherUsername: username,
      );

      await _refreshConversations();

      if (!mounted) return;
      setState(() {
        _selectedConversation = conv;
      });

      await _loadMessages(conversationId);
      _searchController.clear();
      setState(() {
        _searchResults = const [];
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadMessages(String conversationId) async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      final messages = <_Message>[];
      for (final item in rows) {
        final map = item as Map<String, dynamic>;
        messages.add(
          _Message(
            id: map['id'] as String,
            senderId: map['sender_id'] as String,
            text: (map['ciphertext'] ?? '') as String,
            createdAt:
                DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _messages = messages;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _sendMessage() async {
    final conversation = _selectedConversation;
    final text = _messageController.text.trim();

    if (conversation == null || text.isEmpty) {
      return;
    }

    if (!AppSecurity.isValidMessage(text)) {
      setState(() {
        _error = 'Message is empty or too long.';
      });
      return;
    }

    try {
      await Supabase.instance.client.rpc(
        'insert_message_for_user',
        params: {
          'actor_id': widget.currentUserId,
          'conversation_id': conversation.id,
          'ciphertext': text,
        },
      );

      _messageController.clear();
      await _loadMessages(conversation.id);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluchet'),
        actions: [
          IconButton(
            onPressed: () async {
              await widget.onLogout();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                SizedBox(
                  width: 340,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: _searchUsers,
                                decoration: const InputDecoration(
                                  hintText: 'Search user',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () {
                                _searchUsers(_searchController.text);
                              },
                              icon: const Icon(Icons.search),
                            ),
                          ],
                        ),
                      ),
                      if (_searchResults.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final result = _searchResults[index];
                              return ListTile(
                                title: Text(result.username),
                                onTap: () {
                                  _openConversation(
                                    userId: result.userId,
                                    username: result.username,
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent),
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
                              title: Text(conversation.otherUsername),
                              subtitle: const Text('Direct chat'),
                              onTap: () async {
                                setState(() {
                                  _selectedConversation = conversation;
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
                Expanded(
                  child: _selectedConversation == null
                      ? const Center(child: Text('Select a conversation'))
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _selectedConversation!.otherUsername,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                controller: _scrollController,
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final message = _messages[index];
                                  final isMine =
                                      message.senderId == widget.currentUserId;

                                  return Align(
                                    alignment: isMine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      constraints: const BoxConstraints(
                                        maxWidth: 420,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMine
                                            ? const Color(0xFF4F8CFF)
                                            : const Color(0xFF171F33),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(message.text),
                                    ),
                                  );
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _messageController,
                                      onSubmitted: (_) => _sendMessage(),
                                      decoration: const InputDecoration(
                                        hintText: 'Type a message',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: _sendMessage,
                                    icon: const Icon(Icons.send),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

class BluchetStartupApp extends StatelessWidget {
  final String message;

  const BluchetStartupApp({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Card(
              color: const Color(0xFF171F33),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Bluchet',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(message),
                    const SizedBox(height: 16),
                    const Text(
                      'Set SUPABASE_URL and SUPABASE_ANON_KEY in your environment or .env file.',
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

  const _Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
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
