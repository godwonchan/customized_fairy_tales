import 'package:flutter/material.dart';
import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';
import 'rpg_draw_screen.dart';
import '../services/api_service.dart';
import '../widgets/story_image_view.dart';

class FairyTaleDetailScreen extends StatefulWidget {
  final FairyTale tale;
  const FairyTaleDetailScreen({super.key, required this.tale});

  @override
  State<FairyTaleDetailScreen> createState() => _FairyTaleDetailScreenState();
}

class _FairyTaleDetailScreenState extends State<FairyTaleDetailScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.tale.isFavorite;
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // 주인공 이름 입력 다이얼로그. 취소=null, 빈칸=주인공
  Future<String?> _askPlayerName(BuildContext context) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String submit() {
          final t = ctrl.text.trim();
          return t.isEmpty ? '주인공' : t;
        }

        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('주인공 이름 짓기',
              style: TextStyle(
                  color: Color(0xFF3D2C8D), fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('동화 속 주인공이 될 이름이에요 ✨',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 10,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: '이름을 입력하세요',
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFFF3EFFA),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => Navigator.pop(ctx, submit()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7E57C2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, submit()),
              child: const Text('시작하기'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return result;
  }

  // ===== RPG 시작: 이름 입력 → 제목으로 서버 동화 id 찾기 → RpgDrawScreen 이동 =====
  Future<void> _startRpg(BuildContext context, FairyTale tale) async {
    final playerName = await _askPlayerName(context);
    if (playerName == null) return; // 취소
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF7E57C2)),
      ),
    );

    try {
      final stories = tale.isUserStory
          ? await ApiService.getMyStories()
          : await ApiService.getOriginalStories();

      Map<String, dynamic>? match;
      for (final s in stories) {
        final m = s as Map<String, dynamic>;
        final title = (m['title'] ?? '').toString().trim();
        if (title == tale.title.trim()) {
          match = m;
          break;
        }
      }

      if (mounted) Navigator.pop(context); // 로딩 닫기

      if (match == null) {
        _showNoMatchDialog(context, tale, stories);
        return;
      }

      final storyId = (match['id'] as num).toInt();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RpgDrawScreen(
            storyId: storyId,
            storyTitle: tale.title,
            playerName: playerName,
            assetHint: '', // TODO: 사용자가 그린 에셋 설명으로 교체
            maxTurns: 6,
          ),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('RPG 시작 실패: $e')),
      );
    }
  }

  void _showNoMatchDialog(BuildContext context, FairyTale tale, List<dynamic> stories) {
    final titles = stories
        .map((s) => "• ${(s as Map)['title']}  (id: ${s['id']})")
        .join('\n');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('서버에서 동화를 못 찾았어요'),
        content: SingleChildScrollView(
          child: Text(
            "'${tale.title}' 과(와) 같은 제목의 동화가 서버에 없습니다.\n\n"
            "서버에 있는 동화:\n${titles.isEmpty ? '(없음 — 서버가 켜져 있는지 확인)' : titles}",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final tale = widget.tale;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4FF),
      body: Stack(
        children: [
          Positioned(
            top: -60, right: -60,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF9575CD).withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -80, left: -40,
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEC407A).withOpacity(0.06),
              ),
            ),
          ),
          SafeArea(
            child: isTablet ? _buildTabletLayout(context, tale) : _buildPhoneLayout(context, tale),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context, FairyTale tale) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Hero(
            tag: 'tale_${tale.title}',
            child: Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: const Color(0xFF7E57C2).withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 12))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: StoryImageView(imagePath: tale.imagePath, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(position: _slideAnim, child: _buildInfoPanel(context, tale, isTablet: true)),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneLayout(BuildContext context, FairyTale tale) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Hero(
                tag: 'tale_${tale.title}',
                child: SizedBox(width: double.infinity, height: 300,
                    child: StoryImageView(imagePath: tale.imagePath, fit: BoxFit.cover)),
              ),
              Positioned(top: 12, left: 16, child: _backButton()),
              Positioned(top: 12, right: 16, child: _favoriteButton()),
            ],
          ),
          FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(position: _slideAnim, child: _buildInfoPanel(context, tale, isTablet: false)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(BuildContext context, FairyTale tale, {required bool isTablet}) {
    return Padding(
      padding: EdgeInsets.all(isTablet ? 32 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isTablet) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_backButton(), _favoriteButton()]),
            const SizedBox(height: 24),
          ],
          Text('동화 상세', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          const SizedBox(height: 12),
          Text(tale.title,
              style: TextStyle(fontSize: isTablet ? 32 : 26, fontWeight: FontWeight.w700, color: const Color(0xFF3D2C8D))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: const Color(0xFFEDE7F6), borderRadius: BorderRadius.circular(20)),
            child: Text(tale.category,
                style: const TextStyle(fontSize: 12, color: Color(0xFF7E57C2), fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(5, (i) => Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(Icons.star_rounded, size: 20, color: i < 4 ? const Color(0xFFFFB300) : Colors.grey[300]),
            )),
          ),
          const SizedBox(height: 16),
          Text(tale.description,
              style: TextStyle(fontSize: isTablet ? 16 : 14, color: Colors.grey[700], height: 1.7)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Row(children: [_infoItem('카테고리', tale.category), _divider(), _infoItem('유형', tale.isUserStory ? '내 이야기' : '원본')]),
          ),
          const SizedBox(height: 28),
          // ===== 이 동화 읽기 =====
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => TaleReadingScreen(tale: tale, initialPage: 0))),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF9575CD), Color(0xFF7E57C2)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: const Color(0xFF7E57C2).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text('이 동화 읽기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ===== RPG로 플레이 =====
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => _startRpg(context, tale),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF4A2E8C), Color(0xFF1A1145)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: const Color(0xFF4A2E8C).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sports_esports_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text('RPG로 플레이', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: const Icon(Icons.chevron_left, color: Color(0xFF7E57C2), size: 22),
      ),
    );
  }

  Widget _favoriteButton() {
    return GestureDetector(
      onTap: () => setState(() => _isFavorite = !_isFavorite),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 18, color: _isFavorite ? const Color(0xFFE91E63) : Colors.grey[400]),
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFEDE7F6), borderRadius: BorderRadius.circular(20)),
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF7E57C2))),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 32, color: Colors.grey[200]);
}
