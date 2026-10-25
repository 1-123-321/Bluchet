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

class BluchetPalette {
  // Turquoise family: 10 shades, no black/white included.
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

  // Royal blue family: 10 shades, no black/white included.
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

  static const Color primary = turquoise700;
  static const Color primaryDark = turquoise900;
  static const Color accent = royalBlue700;
  static const Color accentDark = royalBlue900;
  static const Color background = Color(0xFFEEF9FF);
  static const Color card = Color(0xFFF5FCFF);
  static const Color surface = Color(0xFFE6F7FF);
  static const Color text = Color(0xFF163E6D);
  static const Color textMuted = Color(0xFF4A6788);
  static const Color success = Color(0xFF4FC2BD);
  static const Color error = Color(0xFFB54C5D);
  static const Color dangerSoft = Color(0xFFFDE7EC);
}

class BluchetTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: BluchetPalette.background,
      colorScheme: const ColorScheme.light(
        primary: BluchetPalette.primary,
        secondary: BluchetPalette.accent,
        surface: BluchetPalette.surface,
        onPrimary: Color(0xFF103666),
        onSecondary: Color(0xFF103666),
        onSurface: BluchetPalette.text,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: BluchetPalette.text,
        displayColor: BluchetPalette.text,
      ),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: BluchetPalette.primary,
        foregroundColor: Color(0xFF103666),
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: BluchetPalette.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEFF8FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BluchetPalette.royalBlue200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BluchetPalette.royalBlue200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BluchetPalette.primary, width: 2),
        ),
        hintStyle: const TextStyle(color: BluchetPalette.textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: const Color(0xFF103666),
          backgroundColor: BluchetPalette.accent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
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
                    color: BluchetPalette.text,
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
      return MaterialApp(
        theme: BluchetTheme.light(),
        home: const Scaffold(
          backgroundColor: BluchetPalette.background,
          body: Center(
            child: CircularProgressIndicator(
              color: BluchetPalette.primary,
            ),
          ),
        ),
      );
    }

    if (_currentUserId == null) {
      return MaterialApp(
        theme: BluchetTheme.light(),
        home: AuthScreen(
          onLogin: _login,
          onRegister: _register,
        ),
      );
    }

    return MaterialApp(
      theme: BluchetTheme.light(),
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
      backgroundColor: BluchetPalette.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              color: BluchetPalette.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BluchetPalette.primary.withOpacity(0.15),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 40,
                        color: BluchetPalette.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Bluchet',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: BluchetPalette.text,
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
                        style: const TextStyle(color: BluchetPalette.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: const Text('Login / Register'),
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
  final TextEditingController _groupNameController = TextEditingController();
  final Set<String> _groupInviteIds = <String>{};

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

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error.toString().replaceFirst('Exception: ', '');
    });
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
          .select('id, username')
          .ilike('username', '%$cleaned%')
          .limit(10);

      final results = <_UserSearchResult>[];
      for (final item in rows) {
        final map = item as Map<String, dynamic>;
        final userId = map['id'] as String;
        final username = map['username'] as String;
        if (userId != widget.currentUserId) {
          results.add(_UserSearchResult(userId: userId, username: username));
        }
      }

      if (!mounted) return;
      setState(() {
        _searchResults = results;
      });
    } catch (error) {
      _showError(error);
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
      setState(() {
        _error = 'At least one other member is required.';
      });
      return;
    }

    final groupTitle = _groupNameController.text.trim();
    final memberIds = <String>{..._groupInviteIds, widget.currentUserId}.toList();

    try {
      final conversationId = await Supabase.instance.client.rpc(
        'create_group_conversation',
        params: {
          'p_actor_id': widget.currentUserId,
          'p_member_ids': memberIds,
          'p_title': groupTitle.isEmpty ? 'Group chat' : groupTitle,
        },
      ) as String;

      _groupNameController.clear();
      _groupInviteIds.clear();

      await _refreshConversations();

      if (!mounted) return;
      setState(() {
        _selectedConversation = _Conversation(
          id: conversationId,
          otherUserId: widget.currentUserId,
          otherUsername: 'Group',
          isGroup: true,
          title: groupTitle.isEmpty ? 'Group chat' : groupTitle,
          memberIds: memberIds,
        );
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

    if (memberIds.isEmpty) {
      return const [];
    }

    final profiles = await Supabase.instance.client
        .from('profiles')
        .select('id, username')
        .in_('id', memberIds);

    return (profiles as List)
        .map((item) => item as Map<String, dynamic>)
        .map(
          (item) => _UserSearchResult(
            userId: item['id'] as String,
            username: item['username'] as String,
          ),
        )
        .toList();
  }

  Future<void> _inviteUsersToGroup(_Conversation group) async {
    final inviteIds = <String>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (innerContext, setDialogState) {
            return AlertDialog(
              title: const Text('Invite members'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search user...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) async {
                        await _searchUsers(value);
                        setDialogState(() {});
                      },
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
                              selected ? Icons.check_circle : Icons.add_circle_outline,
                              color: selected ? BluchetPalette.primary : BluchetPalette.accent,
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

                    await Supabase.instance.client.from('conversation_participants').insert(
                      idsToInvite
                          .map(
                            (userId) => {
                              'conversation_id': group.id,
                              'user_id': userId,
                            },
                          )
                          .toList(),
                    );

                    await _refreshConversations();
                    if (!mounted) return;
                    Navigator.pop(dialogContext);
                    setState(() {
                      _selectedConversation = group;
                    });
                  },
                  child: const Text('Invite'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _refreshConversations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<dynamic> participantRows = await Supabase.instance.client
          .from('conversation_participants')
          .select('conversation_id, user_id')
          .eq('user_id', widget.currentUserId);

      final conversationIds = participantRows
          .map((item) => (item as Map<String, dynamic>)['conversation_id'] as String)
          .toList();

      if (conversationIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _conversations = const [];
          _selectedConversation = null;
          _loading = false;
        });
        return;
      }

      final List<dynamic> conversationRows = await Supabase.instance.client
          .from('conversations')
          .select('id, title')
          .in_('id', conversationIds);

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
        final isGroup = title != null && title.trim().isNotEmpty;

        if (isGroup) {
          final members = await _loadGroupMembers(conversationId);
          conversations.add(
            _Conversation(
              id: conversationId,
              otherUserId: widget.currentUserId,
              otherUsername: 'Group',
              isGroup: true,
              title: title,
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

        if (otherParticipant == null) {
          continue;
        }

        final otherUserId = otherParticipant['user_id'] as String;

        final profile = await Supabase.instance.client
            .from('profiles')
            .select('id, username')
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
      _showError(error);
      setState(() {
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

      await _refreshConversations();

      if (!mounted) return;
      setState(() {
        _selectedConversation = _Conversation(
          id: conversationId,
          otherUserId: userId,
          otherUsername: username,
        );
      });

      await _loadMessages(conversationId);
      _searchController.clear();
      setState(() {
        _searchResults = const [];
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _loadMessages(String conversationId) async {
    try {
      final List<dynamic> rows = await Supabase.instance.client
          .from('messages')
          .select('id, conversation_id, sender_id, ciphertext, created_at')
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
      _showError(error);
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
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BluchetPalette.background,
      appBar: AppBar(
        title: const Text('Bluchet'),
        actions: [
          if (_selectedConversation != null && _selectedConversation!.isGroup)
            IconButton(
              onPressed: () async {
                final members = await _loadGroupMembers(_selectedConversation!.id);
                if (!mounted) return;

                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('Group members'),
                      content: SizedBox(
                        width: 320,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final member = members[index];
                            return ListTile(
                              title: Text(member.username),
                            );
                          },
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    );
                  },
                );
              },
              icon: const Icon(Icons.group),
            ),
          IconButton(
            onPressed: () async {
              await widget.onLogout();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: BluchetPalette.primary,
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _groupNameController,
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
                              backgroundColor: BluchetPalette.turquoise200,
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
                                style: const TextStyle(color: BluchetPalette.text),
                              ),
                              onDeleted: () => _toggleGroupInvite(userId),
                            ),
                        ],
                      ),
                    ),
                  ),
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
                        onPressed: () => _searchUsers(_searchController.text),
                        icon: const Icon(Icons.search),
                        color: BluchetPalette.primaryDark,
                      ),
                    ],
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        final isSelected = _groupInviteIds.contains(result.userId);

                        return ListTile(
                          title: Text(result.username),
                          trailing: Icon(
                            isSelected ? Icons.check_circle : Icons.add_circle_outline,
                            color: isSelected ? BluchetPalette.primary : BluchetPalette.accent,
                          ),
                          onTap: () => _toggleGroupInvite(result.userId),
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: BluchetPalette.error),
                    ),
                  ),
                SizedBox(
                  height: 260,
                  child: ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = _conversations[index];
                      final isSelected = _selectedConversation?.id == conversation.id;

                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: BluchetPalette.royalBlue100,
                        title: Text(
                          conversation.isGroup
                              ? conversation.title
                              : conversation.otherUsername,
                          style: const TextStyle(color: BluchetPalette.text),
                        ),
                        subtitle: Text(
                          conversation.isGroup
                              ? 'Group • ${conversation.memberIds.length} members'
                              : 'Direct chat',
                          style: const TextStyle(color: BluchetPalette.textMuted),
                        ),
                        trailing: conversation.isGroup
                            ? IconButton(
                                icon: const Icon(Icons.person_add_alt_1),
                                color: BluchetPalette.primaryDark,
                                onPressed: () async {
                                  await _inviteUsersToGroup(conversation);
                                },
                              )
                            : null,
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
                Expanded(
                  child: _selectedConversation == null
                      ? const Center(
                          child: Text(
                            'Select a conversation',
                            style: TextStyle(color: BluchetPalette.textMuted),
                          ),
                        )
                      : _ConversationDetailView(
                          conversation: _selectedConversation!,
                          currentUserId: widget.currentUserId,
                          scrollController: _scrollController,
                          messageController: _messageController,
                          messages: _messages,
                          error: _error,
                          onSend: _sendMessage,
                        ),
                ),
              ],
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
  final String? error;
  final Future<void> Function() onSend;

  const _ConversationDetailView({
    required this.conversation,
    required this.currentUserId,
    required this.scrollController,
    required this.messageController,
    required this.messages,
    required this.error,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              conversation.isGroup ? conversation.title : conversation.otherUsername,
              style: const TextStyle(
                fontSize: 24,
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
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final isMine = message.senderId == currentUserId;

              return Align(
                alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 620),
                  decoration: BoxDecoration(
                    color: isMine ? BluchetPalette.primary : BluchetPalette.royalBlue100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color: isMine ? const Color(0xFF103666) : BluchetPalette.text,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    minLines: 1,
                    maxLines: 5,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      hintText: 'Type a message',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 56,
                  height: 56,
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
  final List<String> memberIds;

  const _Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    this.isGroup = false,
    this.title = '',
    this.memberIds = const [],
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
