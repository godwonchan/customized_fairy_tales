import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/crayong_widgets.dart';
import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';
import 'scene_edit_screen.dart';
import '../widgets/story_image_view.dart';
import 'creation/custom_story_create_screen.dart';

class PageSelectionScreen extends StatefulWidget {
  final FairyTale tale;
  final TaleBook taleBook;

  const PageSelectionScreen({
    super.key,
    required this.tale,
    required this.taleBook,
  });

  @override
  State<PageSelectionScreen> createState() => _PageSelectionScreenState();
}

class _PageSelectionScreenState extends State<PageSelectionScreen> {
  int? _selectedPageIndex;
  int _currentGridPage = 0;
  final int _itemsPerPage = 10;

  int get _totalGridPages => (widget.taleBook.totalPages / _itemsPerPage).ceil();

  List<TalePage> get _currentPageItems {
    final start = _currentGridPage * _itemsPerPage;
    final end = (start + _itemsPerPage).clamp(0, widget.taleBook.totalPages);
    return widget.taleBook.pages.sublist(start, end);
  }

  void _openSceneEdit() {
    if (_selectedPageIndex == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SceneEditScreen(
          tale: widget.tale,
          taleBook: widget.taleBook,
          selectedPageIndex: _selectedPageIndex!,
        ),
      ),
    );
  }

  void _openNewStoryWithPictures() {
    final taleIdStr = widget.tale.storyId != null ? 'tale_${widget.tale.storyId}' : widget.tale.id;

    final initialStoryData = {
      'tale_id': taleIdStr,
      'title': widget.tale.title,
      'pages': widget.taleBook.pages.map((p) => {
            'page_number': p.pageNumber,
            'content': p.text,
            'title': '${p.pageNumber}화',
            'characters': <String>[],
          }).toList(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomStoryCreateScreen(
          initialStoryData: initialStoryData,
          taleId: taleIdStr,
        ),
      ),
    );
  }

  void _showGuide() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Image.asset(CrayongImages.proud, height: 110)),
                const SizedBox(height: 12),
                Center(child: Text('장면 고르는 법', style: AppTextStyles.headingLarge())),
                const SizedBox(height: 14),
                for (final hint in const [
                  '한 번에 한 장면만 고를 수 있어요.',
                  '고른 장면부터 뒤의 이야기가 새롭게 바뀌어요.',
                  '마음에 드는 장면은 그대로 두고, 바꾸고 싶은 곳만 골라요.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(Icons.star_rounded, size: 18, color: AppColors.primary),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(hint, style: AppTextStyles.bodyMedium(color: AppColors.textPrimary))),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('알겠어요!'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 700;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isTablet),
            _buildGuideBox(),
            Expanded(child: _buildGrid(isTablet)),
            if (_totalGridPages > 1) _buildPagination(),
            _buildBottomBar(isTablet),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isTablet) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          RoundIconButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('바꾸고 싶은 장면 고르기', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.headingLarge()),
                Text(widget.tale.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption(color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (isTablet) ...[
            _buildStepIndicator(),
            const SizedBox(width: 12),
          ],
          RoundIconButton(icon: Icons.lightbulb_outline_rounded, tooltip: '고르는 법', onTap: _showGuide),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const steps = ['동화 읽기', '장면 고르기', '장면 바꾸기'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: i == 0
                    ? AppColors.secondaryDark
                    : (i == 1 ? AppColors.primary : AppColors.surfaceVariant),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: i == 0
                    ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                    : Text(
                        '${i + 1}',
                        style: AppTextStyles.labelSmall(
                          color: i == 1 ? AppColors.onPrimary : AppColors.textHint,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              steps[i],
              style: i == 1
                  ? AppTextStyles.headingSmall().copyWith(fontSize: 16, height: 1.1)
                  : AppTextStyles.labelSmall(color: AppColors.textHint),
            ),
            if (i < steps.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textHint),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildGuideBox() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
      decoration: AppDecorations.sticker(
        color: AppColors.secondaryLight,
        shadowColor: const Color(0xFFBFDDA5),
        radius: 22,
        depth: 4,
      ),
      child: Row(
        children: [
          Image.asset(CrayongImages.proud, height: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('바꾸고 싶은 장면을 하나만 골라 줘!', style: AppTextStyles.headingSmall()),
                Text(
                  '고른 장면부터 크레용이 이야기를 새롭게 이어 갈게요.',
                  style: AppTextStyles.bodySmall(color: const Color(0xFF3E6F2E)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(bool isTablet) {
    final items = _currentPageItems;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100 ? 5 : (constraints.maxWidth >= 700 ? 4 : 2);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 18,
            childAspectRatio: 0.92,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final actualIndex = _currentGridPage * _itemsPerPage + index;
            return _PageCard(
              page: items[index],
              number: actualIndex + 1,
              description: _getPageDescription(actualIndex),
              selected: _selectedPageIndex == actualIndex,
              frameColor: widget.tale.cardColor,
              onTap: () => setState(() => _selectedPageIndex = actualIndex),
            );
          },
        );
      },
    );
  }

  String _getPageDescription(int index) {
    final pages = widget.taleBook.pages;
    if (index < pages.length) {
      final text = pages[index].text;
      return text.length > 18 ? '${text.substring(0, 18)}...' : text;
    }
    return '${index + 1}페이지';
  }

  Widget _buildPagination() {
    final canPrev = _currentGridPage > 0;
    final canNext = _currentGridPage < _totalGridPages - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Opacity(
            opacity: canPrev ? 1 : 0.4,
            child: RoundIconButton(
              icon: Icons.chevron_left_rounded,
              onTap: () {
                if (canPrev) setState(() => _currentGridPage--);
              },
            ),
          ),
          const SizedBox(width: 14),
          Text('${_currentGridPage + 1} / $_totalGridPages', style: AppTextStyles.headingSmall()),
          const SizedBox(width: 14),
          Opacity(
            opacity: canNext ? 1 : 0.4,
            child: RoundIconButton(
              icon: Icons.chevron_right_rounded,
              onTap: () {
                if (canNext) setState(() => _currentGridPage++);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isTablet) {
    final selectedPage = _selectedPageIndex != null ? widget.taleBook.pages[_selectedPageIndex!] : null;

    final preview = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: selectedPage != null ? widget.tale.cardColor : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selectedPage != null ? AppColors.primary : AppColors.border,
              width: selectedPage != null ? 3 : 2,
            ),
          ),
          child: selectedPage != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: StoryImageView(imagePath: selectedPage.imagePath, fit: BoxFit.cover),
                )
              : const Icon(Icons.touch_app_rounded, color: AppColors.textHint, size: 26),
        ),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isTablet ? 280 : 150),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectedPage != null ? '${_selectedPageIndex! + 1}번 장면을 골랐어요' : '아직 고른 장면이 없어요',
                style: AppTextStyles.headingSmall(),
              ),
              Text(
                selectedPage != null ? selectedPage.text : '위에서 바꾸고 싶은 장면을 눌러 봐요.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );

    final buttons = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        _StickerAction(
          label: '이 그림들로 새 동화 만들기',
          icon: Icons.auto_stories_rounded,
          color: AppColors.surface,
          shadowColor: AppColors.border,
          textColor: AppColors.textPrimary,
          bordered: true,
          onTap: _openNewStoryWithPictures,
        ),
        _StickerAction(
          label: '이 장면 바꾸기',
          icon: Icons.arrow_forward_rounded,
          iconAfter: true,
          color: _selectedPageIndex != null ? AppColors.primary : AppColors.surfaceVariant,
          shadowColor: _selectedPageIndex != null ? AppColors.primaryDark : AppColors.border,
          textColor: _selectedPageIndex != null ? AppColors.onPrimary : AppColors.textHint,
          onTap: _selectedPageIndex != null ? _openSceneEdit : null,
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 2)),
      ),
      child: isTablet
          ? Row(
              children: [
                preview,
                const SizedBox(width: 16),
                Expanded(child: Align(alignment: Alignment.centerRight, child: buttons)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                preview,
                const SizedBox(height: 12),
                buttons,
              ],
            ),
    );
  }
}

class _PageCard extends StatelessWidget {
  final TalePage page;
  final int number;
  final String description;
  final bool selected;
  final Color frameColor;
  final VoidCallback onTap;

  const _PageCard({
    required this.page,
    required this.number,
    required this.description,
    required this.selected,
    required this.frameColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          scale: selected ? 1.05 : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: selected ? AppColors.primaryDark : AppColors.border,
                  blurRadius: 0,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: frameColor,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: StoryImageView(imagePath: page.imagePath, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                          child: Center(
                            child: Text('$number', style: AppTextStyles.labelMedium(color: AppColors.textPrimary)),
                          ),
                        ),
                      ),
                      if (selected)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: AppDecorations.sticker(
                              color: AppColors.primary,
                              shadowColor: AppColors.primaryDark,
                              radius: 15,
                              depth: 2,
                            ),
                            child: const Icon(Icons.check_rounded, size: 20, color: AppColors.onPrimary),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption(
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                  ).copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool iconAfter;
  final Color color;
  final Color shadowColor;
  final Color textColor;
  final bool bordered;
  final VoidCallback? onTap;

  const _StickerAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.shadowColor,
    required this.textColor,
    required this.onTap,
    this.iconAfter = false,
    this.bordered = false,
  });

  @override
  State<_StickerAction> createState() => _StickerActionState();
}

class _StickerActionState extends State<_StickerAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const depth = 4.0;
    final enabled = widget.onTap != null;
    final down = _pressed && enabled;
    final icon = Icon(widget.icon, size: 20, color: widget.textColor);

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          transform: Matrix4.translationValues(0, down ? depth : 0, 0),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(20),
            border: widget.bordered ? Border.all(color: AppColors.border, width: 2) : null,
            boxShadow: [
              BoxShadow(color: widget.shadowColor, blurRadius: 0, offset: Offset(0, down ? 0 : depth)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!widget.iconAfter) ...[icon, const SizedBox(width: 8)],
              Text(widget.label, style: AppTextStyles.button(color: widget.textColor)),
              if (widget.iconAfter) ...[const SizedBox(width: 8), icon],
            ],
          ),
        ),
      ),
    );
  }
}