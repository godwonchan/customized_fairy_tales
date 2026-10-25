import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/crayong_widgets.dart';
import 'fairy_tale_list_screen.dart';
import 'home_screen.dart';
import '../services/api_service.dart';
import '../widgets/story_image_view.dart';
import 'tale_reading_screen.dart';

class AIResultScreen extends StatefulWidget {
  final FairyTale tale;
  final TaleBook taleBook;
  final int editedPageIndex;
  final List<String>? revisedPages;
  final List<String>? generatedImagePaths;
  final String? confirmedRequest;

  const AIResultScreen({
    super.key,
    required this.tale,
    required this.taleBook,
    required this.editedPageIndex,
    this.revisedPages,
    this.generatedImagePaths,
    this.confirmedRequest,
  });

  @override
  State<AIResultScreen> createState() => _AIResultScreenState();
}

class _AIResultScreenState extends State<AIResultScreen>
    with SingleTickerProviderStateMixin {
  late int _currentPage;
  late PageController _pageController;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late TaleBook _updatedTaleBook;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    _currentPage = 0;
    _pageController = PageController(initialPage: 0);

    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    _updatedTaleBook = _buildUpdatedTaleBook();

    if (kDebugMode) {
      debugPrint('AI RESULT revisedPages = ${widget.revisedPages}');
      debugPrint('AI RESULT generatedImagePaths = ${widget.generatedImagePaths}');
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  bool _isEditedIndex(int index) {
    if (widget.revisedPages == null) return false;
    if (index < widget.editedPageIndex) return false;
    if (index >= widget.revisedPages!.length) return false;
    return true;
  }

  String? _generatedImageForIndex(int index) {
    if (widget.generatedImagePaths == null) return null;
    if (index >= widget.generatedImagePaths!.length) return null;

    final path = widget.generatedImagePaths![index].trim();
    if (path.isEmpty) return null;
    return path;
  }

  TaleBook _buildUpdatedTaleBook() {
    final updatedPages = widget.taleBook.pages.asMap().entries.map((entry) {
      final index = entry.key;
      final page = entry.value;

      final hasRevisedText = widget.revisedPages != null && index < widget.revisedPages!.length;
      final revisedImage = _generatedImageForIndex(index);

      return page.copyWith(
        text: hasRevisedText ? widget.revisedPages![index] : page.text,
        imagePath: revisedImage ?? page.imagePath,
      );
    }).toList();

    return TaleBook(tale: widget.tale, pages: updatedPages);
  }

  void _goPrevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _goNextPage() {
    if (_currentPage < _updatedTaleBook.pages.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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

  Future<void> _showSaveDialog() async {
    if (widget.tale.storyId == null) {
      _showMessage('이 동화는 저장할 수 없어요.', image: CrayongImages.surprised);
      return;
    }

    final defaultTitle = '${widget.tale.title} - 내 이야기';
    final controller = TextEditingController(text: defaultTitle);

    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          final value = controller.text.trim();
          Navigator.pop(dialogContext, value.isEmpty ? defaultTitle : value);
        }

        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(CrayongImages.celebrate, height: 110),
                  const SizedBox(height: 10),
                  Text('새 동화에 이름을 지어 줘요', style: AppTextStyles.headingMedium()),
                  const SizedBox(height: 4),
                  Text('나의 책장에 이 이름으로 꽂아 둘게요.', style: AppTextStyles.bodyMedium()),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 50,
                    style: AppTextStyles.bodyLarge(),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(
                      hintText: '동화 이름',
                      prefixIcon: Icon(Icons.edit_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border, width: 2),
                          ),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: submit,
                          child: const Text('책장에 넣기'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (title == null) return;
    await _saveToMyStories(title);
  }

  Future<void> _saveToMyStories(String customTitle) async {
    if (widget.tale.storyId == null) return;

    setState(() => _isSaving = true);

    try {
      await ApiService.saveAsMyStory(storyId: widget.tale.storyId!, customTitle: customTitle);

      if (!widget.tale.isUserStory) {
        await ApiService.resetToOriginal(storyId: widget.tale.storyId!);
      }

      if (!mounted) return;

      _showMessage('나의 책장에 꽂아 뒀어요!', image: CrayongImages.celebrate);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AppShell(initialIndex: 2, initialMyStoriesTab: 1)),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage(kDebugMode ? '저장 실패: $e' : '책장에 못 넣었어요. 다시 해 볼래요?', image: CrayongImages.surprised);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 700;
                    return PageView.builder(
                      controller: _pageController,
                      itemCount: _updatedTaleBook.pages.length,
                      onPageChanged: (index) => setState(() => _currentPage = index),
                      itemBuilder: (context, index) {
                        final page = _updatedTaleBook.pages[index];
                        final isEdited = _isEditedIndex(index);
                        return isWide ? _buildWidePage(page, isEdited) : _buildNarrowPage(page, isEdited);
                      },
                    );
                  },
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          RoundIconButton(icon: Icons.arrow_back_rounded, tooltip: '더 바꾸기', onTap: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          Image.asset(CrayongImages.celebrate, height: 52),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('짜잔! 새 이야기가 완성됐어요', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headingLarge()),
                Text(
                  '${widget.tale.title} · 바뀐 장면에는 초록 표시가 있어요',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(TalePage page, bool isEdited) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: isEdited ? AppColors.secondary : AppColors.border, width: isEdited ? 3 : 2),
              boxShadow: [
                BoxShadow(
                  color: isEdited ? const Color(0xFFBFDDA5) : AppColors.border,
                  blurRadius: 0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                color: widget.tale.cardColor,
                borderRadius: BorderRadius.circular(22),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: StoryImageView(imagePath: page.imagePath, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        if (isEdited)
          Positioned(
            top: 22,
            right: 22,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: AppDecorations.sticker(
                color: AppColors.secondaryDark,
                shadowColor: const Color(0xFF457A36),
                radius: 20,
                depth: 3,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 5),
                  Text('새로 바뀐 장면', style: AppTextStyles.labelMedium(color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTextCard(TalePage page, bool isEdited, {required bool scrollable}) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isEdited && widget.confirmedRequest != null && widget.confirmedRequest!.trim().isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.secondaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.brush_rounded, size: 18, color: AppColors.secondaryDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '이렇게 바꿨어요: ${widget.confirmedRequest!}',
                    style: AppTextStyles.bodySmall(color: const Color(0xFF3E6F2E)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(page.text, style: AppTextStyles.storyBody(fontSize: 20)),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: AppDecorations.card(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isEdited ? AppColors.secondaryLight : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${page.pageNumber}페이지',
              style: AppTextStyles.labelMedium(color: isEdited ? const Color(0xFF3E6F2E) : AppColors.primaryText),
            ),
          ),
          const SizedBox(height: 14),
          if (scrollable) Expanded(child: SingleChildScrollView(child: body)) else body,
        ],
      ),
    );
  }

  Widget _buildWidePage(TalePage page, bool isEdited) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 55, child: _buildImage(page, isEdited)),
          const SizedBox(width: 22),
          Expanded(flex: 45, child: _buildTextCard(page, isEdited, scrollable: true)),
        ],
      ),
    );
  }

  Widget _buildNarrowPage(TalePage page, bool isEdited) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          AspectRatio(aspectRatio: 16 / 10, child: _buildImage(page, isEdited)),
          const SizedBox(height: 16),
          _buildTextCard(page, isEdited, scrollable: false),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final total = _updatedTaleBook.pages.length;
    final canPrev = _currentPage > 0;
    final canNext = _currentPage < total - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 2)),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: canPrev ? 1 : 0.4,
            child: RoundIconButton(icon: Icons.chevron_left_rounded, tooltip: '이전 페이지', onTap: _goPrevPage),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(total, (i) {
              final isCurrent = i == _currentPage;
              final isEdited = _isEditedIndex(i);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isCurrent ? 22 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppColors.primary
                      : (isEdited ? AppColors.secondary : AppColors.border),
                  borderRadius: BorderRadius.circular(5),
                ),
              );
            }),
          ),
          const SizedBox(width: 12),
          Opacity(
            opacity: canNext ? 1 : 0.4,
            child: RoundIconButton(icon: Icons.chevron_right_rounded, tooltip: '다음 페이지', onTap: _goNextPage),
          ),
          const SizedBox(width: 10),
          Text('${_currentPage + 1} / $total', style: AppTextStyles.headingSmall()),
          const Spacer(),
          _SaveButton(loading: _isSaving, onTap: _isSaving ? null : _showSaveDialog),
        ],
      ),
    );
  }
}

class _SaveButton extends StatefulWidget {
  final bool loading;
  final VoidCallback? onTap;

  const _SaveButton({required this.loading, required this.onTap});

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const depth = 5.0;
    final enabled = widget.onTap != null;
    final down = _pressed && enabled;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          transform: Matrix4.translationValues(0, down ? depth : 0, 0),
          decoration: AppDecorations.primaryButton(radius: 20, depth: down ? 0 : depth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary),
                )
              else
                const Icon(Icons.bookmark_add_rounded, size: 22, color: AppColors.onPrimary),
              const SizedBox(width: 8),
              Text('나의 책장에 넣기', style: AppTextStyles.button().copyWith(fontSize: 22)),
            ],
          ),
        ),
      ),
    );
  }
}