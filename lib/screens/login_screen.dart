import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();

  late final AnimationController _floatController;

  bool _isSignUp = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final nickname = _nicknameController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = '아이디와 비밀번호를 모두 입력해 주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = _isSignUp
          ? await ApiService.signup(
              username: username,
              password: password,
              nickname: nickname.isNotEmpty ? nickname : null,
            )
          : await ApiService.login(
              username: username,
              password: password,
            );

      if (!mounted) return;

      final displayName = result['nickname'] ?? result['username'] ?? '친구';
      final message = _isSignUp
          ? '환영해요, $displayName님! 크레용이랑 친구가 됐어요.'
          : '반가워요, $displayName님! 크레용이 기다리고 있었어요.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Image.asset(CrayongImages.wink, width: 32, height: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: AppTextStyles.labelLarge(color: Colors.white),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCrayong(),
                  Container(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                    decoration: AppDecorations.card(radius: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isSignUp ? '이야기 세상 가입하기' : '이야기 세상 로그인',
                          style: AppTextStyles.headingLarge(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isSignUp
                              ? '계정을 만들고 크레용이랑 나만의 동화를 간직해요'
                              : '크레용이랑 동화 여행을 떠나볼까요?',
                          style: AppTextStyles.bodyMedium(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (_errorMessage != null) ...[
                          _buildError(),
                          const SizedBox(height: 14),
                        ],
                        _inputField(
                          controller: _usernameController,
                          hint: '아이디를 입력하세요',
                          icon: Icons.person_outline_rounded,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                        ),
                        const SizedBox(height: 12),
                        _inputField(
                          controller: _passwordController,
                          hint: '비밀번호를 입력하세요',
                          icon: Icons.lock_outline_rounded,
                          isPassword: true,
                          textInputAction: _isSignUp
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onSubmitted: (_) {
                            if (_isSignUp) {
                              FocusScope.of(context).nextFocus();
                            } else if (!_isLoading) {
                              _submit();
                            }
                          },
                        ),
                        if (_isSignUp) ...[
                          const SizedBox(height: 12),
                          _inputField(
                            controller: _nicknameController,
                            hint: '닉네임 (선택 사항)',
                            icon: Icons.face_rounded,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (!_isLoading) _submit();
                            },
                          ),
                        ],
                        const SizedBox(height: 24),
                        _StickerButton(
                          onTap: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.onPrimary,
                                  ),
                                )
                              : Text(
                                  _isSignUp ? '회원가입 완료' : '로그인하기',
                                  style: AppTextStyles.button(),
                                ),
                        ),
                        const SizedBox(height: 14),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isSignUp = !_isSignUp;
                              _errorMessage = null;
                            });
                          },
                          child: Text(
                            _isSignUp
                                ? '이미 계정이 있나요? 로그인하기'
                                : '처음 왔나요? 회원가입하기',
                            style: AppTextStyles.labelMedium(
                              color: AppColors.primaryText,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const AppShell()),
                            );
                          },
                          icon: const Icon(
                            Icons.bolt_rounded,
                            size: 16,
                            color: AppColors.textHint,
                          ),
                          label: Text(
                            '관리자 빠른 시작 (테스트용)',
                            style: AppTextStyles.labelSmall(),
                          ),
                        ),
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

  Widget _buildCrayong() {
    return SizedBox(
      height: 170,
      child: AnimatedBuilder(
        animation: _floatController,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_floatController.value);
          return Transform.translate(
            offset: Offset(0, -8 * t),
            child: child,
          );
        },
        child: Image.asset(
          CrayongImages.main,
          height: 160,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTextStyles.bodySmall(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: AppTextStyles.bodyLarge(),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 20),
        hintText: hint,
      ),
    );
  }
}

class _StickerButton extends StatefulWidget {
  const _StickerButton({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_StickerButton> createState() => _StickerButtonState();
}

class _StickerButtonState extends State<_StickerButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const depth = 4.0;
    final enabled = widget.onTap != null;
    final down = _pressed && enabled;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: SizedBox(
          height: 54 + depth,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            margin: EdgeInsets.only(top: down ? depth : 0, bottom: down ? 0 : depth),
            width: double.infinity,
            alignment: Alignment.center,
            decoration: AppDecorations.primaryButton(depth: down ? 0 : depth),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}