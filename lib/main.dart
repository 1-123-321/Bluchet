import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  int _selectedIndex = 0;
  final _registerKey = GlobalKey<FormState>();
  final _loginKey = GlobalKey<FormState>();
  final _messageKey = GlobalKey<FormState>();

  final _registerUsername = TextEditingController();
  final _registerPassword = TextEditingController();
  final _loginUsername = TextEditingController();
  final _loginPassword = TextEditingController();
  final _messageTo = TextEditingController();
  final _messageSubject = TextEditingController();
  final _messageBody = TextEditingController();
  final _userSearchController = TextEditingController();

  bool _registerDone = false;
  bool _loginDone = false;
  bool _messageDone = false;
  bool _isSubmitting = false;
  bool _isSendingMessage = false;
  bool _isSearchingUsers = false;
  String? _registerError;
  String? _loginError;
  String? _messageError;
  String? _userSearchError;
  String? _currentUserId;
  String? _currentUsername;
  final Map<String, List<String>> _conversationHistory = {};
  final List<String> _userSearchResults = <String>[];
  String? _selectedConversationUser;

  bool get _isLoggedIn => _currentUserId != null;

  String get _statusText {
    if (!widget.configured) {
      return 'A backend még nincs konfigurálva';
    }

    if (widget.startupError != null) {
      return 'A backend inicializálása sikertelen:\n${_friendly(widget.startupError!)}';
    }

    return '';
  }

  Future<String?> _fetchUsernameById(String userId) async {
    final response = await db
        .from('profiles')
        .select('username')
        .eq('id', userId)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    final username = response['username'];
    return username is String ? username : null;
  }

  Future<void> _loadConversationHistory() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      return;
    }

    final conversationIdsResponse = await db
        .from('conversation_participants')
        .select('conversation_id')
        .eq('user_id', currentUserId);

    final conversations = <String, List<String>>{};

    for (final row in conversationIdsResponse as List<dynamic>) {
      final conversationId = row['conversation_id'] as String?;
      if (conversationId == null || conversationId.isEmpty) {
        continue;
      }

      final participantsResponse = await db
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', conversationId);

      String? peerUsername;
      for (final participantRow in participantsResponse as List<dynamic>) {
        final participantUserId = participantRow['user_id'] as String?;
        if (participantUserId == null || participantUserId == currentUserId) {
          continue;
        }

        peerUsername = await _fetchUsernameById(participantUserId) ?? peerUsername;
      }

      final peerName = peerUsername ?? 'ismeretlen';
      final messagesResponse = await db
          .from('messages')
          .select('sender_id, ciphertext')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      final messageList = <String>[];
      for (final messageRow in messagesResponse as List<dynamic>) {
        final senderId = messageRow['sender_id'] as String?;
        final content = messageRow['ciphertext'] as String? ?? '';
        final senderName = senderId == null ? 'ismeretlen' : (await _fetchUsernameById(senderId) ?? 'ismeretlen');

        if (senderId == currentUserId) {
          messageList.add('Én: $content');
        } else {
          messageList.add('$senderName: $content');
        }
      }

      if (messageList.isNotEmpty) {
        conversations[peerName] = messageList;
      }
    }

    if (!mounted) return;

    setState(() {
      _conversationHistory
        ..clear()
        ..addAll(conversations);

      if (_conversationHistory.isNotEmpty) {
        final first = _conversationHistory.keys.first;
        _selectedConversationUser ??= first;
        if (_selectedConversationUser != null && !_conversationHistory.containsKey(_selectedConversationUser)) {
          _selectedConversationUser = first;
        }
      } else {
        _selectedConversationUser = null;
      }
    });
  }

  Future<void> _handleUserSearch() async {
    final query = _normalizeUsername(_userSearchController.text);
    if (query.isEmpty) {
      setState(() {
        _userSearchResults.clear();
        _userSearchError = null;
      });
      return;
    }

    setState(() {
      _isSearchingUsers = true;
      _userSearchError = null;
    });

    try {
      final response = await db
          .from('profiles')
          .select('username')
          .ilike('username', '%$query%')
          .order('username', ascending: true)
          .limit(10);

      final rows = response is List ? response : const <dynamic>[];
      final usernames = <String>[];
      for (final row in rows) {
        if (row is Map) {
          final username = row['username'];
          if (username is String && username.isNotEmpty) {
            usernames.add(_normalizeUsername(username));
          }
        }
      }

      setState(() {
        _userSearchResults
          ..clear()
          ..addAll(usernames.where((user) => user != _currentUsername));
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _userSearchError = _friendly(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _userSearchError = _friendly(e));
    } finally {
      if (mounted) {
        setState(() => _isSearchingUsers = false);
      }
    }
  }

  void _selectUserForMessage(String username) {
    final cleaned = _normalizeUsername(username);
    _messageTo.text = cleaned;
    _selectedConversationUser = cleaned;
    _userSearchController.text = cleaned;
    setState(() {
      _userSearchResults.clear();
      _userSearchError = null;
    });
  }

  void _selectConversation(String username) {
    final cleaned = _normalizeUsername(username);
    _selectedConversationUser = cleaned;
    _messageTo.text = cleaned;
    if (mounted) setState(() {});
  }

  void _addLocalMessage(String username, String message) {
    final cleaned = _normalizeUsername(username);
    final list = _conversationHistory.putIfAbsent(cleaned, () => <String>[]);
    list.add(message);
    _selectedConversationUser = cleaned;
    _messageTo.text = cleaned;
    if (mounted) setState(() {});
  }

  Future<void> _handleRegister() async {
    final username = _normalizeUsername(_registerUsername.text);
    final password = _registerPassword.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _registerDone = false;
        _registerError = 'A felhasználónév és a jelszó kötelező.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _registerError = null;
      _registerDone = false;
    });

    try {
      final result = await db.rpc(
        'register_user',
        params: {'p_username': username, 'p_password': password},
      );

      final userId = result is String ? result : (result as Map?)?['user_id'] as String?;
      if (userId == null || userId.isEmpty) {
        throw Exception('A regisztráció sikertelen.');
      }

      _currentUserId = userId;
      _currentUsername = username;
      await _loadConversationHistory();

      if (!mounted) return;

      setState(() {
        _registerDone = true;
        _registerUsername.clear();
        _registerPassword.clear();
        _selectedIndex = 2;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _registerError = _friendly(e));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _registerError = _friendly(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _registerError = _friendly(e));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleLogin() async {
    final username = _normalizeUsername(_loginUsername.text);
    final password = _loginPassword.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _loginDone = false;
        _loginError = 'A felhasználónév és a jelszó kötelező.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _loginError = null;
      _loginDone = false;
    });

    try {
      final result = await db.rpc(
        'login_user',
        params: {'p_username': username, 'p_password': password},
      );

      final userId = result is String ? result : (result as Map?)?['user_id'] as String?;
      if (userId == null || userId.isEmpty) {
        throw Exception('A bejelentkezés sikertelen.');
      }

      _currentUserId = userId;
      _currentUsername = username;
      await _loadConversationHistory();

      if (!mounted) return;

      setState(() {
        _loginDone = true;
        _loginUsername.clear();
        _loginPassword.clear();
        _selectedIndex = 2;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _loginError = _friendly(e));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _loginError = _friendly(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loginError = _friendly(e));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _handleSendMessage() async {
    final toUsername = _normalizeUsername(_messageTo.text);
    final body = _messageBody.text.trim();
    final currentUserId = _currentUserId;

    if (currentUserId == null) {
      setState(() => _messageError = 'Előbb be kell jelentkezni.');
      return;
    }

    if (toUsername.isEmpty || body.isEmpty) {
      setState(() => _messageError = 'A címzett és az üzenet mező kötelező.');
      return;
    }

    setState(() {
      _isSendingMessage = true;
      _messageError = null;
      _messageDone = false;
    });

    try {
      final profileResponse = await db
          .from('profiles')
          .select('id')
          .eq('username', toUsername)
          .maybeSingle();

      if (profileResponse == null) {
        throw Exception('A címzett felhasználó nem található.');
      }

      final targetUserId = profileResponse['id'] as String;
      final conversationId = await db.rpc(
        'get_or_create_direct_conversation_for_user',
        params: {'actor_id': currentUserId, 'other_user': targetUserId},
      );

      await db.rpc(
        'insert_message_for_user',
        params: {
          'actor_id': currentUserId,
          'conversation_id': conversationId,
          'ciphertext': body,
        },
      );

      _addLocalMessage(toUsername, 'Én: $body');
      await _loadConversationHistory();

      if (!mounted) return;

      setState(() {
        _messageDone = true;
        _messageTo.text = toUsername;
        _messageBody.clear();
        _messageSubject.clear();
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _messageError = _friendly(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messageError = _friendly(e));
    } finally {
      if (mounted) {
        setState(() => _isSendingMessage = false);
      }
    }
  }

  @override
  void dispose() {
    _registerUsername.dispose();
    _registerPassword.dispose();
    _loginUsername.dispose();
    _loginPassword.dispose();
    _messageTo.dispose();
    _messageSubject.dispose();
    _messageBody.dispose();
    _userSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluchet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _blue,
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: Center(
            child: Container(
              width: 820,
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0x0F12202A),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Bluchet',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _TabButton(
                                label: 'Regisztráció',
                                selected: _selectedIndex == 0,
                                onPressed: () => setState(() => _selectedIndex = 0),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _TabButton(
                                label: 'Bejelentkezés',
                                selected: _selectedIndex == 1,
                                onPressed: () => setState(() => _selectedIndex = 1),
                              ),
                            ),
                            if (_isLoggedIn) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: _TabButton(
                                  label: 'Üzenetek',
                                  selected: _selectedIndex == 2,
                                  onPressed: () => setState(() => _selectedIndex = 2),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 26),
                        if (_selectedIndex == 0) _buildRegisterForm(),
                        if (_selectedIndex == 1) _buildLoginForm(),
                        if (_selectedIndex == 2 && !_isLoggedIn)
                          _buildLoginRequiredCard(),
                        if (_selectedIndex == 2 && _isLoggedIn) _buildMessageForm(),
                        const SizedBox(height: 12),
                        if (_selectedIndex == 0 && _registerDone)
                          _buildSuccess('Sikeres regisztráció!'),
                        if (_selectedIndex == 0 && _registerError != null)
                          _buildError(_registerError!),
                        if (_selectedIndex == 1 && _loginDone)
                          _buildSuccess('Sikeres bejelentkezés!'),
                        if (_selectedIndex == 1 && _loginError != null)
                          _buildError(_loginError!),
                        if (_selectedIndex == 2 && _messageDone)
                          _buildSuccess('Az üzenet elküldve.'),
                        if (_selectedIndex == 2 && _messageError != null)
                          _buildError(_messageError!),
                        const SizedBox(height: 12),
                        if (_selectedIndex == 0 && _statusText.isNotEmpty)
                          _buildStatusCard(_statusText),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterForm() {
    return Form(
      key: _registerKey,
      child: Column(
        children: [
          _Field(
            label: 'Felhasználónév',
            hint: 'pelda',
            controller: _registerUsername,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Kötelező mező';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _Field(
            label: 'Jelszó',
            hint: '••••••••',
            controller: _registerPassword,
            obscure: true,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Kötelező mező';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _handleRegister,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFF80B8FF),
                foregroundColor: const Color(0xFF04111D),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _isSubmitting ? 'Feldolgozás...' : 'Regisztráció',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginKey,
      child: Column(
        children: [
          _Field(
            label: 'Felhasználónév',
            hint: 'pelda',
            controller: _loginUsername,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Kötelező mező';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _Field(
            label: 'Jelszó',
            hint: '••••••••',
            controller: _loginPassword,
            obscure: true,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Kötelező mező';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFF80B8FF),
                foregroundColor: const Color(0xFF04111D),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _isSubmitting ? 'Feldolgozás...' : 'Bejelentkezés',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageForm() {
    final conversationNames = _conversationHistory.keys.toList();
    final activeConversation =
        _selectedConversationUser ?? (conversationNames.isNotEmpty ? conversationNames.first : null);
    final messages = activeConversation == null
        ? <String>[]
        : (_conversationHistory[activeConversation] ?? const <String>[]);

    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useSplitView = constraints.maxWidth >= 560;

            return useSplitView
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 220,
                        child: _buildConversationList(conversationNames, activeConversation),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildThreadView(activeConversation, messages),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _buildConversationList(conversationNames, activeConversation),
                      const SizedBox(height: 12),
                      _buildThreadView(activeConversation, messages),
                    ],
                  );
          },
        ),
      ),
    );
  }

  Widget _buildConversationList(List<String> conversationNames, String? activeConversation) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Text(
              'Csevegések',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          if (conversationNames.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Még nincs beszélgetésed.',
                style: TextStyle(color: _muted),
              ),
            )
          else
            ...conversationNames.map((name) {
              final selected = activeConversation == name;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _selectConversation(name),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFF80B8FF) : Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? Colors.transparent : Colors.white.withOpacity(0.06),
                      ),
                    ),
                    child: Text(
                      name,
                      style: TextStyle(
                        color: selected ? const Color(0xFF04111D) : Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildThreadView(String? activeConversation, List<String> messages) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          if (activeConversation == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Válassz ki egy csevegést a bal oldali listából.',
                style: TextStyle(color: _muted),
              ),
            )
          else ...[
            Text(
              'Csevegés: $activeConversation',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 180, maxHeight: 260),
              child: ListView.separated(
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final message = messages[index];
                  final isMine = message.startsWith('Én: ');
                  return Align(
                    alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 360),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isMine ? const Color(0xFF80B8FF) : const Color(0xFF1A2338),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        message,
                        style: TextStyle(
                          color: isMine ? const Color(0xFF04111D) : Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: 'Felhasználó keresése',
                    hint: 'username',
                    controller: _userSearchController,
                    onSubmitted: (_) => _handleUserSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSearchingUsers ? null : _handleUserSearch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF80B8FF),
                      foregroundColor: const Color(0xFF04111D),
                    ),
                    child: Text(_isSearchingUsers ? '...' : 'Keresés'),
                  ),
                ),
              ],
            ),
            if (_userSearchError != null) ...[
              const SizedBox(height: 8),
              _buildError(_userSearchError!),
            ],
            if (_userSearchResults.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _userSearchResults.map((user) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _selectUserForMessage(user),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          user,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _Field(
              label: 'Címzett',
              hint: 'username',
              controller: _messageTo,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Kötelező mező';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Tárgy',
              hint: 'Üzenet tárgya',
              controller: _messageSubject,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Kötelező mező';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _Field(
              label: 'Üzenet',
              hint: 'Írd ide az üzenetedet...',
              controller: _messageBody,
              maxLines: 4,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Kötelező mező';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSendingMessage ? null : _handleSendMessage,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: const Color(0xFF80B8FF),
                  foregroundColor: const Color(0xFF04111D),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _isSendingMessage ? 'Küldés...' : 'Üzenet elküldése',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _muted,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildLoginRequiredCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x1AFF5A5A),
        border: Border.all(color: const Color(0x40FF5A5A)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Előbb jelentkezz be, hogy üzenetet küldhess.',
        style: TextStyle(
          color: Color(0xFFFFB5B5),
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildSuccess(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x1A7AE4B1),
        border: Border.all(color: const Color(0x407AE4B1)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: _success,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildError(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x1AFF5A5A),
        border: Border.all(color: const Color(0x40FF5A5A)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFFFB5B5),
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: selected ? const Color(0xFF80B8FF) : Colors.white.withOpacity(0.02),
        foregroundColor: selected ? const Color(0xFF04111D) : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? Colors.transparent : Colors.white.withOpacity(0.08),
          ),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final int maxLines;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;

  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.maxLines = 1,
    this.validator,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          maxLines: maxLines,
          validator: validator,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF8193A8)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.02),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _blue),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF5A5A)),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ],
    );
  }
}
