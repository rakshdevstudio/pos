import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/constants.dart';
import '../../core/providers/providers.dart';
import '../../domain/models/models.dart';
import '../../services/cart_service.dart';
import '../shared/widgets/sync_status_badge.dart';

final _schoolsProvider = FutureProvider<List<School>>((ref) async {
  return ref.read(schoolRepoProvider).fetchSchools();
});

final _selectedSchoolProvider = StateProvider<School?>((ref) => null);
final _searchQueryProvider = StateProvider<String>((ref) => '');

class SchoolSelectionScreen extends ConsumerWidget {
  const SchoolSelectionScreen({super.key});

  Future<void> _handleSchoolSelection(
    BuildContext context,
    WidgetRef ref,
    School school,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final currentSchoolId = prefs.getString('selectedSchoolId');
    final schoolChanged = currentSchoolId != null &&
        currentSchoolId.isNotEmpty &&
        currentSchoolId != school.id;

    if (schoolChanged && ref.read(cartProvider).items.isNotEmpty) {
      final shouldContinue = await _confirmSchoolSwitch(context);
      if (shouldContinue != true || !context.mounted) {
        return;
      }
    }

    debugPrint('UI Selected School: ${school.name} (${school.id})');
    ref.read(_selectedSchoolProvider.notifier).state = school;

    if (schoolChanged) {
      ref.read(cartProvider.notifier).resetCart();
    }
    if (schoolChanged || currentSchoolId == null || currentSchoolId.isEmpty) {
      ref.read(productRepoProvider).clearCache();
    }

    final branchId = school.branchId ?? '';
    await prefs.setString('selectedSchoolId', school.id);
    await prefs.setString('selectedBranchId', branchId);
    await prefs.setString('selectedSchoolName', school.name);
    await prefs.remove('selected_school_id');
    await prefs.remove('selected_branch_id');
    await prefs.remove('selected_school_name');

    if (context.mounted) {
      context.go('/pos');
    }
  }

  Future<bool?> _confirmSchoolSwitch(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusLG),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Text(
            'Clear current cart?',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            'Switching schools will clear the current cart before loading the new school.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolsAsync = ref.watch(_schoolsProvider);
    final selectedSchool = ref.watch(_selectedSchoolProvider);
    final searchQuery = ref.watch(_searchQueryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: Padding(
          padding: const EdgeInsets.all(AppDimens.spacingMD),
          child: Text(
            AppStrings.brandName,
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.accent,
              letterSpacing: 4,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
        leadingWidth: 120,
        actions: const [
          SyncStatusBadge(),
          SizedBox(width: AppDimens.spacingLG),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.spacing3XL,
              AppDimens.spacing3XL,
              AppDimens.spacing3XL,
              AppDimens.spacingXL,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.selectSchool,
                  style: AppTypography.headlineLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDimens.spacingXS),
                Text(
                  AppStrings.selectSchoolSubtitle,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppDimens.spacingXXL),
                // Search
                TextField(
                  onChanged: (val) {
                    ref.read(_searchQueryProvider.notifier).state = val;
                  },
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    hintText: AppStrings.searchSchools,
                    hintStyle: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textMuted,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppDimens.spacingLG,
                      ),
                      child: Icon(
                        Icons.search_rounded,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                      borderSide:
                          const BorderSide(color: AppColors.accent, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppDimens.spacingLG,
                      vertical: AppDimens.spacingMD,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // School Grid
          Expanded(
            child: schoolsAsync.when(
              data: (schools) {
                final filtered = searchQuery.isEmpty
                    ? schools
                    : schools
                        .where((s) => s.name
                            .toLowerCase()
                            .contains(searchQuery.toLowerCase()))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.school_outlined,
                          size: 48,
                          color: AppColors.textDisabled,
                        ),
                        const SizedBox(height: AppDimens.spacingMD),
                        Text(
                          AppStrings.noSchools,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.spacing3XL,
                    0,
                    AppDimens.spacing3XL,
                    AppDimens.spacing3XL,
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    crossAxisSpacing: AppDimens.spacingLG,
                    mainAxisSpacing: AppDimens.spacingLG,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final school = filtered[index];
                    final isSelected = selectedSchool?.id == school.id;
                    return _SchoolCard(
                      school: school,
                      isSelected: isSelected,
                      onTap: () => _handleSchoolSelection(context, ref, school),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                  color: AppColors.accent,
                  strokeWidth: 2,
                ),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        color: AppColors.textMuted, size: 40),
                    const SizedBox(height: AppDimens.spacingMD),
                    Text(
                      _schoolLoadErrorMessage(e),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppDimens.spacingMD),
                    TextButton(
                      onPressed: () => ref.invalidate(_schoolsProvider),
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: AppColors.accent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _schoolLoadErrorMessage(Object error) {
  final text = error.toString();
  if (text.contains('SUPABASE_ANON_KEY')) {
    return 'School API key is missing';
  }
  if (text.contains('No API key') ||
      text.contains('401') ||
      text.contains('JWT')) {
    return 'Could not authenticate school API';
  }
  return 'Could not load schools';
}

class _SchoolCard extends StatefulWidget {
  final School school;
  final bool isSelected;
  final VoidCallback onTap;

  const _SchoolCard({
    required this.school,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SchoolCard> createState() => _SchoolCardState();
}

class _SchoolCardState extends State<_SchoolCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: AppDimens.animFast),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) {
          _controller.reverse();
          widget.onTap();
        },
        onTapCancel: () => _controller.reverse(),
        child: ScaleTransition(
          scale: _scaleAnim,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: AppDimens.animMedium),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? AppColors.accentGlow
                  : _isHovered
                      ? AppColors.surfaceElevated
                      : AppColors.surface,
              borderRadius: BorderRadius.circular(AppDimens.radiusLG),
              border: Border.all(
                color: widget.isSelected
                    ? AppColors.accent
                    : _isHovered
                        ? AppColors.borderFocus
                        : AppColors.border,
                width: widget.isSelected ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.all(AppDimens.spacingLG),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: widget.school.logoUrl != null
                      ? ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppDimens.radiusMD),
                          child: CachedNetworkImage(
                            imageUrl: widget.school.logoUrl!,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => const Icon(
                              Icons.school_outlined,
                              color: AppColors.textMuted,
                              size: 32,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.school_outlined,
                          color: AppColors.textMuted,
                          size: 32,
                        ),
                ),
                const SizedBox(height: AppDimens.spacingMD),
                Text(
                  widget.school.name.toUpperCase(),
                  style: AppTypography.labelLarge.copyWith(
                    color: widget.isSelected
                        ? AppColors.accent
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.school.city != null) ...[
                  const SizedBox(height: AppDimens.spacingXS),
                  Text(
                    widget.school.city!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
