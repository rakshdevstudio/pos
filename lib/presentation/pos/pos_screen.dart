import 'dart:async';
import 'dart:collection';

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
  final Queue<String> _pendingBarcodeScans = Queue<String>();

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
  bool _isProcessingBarcode = false;
  bool _isScannerFocused = false;

  @override
  void initState() {
    super.initState();
    _barcodeFocus.addListener(_handleBarcodeFocusChanged);
    _loadSchoolContext();
  }

  void _handleBarcodeFocusChanged() {
    if (!mounted || _isScannerFocused == _barcodeFocus.hasFocus) {
      return;
    }

    setState(() {
      _isScannerFocused = _barcodeFocus.hasFocus;
    });
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
    _pendingBarcodeScans.clear();
    _isProcessingBarcode = false;

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

  void _handleBarcodeSubmit(String rawCode) {
    final normalizedCode =
        ref.read(barcodeLookupServiceProvider).normalizeBarcode(rawCode);
    if (normalizedCode == null) {
      _focusBarcodeField();
      return;
    }

    _pendingBarcodeScans.add(normalizedCode);
    _barcodeController.clear();
    if (mounted) {
      setState(() {});
    }
    _focusBarcodeField();

    if (!_isProcessingBarcode) {
      unawaited(_drainBarcodeQueue());
    }
  }

  Future<void> _drainBarcodeQueue() async {
    if (_isProcessingBarcode) {
      return;
    }

    if (mounted) {
      setState(() {
        _isProcessingBarcode = true;
      });
    } else {
      _isProcessingBarcode = true;
    }

    try {
      while (_pendingBarcodeScans.isNotEmpty) {
        final code = _pendingBarcodeScans.removeFirst();
        if (mounted) {
          setState(() {});
        }
        await _processBarcodeScan(code);
        if (!mounted) {
          return;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingBarcode = false;
        });
      } else {
        _isProcessingBarcode = false;
      }
    }
  }

  Future<void> _processBarcodeScan(String barcode) async {
    final schoolId = _schoolId;
    if (schoolId == null) {
      _restoreBarcodeForRescan(barcode);
      return;
    }

    try {
      final match =
          await ref.read(barcodeLookupServiceProvider).lookupVariantByBarcode(
                barcode,
                schoolId: schoolId,
              );
      if (!mounted) return;

      if (match == null) {
        _showBarcodeSnackBar(
          message: AppStrings.barcodeNotFound,
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.error,
          backgroundColor: AppColors.errorDim,
        );
        _restoreBarcodeForRescan(barcode);
        return;
      }

      final addResult = ref
          .read(cartProvider.notifier)
          .addItemWithResult(match.product, match.variant);
      switch (addResult) {
        case CartAddResult.added:
          HapticFeedback.lightImpact();
          unawaited(SystemSound.play(SystemSoundType.click));
          _showBarcodeSnackBar(
            message: _buildBarcodeSuccessMessage(match),
            icon: Icons.check_circle_rounded,
            iconColor: AppColors.success,
            backgroundColor: AppColors.surfaceElevated,
          );
          _focusBarcodeField();
          return;
        case CartAddResult.outOfStock:
          _showBarcodeSnackBar(
            message: 'Out of stock',
            icon: Icons.remove_shopping_cart_rounded,
            iconColor: AppColors.error,
            backgroundColor: AppColors.errorDim,
          );
          _restoreBarcodeForRescan(barcode);
          return;
        case CartAddResult.stockLimitReached:
          _showBarcodeSnackBar(
            message: 'Only ${match.variant.stock} available',
            icon: Icons.inventory_2_rounded,
            iconColor: AppColors.warning,
            backgroundColor: AppColors.surfaceElevated,
          );
          _restoreBarcodeForRescan(barcode);
          return;
      }
    } catch (_) {
      if (!mounted) return;
      _showBarcodeSnackBar(
        message: 'Could not look up barcode',
        icon: Icons.cloud_off_rounded,
        iconColor: AppColors.error,
        backgroundColor: AppColors.errorDim,
      );
      _restoreBarcodeForRescan(barcode);
    }
  }

  void _showBarcodeSnackBar({
    required String message,
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: AppDimens.spacingSM),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatVariantSize(Variant variant) {
    final trimmed = variant.size.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.toLowerCase().startsWith('size ')) {
      return trimmed;
    }
    return 'Size $trimmed';
  }

  String _buildBarcodeSuccessMessage(ProductBarcodeMatch match) {
    final sizeLabel = _formatVariantSize(match.variant);
    if (sizeLabel.isEmpty) {
      return 'Added: ${match.product.name}';
    }
    return 'Added: ${match.product.name} $sizeLabel';
  }

  void _restoreBarcodeForRescan(String barcode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_shouldMaintainScannerFocus || _barcodeFocus.hasFocus) {
        _barcodeFocus.requestFocus();
      }
      if (_pendingBarcodeScans.isNotEmpty ||
          _barcodeController.text.isNotEmpty) {
        return;
      }

      _barcodeController.value = TextEditingValue(
        text: barcode,
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: barcode.length,
        ),
      );
    });
  }

  void _focusBarcodeField({bool selectAll = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (!_shouldMaintainScannerFocus && !_barcodeFocus.hasFocus) {
        return;
      }

      _barcodeFocus.requestFocus();
      final text = _barcodeController.text;
      if (selectAll && text.isNotEmpty) {
        _barcodeController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        );
      } else if (text.isEmpty) {
        _barcodeController.selection = const TextSelection.collapsed(offset: 0);
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
    _barcodeFocus.removeListener(_handleBarcodeFocusChanged);
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

  bool get _shouldMaintainScannerFocus {
    final mediaQuery = MediaQuery.maybeOf(context);
    return mediaQuery == null || mediaQuery.size.width >= 900;
  }

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
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomSpacer),
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
    final isCompactLayout = _isCompactLayout(context);
    final searchField = _SearchField(
      controller: _searchController,
      enabled: _selectedClass != null,
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
      },
    );
    final scannerField = _BarcodeScannerField(
      controller: _barcodeController,
      focusNode: _barcodeFocus,
      isFocused: _isScannerFocused,
      isProcessing: _isProcessingBarcode,
      statusText: _scannerStatusText,
      helperText: _scannerHelperText,
      statusColor: _scannerStatusColor,
      onSubmitted: _handleBarcodeSubmit,
      onClear: () {
        _barcodeController.clear();
        _focusBarcodeField();
      },
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimens.spacingXXL,
        AppDimens.spacingLG,
        AppDimens.spacingXXL,
        AppDimens.spacingSM,
      ),
      child: isCompactLayout
          ? Column(
              children: [
                searchField,
                const SizedBox(height: AppDimens.spacingMD),
                scannerField,
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: searchField),
                const SizedBox(width: AppDimens.spacingMD),
                SizedBox(
                  width: 380,
                  child: scannerField,
                ),
              ],
            ),
    );
  }

  String get _scannerHelperText {
    if (_isProcessingBarcode) {
      final queuedCount = _pendingBarcodeScans.length;
      return queuedCount > 0 ? '$queuedCount queued' : 'Processing scan';
    }
    if (_pendingBarcodeScans.isNotEmpty) {
      return '${_pendingBarcodeScans.length} queued';
    }
    if (!_shouldMaintainScannerFocus) {
      return 'Tap the field to scan or type';
    }
    return 'Keyboard and scanner supported';
  }

  String get _scannerStatusText {
    if (_isScannerFocused) {
      return 'Scanner Ready';
    }
    if (!_shouldMaintainScannerFocus) {
      return 'Scanner Available';
    }
    return 'Tap to refocus scanner';
  }

  Color get _scannerStatusColor {
    return _isScannerFocused ? AppColors.success : AppColors.textMuted;
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

class _BarcodeScannerField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFocused;
  final bool isProcessing;
  final String statusText;
  final String helperText;
  final Color statusColor;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _BarcodeScannerField({
    required this.controller,
    required this.focusNode,
    required this.isFocused,
    required this.isProcessing,
    required this.statusText,
    required this.helperText,
    required this.statusColor,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: AppDimens.animMedium),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimens.radiusLG),
            boxShadow: [
              if (isFocused)
                const BoxShadow(
                  color: AppColors.accentGlow,
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                focusNode: focusNode,
                autocorrect: false,
                enableSuggestions: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
                cursorColor: AppColors.accent,
                textInputAction: TextInputAction.done,
                onSubmitted: onSubmitted,
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
                      color: AppColors.accent,
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
                          onPressed: onClear,
                        )
                      : isProcessing
                          ? const Padding(
                              padding: EdgeInsets.all(AppDimens.spacingMD),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent,
                                ),
                              ),
                            )
                          : null,
                  filled: true,
                  fillColor: isFocused
                      ? AppColors.surfaceHighlight
                      : AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                    borderSide: BorderSide(
                      color: isFocused ? AppColors.accentDim : AppColors.border,
                    ),
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
              const SizedBox(height: AppDimens.spacingSM),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                      boxShadow: [
                        if (isFocused)
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppDimens.spacingSM),
                  Text(
                    statusText,
                    style: AppTypography.labelMedium.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppDimens.spacingSM),
                  Expanded(
                    child: Text(
                      helperText,
                      textAlign: TextAlign.right,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
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
