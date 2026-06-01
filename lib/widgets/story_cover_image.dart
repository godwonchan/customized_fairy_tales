import 'package:flutter/material.dart';

class StoryCoverImage extends StatelessWidget {
  final String assetPath;
  final BoxFit fit;
  final double? width;
  final double? height;
  final IconData fallbackIcon;

  const StoryCoverImage({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallbackIcon = Icons.auto_stories,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) {
        return Container(
          width: width,
          height: height,
          color: const Color(0xFFEDE7F6),
          alignment: Alignment.center,
          child: Icon(
            fallbackIcon,
            size: 56,
            color: const Color(0xFF7E57C2),
          ),
        );
      },
    );
  }
}