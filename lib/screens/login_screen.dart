import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../services/api_service.dart';
import 'fairy_tale_list_screen.dart';
import 'home_screen.dart'; // AppShell이 정의된 파일

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _isSignUp = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
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
      // 1. API 호출 후 반환값(유저 정보) 받기
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

      // 2. 환영 메시지 생성 (닉네임 기준)
      final displayName = result['nickname'] ?? result['username'] ?? '친구';
      final message = _isSignUp
          ? '🎉 환영합니다, $displayName님! 가입이 완료되었어요.'
          : '✨ 반가워요, $displayName님! 동화 여행을 시작해 볼까요?';

      // 3. 플로팅 스낵바 띄우기
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF7E57C2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          duration: const Duration(seconds: 3),
        ),
      );

      // 4. 메인 홈 화면으로 전환
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
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7E57C2).withOpacity(0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 상단 요정 애니메이션
                    SizedBox(
                      height: 120,
                      child: Lottie.asset(
                        'assets/animations/fairy.json',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isSignUp ? '이야기 세상 가입하기' : '이야기 세상 로그인',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3D2C8D),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isSignUp
                          ? '계정을 만들고 나만의 동화를 간직해 보세요!'
                          : '로그인하고 마법 같은 동화를 시작해 볼까요?',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // 에러 메시지
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: Colors.red),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 입력 필드
                    _inputField(
                      controller: _usernameController,
                      hint: '아이디를 입력하세요',
                      icon: Icons.person_outline_rounded,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) {
                        // 아이디 입력 후 엔터 치면 비밀번호 창으로 포커스 이동
                        FocusScope.of(context).nextFocus();
                      },
                    ),
                    const SizedBox(height: 12),
                    _inputField(
                      controller: _passwordController,
                      hint: '비밀번호를 입력하세요',
                      icon: Icons.lock_outline_rounded,
                      isPassword: true,
                      // 회원가입 모드면 닉네임 창으로 가고, 일반 로그인이면 바로 완료(done)
                      textInputAction: _isSignUp ? TextInputAction.next : TextInputAction.done,
                      onSubmitted: (_) {
                        if (_isSignUp) {
                          FocusScope.of(context).nextFocus();
                        } else {
                          // 🚀 비밀번호에서 엔터 누르면 즉시 로그인 실행!
                          if (!_isLoading) _submit();
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
                          // 🚀 닉네임에서 엔터 누르면 즉시 가입 완료 실행!
                          if (!_isLoading) _submit();
                        },
                      ),
                    ],
                    const SizedBox(height: 24),

                    // 로그인/회원가입 버튼
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7E57C2),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : Text(
                          _isSignUp ? '회원가입 완료' : '로그인하기',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 전환 텍스트 (로그인 <-> 회원가입)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isSignUp = !_isSignUp;
                          _errorMessage = null;
                        });
                      },
                      child: Text(
                        _isSignUp
                            ? '이미 계정이 있으신가요? 로그인하기'
                            : '처음 오셨나요? 회원가입하기',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF7E57C2),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // 👇 [여기 추가!] 3번: 관리자 빠른 로그인 버튼
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const AppShell()),
                        );
                      },
                      icon: const Icon(Icons.bolt_rounded, size: 18, color: Color(0xFFB39DDB)),
                      label: const Text(
                        '⚡ 관리자 빠른 시작 (테스트용)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9575CD),
                          fontWeight: FontWeight.w600,
                        ),
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



  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputAction? textInputAction,      // 👈 추가: 키보드 엔터 모양 (next / done)
    void Function(String)? onSubmitted,    // 👈 추가: 엔터 쳤을 때 실행할 함수
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      textInputAction: textInputAction,      // 👈 연결
      onSubmitted: onSubmitted,              // 👈 연결
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF7E57C2), size: 20),
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
        filled: true,
        fillColor: const Color(0xFFF8F4FF),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

