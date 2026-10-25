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

String _buildInternalEmail(String username) {
  final safe = username
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '.');

  final label = safe.isEmpty ? 'user' : safe;
  // Use a reserved placeholder domain because Supabase rejects some synthetic
  // domains like @test.com during auth validation.
  return '$label@example.com';
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

  bool _registerDone = false;
  bool _loginDone = false;
  bool _messageDone = false;
  bool _isSubmitting = false;
  bool _isSendingMessage = false;
  String? _registerError;
  String? _loginError;
  String? _messageError;

  String get _statusText {
    if (!widget.configured) {
      return 'A backend még nincs konfigurálva';
    }

    if (widget.startupError != null) {
      return 'A backend inicializálása sikertelen:\n${_friendly(widget.startupError!)}';
    }

    return '';
  }

  Future<void> _handleRegister() async {
    final username = _normalizeUsername(_registerUsername.text);
    final password = _registerPassword.text.trim();
    final hiddenEmail = _buildInternalEmail(username);

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
      final authResponse = await db.auth.signUp(
        email: hiddenEmail,
        password: password,
      );

      final user = authResponse.user;
      if (user != null) {
        await db.from('profiles').upsert({
          'id': user.id,
          'username': username,
          'email': hiddenEmail,
          'email_verified': user.emailConfirmedAt != null,
        }).select();
      }

      if (!mounted) return;

      setState(() {
        _registerDone = true;
        _registerUsername.clear();
        _registerPassword.clear();
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
    final hiddenEmail = _buildInternalEmail(username);

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
      await db.auth.signInWithPassword(
        email: hiddenEmail,
        password: password,
      );

      if (!mounted) return;

      setState(() {
        _loginDone = true;
        _loginUsername.clear();
        _loginPassword.clear();
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
    final currentUser = db.auth.currentUser;

    if (currentUser == null) {
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
        'get_or_create_direct_conversation',
        params: {'other_user': targetUserId},
      );

      await db.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': currentUser.id,
        'ciphertext': body,
      });

      if (!mounted) return;

      setState(() {
        _messageDone = true;
        _messageTo.clear();
        _messageSubject.clear();
        _messageBody.clear();
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
                            const SizedBox(width: 8),
                            Expanded(
                              child: _TabButton(
                                label: 'Üzenet küldése',
                                selected: _selectedIndex == 2,
                                onPressed: () => setState(() => _selectedIndex = 2),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        if (_selectedIndex == 0) _buildRegisterForm(),
                        if (_selectedIndex == 1) _buildLoginForm(),
                        if (_selectedIndex == 2) _buildMessageForm(),
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
    return Form(
      key: _messageKey,
      child: Column(
        children: [
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          _Field(
            label: 'Üzenet',
            hint: 'Írd ide az üzenetedet...',
            controller: _messageBody,
            maxLines: 6,
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

  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.maxLines = 1,
    this.validator,
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
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF9FB1C2),
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.02),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF80B8FF)),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
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
