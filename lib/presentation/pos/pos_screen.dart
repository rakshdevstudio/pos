import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/constants.dart';
import '../../core/providers/providers.dart';
import '../../data/remote/api_client.dart';
import '../../domain/models/models.dart';
import '../../services/cart_service.dart';
import '../shared/widgets/sync_status_badge.dart';
import 'cart_panel.dart';
import 'product_card.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  static const String _genderAll = 'All';
  static const List<String> _genderFilters = [
    _genderAll,
    'Boys',
    'Girls',
    'Unisex',
  ];

  final _searchController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _barcodeFocus = FocusNode();
  final _mobileScrollController = ScrollController();

  String? _schoolId;
  String? _schoolName;
  List<SchoolClass> _classes = const [];
  SchoolClass? _selectedClass;
  String _selectedGender = _genderAll;
  String _searchQuery = '';
  String? _selectedCategory;
  List<Product> _products = const [];
  bool _isLoadingClasses = false;
  bool _isLoadingProducts = false;
  Object? _classesError;
  Object? _productsError;
  int _classRequestId = 0;
  int _productRequestId = 0;

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
    _loadSchoolContext();
  }

  Future<void> _loadSchoolContext() async {
    final prefs = await SharedPreferences.getInstance();
    final schoolId = _selectedSchoolIdFromPrefs(prefs);
    if (schoolId == null) {
      if (mounted) context.go('/schools');
      return;
    }

    final previousSchoolId = _schoolId;
    final schoolChanged =
        previousSchoolId != null && previousSchoolId != schoolId;
    if (schoolChanged) {
      ref.read(cartProvider.notifier).resetCart();
      ref.read(productRepoProvider).clearCache();
    }

    final schoolName = prefs.getString('selectedSchoolName') ?? 'Store';
    debugPrint('[POS] Selected school: $schoolName ($schoolId)');

    if (!mounted) return;
    _productRequestId++;
    setState(() {
      _schoolId = schoolId;
      _schoolName = schoolName;
      _classes = const [];
      _selectedClass = null;
      _selectedGender = _genderAll;
      _searchQuery = '';
      _selectedCategory = null;
      _products = const [];
      _classesError = null;
      _productsError = null;
      _isLoadingClasses = true;
      _isLoadingProducts = false;
    });
    _searchController.clear();
    _barcodeController.clear();

    await _loadClasses(schoolId);
    _focusBarcodeField();
  }

  Future<void> _loadClasses(String schoolId) async {
    final requestId = ++_classRequestId;
    _productRequestId++;
    setState(() {
      _isLoadingClasses = true;
      _classesError = null;
      _classes = const [];
      _selectedClass = null;
      _selectedGender = _genderAll;
      _products = const [];
      _productsError = null;
      _selectedCategory = null;
    });

    try {
      final classes = await ref.read(schoolRepoProvider).fetchClasses(schoolId);
      if (!mounted || requestId != _classRequestId) return;
      setState(() {
        _classes = classes;
        _isLoadingClasses = false;
        _classesError = null;
      });
    } catch (error) {
      if (!mounted || requestId != _classRequestId) return;
      setState(() {
        _classes = const [];
        _isLoadingClasses = false;
        _classesError = error;
      });
    }
  }

  String? _selectedSchoolIdFromPrefs(SharedPreferences prefs) {
    final selectedSchoolId = prefs.getString('selectedSchoolId');
    return selectedSchoolId?.isNotEmpty == true ? selectedSchoolId : null;
  }

  Future<void> _handleClassSelected(SchoolClass schoolClass) async {
    if (_selectedClass?.id == schoolClass.id) return;

    debugPrint(
      '[POS] Selected class: ${schoolClass.name.trim()} (${schoolClass.id})',
    );
    debugPrint('[POS] Selected gender: $_genderAll');

    setState(() {
      _selectedClass = schoolClass;
      _selectedGender = _genderAll;
      _selectedCategory = null;
      _products = const [];
      _productsError = null;
      _isLoadingProducts = true;
    });

    await _loadProducts();
  }

  Future<void> _handleGenderSelected(String gender) async {
    if (_selectedGender == gender) return;

    debugPrint('[POS] Selected gender: $gender');

    setState(() {
      _selectedGender = gender;
      _selectedCategory = null;
      _products = const [];
      _productsError = null;
      _isLoadingProducts = true;
    });

    await _loadProducts();
  }

  Future<void> _loadProducts() async {
    final schoolId = _schoolId;
    final selectedClass = _selectedClass;
    if (schoolId == null || selectedClass == null) {
      if (!mounted) return;
      setState(() {
        _products = const [];
        _isLoadingProducts = false;
        _productsError = null;
      });
      return;
    }

    final requestId = ++_productRequestId;
    setState(() {
      _isLoadingProducts = true;
      _productsError = null;
    });

    try {
      final products = await ref.read(productRepoProvider).fetchProducts(
            schoolId: schoolId,
            classId: selectedClass.id,
            gender: _selectedGender,
          );
      if (!mounted || requestId != _productRequestId) return;

      final categories = products
          .map((product) => product.category)
          .whereType<String>()
          .where((category) => category.trim().isNotEmpty)
          .toSet();
      setState(() {
        _products = products;
        _isLoadingProducts = false;
        _productsError = null;
        if (_selectedCategory != null &&
            !categories.contains(_selectedCategory)) {
          _selectedCategory = null;
        }
      });
      debugPrint('[POS] Filtered product count: ${products.length}');
    } catch (error) {
      if (!mounted || requestId != _productRequestId) return;
      setState(() {
        _products = const [];
        _isLoadingProducts = false;
        _productsError = error;
      });
    }
  }

  Future<void> _refreshProducts() async {
    if (_schoolId == null) return;
    if (_selectedClass == null) {
      await _loadClasses(_schoolId!);
      return;
    }
    await _loadProducts();
  }

  Future<void> _handleBarcodeSubmit(String rawCode) async {
    final sku = rawCode.trim();
    if (sku.isEmpty) return;
    if (_shouldDrop(sku)) {
      _barcodeController.clear();
      _focusBarcodeField();
      return;
    }

    final schoolId = _schoolId;
    if (schoolId == null) {
      _barcodeController.clear();
      _focusBarcodeField();
      return;
    }

    final match = await ref.read(productRepoProvider).lookupProductByBarcode(
          schoolId: schoolId,
          barcode: sku,
        );
    if (!mounted) return;

    if (match == null) {
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
      _barcodeController.clear();
      _focusBarcodeField();
      return;
    }

    final added =
        ref.read(cartProvider.notifier).addItem(match.product, match.variant);
    if (!added) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Out of stock')),
      );
      _barcodeController.clear();
      _focusBarcodeField();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 16,
            ),
            const SizedBox(width: AppDimens.spacingSM),
            Expanded(
              child: Text(
                '${match.product.name} (${match.variant.size}) added via barcode',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );

    _barcodeController.clear();
    _focusBarcodeField();
  }

  void _focusBarcodeField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _barcodeFocus.requestFocus();
      }
    });
  }

  List<String> get _categories => _products
      .map((product) => product.category)
      .whereType<String>()
      .where((category) => category.trim().isNotEmpty)
      .toSet()
      .toList();

  List<Product> get _visibleProducts {
    var filtered = _products;
    if (_searchQuery.isNotEmpty) {
      final normalizedQuery = _searchQuery.toLowerCase();
      filtered = filtered
          .where((product) => product.name.toLowerCase().contains(
                normalizedQuery,
              ))
          .toList();
    }
    if (_selectedCategory != null) {
      filtered = filtered
          .where((product) => product.category == _selectedCategory)
          .toList();
    }
    return filtered;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    _mobileScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: false,
      body: _schoolId == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : _buildPosLayout(),
      bottomNavigationBar: _isCompactLayout(context)
          ? _MobileCartSummaryBar(
              controller: _mobileScrollController,
            )
          : null,
    );
  }

  Widget _buildPosLayout() {
    if (_isCompactLayout(context)) {
      return _buildMobileLayout();
    }

    return _buildDesktopLayout();
  }

  bool _isCompactLayout(BuildContext context) =>
      MediaQuery.of(context).size.width < 900;

  Widget _buildDesktopLayout() {
    final productsPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(),
        const Divider(height: 1, color: AppColors.border),
        _buildSearchAndBarcode(),
        _buildBrowseControls(),
        _buildCategoryFilter(),
        Expanded(child: _buildProductGrid()),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(
          width: 320,
          child: CartPanel(),
        ),
        const VerticalDivider(
          width: 1,
          thickness: 1,
          color: AppColors.border,
        ),
        Expanded(child: productsPanel),
      ],
    );
  }

  Widget _buildMobileLayout() {
    const bottomSpacer = 96.0;

    return CustomScrollView(
      controller: _mobileScrollController,
      physics: const BouncingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: _buildTopBar()),
        const SliverToBoxAdapter(
          child: Divider(height: 1, color: AppColors.border),
        ),
        SliverToBoxAdapter(child: _buildSearchAndBarcode()),
        SliverToBoxAdapter(child: _buildBrowseControls()),
        SliverToBoxAdapter(child: _buildCategoryFilter()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppDimens.spacingXXL,
            AppDimens.spacingSM,
            AppDimens.spacingXXL,
            AppDimens.spacingMD,
          ),
          sliver: _buildProductSliverGrid(),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: bottomSpacer),
            child: CartPanel(compactMobile: true),
          ),
        ),
      ],
    );
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
          Expanded(
            flex: 3,
            child: _SearchField(
              controller: _searchController,
              enabled: _selectedClass != null,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          const SizedBox(width: AppDimens.spacingMD),
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

  Widget _buildBrowseControls() {
    final isCompactLayout = MediaQuery.of(context).size.width <= 600;
    final horizontalPadding =
        isCompactLayout ? AppDimens.spacingLG : AppDimens.spacingXXL;
    final verticalPadding =
        isCompactLayout ? AppDimens.spacingMD : AppDimens.spacingSM;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.spacingXXL,
        AppDimens.spacingSM,
        AppDimens.spacingXXL,
        AppDimens.spacingSM,
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusLG),
          border: Border.all(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: isCompactLayout ? 220 : double.infinity,
          ),
          child: SingleChildScrollView(
            physics: isCompactLayout
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSelectionSummary(),
                SizedBox(
                    height: isCompactLayout
                        ? AppDimens.spacingMD
                        : AppDimens.spacingLG),
                _buildClassSelector(),
                if (_selectedClass != null) ...[
                  SizedBox(
                      height: isCompactLayout
                          ? AppDimens.spacingMD
                          : AppDimens.spacingLG),
                  _buildGenderSelector(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionSummary() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ContextChip(
            label: 'School',
            value: _schoolName ?? 'Store',
            icon: Icons.school_rounded,
          ),
          const SizedBox(width: AppDimens.spacingSM),
          _ContextChip(
            label: 'Class',
            value: _selectedClass == null
                ? 'Select'
                : _formatLabel(_selectedClass!.name),
            icon: Icons.grid_view_rounded,
          ),
          const SizedBox(width: AppDimens.spacingSM),
          _ContextChip(
            label: 'Gender',
            value: _selectedGender,
            icon: Icons.wc_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildClassSelector() {
    if (_isLoadingClasses) {
      return const _SelectorStatusCard(
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accent,
          ),
        ),
        title: 'Loading classes',
        subtitle: 'Fetching available classes for this school',
      );
    }

    if (_classesError != null) {
      return _SelectorStatusCard(
        icon: const Icon(
          Icons.cloud_off_rounded,
          size: 18,
          color: AppColors.textMuted,
        ),
        title: 'Could not load classes',
        subtitle: 'Please retry to continue browsing products',
        action: TextButton(
          onPressed: () => _loadClasses(_schoolId!),
          child: const Text(
            'Retry',
            style: TextStyle(color: AppColors.accent),
          ),
        ),
      );
    }

    if (_classes.isEmpty) {
      return const _SelectorStatusCard(
        icon: Icon(
          Icons.grid_off_rounded,
          size: 18,
          color: AppColors.textMuted,
        ),
        title: 'No classes available',
        subtitle: 'This school does not have any active classes yet',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.grid_view_rounded,
          label: 'Select Class',
        ),
        const SizedBox(height: AppDimens.spacingSM),
        Wrap(
          spacing: AppDimens.spacingSM,
          runSpacing: AppDimens.spacingSM,
          children: _classes
              .map(
                (schoolClass) => _SelectionChip(
                  label: _formatLabel(schoolClass.name),
                  isSelected: _selectedClass?.id == schoolClass.id,
                  onTap: () => _handleClassSelected(schoolClass),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          icon: Icons.wc_rounded,
          label: 'Select Gender',
        ),
        const SizedBox(height: AppDimens.spacingSM),
        Wrap(
          spacing: AppDimens.spacingSM,
          runSpacing: AppDimens.spacingSM,
          children: _genderFilters
              .map(
                (gender) => _SelectionChip(
                  label: gender,
                  isSelected: _selectedGender == gender,
                  onTap: () => _handleGenderSelected(gender),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    if (_selectedClass == null || _categories.isEmpty) {
      return const SizedBox(height: AppDimens.spacingSM);
    }

    return SizedBox(
      height: 44,
      child: ListView(
        key: ValueKey(
          'categories_${_schoolId}_${_selectedClass?.id}_$_selectedGender',
        ),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDimens.spacingXXL),
        children: [
          _CategoryChip(
            label: 'All',
            isSelected: _selectedCategory == null,
            onTap: () {
              setState(() {
                _selectedCategory = null;
              });
            },
          ),
          ..._categories.map(
            (category) => _CategoryChip(
              label: category,
              isSelected: _selectedCategory == category,
              onTap: () {
                setState(() {
                  _selectedCategory = category;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_selectedClass == null) {
      return _buildEmptyState(
        icon: Icons.grid_view_rounded,
        message: 'Select class to view products',
      );
    }

    if (_isLoadingProducts) {
      return Center(
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
      );
    }

    if (_productsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: AppColors.textMuted,
              size: 40,
            ),
            const SizedBox(height: AppDimens.spacingMD),
            Text(
              'Could not load products',
              style:
                  AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppDimens.spacingMD),
            TextButton(
              onPressed: _refreshProducts,
              child: const Text(
                'Retry',
                style: TextStyle(color: AppColors.accent),
              ),
            ),
          ],
        ),
      );
    }

    if (_products.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off_rounded,
        message: 'No products found',
      );
    }

    final visibleProducts = _visibleProducts;
    if (visibleProducts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off_rounded,
        message: 'No products found',
      );
    }

    return GridView.builder(
      key: ValueKey(
        'products_${_schoolId}_${_selectedClass?.id}_$_selectedGender',
      ),
      padding: const EdgeInsets.all(AppDimens.spacingXXL),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: AppDimens.productCardWidth + 20,
        crossAxisSpacing: AppDimens.spacingMD,
        mainAxisSpacing: AppDimens.spacingMD,
        childAspectRatio: 0.72,
      ),
      itemCount: visibleProducts.length,
      itemBuilder: (context, index) {
        final product = visibleProducts[index];
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
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 16,
                      ),
                      const SizedBox(width: AppDimens.spacingSM),
                      Text(
                        '${product.name} added',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textPrimary),
                      ),
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
  }

  Widget _buildProductSliverGrid() {
    if (_selectedClass == null) {
      return SliverToBoxAdapter(
        child: _buildEmptyState(
          icon: Icons.grid_view_rounded,
          message: 'Select class to view products',
        ),
      );
    }

    if (_isLoadingProducts) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 56),
          child: Center(
            child: CircularProgressIndicator(
              color: AppColors.accent,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    if (_productsError != null) {
      return SliverToBoxAdapter(
        child: _buildEmptyErrorState(
          icon: Icons.wifi_off_rounded,
          message: 'Could not load products',
          actionLabel: 'Retry',
          onAction: _refreshProducts,
        ),
      );
    }

    if (_products.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyState(
          icon: Icons.search_off_rounded,
          message: 'No products found',
        ),
      );
    }

    final visibleProducts = _visibleProducts;
    if (visibleProducts.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildEmptyState(
          icon: Icons.search_off_rounded,
          message: 'No products found',
        ),
      );
    }

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: AppDimens.productCardWidth + 20,
        crossAxisSpacing: AppDimens.spacingMD,
        mainAxisSpacing: AppDimens.spacingMD,
        childAspectRatio: 0.72,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final product = visibleProducts[index];
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
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.success,
                          size: 16,
                        ),
                        const SizedBox(width: AppDimens.spacingSM),
                        Text(
                          '${product.name} added',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textPrimary),
                        ),
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
            key: ValueKey(product.id),
          );
        },
        childCount: visibleProducts.length,
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textDisabled, size: 40),
          const SizedBox(height: AppDimens.spacingMD),
          Text(
            message,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyErrorState({
    required IconData icon,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textDisabled, size: 40),
          const SizedBox(height: AppDimens.spacingMD),
          Text(
            message,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: AppDimens.spacingMD),
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel,
              style: const TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLabel(String value) {
    final words = value
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return value;
    return words
        .map(
          (word) => '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final void Function(String) onChanged;

  const _SearchField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          enabled: enabled,
          onChanged: onChanged,
          style: AppTypography.bodyLarge.copyWith(
            color: enabled ? AppColors.textPrimary : AppColors.textMuted,
          ),
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            hintText: enabled
                ? AppStrings.searchProducts
                : 'Select class to search products',
            hintStyle:
                AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
            prefixIcon: const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppDimens.spacingLG),
              child: Icon(
                Icons.search_rounded,
                size: 20,
                color: AppColors.textMuted,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(),
            suffixIcon: value.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
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
            disabledBorder: OutlineInputBorder(
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
      },
    );
  }
}

class _ContextChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ContextChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingMD,
        vertical: AppDimens.spacingSM,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppDimens.radiusFull),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: AppDimens.spacingXS),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textMuted,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectionChip({
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimens.spacingLG,
          vertical: AppDimens.spacingSM,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(AppDimens.radiusFull),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : const [],
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: isSelected ? AppColors.background : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.accent),
        const SizedBox(width: AppDimens.spacingXS),
        Text(
          label,
          style: AppTypography.labelLarge.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _SelectorStatusCard extends StatelessWidget {
  final Widget icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _SelectorStatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimens.spacingLG),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(AppDimens.radiusLG),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: AppDimens.spacingMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppDimens.spacingXS),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) action!,
        ],
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
              const Icon(
                Icons.swap_horiz_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppDimens.spacingSM),
              Text(
                'Switch School',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(
                Icons.logout_rounded,
                size: 16,
                color: AppColors.error,
              ),
              const SizedBox(width: AppDimens.spacingSM),
              Text(
                'Sign Out',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.error,
                ),
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

class _MobileCartSummaryBar extends ConsumerWidget {
  final ScrollController controller;

  const _MobileCartSummaryBar({required this.controller});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.spacingMD,
          0,
          AppDimens.spacingMD,
          AppDimens.spacingMD,
        ),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppDimens.radiusLG),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppDimens.radiusLG),
            onTap: () {
              if (!controller.hasClients) return;
              controller.animateTo(
                controller.position.maxScrollExtent,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimens.spacingLG,
                vertical: AppDimens.spacingMD,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppDimens.radiusLG),
                border: Border.all(color: AppColors.border),
                gradient: LinearGradient(
                  colors: [
                    AppColors.surface,
                    AppColors.surface.withValues(alpha: 0.96),
                  ],
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.shopping_cart_outlined,
                    size: 18,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: AppDimens.spacingSM),
                  Expanded(
                    child: Text(
                      'Cart (${cart.itemCount} items)',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppDimens.spacingSM),
                  Text(
                    '₹${cart.total.toStringAsFixed(0)}',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
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
