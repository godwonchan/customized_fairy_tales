import 'package:flutter/material.dart';
import '../screens/fairy_tale_list_screen.dart';
import '../theme/app_theme.dart';
import 'story_image_view.dart';

class StoryBookCard extends StatefulWidget {
  final FairyTale tale;
  final VoidCallback onTap;
  final Color? chipColor;
  final Color? chipTextColor;

  const StoryBookCard({
    super.key,
    required this.tale,
    required this.onTap,
    this.chipColor,
    this.chipTextColor,
  });

  @override
  State<StoryBookCard> createState() => _StoryBookCardState();
}

class _StoryBookCardState extends State<StoryBookCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tale = widget.tale;
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
          transform: Matrix4.translationValues(0, _pressed ? depth : 0, 0),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.border,
                blurRadius: 0,
                offset: Offset(0, _pressed ? 0 : depth),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: tale.cardColor,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: StoryImageView(
                        imagePath: tale.imagePath,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tale.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.headingMedium().copyWith(height: 1.2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tale.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: widget.chipColor ?? AppColors.secondaryLight,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              tale.category,
                              style: AppTextStyles.labelSmall(
                                color: widget.chipTextColor ?? const Color(0xFF3E6F2E),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: AppDecorations.sticker(
                              color: AppColors.primary,
                              shadowColor: AppColors.primaryDark,
                              radius: 15,
                              depth: 2,
                            ),
                            child: const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.onPrimary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CrayongStatusView extends StatelessWidget {
  final String image;
  final String title;
  final String? message;
  final Widget? child;
  final double imageHeight;

  const CrayongStatusView({
    super.key,
    required this.image,
    required this.title,
    this.message,
    this.child,
    this.imageHeight = 180,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(image, height: imageHeight, fit: BoxFit.contain),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.headingMedium(), textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  message!,
                  style: AppTextStyles.bodyMedium(),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (child != null) ...[
              const SizedBox(height: 18),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const RoundIconButton({super.key, required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 44,
          height: 44,
          decoration: AppDecorations.card(radius: 22),
          child: Icon(icon, size: 22, color: AppColors.textPrimary),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

int storyGridColumns(double width) => width >= 1100 ? 4 : (width >= 700 ? 3 : 2);