import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/crayong_widgets.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nicknameController = TextEditingController();
  String _username = '';
  String _savedNickname = '';
  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    final info = await ApiService.getUserInfo();
    if (!mounted) return;
    setState(() {
      _username = info['username']!;
      _savedNickname = info['nickname']!;
      _nicknameController.text = _savedNickname;
      _isLoading = false;
    });
  }

  void _showMessage(String text, {String image = CrayongImages.wink}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Image.asset(image, width: 30, height: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: AppTextStyles.labelLarge(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveNickname() async {
    final newNick = _nicknameController.text.trim();
    if (newNick.isEmpty) {
      _showMessage('닉네임을 입력해 주세요.', image: CrayongImages.surprised);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ApiService.updateNickname(newNick);
      if (!mounted) return;
      _showMessage('이제 "$newNick"(이)라고 부를게요!', image: CrayongImages.celebrate);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        kDebugMode ? '변경 실패: $e' : '닉네임을 못 바꿨어요. 잠시 후 다시 해 볼래요?',
        image: CrayongImages.surprised,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(CrayongImages.surprised, height: 100),
                const SizedBox(height: 12),
                Text('정말 로그아웃할까요?', style: AppTextStyles.headingMedium()),
                const SizedBox(height: 4),
                Text(
                  '크레용이 여기서 기다리고 있을게요.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium(),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border, width: 2),
                        ),
                        child: const Text('더 있을래요'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          textStyle: AppTextStyles.button(color: Colors.white),
                        ),
                        child: const Text('로그아웃'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirm == true) {
      await ApiService.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  RoundIconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Text('내 프로필', style: AppTextStyles.display()),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const CrayongStatusView(
                      image: CrayongImages.drawing,
                      title: '내 정보를 가져오고 있어요',
                      child: SizedBox(
                        width: 160,
                        child: LinearProgressIndicator(minHeight: 6, borderRadius: BorderRadius.all(Radius.circular(3))),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Column(
                            children: [
                              _buildAvatar(),
                              const SizedBox(height: 14),
                              Text(
                                _savedNickname.isNotEmpty ? _savedNickname : '동화친구',
                                style: AppTextStyles.display(),
                              ),
                              Text('크레용의 동화 친구', style: AppTextStyles.bodyMedium()),
                              const SizedBox(height: 24),
                              _buildInfoCard(),
                              const SizedBox(height: 20),
                              _buildLogoutButton(),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return SizedBox(
      width: 150,
      height: 124,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 5),
              boxShadow: const [
                BoxShadow(color: AppColors.border, blurRadius: 0, offset: Offset(0, 5)),
              ],
            ),
            child: const Icon(Icons.face_rounded, size: 64, color: AppColors.primaryText),
          ),
          Positioned(
            right: -10,
            bottom: -6,
            child: Image.asset(CrayongImages.wink, height: 70),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('계정 정보', style: AppTextStyles.headingMedium()),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.secondaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.badge_rounded, size: 20, color: AppColors.secondaryDark),
              ),
              const SizedBox(width: 12),
              Text('아이디', style: AppTextStyles.bodyMedium()),
              const Spacer(),
              Text(
                _username.isNotEmpty ? _username : '로컬 사용자',
                style: AppTextStyles.labelLarge(),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Text('닉네임 바꾸기', style: AppTextStyles.labelMedium()),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nicknameController,
                  style: AppTextStyles.bodyLarge(),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!_isSaving) _saveNickname();
                  },
                  decoration: const InputDecoration(
                    hintText: '불리고 싶은 이름',
                    prefixIcon: Icon(Icons.edit_rounded, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveNickname,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary),
                        )
                      : const Text('저장'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _handleLogout,
        icon: const Icon(Icons.logout_rounded, color: AppColors.accentDark, size: 20),
        label: Text('로그아웃', style: AppTextStyles.button(color: AppColors.accentDark)),
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.accentLight, width: 2),
        ),
      ),
    );
  }
}