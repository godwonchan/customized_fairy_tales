import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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

  String get _resolvedPath {
    if (!_isNetworkImage) return imagePath;

    // 웹(크롬)은 그대로
    if (kIsWeb) return imagePath;

    // 안드로이드 실제 기기 & 에뮬레이터 모두 처리
    String resolved = imagePath;

    // localhost → 192.168.219.110 (실제 기기용)
    resolved = resolved.replaceFirst('http://localhost:', 'http://192.168.219.110:');
    // 127.0.0.1 → 192.168.219.110
    resolved = resolved.replaceFirst('http://127.0.0.1:', 'http://192.168.219.110:');
    // 10.0.2.2 → 192.168.219.110
    resolved = resolved.replaceFirst('http://10.0.2.2:', 'http://192.168.219.110:');

    return resolved;
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