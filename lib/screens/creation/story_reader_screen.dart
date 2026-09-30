// lib/screens/creation/story_reader_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../home_screen.dart';

class StoryReaderScreen extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> pages;
  final Map<String, Uint8List?> assetPngBytes;

  const StoryReaderScreen({
    super.key,
    required this.title,
    required this.pages,
    required this.assetPngBytes,
  });

  @override
  State<StoryReaderScreen> createState() => _StoryReaderScreenState();
}

class _StoryReaderScreenState extends State<StoryReaderScreen>
    with SingleTickerProviderStateMixin {
  static const String _baseUrl = 'http://localhost:8000';
  final PageController _pageController = PageController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, Uint8List> _ttsCache = {};

  int _currentPageIndex = 0;
  bool _isPlayingVoice = false;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: -8.0, end: 4.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    // 첫 페이지 진입 시 자동 구연동화 읽기
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.pages.isNotEmpty) {
        _readCurrentPage(widget.pages[0]['content']);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _audioPlayer.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  // 🔊 루미 목소리 구연동화 낭독
  Future<void> _readCurrentPage(String text) async {
    try {
      await _audioPlayer.stop();
      setState(() => _isPlayingVoice = true);

      if (_ttsCache.containsKey(text)) {
        await _audioPlayer.play(BytesSource(_ttsCache[text]!));
      } else {
        final res = await http.post(
          Uri.parse('$_baseUrl/api/chat/tts'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'text': text}),
        );

        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final String audioB64 = data['audio_base64'] ?? '';
          if (audioB64.isNotEmpty) {
            final bytes = base64Decode(audioB64);
            _ttsCache[text] = bytes;
            await _audioPlayer.play(BytesSource(bytes));
          }
        }
      }

      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlayingVoice = false);
      });
    } catch (e) {
      debugPrint('구연동화 재생 오류: $e');
      if (mounted) setState(() => _isPlayingVoice = false);
    }
  }

  void _goToPreviousPage() {
    if (_currentPageIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToNextPage() {
    if (_currentPageIndex < widget.pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  bool _isSaving = false; // 💡 저장 중복 클릭 방지용 상태 변수

  // 📚 백엔드 보관함에 영구 저장 후 홈으로 이동
  Future<void> _saveAndNavigateToLibrary() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    await _audioPlayer.stop();

    try {
      // 1. 백엔드 규격에 맞게 페이지 목록 조립
      final List<Map<String, dynamic>> pagesPayload = [];
      for (int i = 0; i < widget.pages.length; i++) {
        final p = widget.pages[i];
        pagesPayload.add({
          'page_number': p['page_number'] ?? (i + 1),
          'title': p['title'] ?? '${i + 1}화',
          'content': p['content'] ?? '',
          'image_url': p['imageUrl'] ?? '',
        });
      }

      final body = {
        'title': widget.title,
        'mood': '신나는 모험',
        'pages': pagesPayload,
      };

      // 2. 백엔드 저장 API 호출
      final res = await http.post(
        Uri.parse('$_baseUrl/api/stories'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ 동화책이 보관함에 안전하게 저장되었어!'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 2),
          ),
        );

        // 3. 서재(홈) 화면으로 이동
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AppShell()),
              (route) => false,
        );
      } else {
        throw Exception('서버 응답 오류: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('보관함 저장 실패: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 중 문제가 생겼어: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasPrev = _currentPageIndex > 0;
    final bool hasNext = _currentPageIndex < widget.pages.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1433),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () {
            _audioPlayer.stop();
            Navigator.pop(context);
          },
        ),
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isPlayingVoice ? Icons.volume_up_rounded : Icons.volume_mute_rounded,
              color: _isPlayingVoice ? const Color(0xFFCE93D8) : Colors.white70,
              size: 26,
            ),
            onPressed: () {
              if (_isPlayingVoice) {
                _audioPlayer.stop();
                setState(() => _isPlayingVoice = false);
              } else {
                _readCurrentPage(widget.pages[_currentPageIndex]['content']);
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // ── 📖 좌우 2분할 펼친 면 동화책 PageView ──
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: widget.pages.length,
                      onPageChanged: (idx) {
                        setState(() => _currentPageIndex = idx);
                        _readCurrentPage(widget.pages[idx]['content']);
                      },
                      itemBuilder: (context, index) {
                        final page = widget.pages[index];

                        return Center(
                          child: ConstrainedBox(
                            // 💡 양장본 동화책 비율 (가로 최대 1060px, 세로 최대 580px)
                            constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 580),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(28),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.4),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(28),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // 🎨 [왼쪽 면]: 1:1 정사각 그림 영역 (잘림 0% 보장!)
                                      Expanded(
                                        flex: 11,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            _buildBackgroundImage(page['imageUrl']),
                                            // 페이지 뱃지
                                            Positioned(
                                              top: 18,
                                              left: 18,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withOpacity(0.65),
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  page['page'] ?? '',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // 📖 [가운데 책 접힘선]: 실제 종이책 느낌의 은은한 음영
                                      Container(
                                        width: 1.5,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.black.withOpacity(0.04),
                                              Colors.black.withOpacity(0.18),
                                              Colors.black.withOpacity(0.04),
                                            ],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                        ),
                                      ),

                                      // 📜 [오른쪽 면]: 시원하고 여유로운 동화 글 영역 (잘림 0%)
                                      Expanded(
                                        flex: 10,
                                        child: Container(
                                          color: const Color(0xFFFCFCFD),
                                          padding: const EdgeInsets.fromLTRB(36, 40, 36, 32),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // 소제목
                                              Text(
                                                page['title'] ?? '',
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF3D2C8D),
                                                  letterSpacing: -0.5,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 16),

                                              // 본문 (글씨 확대 & 넉넉한 줄간격)
                                              Expanded(
                                                child: SingleChildScrollView(
                                                  physics: const BouncingScrollPhysics(),
                                                  child: Text(
                                                    page['content'] ?? '',
                                                    style: const TextStyle(
                                                      fontSize: 18.5,
                                                      color: Color(0xFF2C2440),
                                                      height: 1.7,
                                                      fontWeight: FontWeight.w600,
                                                      letterSpacing: -0.3,
                                                    ),
                                                  ),
                                                ),
                                              ),
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
                        );
                      },
                    ),
                  ),
                ),

                // ── 하단 컨트롤 바 (이전 / 인디케이터 / 다음 or 보관함) ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: hasPrev ? _goToPreviousPage : null,
                        icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                        label: const Text('이전', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white24,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white10,
                          disabledForegroundColor: Colors.white30,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          elevation: 0,
                        ),
                      ),
                      const Spacer(),

                      // 중앙 인디케이터 점(Dot)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(widget.pages.length, (i) {
                          final isSelected = _currentPageIndex == i;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: isSelected ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFCE93D8) : Colors.white24,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                      const Spacer(),

                      if (hasNext)
                        ElevatedButton.icon(
                          onPressed: _goToNextPage,
                          icon: const Text('다음', style: TextStyle(fontWeight: FontWeight.bold)),
                          label: const Icon(Icons.arrow_forward_ios, size: 14),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7E57C2),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            elevation: 4,
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveAndNavigateToLibrary,
                          icon: _isSaving
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Icon(Icons.check_circle_outline, size: 16),
                          label: Text(
                            _isSaving ? '보관함에 저장 중...' : '보관함으로',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.white24,
                            disabledForegroundColor: Colors.white54,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            elevation: 4,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // ── 화면 양옆 플로팅 화살표 버튼 ──
            if (hasPrev)
              Positioned(
                left: 12,
                top: MediaQuery.of(context).size.height * 0.42,
                child: _buildBigNavButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: '이전 쪽',
                  onTap: _goToPreviousPage,
                ),
              ),

            if (hasNext)
              Positioned(
                right: 12,
                top: MediaQuery.of(context).size.height * 0.42,
                child: _buildBigNavButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: '다음 쪽',
                  onTap: _goToNextPage,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBigNavButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF9575CD), Color(0xFF5E35B1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.white.withOpacity(0.6), width: 1.5),
            ),
            child: Icon(icon, color: Colors.white, size: 38),
          ),
        ),
      ),
    );
  }

  // 💡 1:1 이미지가 온전하게 보이도록 fit 설정
  Widget _buildBackgroundImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(color: const Color(0xFFEDE7F6));
    }

    if (imageUrl.startsWith('data:image') || !imageUrl.startsWith('http')) {
      try {
        final base64String = imageUrl.contains(',') ? imageUrl.split(',').last : imageUrl;
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => Container(color: const Color(0xFFEDE7F6)),
        );
      } catch (e) {
        debugPrint('Base64 파싱 오류: $e');
      }
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator(color: Color(0xFF7E57C2)));
      },
      errorBuilder: (ctx, err, stack) => Container(
        color: const Color(0xFFEDE7F6),
        child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
      ),
    );
  }
}