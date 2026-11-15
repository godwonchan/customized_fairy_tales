import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFFFFF3DE); // 크림색 바탕
  static const Color surface = Color(0xFFFFFDF9); // 흰색에 가까운 카드 (크림색 바탕과 구분)
  static const Color surfaceVariant = Color(0xFFFFEBCB);
  static const Color inputFill = Color(0xFFFFFDF7);
  static const Color border = Color(0xFFEBCFA6);

  static const Color primary = Color(0xFFFFCB3D);
  static const Color primaryLight = Color(0xFFFFEDAA);
  static const Color primaryDark = Color(0xFFE9A91F);
  static const Color onPrimary = Color(0xFF6A3516);
  static const Color primaryText = Color(0xFFB4691C);

  static const Color secondary = Color(0xFF8FCB5E);
  static const Color secondaryLight = Color(0xFFDCEFB8);
  static const Color secondaryDark = Color(0xFF5A9A3C);

  static const Color accent = Color(0xFFF08FA0);
  static const Color accentLight = Color(0xFFFFE0E6);
  static const Color accentDark = Color(0xFFC9566B);

  static const Color textPrimary = Color(0xFF4E2C15);
  static const Color textSecondary = Color(0xFF8A6238);
  static const Color textHint = Color(0xFFB89F84);

  static const Color error = Color(0xFFD9604F);
  static const Color errorLight = Color(0xFFFDECEA);
  static const Color success = secondaryDark;

  static const Color cardShadow = Color(0x47A9794A);
}

class AppTextStyles {
  AppTextStyles._();

  static TextStyle display({Color? color}) => GoogleFonts.jua(
        fontSize: 32,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle headingLarge({Color? color}) => GoogleFonts.jua(
        fontSize: 26,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textPrimary,
        height: 1.4,
      );

  static TextStyle headingMedium({Color? color}) => GoogleFonts.jua(
        fontSize: 22,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textPrimary,
        height: 1.4,
      );

  static TextStyle headingSmall({Color? color}) => GoogleFonts.jua(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textPrimary,
        height: 1.5,
      );

  static TextStyle bodyLarge({Color? color}) => GoogleFonts.gothicA1(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textPrimary,
        height: 1.6,
      );

  static TextStyle bodyMedium({Color? color}) => GoogleFonts.gothicA1(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textSecondary,
        height: 1.6,
      );

  static TextStyle bodySmall({Color? color}) => GoogleFonts.gothicA1(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textHint,
        height: 1.5,
      );

  static TextStyle labelLarge({Color? color}) => GoogleFonts.jua(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textPrimary,
        letterSpacing: 0.3,
      );

  static TextStyle labelMedium({Color? color}) => GoogleFonts.jua(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.textSecondary,
        letterSpacing: 0.2,
      );

  static TextStyle labelSmall({Color? color}) => GoogleFonts.jua(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.textHint,
        letterSpacing: 0.5,
      );

  static TextStyle button({Color? color}) => GoogleFonts.jua(
        fontSize: 20,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.onPrimary,
        height: 1.2,
      );

  static TextStyle caption({Color? color}) => GoogleFonts.gothicA1(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textHint,
      );

  static TextStyle storyBody({Color? color, double? fontSize}) =>
      GoogleFonts.gothicA1(
        fontSize: fontSize ?? 17,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textPrimary,
        height: 1.8,
      );

  static TextStyle storyTitle({Color? color}) => GoogleFonts.jua(
        fontSize: 24,
        fontWeight: FontWeight.w400,
        color: color ?? AppColors.textPrimary,
        height: 1.4,
      );
}

class AppTheme {
  AppTheme._();

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          surface: AppColors.surface,
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          secondary: AppColors.secondary,
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: TextTheme(
          displayLarge: AppTextStyles.display(),
          headlineLarge: AppTextStyles.headingLarge(),
          headlineMedium: AppTextStyles.headingMedium(),
          headlineSmall: AppTextStyles.headingSmall(),
          bodyLarge: AppTextStyles.bodyLarge(),
          bodyMedium: AppTextStyles.bodyMedium(),
          bodySmall: AppTextStyles.bodySmall(),
          labelLarge: AppTextStyles.labelLarge(),
          labelMedium: AppTextStyles.labelMedium(),
          labelSmall: AppTextStyles.labelSmall(),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          titleTextStyle: AppTextStyles.headingMedium(),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            textStyle: AppTextStyles.button(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            textStyle: AppTextStyles.button(),
            side: const BorderSide(color: AppColors.primary, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryText,
            textStyle: AppTextStyles.labelLarge(color: AppColors.primaryText),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.inputFill,
          hintStyle: AppTextStyles.bodyMedium(color: AppColors.textHint),
          labelStyle: AppTextStyles.labelMedium(),
          prefixIconColor: AppColors.primaryText,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.border, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.border, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.border, width: 2),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surfaceVariant,
          labelStyle: AppTextStyles.labelMedium(color: AppColors.textPrimary),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primaryText,
          unselectedItemColor: AppColors.textHint,
          selectedLabelStyle: AppTextStyles.labelSmall(color: AppColors.primaryText),
          unselectedLabelStyle: AppTextStyles.labelSmall(),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.border,
          thickness: 1,
          space: 1,
        ),
        iconTheme: const IconThemeData(
          color: AppColors.textPrimary,
          size: 24,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primary,
          linearTrackColor: AppColors.surfaceVariant,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.primary,
          inactiveTrackColor: AppColors.surfaceVariant,
          thumbColor: AppColors.primaryDark,
          overlayColor: AppColors.primary.withOpacity(0.15),
          trackHeight: 6,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) =>
              states.contains(MaterialState.selected)
                  ? AppColors.surface
                  : AppColors.textHint),
          trackColor: MaterialStateProperty.resolveWith((states) =>
              states.contains(MaterialState.selected)
                  ? AppColors.secondary
                  : AppColors.surfaceVariant),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textHint,
          labelStyle: AppTextStyles.labelLarge(),
          unselectedLabelStyle: AppTextStyles.labelMedium(),
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: AppColors.primary, width: 4),
            borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titleTextStyle: AppTextStyles.headingSmall(),
          contentTextStyle: AppTextStyles.bodyMedium(),
          elevation: 0,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.textPrimary,
          contentTextStyle: AppTextStyles.bodyMedium(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
}

class AppDecorations {
  AppDecorations._();

  // 장난감처럼 도톰한 크림색 카드: 밝은 원목색 테두리 + 아래로 깔리는 부드러운 그림자
  static BoxDecoration card({double radius = 20, Color? color}) => BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border, width: 2),
        boxShadow: const [
          BoxShadow(color: AppColors.border, offset: Offset(0, 4)),
          BoxShadow(color: AppColors.cardShadow, blurRadius: 8, offset: Offset(0, 8)),
        ],
      );

  static BoxDecoration sticker({
    required Color color,
    required Color shadowColor,
    double radius = 16,
    double depth = 4,
  }) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 0,
            offset: Offset(0, depth),
          ),
        ],
      );

  static BoxDecoration primaryButton({double radius = 16, double depth = 4}) =>
      sticker(
        color: AppColors.primary,
        shadowColor: AppColors.primaryDark,
        radius: radius,
        depth: depth,
      );

  static BoxDecoration gradientBackground() =>
      const BoxDecoration(color: AppColors.background);

  static BoxDecoration accentCard({double radius = 16}) => BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border, width: 1.5),
      );
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 16);
  static const EdgeInsets cardPadding = EdgeInsets.all(16);
  static const EdgeInsets sectionPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 12);
}

class CrayongImages {
  CrayongImages._();

  static const String _base = 'assets/images/dragon';
  static const String main = '$_base/dragon_main.png';
  static const String wink = '$_base/dragon_wink.png';
  static const String walk = '$_base/dragon_walk.png';
  static const String proud = '$_base/dragon_proud.png';
  static const String painter = '$_base/dragon_painter.png';
  static const String drawing = '$_base/dragon_drawing.png';
  static const String celebrate = '$_base/dragon_celebrate.png';
  static const String lying = '$_base/dragon_lying.png';
  static const String surprised = '$_base/dragon_surprised.png';
  static const String lyingAnim = '$_base/dragon_lying_anim.webp';
}

/// 크림색 도트 무늬 바탕을 까는 Scaffold. 쓰는 법은 Scaffold 와 같다.
class ToyScaffold extends StatelessWidget {
  static const String roomImage = 'assets/toy_shelf/backgrounds/background_room.png';

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Color? backgroundColor; // Scaffold 와 맞추려고 받기만 한다 (배경은 항상 크림색 도트 무늬)
  final bool? resizeToAvoidBottomInset;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final bool extendBody;
  final bool extendBodyBehindAppBar;

  const ToyScaffold({
    super.key,
    this.appBar,
    this.body,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    // 크림색 바탕에 은은한 도트 무늬 (그림책 속지 느낌). 무늬는 화면마다 한 번만 그린다.
    return ColoredBox(
      color: AppColors.background,
      child: CustomPaint(
        painter: const _DotPaperPainter(),
        isComplex: true,
        willChange: false,
        child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: body,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
        extendBody: extendBody,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
        ),
      ),
    );
  }
}

class _DotPaperPainter extends CustomPainter {
  const _DotPaperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFFF7DDB4);
    const gap = 44.0;
    int row = 0;
    for (double y = gap / 2; y < size.height; y += gap, row++) {
      // 줄마다 반 칸씩 엇갈리게
      for (double x = (row.isEven ? gap / 2 : gap); x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotPaperPainter oldDelegate) => false;
}
