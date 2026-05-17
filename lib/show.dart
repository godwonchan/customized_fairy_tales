import 'package:flutter/material.dart';
import 'main.dart';
import 'main_list.dart';
import 'drawing_story_screen.dart';
import 'audio.dart'; 

void main() {
  runApp(const ShowPage());
}

class ShowPage extends StatelessWidget {
  const ShowPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const StoryDetailPage(),
      theme: ThemeData(
        fontFamily: 'Pretendard',
        scaffoldBackgroundColor: const Color(0xFFFFF7FF),
      ),
    );
  }
}

class StoryDetailPage extends StatelessWidget {
  const StoryDetailPage({super.key});

  static const double designWidth = 1366;
  static const double designHeight = 1024;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7ECF4),
      body: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: designWidth,
            height: designHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFF7FF), Color(0xFFFFFBF7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    const Sidebar(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
                        child: Row(
                          children: [
                            Expanded(flex: 5, child: StoryImageCard()),
                            const SizedBox(width: 28),
                            Expanded(flex: 7, child: DetailCard()),
                          ],
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
}

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      margin: const EdgeInsets.all(22),
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          _menu(
            Icons.home_outlined,
            '홈',
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const StoryHomePage()),
              );
            },
          ),
          const SizedBox(height: 24),
          _menu(Icons.home_rounded, '동화 목록', selected: true),
          const SizedBox(height: 24),
          _menu(Icons.bookmark_border_rounded, '그린 동화'),
          const SizedBox(height: 24),
          _menu(Icons.auto_awesome_outlined, '그림으로\n만들기', badge: true),
          const Spacer(),
          _menu(Icons.favorite_border_rounded, '즐겨찾기'),
          const SizedBox(height: 24),
          _menu(Icons.settings_outlined, '설정'),
          const SizedBox(height: 24),
          const CircleAvatar(
            radius: 22,
            backgroundImage: AssetImage('lib/assets/girls.png'),
          ),
        ],
      ),
    );
  }

  Widget _menu(
    IconData icon,
    String text, {
    bool selected = false,
    bool badge = false,
    VoidCallback? onTap,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFEDE2FF)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: selected
                      ? const Color(0xFF7D5BE6)
                      : const Color(0xFF707070),
                  size: 26,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  fontWeight:
                      selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? const Color(0xFF7D5BE6)
                      : const Color(0xFF555555),
                ),
              ),
            ],
          ),
        ),
        if (badge)
          Positioned(
            right: -4,
            top: -2,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5A5A),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'NEW',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class StoryImageCard extends StatelessWidget {
  StoryImageCard({super.key});

  final String imagePath = 'lib/assets/girls.png';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withOpacity(0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
              Positioned(
                top: 18,
                left: 18,
                child: GestureDetector(
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MainListPage_01(),
                      ),
                    );
                  },
                  child: _circleButton(Icons.arrow_back_ios_new_rounded),
                ),
              ),
              Positioned(
                top: 18,
                right: 18,
                child: _circleButton(
                  Icons.favorite_border_rounded,
                  color: const Color(0xFFFF5A68),
                ),
              ),
              Positioned(
                bottom: 22,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          size: 18,
                          color: Color(0xFF7A4F32),
                        ),
                        SizedBox(width: 7),
                        Text(
                          '미리보기',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF7A4F32),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleButton(IconData icon,
      {Color color = const Color(0xFF565656)}) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08), blurRadius: 12),
        ],
      ),
      child: Icon(icon, color: color, size: 25),
    );
  }
}

class DetailCard extends StatelessWidget {
  DetailCard({super.key});

  final thumbnails = const [
    'lib/assets/girls.png',
    'lib/assets/pino.png',
    'lib/assets/sea_girl.png',
    'lib/assets/magic.png',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFF0DDF6)),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.10),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _chip('고전 동화'),
              const Spacer(),
              _smallButton(Icons.favorite_border_rounded, '좋아요'),
              const SizedBox(width: 12),
              _smallButton(Icons.bookmark_border_rounded, '저장'),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            '빨간 망토 📖✨',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: Color(0xFF351F13),
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '숲 속에서 만나는 용기와 지혜의 이야기',
            style: TextStyle(
              fontSize: 18,
              color: Color(0xFF77706D),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 10,
            children: [
              _chip('# 고전동화'),
              _chip('# 모험'),
              _chip('# 우정'),
              _chip('# 용기'),
              _chip('# 지혜'),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFFEADCF4)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _infoBox(
                  Icons.groups_rounded,
                  '추천 연령',
                  '5~9세',
                  const Color(0xFF8B6BE8),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _infoBox(
                  Icons.access_time_rounded,
                  '예상 시간',
                  '7분',
                  const Color(0xFFFFA53D),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _infoBox(
                  Icons.description_rounded,
                  '글자 수',
                  '약 2,400자',
                  const Color(0xFF5FC477),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _primaryButton(),
          const SizedBox(height: 12),
          _outlineButton(context),
          const SizedBox(height: 28),
          Row(
            children: const [
              Text(
                '이야기 속 장면 미리보기',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF35231B),
                ),
              ),
              Spacer(),
              Text(
                '모두 보기 〉',
                style: TextStyle(
                  color: Color(0xFF8A8190),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: thumbnails.asMap().entries.map((entry) {
              return Expanded(
                child: Container(
                  height: 112,
                  margin: EdgeInsets.only(
                    right: entry.key == thumbnails.length - 1 ? 0 : 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: entry.key == 0
                        ? Border.all(
                            color: const Color(0xFF8E67F2), width: 3)
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child:
                        Image.asset(entry.value, fit: BoxFit.cover),
                  ),
                ),
              );
            }).toList(),
          ),
          const Spacer(),

          // ✅ 오디오로 듣기 버튼 - AudioPlayerPage로 이동
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AudioPlayerPage(),
                ),
              );
            },
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: const Color(0xFFF5E9FF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE1C8FF)),
              ),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.headphones_rounded,
                        color: Color(0xFF805CE5)),
                    SizedBox(width: 12),
                    Text(
                      '오디오로 듣기',
                      style: TextStyle(
                        color: Color(0xFF805CE5),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(width: 24),
                    Text(
                      '▂▃▅▆▅▃▂',
                      style: TextStyle(
                        color: Color(0xFFD5B9FF),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF0E2FF),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF7D5BE6),
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _smallButton(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEBDDD5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: const Color(0xFFFF5A68)),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF4A3428),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(
      IconData icon, String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDE1DD)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withOpacity(0.18),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF6B5F5A),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF2E1F17),
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _primaryButton() {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF9B70F1), Color(0xFF7653DD)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7653DD).withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          '🪄  동화 읽기',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _outlineButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DrawingStoryScreen(),
          ),
        );
      },
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFD5B9FF),
            width: 2,
          ),
        ),
        child: const Center(
          child: Text(
            '🖌️  그림으로 동화 만들기   NEW',
            style: TextStyle(
              color: Color(0xFF7D5BE6),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}