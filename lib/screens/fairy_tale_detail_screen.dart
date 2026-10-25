import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/favorites_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/crayong_widgets.dart';
import 'fairy_tale_list_screen.dart';
import 'tale_reading_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleFavorite() {
    final provider = context.read<FavoritesProvider>();
    final willAdd = !provider.isFavorite(widget.tale);
    provider.toggleFavorite(widget.tale);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1500),
        content: Row(
          children: [
            Image.asset(willAdd ? CrayongImages.celebrate : CrayongImages.lying, width: 30, height: 30),
            const SizedBox(width: 10),
            Text(
              willAdd ? '좋아하는 이야기에 넣었어요!' : '좋아하는 이야기에서 뺐어요.',
              style: AppTextStyles.labelLarge(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  void _openReading() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TaleReadingScreen(tale: widget.tale, initialPage: 0)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tale = widget.tale;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x55FFE9A8)),
            ),
          ),
          Positioned(
            bottom: -90,
            left: -50,
            child: Container(
              width: 260,
              height: 260,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x55D9EEC5)),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 700;
                return isWide ? _buildWideLayout(tale) : _buildNarrowLayout(tale);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(FairyTale tale) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: _buildCover(tale)),
          const SizedBox(width: 36),
          Expanded(
            flex: 5,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        RoundIconButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
                        const Spacer(),
                        _favoriteButton(),
                      ],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 24),
                        child: _buildInfo(tale, titleSize: 40),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ReadButton(onTap: _openReading),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(FairyTale tale) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              RoundIconButton(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
              const Spacer(),
              _favoriteButton(),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 300, width: double.infinity, child: _buildCover(tale)),
                const SizedBox(height: 22),
                FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(position: _slideAnim, child: _buildInfo(tale, titleSize: 32)),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: _ReadButton(onTap: _openReading),
        ),
      ],
    );
  }

  Widget _buildCover(FairyTale tale) {
    return Hero(
      tag: 'tale_${tale.title}',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.border, width: 2),
          boxShadow: const [
            BoxShadow(color: AppColors.border, blurRadius: 0, offset: Offset(0, 7)),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: tale.cardColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: StoryImageView(imagePath: tale.imagePath, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  Widget _buildInfo(FairyTale tale, {required double titleSize}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(
              tale.category,
              background: AppColors.secondaryLight,
              color: const Color(0xFF3E6F2E),
              icon: Icons.menu_book_rounded,
            ),
            _chip(
              tale.isUserStory ? '내가 만든 이야기' : '원래 동화',
              background: tale.isUserStory ? AppColors.primaryLight : AppColors.surfaceVariant,
              color: AppColors.primaryText,
              icon: tale.isUserStory ? Icons.brush_rounded : Icons.auto_stories_rounded,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          tale.title,
          style: AppTextStyles.display().copyWith(fontSize: titleSize, height: 1.2),
        ),
        const SizedBox(height: 12),
        Text(
          tale.description,
          style: AppTextStyles.bodyLarge(color: AppColors.textSecondary).copyWith(height: 1.8),
        ),
        const SizedBox(height: 22),
        _buildCrayongTip(),
      ],
    );
  }

  Widget _buildCrayongTip() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
      decoration: AppDecorations.sticker(
        color: AppColors.secondaryLight,
        shadowColor: const Color(0xFFBFDDA5),
        radius: 22,
        depth: 4,
      ),
      child: Row(
        children: [
          Image.asset(CrayongImages.wink, height: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('크레용이 읽어 줄게요!', style: AppTextStyles.headingSmall()),
                Text(
                  '읽다가 바꾸고 싶은 장면이 있으면 내 마음대로 바꿀 수도 있어요.',
                  style: AppTextStyles.bodySmall(color: const Color(0xFF3E6F2E)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {required Color background, required Color color, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(text, style: AppTextStyles.labelMedium(color: color)),
        ],
      ),
    );
  }

  Widget _favoriteButton() {
    final isFav = context.watch<FavoritesProvider>().isFavorite(widget.tale);
    return GestureDetector(
      onTap: _toggleFavorite,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          height: 44,
          decoration: BoxDecoration(
            color: isFav ? AppColors.accentLight : AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: isFav ? AppColors.accent : AppColors.border, width: 2),
            boxShadow: [
              BoxShadow(
                color: isFav ? const Color(0xFFF1D6CA) : AppColors.border,
                blurRadius: 0,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 20,
                color: isFav ? AppColors.accentDark : AppColors.textHint,
              ),
              const SizedBox(width: 6),
              Text(
                isFav ? '좋아해요' : '즐겨찾기',
                style: AppTextStyles.headingSmall(
                  color: isFav ? AppColors.accentDark : AppColors.textSecondary,
                ).copyWith(fontSize: 16, height: 1.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadButton extends StatefulWidget {
  final VoidCallback onTap;

  const _ReadButton({required this.onTap});

  @override
  State<_ReadButton> createState() => _ReadButtonState();
}

class _ReadButtonState extends State<_ReadButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const depth = 5.0;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 62,
          width: double.infinity,
          transform: Matrix4.translationValues(0, _pressed ? depth : 0, 0),
          decoration: AppDecorations.primaryButton(radius: 20, depth: _pressed ? 0 : depth),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.menu_book_rounded, color: AppColors.onPrimary, size: 24),
              const SizedBox(width: 10),
              Text('이 동화 읽기', style: AppTextStyles.button().copyWith(fontSize: 24)),
            ],
          ),
        ),
      ),
    );
  }
}