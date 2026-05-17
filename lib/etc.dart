import 'package:flutter/material.dart';
import 'main.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfffff8fb),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: 680,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 28),

                  // ✅ 뒤로가기 버튼 (좌측 정렬)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.07),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Color(0xff8a63df),
                          size: 22,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ✅ 첫 번째 그룹
                  _settingsGroup([
                    _SettingsItem(
                      icon: Icons.person_outline_rounded,
                      iconColor: const Color(0xffe57373),
                      label: '계정 관리',
                      onTap: () {},
                    ),
                    _SettingsItem(
                      icon: Icons.notifications_none_rounded,
                      iconColor: const Color(0xffe57373),
                      label: '알림 설정',
                      onTap: () {},
                    ),
                    _SettingsItem(
                      icon: Icons.text_fields_rounded,
                      iconColor: const Color(0xffe57373),
                      label: '글자 크기',
                      value: '중간',
                      onTap: () {},
                    ),
                    _SettingsItem(
                      icon: Icons.grid_view_rounded,
                      iconColor: const Color(0xffe57373),
                      label: '배경 테마',
                      value: '라벤더',
                      onTap: () {},
                      showDivider: false,
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // ✅ 두 번째 그룹
                  _settingsGroup([
                    _SettingsItem(
                      icon: Icons.work_outline_rounded,
                      iconColor: const Color(0xff8a63df),
                      label: '데이터 관리',
                      onTap: () {},
                    ),
                    
                    _SettingsItem(
                      icon: Icons.info_outline_rounded,
                      iconColor: const Color(0xff8a63df),
                      label: '앱 정보',
                      value: 'v1.0.0',
                      onTap: () {},
                      showDivider: false,
                    ),
                  ]),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsGroup(List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(children: items),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? value;
  final VoidCallback onTap;
  final bool showDivider;

  const _SettingsItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.value,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xff2d2323),
                    ),
                  ),
                ),
                if (value != null)
                  Text(
                    value!,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xffaaa4b3),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xffaaa4b3),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            thickness: 1,
            indent: 92,
            endIndent: 28,
            color: Color(0xfff0ecf5),
          ),
      ],
    );
  }
}