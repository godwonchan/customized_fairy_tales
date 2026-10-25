import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/font_size_provider.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final settings = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGroupTitle('내 계정'),
                  _buildGroup([
                    _SettingRow(
                      icon: Icons.person_rounded,
                      iconBg: AppColors.primaryLight,
                      iconColor: AppColors.primaryText,
                      label: '계정 관리',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      ),
                    ),
                    _SettingRow(
                      icon: Icons.notifications_rounded,
                      iconBg: AppColors.secondaryLight,
                      iconColor: AppColors.secondaryDark,
                      label: '알림 설정',
                      onTap: _showComingSoon,
                    ),
                  ]),
                  const SizedBox(height: 22),
                  _buildGroupTitle('읽기 설정'),
                  _buildGroup([
                    _buildFontSizeRow(),
                  ]),
                  const SizedBox(height: 22),
                  _buildGroupTitle('그 밖에'),
                  _buildGroup([
                    _SettingRow(
                      icon: Icons.folder_rounded,
                      iconBg: const Color(0xFFE2F0F8),
                      iconColor: const Color(0xFF4F93C2),
                      label: '데이터 관리',
                      onTap: _showComingSoon,
                    ),
                    _SettingRow(
                      icon: Icons.headset_mic_rounded,
                      iconBg: AppColors.accentLight,
                      iconColor: AppColors.accentDark,
                      label: '고객센터',
                      onTap: _showComingSoon,
                    ),
                    _SettingRow(
                      icon: Icons.info_rounded,
                      iconBg: AppColors.surfaceVariant,
                      iconColor: AppColors.primaryText,
                      label: '앱 정보',
                      value: 'v1.0.0',
                      onTap: _showAppInfo,
                    ),
                  ]),
                ],
              );

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('설정', style: AppTextStyles.display()),
                            const SizedBox(width: 8),
                            Image.asset(CrayongImages.wink, height: 44),
                          ],
                        ),
                        const SizedBox(height: 16),
                        settings,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildGroupTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(text, style: AppTextStyles.labelMedium()),
    );
  }

  Widget _buildGroup(List<Widget> rows) {
    return Container(
      decoration: AppDecorations.card(radius: 22),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              const Divider(height: 1, indent: 68, endIndent: 18, color: AppColors.border),
          ],
        ],
      ),
    );
  }

  Widget _buildFontSizeRow() {
    final fontSizeProvider = context.watch<FontSizeProvider>();
    const fontSizes = FontSizeProvider.options;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconTile(
                icon: Icons.text_fields_rounded,
                background: AppColors.secondaryLight,
                color: AppColors.secondaryDark,
              ),
              const SizedBox(width: 14),
              Text('글자 크기', style: AppTextStyles.headingSmall()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(fontSizes.length, (i) {
              final size = fontSizes[i];
              final isSelected = fontSizeProvider.size == size;
              final previewSize = [15.0, 18.0, 22.0][i];
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < fontSizes.length - 1 ? 10 : 0),
                  child: GestureDetector(
                    onTap: () => context.read<FontSizeProvider>().setSize(size),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.inputFill,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.border,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isSelected ? AppColors.primaryDark : AppColors.border,
                              blurRadius: 0,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          size,
                          style: AppTextStyles.headingSmall(
                            color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
                          ).copyWith(fontSize: previewSize, height: 1.1),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  void _showAppInfo() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(CrayongImages.wink, height: 110),
                const SizedBox(height: 12),
                Text('동화랑', style: AppTextStyles.headingLarge()),
                const SizedBox(height: 2),
                Text('버전 v1.0.0', style: AppTextStyles.caption()),
                const SizedBox(height: 12),
                Text(
                  'AI 기술을 활용한\n아동 맞춤형 동화 생성 앱',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('확인'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Image.asset(CrayongImages.drawing, width: 30, height: 30),
            const SizedBox(width: 10),
            Text('크레용이 열심히 만들고 있어요!', style: AppTextStyles.labelLarge(color: Colors.white)),
          ],
        ),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color color;

  const _IconTile({required this.icon, required this.background, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 21, color: color),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String? value;
  final VoidCallback onTap;

  const _SettingRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _IconTile(icon: icon, background: iconBg, color: iconColor),
              const SizedBox(width: 14),
              Text(label, style: AppTextStyles.headingSmall()),
              const Spacer(),
              if (value != null) ...[
                Text(value!, style: AppTextStyles.labelMedium(color: AppColors.textHint)),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}