import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/constants.dart';
import '../../core/providers/providers.dart';
import '../../data/remote/api_client.dart';
import '../../domain/models/models.dart';
import '../../services/cart_service.dart';
import '../shared/widgets/sync_status_badge.dart';
import 'cart_panel.dart';
import 'product_card.dart';

final _productsProvider =
    FutureProvider.family<List<Product>, String>((ref, schoolId) async {
  final repo = ref.read(productRepoProvider);
  return repo.getProducts(schoolId);
});

final _searchQueryPosProvider = StateProvider<String>((ref) => '');
final _selectedCategoryProvider = StateProvider<String?>((ref) => null);

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _searchController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _barcodeFocus = FocusNode();
  String? _schoolId;
  String? _schoolName;

  String? _lastCode;
  DateTime? _lastTime;

  bool _shouldDrop(String code) {
    final now = DateTime.now();
    if (_lastCode == code &&
        _lastTime != null &&
        now.difference(_lastTime!) < const Duration(milliseconds: 400)) {
      return true;
    }
    _lastCode = code;
    _lastTime = now;
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadSchool();
  }

  Future<void> _loadSchool() async {
    final prefs = await SharedPreferences.getInstance();
    final id = _productSchoolIdFromPrefs(prefs);
    if (id == null) {
      if (mounted) context.go('/schools');
      return;
    }

    final name = prefs.getString('selectedSchoolName') ??
        prefs.getString('selected_school_name') ??
        'Store';
    setState(() {
      _schoolId = id;
      _schoolName = name;
    });
  }

  String? _productSchoolIdFromPrefs(SharedPreferences prefs) {
    final legacySchoolId = prefs.get('selected_school_id');
    final selectedSchoolId = prefs.getString('selectedSchoolId') ??
        (legacySchoolId is String ? legacySchoolId : null);
    return selectedSchoolId?.isNotEmpty == true ? selectedSchoolId : null;
  }

  void _handleBarcodeSubmit(String sku) {
    if (sku.isEmpty) return;
    if (_shouldDrop(sku)) {
      _barcodeController.clear();
      _barcodeFocus.requestFocus();
      return;
    }

    final variant = ref.read(productRepoProvider).findVariantBySku(sku);
    if (variant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.barcodeNotFound,
            style:
                AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
          ),
          backgroundColor: AppColors.errorDim,
        ),
      );
    } else {
      // Find parent product
      if (_schoolId != null) {
        final products =
            ref.read(productRepoProvider).getCachedProducts(_schoolId!);
        if (products.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Products are still loading')),
          );
          _barcodeController.clear();
          _barcodeFocus.requestFocus();
          return;
        }
        final product = products.firstWhere(
          (p) => p.variants.any((v) => v.id == variant.id),
          orElse: () => products.first,
        );
        final added = ref.read(cartProvider.notifier).addItem(product, variant);
        if (!added) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Out of stock')),
          );
          _barcodeController.clear();
          _barcodeFocus.requestFocus();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 16),
                const SizedBox(width: AppDimens.spacingSM),
                Text(
                  '${product.name} (${variant.size}) added via barcode',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        );
      }
    }
    _barcodeController.clear();
    _barcodeFocus.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: _schoolId == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : _buildPosLayout(),
    );
  }

  Widget _buildPosLayout() {
    final width = MediaQuery.of(context).size.width;

    final productsPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(),
        const Divider(height: 1, color: AppColors.border),
        _buildSearchAndBarcode(),
        _buildCategoryFilter(),
        Expanded(child: _buildProductGrid()),
      ],
    );

    if (width > 600) {
      // TABLET / LARGE SCREEN (Landscape split)
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            width: 320,
            child: CartPanel(),
          ),
          const VerticalDivider(
              width: 1, thickness: 1, color: AppColors.border),
          Expanded(
            child: productsPanel,
          ),
        ],
      );
    } else {
      // MOBILE (Portrait stacked)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: productsPanel,
          ),
          const Divider(height: 1, color: AppColors.border),
          const Expanded(
            flex: 4,
            child: CartPanel(),
          ),
        ],
      );
    }
  }

  Widget _buildTopBar() {
    return Container(
      height: AppDimens.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.spacingXXL),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _schoolName ?? 'Store',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppDimens.spacingXS),
                Text(
                  '· POS',
                  style: AppTypography.headlineSmall.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDimens.spacingMD),
          const SyncStatusBadge(),
          const SizedBox(width: AppDimens.spacingMD),
          _ProfileMenu(),
        ],
      ),
    );
  }

  Widget _buildSearchAndBarcode() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.spacingXXL,
        AppDimens.spacingLG,
        AppDimens.spacingXXL,
        AppDimens.spacingSM,
      ),
      child: Row(
        children: [
          // Product search
          Expanded(
            flex: 3,
            child: _SearchField(
              controller: _searchController,
              onChanged: (val) {
                ref.read(_searchQueryPosProvider.notifier).state = val;
              },
            ),
          ),
          const SizedBox(width: AppDimens.spacingMD),
          // Barcode input (hidden but focused for USB scanner)
          Expanded(
            flex: 2,
            child: TextField(
              controller: _barcodeController,
              focusNode: _barcodeFocus,
              style: AppTypography.bodyLarge
                  .copyWith(color: AppColors.textPrimary),
              cursorColor: AppColors.accent,
              textInputAction: TextInputAction.done,
              onSubmitted: _handleBarcodeSubmit,
              decoration: InputDecoration(
                hintText: AppStrings.scanBarcode,
                hintStyle: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textMuted,
                ),
                prefixIcon: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: AppDimens.spacingLG),
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 18,
                    color: AppColors.textMuted,
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
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    if (_schoolId == null) return const SizedBox.shrink();
    final productsAsync = ref.watch(_productsProvider(_schoolId!));
    return productsAsync.maybeWhen(
      data: (products) {
        final categories = products
            .map((p) => p.category)
            .whereType<String>()
            .toSet()
            .toList();
        if (categories.isEmpty) {
          return const SizedBox(height: AppDimens.spacingSM);
        }
        final selectedCat = ref.watch(_selectedCategoryProvider);
        return SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: AppDimens.spacingXXL),
            children: [
              _CategoryChip(
                label: 'All',
                isSelected: selectedCat == null,
                onTap: () =>
                    ref.read(_selectedCategoryProvider.notifier).state = null,
              ),
              ...categories.map((cat) => _CategoryChip(
                    label: cat,
                    isSelected: selectedCat == cat,
                    onTap: () => ref
                        .read(_selectedCategoryProvider.notifier)
                        .state = cat,
                  )),
            ],
          ),
        );
      },
      orElse: () => const SizedBox(height: AppDimens.spacingSM),
    );
  }

  Widget _buildProductGrid() {
    if (_schoolId == null) return const SizedBox.shrink();
    final productsAsync = ref.watch(_productsProvider(_schoolId!));
    final searchQuery = ref.watch(_searchQueryPosProvider);
    final selectedCat = ref.watch(_selectedCategoryProvider);

    return productsAsync.when(
      data: (products) {
        var filtered = products;
        if (searchQuery.isNotEmpty) {
          filtered = filtered
              .where((p) =>
                  p.name.toLowerCase().contains(searchQuery.toLowerCase()))
              .toList();
        }
        if (selectedCat != null) {
          filtered = filtered.where((p) => p.category == selectedCat).toList();
        }

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off_rounded,
                    color: AppColors.textDisabled, size: 40),
                const SizedBox(height: AppDimens.spacingMD),
                Text(
                  searchQuery.isEmpty && selectedCat == null
                      ? 'No products available'
                      : 'No products found',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(AppDimens.spacingXXL),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: AppDimens.productCardWidth + 20,
            crossAxisSpacing: AppDimens.spacingMD,
            mainAxisSpacing: AppDimens.spacingMD,
            childAspectRatio: 0.72,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final product = filtered[index];
            return ProductCard(
              product: product,
              onTap: () {
                if (product.variants.length == 1) {
                  final variant = product.variants.first;
                  if (variant.stock <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Out of stock')),
                    );
                    return;
                  }
                  HapticFeedback.lightImpact();
                  final added =
                      ref.read(cartProvider.notifier).addItem(product, variant);
                  if (!added) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppColors.success, size: 16),
                          const SizedBox(width: AppDimens.spacingSM),
                          Text('${product.name} added',
                              style: AppTypography.bodySmall
                                  .copyWith(color: AppColors.textPrimary)),
                        ],
                      ),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: AppColors.surfaceElevated,
                    ),
                  );
                } else {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => VariantSheet(product: product),
                  );
                }
              },
            );
          },
        );
      },
      loading: () => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: AppColors.accent,
              strokeWidth: 2,
            ),
            const SizedBox(height: AppDimens.spacingMD),
            Text(
              'Loading products...',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                color: AppColors.textMuted, size: 40),
            const SizedBox(height: AppDimens.spacingMD),
            Text(
              'Could not load products',
              style:
                  AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppDimens.spacingMD),
            TextButton(
              onPressed: () => ref.invalidate(_productsProvider(_schoolId!)),
              child: const Text('Retry',
                  style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onChanged;

  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: AppStrings.searchProducts,
        hintStyle:
            AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
        prefixIcon: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppDimens.spacingLG),
          child:
              Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
        ),
        prefixIconConstraints: const BoxConstraints(),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 16, color: AppColors.textMuted),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              )
            : null,
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
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.spacingLG,
          vertical: AppDimens.spacingMD,
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: AppDimens.animFast),
        margin: const EdgeInsets.only(right: AppDimens.spacingSM),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.spacingLG,
          vertical: AppDimens.spacingXS,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusFull),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: AppTypography.labelMedium.copyWith(
            color: isSelected ? AppColors.background : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

class _ProfileMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
        side: const BorderSide(color: AppColors.border),
      ),
      offset: const Offset(0, 8),
      onSelected: (value) async {
        if (value == 'logout') {
          await ApiClient.clearToken();
          if (context.mounted) {
            context.go('/');
          }
        } else if (value == 'switch_school') {
          if (context.mounted) {
            context.go('/schools');
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'switch_school',
          child: Row(
            children: [
              const Icon(Icons.swap_horiz_rounded,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: AppDimens.spacingSM),
              Text(
                'Switch School',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(Icons.logout_rounded,
                  size: 16, color: AppColors.error),
              const SizedBox(width: AppDimens.spacingSM),
              Text(
                'Sign Out',
                style:
                    AppTypography.bodyMedium.copyWith(color: AppColors.error),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(AppDimens.spacingSM),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusSM),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(
          Icons.person_outline_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
