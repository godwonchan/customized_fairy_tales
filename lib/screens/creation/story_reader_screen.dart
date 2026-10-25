import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../widgets/crayong_widgets.dart';
import '../home_screen.dart';

class StoryReaderScreen extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> pages;
  final Map<String, Uint8List?> assetPngBytes;
  final String? taleId;

  const StoryReaderScreen({
    super.key,
    required this.title,
    required this.pages,
    required this.assetPngBytes,
    this.taleId,
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
  StreamSubscription<void>? _completeSub;

  int _currentPageIndex = 0;
  bool _isPlayingVoice = false;
  bool _isSaving = false;

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: -6.0, end: 4.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlayingVoice = false);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.pages.isNotEmpty) {
        _readCurrentPage(widget.pages[0]['content']);
      }
    });
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _pageController.dispose();
    _audioPlayer.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  Future<void> _readCurrentPage(String? text) async {
    if (text == null || text.trim().isEmpty) return;
    try {
      await _audioPlayer.stop();
      if (!mounted) return;
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
          } else if (mounted) {
            setState(() => _isPlayingVoice = false);
          }
        } else if (mounted) {
          setState(() => _isPlayingVoice = false);
        }
      }
    } catch (e) {
      debugPrint('구연동화 재생 오류: $e');
      if (mounted) setState(() => _isPlayingVoice = false);
    }
  }

  void _toggleVoice() {
    if (_isPlayingVoice) {
      _audioPlayer.stop();
      setState(() => _isPlayingVoice = false);
    } else {
      _readCurrentPage(widget.pages[_currentPageIndex]['content']);
    }
  }

  void _goToPreviousPage() {
    if (_currentPageIndex > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    }
  }

  void _goToNextPage() {
    if (_currentPageIndex < widget.pages.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    }
  }

  void _showMessage(String text, {String image = CrayongImages.wink}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Image.asset(image, width: 30, height: 30),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppTextStyles.labelLarge(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Future<void> _linkSketchesToStory(dynamic storyId) async {
    if (widget.taleId == null || storyId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final from = 'tale_${widget.taleId!.replaceFirst(RegExp(r'^tale_'), '')}_';
    final to = 'tale_${storyId}_';
    for (final key in prefs.getKeys().where((k) => k.startsWith(from)).toList()) {
      final value = prefs.getString(key);
      if (value != null) await prefs.setString(to + key.substring(from.length), value);
    }
  }

  Future<void> _saveAndNavigateToLibrary() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    await _audioPlayer.stop();

    try {
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
        if (widget.taleId != null) 'id': widget.taleId,
        if (widget.taleId != null) 'tale_id': widget.taleId,
        'title': widget.title,
        'mood': '신나는 모험',
        'pages': pagesPayload,
      };

      final res = await http.post(
        Uri.parse('$_baseUrl/api/stories'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        await _linkSketchesToStory(jsonDecode(res.body)['story_id']);
        if (!mounted) return;
        _showMessage('나의 책장에 꽂아 뒀어요!', image: CrayongImages.celebrate);

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AppShell(initialIndex: 2, initialMyStoriesTab: 1)),
          (route) => false,
        );
      } else {
        throw Exception('서버 응답 오류: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('보관함 저장 실패: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        _showMessage(
          kDebugMode ? '저장 중 문제가 생겼어요: $e' : '책장에 못 넣었어요. 다시 해 볼래요?',
          image: CrayongImages.surprised,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasPrev = _currentPageIndex > 0;
    final bool hasNext = _currentPageIndex < widget.pages.length - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                children: [
                  ScrollConfiguration(
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
                      itemBuilder: (context, index) => _buildBookSpread(widget.pages[index]),
                    ),
                  ),
                  if (hasPrev)
                    Positioned(
                      left: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _buildBigNavButton(icon: Icons.chevron_left_rounded, tooltip: '이전 쪽', onTap: _goToPreviousPage),
                      ),
                    ),
                  if (hasNext)
                    Positioned(
                      right: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _buildBigNavButton(icon: Icons.chevron_right_rounded, tooltip: '다음 쪽', onTap: _goToNextPage),
                      ),
                    ),
                ],
              ),
            ),
            _buildBottomBar(hasPrev, hasNext),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          RoundIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () {
              _audioPlayer.stop();
              Navigator.pop(context);
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headingLarge()),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _toggleVoice,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 48,
                padding: const EdgeInsets.fromLTRB(6, 4, 16, 4),
                decoration: BoxDecoration(
                  color: _isPlayingVoice ? AppColors.secondaryLight : AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _isPlayingVoice ? AppColors.secondary : AppColors.border, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _isPlayingVoice ? const Color(0xFFBFDDA5) : AppColors.border,
                      blurRadius: 0,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _bounceAnimation,
                      builder: (_, child) => Transform.translate(
                        offset: Offset(0, _isPlayingVoice ? _bounceAnimation.value * 0.5 : 0),
                        child: child,
                      ),
                      child: Image.asset(CrayongImages.wink, height: 38),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _isPlayingVoice ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      size: 20,
                      color: _isPlayingVoice ? AppColors.secondaryDark : AppColors.textHint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isPlayingVoice ? '크레용이 읽는 중' : '읽어 줘',
                      style: AppTextStyles.headingSmall(
                        color: _isPlayingVoice ? const Color(0xFF3E6F2E) : AppColors.textSecondary,
                      ).copyWith(fontSize: 16, height: 1.1),
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

  Widget _buildBookSpread(Map<String, dynamic> page) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1060, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(84, 10, 84, 16),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.border, width: 2),
              boxShadow: const [BoxShadow(color: AppColors.border, blurRadius: 0, offset: Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 11,
                    child: Container(
                      color: AppColors.surfaceVariant,
                      padding: const EdgeInsets.all(14),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1.0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildBackgroundImage(page['imageUrl']),
                                if ((page['page'] ?? '').toString().isNotEmpty)
                                  Positioned(
                                    top: 14,
                                    left: 14,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        page['page'].toString(),
                                        style: AppTextStyles.labelMedium(color: AppColors.primaryText),
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
                  Container(width: 2, color: AppColors.border),
                  Expanded(
                    flex: 10,
                    child: Container(
                      color: AppColors.surface,
                      padding: const EdgeInsets.fromLTRB(32, 34, 32, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            page['title'] ?? '',
                            style: AppTextStyles.headingLarge(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Text(page['content'] ?? '', style: AppTextStyles.storyBody(fontSize: 20)),
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
  }

  Widget _buildBottomBar(bool hasPrev, bool hasNext) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 2)),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: hasPrev ? 1 : 0.4,
            child: RoundIconButton(icon: Icons.chevron_left_rounded, tooltip: '이전 쪽', onTap: _goToPreviousPage),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.pages.length, (i) {
              final isSelected = _currentPageIndex == i;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isSelected ? 24 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(5),
                ),
              );
            }),
          ),
          const Spacer(),
          if (hasNext)
            _StickerButton(
              label: '다음 쪽',
              icon: Icons.arrow_forward_rounded,
              iconAfter: true,
              onTap: _goToNextPage,
            )
          else
            _StickerButton(
              label: _isSaving ? '책장에 넣는 중...' : '나의 책장에 넣기',
              icon: Icons.bookmark_add_rounded,
              loading: _isSaving,
              green: true,
              onTap: _isSaving ? null : _saveAndNavigateToLibrary,
            ),
        ],
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
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 2),
              boxShadow: const [BoxShadow(color: AppColors.border, blurRadius: 0, offset: Offset(0, 4))],
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 36),
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundImage(String? imageUrl) {
    Widget placeholder() => Container(
          color: AppColors.surfaceVariant,
          child: Center(child: Image.asset(CrayongImages.drawing, height: 120)),
        );

    if (imageUrl == null || imageUrl.isEmpty) {
      return placeholder();
    }

    if (imageUrl.startsWith('data:image') || !imageUrl.startsWith('http')) {
      try {
        final base64String = imageUrl.contains(',') ? imageUrl.split(',').last : imageUrl;
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => placeholder(),
        );
      } catch (e) {
        debugPrint('Base64 파싱 오류: $e');
      }
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator(color: AppColors.primaryDark));
      },
      errorBuilder: (ctx, err, stack) => placeholder(),
    );
  }
}

class _StickerButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool iconAfter;
  final bool loading;
  final bool green;
  final VoidCallback? onTap;

  const _StickerButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconAfter = false,
    this.loading = false,
    this.green = false,
  });

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
    final color = widget.green ? AppColors.secondaryDark : AppColors.primary;
    final shadow = widget.green ? const Color(0xFF457A36) : AppColors.primaryDark;
    final textColor = widget.green ? Colors.white : AppColors.onPrimary;
    final iconWidget = widget.loading
        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: textColor))
        : Icon(widget.icon, size: 20, color: textColor);

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          transform: Matrix4.translationValues(0, down ? depth : 0, 0),
          decoration: AppDecorations.sticker(color: color, shadowColor: shadow, radius: 20, depth: down ? 0 : depth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.iconAfter) ...[iconWidget, const SizedBox(width: 8)],
              Text(widget.label, style: AppTextStyles.button(color: textColor)),
              if (widget.iconAfter) ...[const SizedBox(width: 8), iconWidget],
            ],
          ),
        ),
      ),
    );
  }
}