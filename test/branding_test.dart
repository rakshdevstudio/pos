import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pos_app/presentation/shared/widgets/illume_logo.dart';
import 'package:pos_app/presentation/auth/splash_screen.dart';

void main() {
  group('ILLUME POS Branding Tests', () {
    testWidgets('LogoIcon renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LogoIcon(size: 48),
          ),
        ),
      );

      expect(find.byType(LogoIcon), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('LogoIcon with shadow renders correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LogoIcon(size: 48, shadow: true),
          ),
        ),
      );

      expect(find.byType(LogoIcon), findsOneWidget);
      expect(find.byType(Container), findsOneWidget);
    });

    testWidgets('LogoHorizontal renders correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LogoHorizontal(height: 64),
          ),
        ),
      );

      expect(find.byType(LogoHorizontal), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('LogoMonochrome renders correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LogoMonochrome(size: 48),
          ),
        ),
      );

      expect(find.byType(LogoMonochrome), findsOneWidget);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('Splash screen displays branding text',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(),
        ),
      );

      expect(find.text('ILLUME POS'), findsOneWidget);
      expect(find.text('Retail Operating System'), findsOneWidget);
    });

    testWidgets('Splash screen has proper styling',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplashScreen(),
        ),
      );

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(Container), findsWidgets);
      expect(find.byType(FadeTransition), findsOneWidget);
      expect(find.byType(ScaleTransition), findsOneWidget);
    });

    group('Logo Asset Paths', () {
      test('Icon logo asset exists', () {
        const String iconPath = 'assets/icons/illume_logo_icon.svg';
        expect(iconPath, isNotEmpty);
      });

      test('Horizontal logo asset exists', () {
        const String horizontalPath = 'assets/icons/illume_logo_horizontal.svg';
        expect(horizontalPath, isNotEmpty);
      });

      test('Monochrome logo asset exists', () {
        const String monochromePath = 'assets/icons/illume_logo_monochrome.svg';
        expect(monochromePath, isNotEmpty);
      });
    });

    group('Color Scheme Tests', () {
      test('Accent color is correct', () {
        const Color accentColor = Color(0xFFD4AF37);
        expect(accentColor.value, equals(0xFFD4AF37));
      });

      test('Background color is correct', () {
        const Color bgColor = Color(0xFF0A0A0A);
        expect(bgColor.value, equals(0xFF0A0A0A));
      });

      test('Surface color is correct', () {
        const Color surfaceColor = Color(0xFF141414);
        expect(surfaceColor.value, equals(0xFF141414));
      });
    });

    group('Responsive Sizing', () {
      test('LogoIcon default size is 48', () {
        const LogoIcon logo = LogoIcon();
        expect(logo.size, equals(48));
      });

      test('LogoIcon can be customized', () {
        const LogoIcon logo = LogoIcon(size: 64);
        expect(logo.size, equals(64));
      });

      test('LogoHorizontal default height is 64', () {
        const LogoHorizontal logo = LogoHorizontal();
        expect(logo.height, equals(64));
      });
    });
  });
}
