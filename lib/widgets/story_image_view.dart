import 'package:flutter/material.dart';
import '../config/app_config.dart';

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

  // ✅ 플랫폼에 맞게 URL 자동 교체
  String get _resolvedPath {
    if (!_isNetworkImage) return imagePath;
    // 서버가 적어 둔 localhost·127.0.0.1 주소를 지금 서버 주소로 (크롬·에뮬레이터·태블릿 모두, lib/config/app_config.dart)
    return AppConfig.resolve(imagePath);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolvedPath;
    debugPrint('StoryImageView imagePath = $resolved');

    if (_isNetworkImage) {
      return Image.network(
        resolved,
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
      resolved,
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