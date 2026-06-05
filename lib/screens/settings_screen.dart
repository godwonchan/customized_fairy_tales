import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════
//  설정 화면
// ═══════════════════════════════════════════════════════════════

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // 설정값
  String _fontSize = '중간';
  String _bgTheme = '라벤더';

  final List<String> _fontSizes = ['작게', '중간', '크게'];
  final List<String> _bgThemes = ['라벤더', '민트', '핑크', '하늘'];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isTablet ? 32 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 브레드크럼
                Text('10 설정',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[500])),
                const SizedBox(height: 8),
                // 제목
                Text('설정',
                    style: TextStyle(
                        fontSize: isTablet ? 28 : 22,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF3D2C8D))),
                const SizedBox(height: 24),

                // ── 계정 설정 그룹 ──
                _buildSectionGroup([
                  _buildSettingItem(
                    icon: Icons.person_outline,
                    label: '계정 관리',
                    onTap: () => _showComingSoon(context),
                    isTablet: isTablet,
                  ),
                  _buildSettingItem(
                    icon: Icons.notifications_none_rounded,
                    label: '알림 설정',
                    onTap: () => _showComingSoon(context),
                    isTablet: isTablet,
                  ),
                  _buildSettingItemWithValue(
                    icon: Icons.text_fields_rounded,
                    label: '글자 크기',
                    value: _fontSize,
                    onTap: () => _showFontSizeDialog(context),
                    isTablet: isTablet,
                  ),
                  _buildSettingItemWithValue(
                    icon: Icons.color_lens_outlined,
                    label: '배경 테마',
                    value: _bgTheme,
                    onTap: () => _showBgThemeDialog(context),
                    isTablet: isTablet,
                    isLast: true,
                  ),
                ]),

                const SizedBox(height: 16),

                // ── 기타 그룹 ──
                _buildSectionGroup([
                  _buildSettingItem(
                    icon: Icons.storage_outlined,
                    label: '데이터 관리',
                    onTap: () => _showComingSoon(context),
                    isTablet: isTablet,
                  ),
                  _buildSettingItem(
                    icon: Icons.headset_mic_outlined,
                    label: '고객센터',
                    onTap: () => _showComingSoon(context),
                    isTablet: isTablet,
                  ),
                  _buildSettingItemWithValue(
                    icon: Icons.info_outline_rounded,
                    label: '앱 정보',
                    value: 'v1.0.0',
                    onTap: () => _showAppInfo(context),
                    isTablet: isTablet,
                    isLast: true,
                    showArrow: false,
                  ),
                ]),

                const SizedBox(height: 32),

                // ── 토끼 캐릭터 ──
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: isTablet ? 120 : 100,
                        height: isTablet ? 120 : 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE7F6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.emoji_nature,
                            size: isTablet ? 64 : 54,
                            color: const Color(0xFF7E57C2)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '무엇이든 도와드릴게요! 😊',
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 설정 그룹 컨테이너 ──
  Widget _buildSectionGroup(List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(children: items),
    );
  }

  // ── 일반 설정 아이템 ──
  Widget _buildSettingItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isTablet,
    bool isLast = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 20 : 16,
            vertical: isTablet ? 16 : 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                      color: Colors.grey[100]!, width: 1)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF7E57C2)),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontSize: isTablet ? 15 : 14,
                    color: const Color(0xFF3D2C8D),
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(Icons.chevron_right,
                size: 20, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  // ── 값이 있는 설정 아이템 ──
  Widget _buildSettingItemWithValue({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    required bool isTablet,
    bool isLast = false,
    bool showArrow = true,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 20 : 16,
            vertical: isTablet ? 16 : 14),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                      color: Colors.grey[100]!, width: 1)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF7E57C2)),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontSize: isTablet ? 15 : 14,
                    color: const Color(0xFF3D2C8D),
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(value,
                style: TextStyle(
                    fontSize: isTablet ? 14 : 13,
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w400)),
            if (showArrow) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right,
                  size: 20, color: Colors.grey[400]),
            ],
          ],
        ),
      ),
    );
  }

  // ── 글자 크기 선택 다이얼로그 ──
  void _showFontSizeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('글자 크기',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3D2C8D))),
              const SizedBox(height: 16),
              ..._fontSizes.map((size) {
                final isSelected = _fontSize == size;
                return GestureDetector(
                  onTap: () {
                    setState(() => _fontSize = size);
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFEDE7F6)
                          : const Color(0xFFF8F4FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isSelected
                              ? const Color(0xFF7E57C2)
                              : Colors.transparent),
                    ),
                    child: Row(
                      children: [
                        Text(size,
                            style: TextStyle(
                                fontSize: 14,
                                color: isSelected
                                    ? const Color(0xFF7E57C2)
                                    : const Color(0xFF3D2C8D),
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                        const Spacer(),
                        if (isSelected)
                          const Icon(Icons.check,
                              size: 18, color: Color(0xFF7E57C2)),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ── 배경 테마 선택 다이얼로그 ──
  void _showBgThemeDialog(BuildContext context) {
    final themeColors = {
      '라벤더': const Color(0xFFEDE7F6),
      '민트': const Color(0xFFE8F5E9),
      '핑크': const Color(0xFFFCE4EC),
      '하늘': const Color(0xFFE3F2FD),
    };

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('배경 테마',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3D2C8D))),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _bgThemes.map((theme) {
                  final isSelected = _bgTheme == theme;
                  final color = themeColors[theme]!;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _bgTheme = theme);
                      Navigator.pop(context);
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF7E57C2)
                                    : Colors.transparent,
                                width: 2.5),
                          ),
                          child: isSelected
                              ? const Center(
                                  child: Icon(Icons.check,
                                      color: Color(0xFF7E57C2),
                                      size: 24))
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(theme,
                            style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? const Color(0xFF7E57C2)
                                    : Colors.grey[600],
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 앱 정보 다이얼로그 ──
  void _showAppInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9575CD), Color(0xFF7E57C2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.auto_stories,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              const Text('동화 앱',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3D2C8D))),
              const SizedBox(height: 4),
              Text('버전 v1.0.0',
                  style: TextStyle(
                      fontSize: 14, color: Colors.grey[400])),
              const SizedBox(height: 12),
              Text(
                'AI 기술을 활용하여 아동 사용자 맞춤형\n동화 생성 시스템',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.5),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7E57C2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 12),
                  elevation: 0,
                ),
                child: const Text('확인'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 준비 중 토스트 ──
  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('준비 중이에요! 😊'),
        backgroundColor: const Color(0xFF7E57C2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}
