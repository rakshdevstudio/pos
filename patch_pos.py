import re

with open('lib/presentation/pos/pos_screen.dart', 'r') as f:
    content = f.read()

# Add variables and scannerFocusNode
content = re.sub(
    r'  List<HeldBillDraft> _draftBills = const \[\];\n',
    r'  List<HeldBillDraft> _draftBills = const [];\n\n  late final FocusNode scannerFocusNode;\n  final StringBuffer _globalScannerBuffer = StringBuffer();\n',
    content
)

# Add initState stuff and handleScannerInput
init_state_new = """  @override
  void initState() {
    super.initState();
    scannerFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('POS SCREEN FOCUS ACTIVE');
      scannerFocusNode.requestFocus();
    });
    
    _barcodeFocus.addListener(_handleBarcodeFocusChanged);
    _searchFocus.addListener(_handleSearchFocusChanged);
    unawaited(_loadDraftBills());
    _loadSchoolContext();
  }

  void _handleScannerInput(RawKeyEvent event) {
    if (_searchFocus.hasFocus) return;

    if (event is RawKeyDownEvent) {
      debugPrint('RAW KEY RECEIVED: character: ${event.character}');

      if (event.logicalKey == LogicalKeyboardKey.enter) {
        final barcode = _globalScannerBuffer.toString().trim();
        debugPrint('SCANNER ENTER RECEIVED:');

        if (barcode.isNotEmpty) {
          debugPrint('SUBMITTING BARCODE: $barcode');
          _handleBarcodeSubmit(barcode);
        }

        _globalScannerBuffer.clear();
        scannerFocusNode.requestFocus();
      } else if (event.character != null && event.character!.trim().isNotEmpty) {
        _globalScannerBuffer.write(event.character);
      }
    }
  }
"""

content = re.sub(
    r'  @override\n  void initState\(\) \{\n    super.initState\(\);\n    _barcodeFocus.addListener\(_handleBarcodeFocusChanged\);\n    _searchFocus.addListener\(_handleSearchFocusChanged\);\n    unawaited\(_loadDraftBills\(\)\);\n    _loadSchoolContext\(\);\n  \}',
    init_state_new,
    content
)

# Replace dispose
content = re.sub(
    r'  void dispose\(\) \{\n    _searchController.dispose\(\);',
    r'  void dispose() {\n    scannerFocusNode.dispose();\n    _searchController.dispose();',
    content
)

# Wrap Scaffold in RawKeyboardListener
content = re.sub(
    r'      child: Focus\(\n        child: Scaffold\(',
    r'      child: RawKeyboardListener(\n        focusNode: scannerFocusNode,\n        autofocus: true,\n        onKey: _handleScannerInput,\n        child: Scaffold(',
    content
)

# Add focus requests in a few places
# 1. after product added (_processBarcodeScan ends at line 720 or so)
content = re.sub(
    r'        _isProcessingBarcode = false;\n      }\n    }\n  }',
    r'        _isProcessingBarcode = false;\n      }\n      if (mounted) FocusScope.of(context).requestFocus(scannerFocusNode);\n    }\n  }',
    content
)

# 2. after dialog closed in _startCheckout
content = re.sub(
    r'        if \(dialogResult == true && mounted\) \{\n          unawaited\(_startCheckout\(\)\);\n        \}',
    r'        if (mounted) FocusScope.of(context).requestFocus(scannerFocusNode);\n        if (dialogResult == true && mounted) {\n          unawaited(_startCheckout());\n        }',
    content
)

with open('lib/presentation/pos/pos_screen.dart', 'w') as f:
    f.write(content)
