import 'package:flutter/material.dart';
<<<<<<< HEAD
=======
import 'package:flutter/cupertino.dart';
>>>>>>> wonchan_ui_fixed
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/favorites_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => FavoritesProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '동화 앱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'NotoSansKR',
        scaffoldBackgroundColor: const Color(0xFFF8F4FF),
        colorScheme: ColorScheme.fromSeed(
<<<<<<< HEAD
            seedColor: const Color(0xFFB39DDB)),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
=======
          seedColor: const Color(0xFFB39DDB),
        ),
        pageTransitionsTheme: PageTransitionsTheme(
          builders: {
            TargetPlatform.android: const CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: const CupertinoPageTransitionsBuilder(),
>>>>>>> wonchan_ui_fixed
          },
        ),
      ),
      home: const AppShell(),
    );
  }
}