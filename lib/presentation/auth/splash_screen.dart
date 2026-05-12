import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/constants.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _scaleAnim = Tween<double>(begin: 0.85, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.forward();

    // Auto-navigate to login after splash screen animation completes
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        context.go('/');
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.background,
              AppColors.surfaceElevated.withValues(alpha: 0.5),
              AppColors.background,
            ],
            stops: const [0, 0.5, 1],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ILLUME Icon with subtle glow
                  Container(
                    width: 120,
                    height: 120,
                    padding: const EdgeInsets.all(AppDimens.spacingLG),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.15),
                          blurRadius: 40,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/icons/illume_logo_icon.svg',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: AppDimens.spacing5XL),

                  // ILLUME POS Text
                  Text(
                    'ILLUME POS',
                    style: AppTypography.displayMedium.copyWith(
                      color: AppColors.textPrimary,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(height: AppDimens.spacingMD),

                  // Subtitle
                  Text(
                    'Retail Operating System',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textMuted,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
