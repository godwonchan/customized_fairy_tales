// lib/config/app_config.dart
// 서버 주소를 한 곳에서 정한다. 앞에 있는 것이 우선:
//   1. 앱 안에서 입력해 저장한 주소 (로그인 화면의 크레용을 길게 누르기) - 전시장에서 노트북 IP 가 바뀌어도 다시 빌드하지 않게
//   2. 빌드할 때 넣은 주소: flutter build apk --dart-define=SERVER_URL=http://192.168.0.10:8000
//   3. 실행 환경별 기본값: 크롬 = 127.0.0.1, 안드로이드 에뮬레이터(안드로이드 스튜디오 Run) = 10.0.2.2
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String _prefsKey = 'server_url';
  static const String _buildUrl = String.fromEnvironment('SERVER_URL');
  static String _savedUrl = '';

  /// 앱 시작 때 한 번 불러 둔다 (main 에서 runApp 전에).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _savedUrl = prefs.getString(_prefsKey) ?? '';
  }

  static String get defaultUrl {
    if (_buildUrl.isNotEmpty) return _buildUrl;
    if (kIsWeb) return 'http://127.0.0.1:8000';
    return 'http://10.0.2.2:8000'; // 안드로이드 에뮬레이터에서 본 컴퓨터
  }

  static String get serverUrl => _savedUrl.isNotEmpty ? _savedUrl : defaultUrl;

  /// 입력한 주소를 저장한다. 빈 값이면 저장한 주소를 지우고 기본값으로 돌아간다.
  static Future<void> save(String url) async {
    var u = url.trim();
    if (u.isNotEmpty && !u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    final prefs = await SharedPreferences.getInstance();
    if (u.isEmpty) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, u);
    }
    _savedUrl = u;
  }

  /// 서버가 만들어 둔 그림 주소(http://127.0.0.1:8000/... 등)를 지금 서버 주소로 바꾼다.
  /// 서버는 자기 자신을 127.0.0.1 로 적어 두지만, 태블릿에서는 그 주소가 태블릿 자신을 뜻한다.
  static String resolve(String url) {
    for (final local in ['http://localhost:8000', 'http://127.0.0.1:8000', 'http://10.0.2.2:8000']) {
      if (url.startsWith(local)) return serverUrl + url.substring(local.length);
    }
    return url;
  }
}

/// 서버 주소 입력 창 (로그인 화면의 크레용을 길게 누르면 열린다).
Future<void> showServerSettings(BuildContext context) async {
  final controller = TextEditingController(text: AppConfig.serverUrl);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('서버 주소'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'http://192.168.0.10:8000'),
          ),
          const SizedBox(height: 8),
          Text('비우고 저장하면 기본값: ${AppConfig.defaultUrl}', style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
      ],
    ),
  );
  if (saved == true) {
    await AppConfig.save(controller.text);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('서버 주소: ${AppConfig.serverUrl}')));
    }
  }
  controller.dispose();
}
