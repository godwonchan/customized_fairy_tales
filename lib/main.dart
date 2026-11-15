import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'providers/favorites_provider.dart';
import 'providers/font_size_provider.dart';
import 'screens/login_screen.dart';
import 'screens/creation/custom_story_create_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 전체 화면: 위쪽 상태 줄과 아래쪽 내비게이션 줄을 숨긴다.
  // - 가로 태블릿(16:10) 화면을 전부 써서 시안 그림이 좌우 여백 없이 꽉 찬다
  // - 아이가 실수로 홈·뒤로 버튼을 눌러 앱 밖으로 나가는 일도 줄어든다 (화면 가장자리를 쓸면 잠깐 다시 나타남)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await AppConfig.load(); // 앱에서 입력해 둔 서버 주소 불러오기
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ChangeNotifierProvider(create: (_) => FontSizeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final textScale = context.watch<FontSizeProvider>().scale;

    return MaterialApp(
      title: '동화랑',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme.copyWith(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const LoginScreen(),
    );
  }
}