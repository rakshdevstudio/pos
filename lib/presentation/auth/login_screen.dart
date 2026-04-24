import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/constants.dart';
import '../../data/remote/api_client.dart';
import '../shared/widgets/illume_button.dart';
import '../shared/widgets/illume_text_field.dart';

final _loginLoadingProvider = StateProvider<bool>((ref) => false);
final _loginErrorProvider = StateProvider<String?>((ref) => null);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showPassword = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    ref.read(_loginLoadingProvider.notifier).state = true;
    ref.read(_loginErrorProvider.notifier).state = null;

    try {
      // Mock login for UI testing
      if (_emailController.text.trim() == 'admin@illume.in' && 
          _passwordController.text == 'admin123') {
        await Future.delayed(const Duration(seconds: 1)); // Simulate network
        await ApiClient.saveToken('mock_admin_token_12345');
        if (mounted) context.go('/schools');
        return;
      }

      final apiClient = ApiClient();
      final baseUrl = ApiClient.baseUrl;
      final response = await apiClient.dio.post(
        '$baseUrl/auth/login',
        data: {
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        },
      );

      final token = response.data['token'] as String?;
      if (token != null) {
        await ApiClient.saveToken(token);
        if (mounted) context.go('/schools');
      } else {
        ref.read(_loginErrorProvider.notifier).state =
            AppStrings.loginError;
      }
    } catch (e) {
      ref.read(_loginErrorProvider.notifier).state = AppStrings.loginError;
    } finally {
      if (mounted) {
        ref.read(_loginLoadingProvider.notifier).state = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(_loginLoadingProvider);
    final error = ref.watch(_loginErrorProvider);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Main content
          Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimens.spacingXXL),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Brand logo / name
                          Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(
                                        AppDimens.radiusLG),
                                    border: Border.all(
                                        color: AppColors.border),
                                  ),
                                  child: const Icon(
                                    Icons.diamond_outlined,
                                    color: AppColors.accent,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: AppDimens.spacingLG),
                                Text(
                                  AppStrings.brandName,
                                  style: AppTypography.displayMedium.copyWith(
                                    color: AppColors.textPrimary,
                                    letterSpacing: 8,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                                const SizedBox(height: AppDimens.spacingXS),
                                Text(
                                  AppStrings.loginSubtitle,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textMuted,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: AppDimens.spacing5XL),

                          // Email
                          IllumeTextField(
                            controller: _emailController,
                            hintText: AppStrings.email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            prefixIcon: const Icon(
                              Icons.mail_outline_rounded,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Email required';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: AppDimens.spacingMD),

                          // Password
                          IllumeTextField(
                            controller: _passwordController,
                            hintText: AppStrings.password,
                            obscureText: !_showPassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _handleLogin(),
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: AppColors.textMuted,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 18,
                                color: AppColors.textMuted,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showPassword = !_showPassword;
                                });
                              },
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Password required';
                              }
                              return null;
                            },
                          ),

                          // Error message
                          AnimatedSize(
                            duration: const Duration(
                                milliseconds: AppDimens.animMedium),
                            child: error != null
                                ? Padding(
                                    padding: const EdgeInsets.only(
                                        top: AppDimens.spacingMD),
                                    child: Container(
                                      padding: const EdgeInsets.all(
                                          AppDimens.spacingMD),
                                      decoration: BoxDecoration(
                                        color: AppColors.errorDim,
                                        borderRadius: BorderRadius.circular(
                                            AppDimens.radiusSM),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.error_outline_rounded,
                                            size: 16,
                                            color: AppColors.error,
                                          ),
                                          const SizedBox(
                                              width: AppDimens.spacingSM),
                                          Text(
                                            error,
                                            style: AppTypography.bodySmall
                                                .copyWith(
                                              color: AppColors.error,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),

                          const SizedBox(height: AppDimens.spacingXXL),

                          IllumeButton(
                            label: AppStrings.login,
                            onPressed: _handleLogin,
                            isLoading: isLoading,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
