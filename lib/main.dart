import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Ignore a missing .env when values are supplied via --dart-define.
  }

  final url = _readEnv('SUPABASE_URL');
  final anonKey = _readEnv('SUPABASE_ANON_KEY');

  final isConfigured =
      url.startsWith('https://') && url.isNotEmpty && anonKey.isNotEmpty;

  if (!isConfigured) {
    runApp(
      const BluchetStartupApp(
        message: 'Missing SUPABASE_URL or SUPABASE_ANON_KEY',
      ),
    );
    return;
  }

  try {
    await Supabase.initialize(url: url, anonKey: anonKey);
  } catch (error) {
    runApp(BluchetStartupApp(message: error.toString()));
    return;
  }

  runApp(const BluchetApp());
}

String _readEnv(String key) {
  const fromDartDefineValues = <String, String>{};
  final fromDartDefine = String.fromEnvironment(key, defaultValue: '');
  if (fromDartDefine.isNotEmpty) return fromDartDefine;
  return dotenv.env[key] ?? fromDartDefineValues[key] ?? '';
}

class AppSecurity {
  static bool isValidUsername(String value) =>
      RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(value.trim());

  static bool isValidPassword(String value) => value.length >= 6;

  static bool isValidMessage(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && trimmed.length <= 2000;
  }
}

class BluchetPalette {
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

  static const Color primary = royalBlue700;
  static const Color primaryDark = royalBlue900;
  static const Color accent = turquoise800;
  static const Color accentDark = turquoise900;
  static const Color background = Color(0xFF15191B);
  static const Color card = Color(0xFF202629);
  static const Color surface = Color(0xFF293235);
  static const Color text = Color(0xFFE8F0EF);
  static const Color textMuted = Color(0xFFB2C0BE);
  static const Color inputText = Color(0xFFF0F5F4);
  static const Color inputLabel = Color(0xFFB0BFBC);
  static const Color success = Color(0xFF1A8A89);
  // Errors use a clear yellow warning color instead of red.
  static const Color error = Color(0xFFFFD45C);
  static const Color dangerSoft = Color(0xFF3B3522);
}

class BluchetTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: BluchetPalette.background,
      colorScheme: const ColorScheme.dark(
        primary: BluchetPalette.primary,
        secondary: BluchetPalette.accent,
        surface: BluchetPalette.surface,
        error: BluchetPalette.error,
        onPrimary: Color(0xFFF4F7F7),
        onSecondary: Color(0xFFF4F7F7),
        onSurface: BluchetPalette.text,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: BluchetPalette.text,
            displayColor: BluchetPalette.text,
          ),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: BluchetPalette.primary,
        foregroundColor: Color(0xFFF4F7F7),
        elevation: 0,
        toolbarHeight: 52,
        iconTheme: IconThemeData(size: 20),
        actionsIconTheme: IconThemeData(size: 20),
      ),
      cardTheme: CardThemeData(
        color: BluchetPalette.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF252D30),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: BluchetPalette.royalBlue200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: BluchetPalette.royalBlue200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: BluchetPalette.accent, width: 2.5),
        ),
        hintStyle: const TextStyle(color: BluchetPalette.inputLabel),
        labelStyle: const TextStyle(color: BluchetPalette.inputLabel),
        floatingLabelStyle: const TextStyle(
          color: BluchetPalette.accentDark,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: const Color(0xFFF4F7F7),
          backgroundColor: BluchetPalette.accent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
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
                    color: BluchetPalette.error,
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
    try {
      // Older builds stored a plain profile UUID without a Supabase Auth
      // session. That is not an authenticated identity, so discard it.
      await _storage.delete(key: 'bluchet_user_id');
      final user = Supabase.instance.client.auth.currentUser;
      if (!mounted) return;
      setState(() {
        _currentUserId = user?.id;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentUserId = null;
        _loading = false;
      });
    }
  }

  // The user only sees a username. Supabase Auth still receives a
  // syntactically valid, non-deliverable internal address.
  String _internalEmail(String username) =>
      '${username.trim().toLowerCase()}@bluchet.invalid';

  Future<void> _login(String username, String password) async {
    if (!AppSecurity.isValidUsername(username)) {
      throw Exception(
        'Username must be 3-24 chars, letters/numbers/underscore only.',
      );
    }
    if (!AppSecurity.isValidPassword(password)) {
      throw Exception('Password must be at least 6 characters.');
    }

    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: _internalEmail(username),
      password: password,
    );
    final userId = response.user?.id;
    if (userId == null) {
      throw Exception('Login did not return a valid authenticated user.');
    }

    if (!mounted) return;
    setState(() => _currentUserId = userId);
  }

  Future<void> _register(String username, String password) async {
    if (!AppSecurity.isValidUsername(username)) {
      throw Exception(
        'Username must be 3-24 chars, letters/numbers/underscore only.',
      );
    }
    if (!AppSecurity.isValidPassword(password)) {
      throw Exception('Password must be at least 6 characters.');
    }

    final normalizedUsername = username.trim().toLowerCase();
    final response = await Supabase.instance.client.auth.signUp(
      email: _internalEmail(normalizedUsername),
      password: password,
      data: {'username': normalizedUsername},
    );

    final userId = response.user?.id;
    if (userId == null) {
      throw Exception('Registration did not return a valid user ID.');
    }
    if (response.session == null) {
      throw Exception(
        'Registration succeeded, but Supabase requires email confirmation. '
        'Disable Confirm email in Supabase Auth settings, then sign in.',
      );
    }

    if (!mounted) return;
    setState(() => _currentUserId = userId);
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    await _storage.delete(key: 'bluchet_user_id');
    if (!mounted) return;
    setState(() => _currentUserId = null);
  }

  Future<void> _onAccountDeleted() async {
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The account may already be deleted, so clear the local session anyway.
    }
    await _storage.delete(key: 'bluchet_user_id');
    if (!mounted) return;
    setState(() => _currentUserId = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return MaterialApp(
        theme: BluchetTheme.light(),
        home: const Scaffold(
          backgroundColor: BluchetPalette.background,
          body: Center(
            child: CircularProgressIndicator(color: BluchetPalette.primary),
          ),
        ),
      );
    }

    if (_currentUserId == null) {
      return MaterialApp(
        theme: BluchetTheme.light(),
        home: AuthScreen(onLogin: _login, onRegister: _register),
      );
    }

    return MaterialApp(
      theme: BluchetTheme.light(),
      home: ChatScreen(
        currentUserId: _currentUserId!,
        onLogout: _logout,
        onAccountDeleted: _onAccountDeleted,
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

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Username and password are required.');
      return;
    }
    if (!AppSecurity.isValidUsername(username)) {
      setState(() {
        _error =
            'Username must be 3-24 chars, letters/numbers/underscore only.';
      });
      return;
    }
    if (!AppSecurity.isValidPassword(password)) {
      setState(() => _error = 'Password must be at least 6 characters.');
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
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
            padding: const EdgeInsets.all(16),
            child: Card(
              color: BluchetPalette.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BluchetPalette.primary.withOpacity(0.15),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/app_icon.png',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.image_not_supported_outlined,
                            size: 30,
                            color: BluchetPalette.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Bluchet',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: BluchetPalette.text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _usernameController,
                      style: const TextStyle(color: BluchetPalette.inputText),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordController,
                      style: const TextStyle(color: BluchetPalette.inputText),
                      obscureText: true,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(color: BluchetPalette.error),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: Text(_isSubmitting ? 'Please wait…' : 'Continue'),
                      ),
                    ),
                    const SizedBox(height: 6),
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
  final Future<void> Function() onAccountDeleted;

  const ChatScreen({
    super.key,
    required this.currentUserId,
    required this.onLogout,
    required this.onAccountDeleted,
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
  int _searchRequestGeneration = 0;
  bool _searchingUsers = false;
  String? _searchError;
  List<_Conversation> _conversations = const [];
  final Map<String, int> _unreadCounts = <String, int>{};
  _Conversation? _selectedConversation;
  List<_Message> _messages = const [];
  final Map<String, String> _senderUsernames = <String, String>{};
  bool _showConversationScreen = false;
  int _messageLoadGeneration = 0;
  Timer? _messageRefreshTimer;
  bool _pollingMessages = false;
  int _activityRefreshTicks = 0;

  @override
  void initState() {
    super.initState();
    _refreshConversations();

    // Poll only the currently open conversation. This makes incoming messages
    // appear even when Realtime is not configured for the messages table.
    _messageRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _activityRefreshTicks++;
      if (_activityRefreshTicks >= 10) {
        _activityRefreshTicks = 0;
        _refreshConversationActivity();
      }

      final conversationId = _selectedConversation?.id;
      if (conversationId == null || _pollingMessages) return;
      _pollingMessages = true;
      _loadMessages(conversationId, scrollToBottom: false).whenComplete(() {
        _pollingMessages = false;
      });
    });
  }

  @override
  void dispose() {
    _messageRefreshTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _messageController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error.toString().replaceFirst('Exception: ', '');
    });
  }

  Future<Map<String, String>> _loadUsernames(List<String> userIds) async {
    if (userIds.isEmpty) return <String, String>{};
    final response = await Supabase.instance.client.rpc(
      'get_usernames_for_current_user',
      params: {'p_user_ids': userIds},
    );
    if (response is! List) {
      throw Exception('Username lookup returned an unexpected response.');
    }
    final names = <String, String>{};
    for (final item in response) {
      final row = Map<String, dynamic>.from(item as Map);
      final id = row['id']?.toString();
      final username = row['username']?.toString().trim();
      if (id != null && username != null && username.isNotEmpty) {
        names[id] = username;
      }
    }
    return names;
  }

  Future<void> _searchUsers(String term) async {
    // Every keystroke invalidates earlier requests. A slow response for an
    // older term must never replace results for the latest term.
    final requestGeneration = ++_searchRequestGeneration;
    final cleaned = term.trim();

    if (cleaned.length < 2) {
      if (!mounted) return;
      setState(() {
        _searchResults = const [];
        _searchingUsers = false;
        _searchError = cleaned.isEmpty ? null : 'Type at least 2 characters.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _searchingUsers = true;
      _searchError = null;
      _searchResults = const [];
    });

    try {
      final response = await Supabase.instance.client.rpc(
        'search_profiles',
        params: {'search_term': cleaned.toLowerCase()},
      );

      if (!mounted || requestGeneration != _searchRequestGeneration) return;
      if (response is! List) {
        throw const FormatException('Unexpected search response.');
      }

      final results = <_UserSearchResult>[];
      final seenIds = <String>{};
      for (final item in response) {
        if (item is! Map) continue;
        final userId = item['id']?.toString();
        final username = item['username']?.toString().trim();
        if (userId == null ||
            username == null ||
            username.isEmpty ||
            userId == widget.currentUserId ||
            !seenIds.add(userId)) {
          continue;
        }
        results.add(_UserSearchResult(userId: userId, username: username));
      }

      if (!mounted || requestGeneration != _searchRequestGeneration) return;
      setState(() {
        _searchResults = results;
        _searchingUsers = false;
        _searchError = null;
      });
    } catch (error) {
      if (!mounted || requestGeneration != _searchRequestGeneration) return;
      setState(() {
        _searchResults = const [];
        _searchingUsers = false;
        _searchError = 'User search failed. Check your connection and try again.';
      });
      // Keep the raw error available for debugging without exposing database
      // details in the UI.
      debugPrint('Bluchet user search failed: $error');
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
      setState(() => _error = 'At least one other member is required.');
      return;
    }

    final groupTitle = _groupNameController.text.trim();
    final memberIds = <String>{..._groupInviteIds, widget.currentUserId}.toList();

    try {
      final response = await Supabase.instance.client.rpc(
        'create_group_conversation_for_current_user',
        params: {
          'p_member_ids': memberIds,
          'p_title': groupTitle.isEmpty ? 'Group chat' : groupTitle,
        },
      );
      final conversationId = response.toString();
      if (conversationId.isEmpty || conversationId == 'null') {
        throw Exception('Group creation did not return a conversation ID.');
      }

      _groupNameController.clear();
      _groupInviteIds.clear();
      await _refreshConversations();

      if (!mounted) return;
      final title = groupTitle.isEmpty ? 'Group chat' : groupTitle;
      setState(() {
        _showConversationScreen = true;
        _selectedConversation = _Conversation(
          id: conversationId,
          otherUserId: widget.currentUserId,
          otherUsername: 'Group',
          isGroup: true,
          title: title,
          createdBy: widget.currentUserId,
          memberIds: memberIds,
        );
        _messages = const [];
        _error = null;
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
    if (memberIds.isEmpty) return const [];

    // Resolve names through a narrowly scoped SECURITY DEFINER RPC.
    final usernameById = await _loadUsernames(memberIds);

    return memberIds
        .map((id) => _UserSearchResult(
              userId: id,
              username: usernameById[id] ?? 'Unknown user',
            ))
        .toList();
  }

  Future<void> _inviteUsersToGroup(_Conversation group) async {
    final inviteIds = <String>{};
    _searchController.clear();
    _searchResults = const [];
    _searchError = null;
    _searchingUsers = false;
    _searchRequestGeneration++;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setDialogState) => AlertDialog(
          title: const Text('Invite members'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: BluchetPalette.inputText),
                  decoration: const InputDecoration(
                    hintText: 'Search user...',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) async {
                    await _searchUsers(value);
                    setDialogState(() {});
                  },
                ),
                if (_searchingUsers)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_searchError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _searchError!,
                      style: const TextStyle(color: BluchetPalette.error),
                    ),
                  ),
                if (!_searchingUsers &&
                    _searchError == null &&
                    _searchController.text.trim().length >= 2 &&
                    _searchResults.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No users found.'),
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
                          selected
                              ? Icons.check_circle
                              : Icons.add_circle_outline,
                          color: selected
                              ? BluchetPalette.primary
                              : BluchetPalette.accent,
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

                try {
                  await Supabase.instance.client.rpc(
                    'invite_users_to_group_for_current_user',
                    params: {
                      'p_conversation_id': group.id,
                      'p_user_ids': idsToInvite,
                    },
                  );
                  await _refreshConversations();
                  if (!mounted) return;
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  setState(() => _selectedConversation = group);
                } catch (error) {
                  _showError(error);
                }
              },
              child: const Text('Invite'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshConversations() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<dynamic> participantRows = await Supabase.instance.client
          .from('conversation_participants')
          .select('conversation_id, user_id')
          .eq('user_id', widget.currentUserId);

      // A conversation may appear more than once in the participant query.
      // Build a stable, unique list before fetching conversation metadata.
      final conversationIds = participantRows
          .map((item) =>
              (item as Map<String, dynamic>)['conversation_id'] as String)
          .toSet()
          .toList();

      if (conversationIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _conversations = const [];
          _selectedConversation = null;
          _messages = const [];
          _loading = false;
        });
        return;
      }

      // Fetch unread counts independently so a missing/unapplied unread SQL
      // migration cannot prevent the conversation list itself from loading.
      try {
        final unreadResponse = await Supabase.instance.client.rpc(
          'get_unread_counts_for_current_user',
        );
        if (unreadResponse is List) {
          _unreadCounts
            ..clear()
            ..addEntries(unreadResponse.map((item) {
              final row = Map<String, dynamic>.from(item as Map);
              return MapEntry(
                row['conversation_id'].toString(),
                int.tryParse(row['unread_count'].toString()) ?? 0,
              );
            }));
        }
      } catch (_) {
        // Unread badges stay hidden until the SQL migration is installed.
      }

      final List<dynamic> conversationRows = await Supabase.instance.client
          .from('conversations')
          .select('id, title, is_direct, created_by')
          .inFilter('id', conversationIds);

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
        // Group/direct classification comes from the database flag, never
        // from the title: direct chats can also have custom titles.
        final isGroup = meta?['is_direct'] == false;

        if (isGroup) {
          final members = await _loadGroupMembers(conversationId);
          conversations.add(
            _Conversation(
              id: conversationId,
              otherUserId: widget.currentUserId,
              otherUsername: 'Group',
              isGroup: true,
              title: title ?? 'Group chat',
              createdBy: meta?['created_by']?.toString(),
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
        if (otherParticipant == null) continue;

        final otherUserId = otherParticipant['user_id'] as String;
        final usernameById = await _loadUsernames([otherUserId]);
        final username = usernameById[otherUserId] ?? 'Unknown user';

        conversations.add(
          _Conversation(
            id: conversationId,
            otherUserId: otherUserId,
            otherUsername: username,
          ),
        );
      }

      if (!mounted) return;
      // Defensive de-duplication prevents repeated participant rows from
      // creating duplicate entries in the chat list.
      final uniqueConversations = <String, _Conversation>{
        for (final conversation in conversations)
          conversation.id: conversation,
      }.values.toList();
      // Sort using the timestamp of each conversation's newest message.
      // The timestamp is read from Supabase (not guessed from local send time),
      // and conversations with no messages remain at the bottom.
      final activityByConversation = <String, DateTime>{};
      for (final conversation in uniqueConversations) {
        try {
          final latestMessage = await Supabase.instance.client
              .from('messages')
              .select('created_at')
              .eq('conversation_id', conversation.id)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          final createdAt = latestMessage?['created_at'];
          if (createdAt != null) {
            final parsed = DateTime.tryParse(createdAt.toString());
            if (parsed != null) {
              activityByConversation[conversation.id] = parsed;
            }
          }
        } catch (_) {
          // Keep the list usable if message timestamps are not readable.
        }
      }
      final conversationsWithActivity = uniqueConversations.map((conversation) {
        return _Conversation(
          id: conversation.id,
          otherUserId: conversation.otherUserId,
          otherUsername: conversation.otherUsername,
          isGroup: conversation.isGroup,
          title: conversation.title,
          createdBy: conversation.createdBy,
          memberIds: conversation.memberIds,
          lastActivityAt: activityByConversation[conversation.id],
        );
      }).toList();
      conversationsWithActivity.sort((a, b) {
        final aTime = a.lastActivityAt;
        final bTime = b.lastActivityAt;
        if (aTime == null && bTime != null) return 1;
        if (aTime != null && bTime == null) return -1;
        if (aTime != null && bTime != null) {
          final byActivity = bTime.compareTo(aTime);
          if (byActivity != 0) return byActivity;
        }
        return a.id.compareTo(b.id);
      });

      final previousSelectedId = _selectedConversation?.id;
      final selectedStillExists = conversationsWithActivity.any(
        (conversation) => conversation.id == previousSelectedId,
      );
      final nextSelected = selectedStillExists
          ? conversationsWithActivity.firstWhere(
              (conversation) => conversation.id == previousSelectedId,
            )
          : (conversationsWithActivity.isNotEmpty ? conversationsWithActivity.first : null);
      final selectionChanged = nextSelected?.id != previousSelectedId;
      setState(() {
        _conversations = conversationsWithActivity;
        _selectedConversation = nextSelected;
        if (selectionChanged) _messages = const [];
        _loading = false;
      });
      if (selectionChanged) {
        // Invalidate any pending response for the previous chat.
        _messageLoadGeneration++;
      }

      if (_selectedConversation != null) {
        await _loadMessages(_selectedConversation!.id);
      } else if (mounted) {
        setState(() => _messages = const []);
      }
    } catch (error) {
      _showError(error);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshConversationActivity() async {
    final current = List<_Conversation>.from(_conversations);
    if (!mounted || current.isEmpty) return;

    final activityByConversation = <String, DateTime>{};
    for (final conversation in current) {
      try {
        final latestMessage = await Supabase.instance.client
            .from('messages')
            .select('created_at')
            .eq('conversation_id', conversation.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        final createdAt = latestMessage?['created_at'];
        if (createdAt != null) {
          final parsed = DateTime.tryParse(createdAt.toString());
          if (parsed != null) activityByConversation[conversation.id] = parsed;
        }
      } catch (_) {
        // Preserve the current order if activity cannot be read.
      }
    }

    if (!mounted) return;
    final updated = current.map((conversation) {
      return _Conversation(
        id: conversation.id,
        otherUserId: conversation.otherUserId,
        otherUsername: conversation.otherUsername,
        isGroup: conversation.isGroup,
        title: conversation.title,
        createdBy: conversation.createdBy,
        memberIds: conversation.memberIds,
        lastActivityAt: activityByConversation[conversation.id],
      );
    }).toList();
    updated.sort((a, b) {
      final aTime = a.lastActivityAt;
      final bTime = b.lastActivityAt;
      if (aTime == null && bTime != null) return 1;
      if (aTime != null && bTime == null) return -1;
      if (aTime != null && bTime != null) {
        final byActivity = bTime.compareTo(aTime);
        if (byActivity != 0) return byActivity;
      }
      return a.id.compareTo(b.id);
    });

    setState(() {
      _conversations = updated;
      final selectedId = _selectedConversation?.id;
      if (selectedId != null) {
        for (final conversation in updated) {
          if (conversation.id == selectedId) {
            _selectedConversation = conversation;
            break;
          }
        }
      }
    });
  }

  Future<void> _openConversation({
    required String userId,
    required String username,
  }) async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_or_create_direct_conversation_for_current_user',
        params: {'other_user': userId},
      );
      final conversationId = response.toString();

      await _refreshConversations();
      if (!mounted) return;
      setState(() {
        _showConversationScreen = true;
        _selectedConversation = _Conversation(
          id: conversationId,
          otherUserId: userId,
          otherUsername: username,
        );
        _messages = const [];
        _error = null;
        _searchController.clear();
        _searchResults = const [];
        _searchError = null;
        _searchingUsers = false;
        _searchRequestGeneration++;
      });
      await _loadMessages(conversationId);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _loadMessages(
    String conversationId, {
    bool scrollToBottom = true,
  }) async {
    // If the user switches chats while a request is in flight, ignore the
    // older response so it cannot paint group messages into a private chat.
    final requestGeneration = ++_messageLoadGeneration;
    try {
      final response = await Supabase.instance.client.rpc(
        'get_messages_for_current_user',
        params: {'p_conversation_id': conversationId},
      );
      if (response is! List) {
        throw Exception('The message query returned an unexpected response.');
      }

      final messages = <_Message>[];
      for (final item in response) {
        final map = Map<String, dynamic>.from(item as Map);
        messages.add(
          _Message(
            id: map['id'].toString(),
            senderId: map['sender_id'].toString(),
            text: (map['ciphertext'] ?? '').toString(),
            createdAt: DateTime.tryParse(
                  (map['created_at'] ?? '').toString(),
                ) ??
                DateTime.now(),
          ),
        );
      }

      // Resolve all senders with one batched query rather than one query per message.
      final senderIds = messages.map((message) => message.senderId).toSet().toList();
      final resolvedNames = <String, String>{};
      if (senderIds.isNotEmpty) {
        try {
          resolvedNames.addAll(await _loadUsernames(senderIds));
        } catch (_) {
          // Keep messages usable if username lookup is unavailable.
        }
      }

      if (!mounted ||
          requestGeneration != _messageLoadGeneration ||
          _selectedConversation?.id != conversationId) {
        return;
      }
      setState(() {
        _messages = messages;
        _senderUsernames
          ..clear()
          ..addAll(resolvedNames);
        _error = null;
        _unreadCounts[conversationId] = 0;
      });

      // Mark read for this user only. Failure to update the read marker must
      // not hide messages or break sending/receiving.
      try {
        await Supabase.instance.client.rpc(
          'mark_conversation_read_for_current_user',
          params: {'p_conversation_id': conversationId},
        );
      } catch (_) {
        // The SQL migration may not have been applied yet.
      }

      if (scrollToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients &&
            requestGeneration == _messageLoadGeneration &&
            _selectedConversation?.id == conversationId) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
        });
      }
    } catch (error) {
      if (mounted &&
          requestGeneration == _messageLoadGeneration &&
          _selectedConversation?.id == conversationId) {
        _showError(error);
      }
    }
  }

  Future<void> _deleteGroup(_Conversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text(
          'This permanently deletes “${conversation.title}” and its messages for every member.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: BluchetPalette.error),
            child: const Text('Delete group'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.rpc(
        'delete_group_for_current_user',
        params: {'p_conversation_id': conversation.id},
      );
      if (!mounted) return;
      setState(() {
        _conversations = _conversations
            .where((item) => item.id != conversation.id)
            .toList();
        if (_selectedConversation?.id == conversation.id) {
          _selectedConversation = null;
          _messages = const [];
          _showConversationScreen = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group deleted.')),
      );
      await _refreshConversations();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account permanently?'),
        content: const Text(
          'Your account will be permanently deleted. Your profile and data linked to it may also be deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: BluchetPalette.error),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.rpc('delete_my_account');
      await widget.onAccountDeleted();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _sendMessage() async {
    final conversation = _selectedConversation;
    final text = _messageController.text.trim();
    if (conversation == null || text.isEmpty) return;

    if (!AppSecurity.isValidMessage(text)) {
      setState(() => _error = 'Message is empty or too long.');
      return;
    }

    try {
      await Supabase.instance.client.rpc(
        'insert_message_for_current_user',
        params: {
          'p_conversation_id': conversation.id,
          'p_ciphertext': text,
        },
      );

      _messageController.clear();
      await _loadMessages(conversation.id);
      await _refreshConversations();
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BluchetPalette.background,
      appBar: AppBar(
        leading: _showConversationScreen
            ? IconButton(
                tooltip: 'Back to conversations',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showConversationScreen = false),
              )
            : null,
        title: Text(
          _showConversationScreen && _selectedConversation != null
              ? (_selectedConversation!.isGroup
                  ? _selectedConversation!.title
                  : _selectedConversation!.otherUsername)
              : 'Bluchet',
        ),
        actions: [
          if (_showConversationScreen &&
              _selectedConversation?.isGroup == true &&
              (_selectedConversation!.createdBy == widget.currentUserId ||
                  _selectedConversation!.createdBy == null))
            IconButton(
              tooltip: 'Delete group',
              icon: const Icon(Icons.delete_outline),
              color: BluchetPalette.error,
              onPressed: () => _deleteGroup(_selectedConversation!),
            ),
          if (_showConversationScreen && _selectedConversation?.isGroup == true)
            IconButton(
              onPressed: () async {
                final selected = _selectedConversation;
                if (selected == null) return;
                try {
                  final members = await _loadGroupMembers(selected.id);
                  if (!mounted) return;
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Group members'),
                      content: SizedBox(
                        width: 320,
                        child: members.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'No members found. Check Supabase access to conversation_participants and profiles.',
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: members.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) => ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: BluchetPalette.turquoise100,
                                    foregroundColor: BluchetPalette.primaryDark,
                                    child: Text(members[index].username.isEmpty
                                        ? '?'
                                        : members[index].username[0].toUpperCase()),
                                  ),
                                  title: Text(members[index].username),
                                  subtitle: members[index].userId == widget.currentUserId
                                      ? const Text('You')
                                      : null,
                                ),
                              ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                } catch (error) {
                  _showError(error);
                }
              },
              icon: const Icon(Icons.group),
            ),
          IconButton(
            tooltip: 'Delete account',
            onPressed: _deleteAccount,
            icon: const Icon(Icons.person_remove_alt_1),
            color: BluchetPalette.error,
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _showConversationScreen && _selectedConversation != null
          ? PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && mounted) {
                  setState(() => _showConversationScreen = false);
                }
              },
              child: _ConversationDetailView(
                conversation: _selectedConversation!,
                currentUserId: widget.currentUserId,
                scrollController: _scrollController,
                messageController: _messageController,
                messages: _messages,
                senderUsernames: _senderUsernames,
                error: _error,
                onSend: _sendMessage,
              ),
            )
          : _loading
          ? const Center(
              child: CircularProgressIndicator(color: BluchetPalette.primary),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _groupNameController,
                          style: const TextStyle(color: BluchetPalette.inputText),
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
                              backgroundColor: BluchetPalette.turquoise800,
                              side: const BorderSide(color: BluchetPalette.turquoise600),
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
                                style: const TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onDeleted: () => _toggleGroupInvite(userId),
                            ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: BluchetPalette.inputText),
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
                if (_searchingUsers)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_searchError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text(
                      _searchError!,
                      style: const TextStyle(color: BluchetPalette.error),
                    ),
                  ),
                if (!_searchingUsers &&
                    _searchError == null &&
                    _searchController.text.trim().length >= 2 &&
                    _searchResults.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Text('No users found.'),
                  ),
                if (_searchResults.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        final isSelected =
                            _groupInviteIds.contains(result.userId);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: BluchetPalette.royalBlue100,
                            foregroundColor: BluchetPalette.primaryDark,
                            child: Text(result.username.isEmpty
                                ? '?'
                                : result.username[0].toUpperCase()),
                          ),
                          title: Text(result.username),
                          subtitle: const Text('Private chat or add to group'),
                          trailing: Wrap(
                            spacing: 2,
                            children: [
                              IconButton(
                                tooltip: 'Open private chat',
                                icon: const Icon(Icons.chat_bubble_outline),
                                color: BluchetPalette.primary,
                                onPressed: () => _openConversation(
                                  userId: result.userId,
                                  username: result.username,
                                ),
                              ),
                              IconButton(
                                tooltip: isSelected ? 'Remove from group' : 'Add to group',
                                icon: Icon(isSelected
                                    ? Icons.check_circle
                                    : Icons.group_add_outlined),
                                color: isSelected
                                    ? BluchetPalette.primary
                                    : BluchetPalette.accentDark,
                                onPressed: () => _toggleGroupInvite(result.userId),
                              ),
                            ],
                          ),
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
                      border: Border.all(color: BluchetPalette.error.withOpacity(0.7)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: BluchetPalette.error),
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
                        selectedTileColor: const Color(0xFF303E40),
                        title: Text(
                          conversation.isGroup
                              ? conversation.title
                              : conversation.otherUsername,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFFE8F0EF)
                                : BluchetPalette.text,
                          ),
                        ),
                        subtitle: Text(
                          conversation.isGroup
                              ? 'Group • ${conversation.memberIds.length} members'
                              : 'Direct chat',
                          style:
                              const TextStyle(color: BluchetPalette.textMuted),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((_unreadCounts[conversation.id] ?? 0) > 0)
                              Container(
                                width: 10,
                                height: 10,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: const BoxDecoration(
                                  color: BluchetPalette.turquoise500,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            if (conversation.isGroup)
                              IconButton(
                                tooltip: 'Invite members',
                                icon: const Icon(Icons.person_add_alt_1),
                                color: BluchetPalette.primaryDark,
                                onPressed: () =>
                                    _inviteUsersToGroup(conversation),
                              ),
                          ],
                        ),
                        onTap: () async {
                          setState(() {
                            _showConversationScreen = true;
                            _selectedConversation = conversation;
                            _messages = const [];
                            _error = null;
                          });
                          await _loadMessages(conversation.id);
                        },
                      );
                    },
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
  final Map<String, String> senderUsernames;
  final String? error;
  final Future<void> Function() onSend;

  const _ConversationDetailView({
    required this.conversation,
    required this.currentUserId,
    required this.scrollController,
    required this.messageController,
    required this.messages,
    required this.senderUsernames,
    required this.error,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              conversation.isGroup
                  ? conversation.title
                  : conversation.otherUsername,
              style: const TextStyle(
                fontSize: 20,
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
          child: messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum_outlined,
                            size: 34, color: BluchetPalette.primary),
                        const SizedBox(height: 10),
                        const Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: BluchetPalette.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Send the first message below. If old messages should appear, check SELECT permissions on the Supabase messages table.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: BluchetPalette.textMuted),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMine = message.senderId == currentUserId;
                    final localTime = message.createdAt.toLocal();
                    final time = '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
                    final senderName = senderUsernames[message.senderId];
                    return Align(
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(maxWidth: 620),
                        decoration: BoxDecoration(
                          color: isMine
                              ? const Color(0xFF293545)
                              : const Color(0xFF293B3A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (conversation.isGroup && senderName != null) ...[
                              Text(
                                senderName,
                                style: const TextStyle(
                                  color: BluchetPalette.turquoise300,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            Text(
                              message.text,
                              style: const TextStyle(
                                color: Color(0xFFF0F5F4),
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              time,
                              style: const TextStyle(
                                color: Color(0xFFB2C0BE),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    style: const TextStyle(color: BluchetPalette.inputText),
                    minLines: 1,
                    maxLines: 5,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      hintText: 'Type a message',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 44,
                  height: 44,
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
  final String? createdBy;
  final List<String> memberIds;
  final DateTime? lastActivityAt;

  const _Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    this.isGroup = false,
    this.title = '',
    this.createdBy,
    this.memberIds = const [],
    this.lastActivityAt,
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
