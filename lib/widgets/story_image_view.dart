import 'package:flutter/material.dart';

class StoryImageView extends StatelessWidget {
  final String imagePath;
  final BoxFit fit;

  const StoryImageView({
    super.key,
    required this.imagePath,
    this.fit = BoxFit.cover,
  });

  bool get _isNetworkImage {
    return imagePath.startsWith('http://') ||
        imagePath.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('StoryImageView imagePath = $imagePath');

    if (_isNetworkImage) {
      return Image.network(
        imagePath,
        fit: fit,
        errorBuilder: (_, error, __) {
          debugPrint('network image load error: $error');
          return Container(
            color: const Color(0xFFF3EFFF),
            alignment: Alignment.center,
            child: const Icon(
              Icons.broken_image,
              size: 60,
              color: Color(0xFF7E57C2),
            ),
          );
        },
      );
    }

    return Image.asset(
      imagePath,
      fit: fit,
      errorBuilder: (_, error, __) {
        debugPrint('asset image load error: $error');
        return Container(
          color: const Color(0xFFF3EFFF),
          alignment: Alignment.center,
          child: const Icon(
            Icons.auto_stories,
            size: 60,
            color: Color(0xFF7E57C2),
          ),
        );
      },
    );
  }
}