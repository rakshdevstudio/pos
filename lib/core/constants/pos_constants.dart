class PosConstants {
  PosConstants._();

  static const int lowStockThreshold = 3;
  static const Duration duplicateScanWindow = Duration(milliseconds: 650);
  static const Duration barcodeToastDuration = Duration(milliseconds: 1200);
  static const Duration scannerRefocusDelay = Duration(milliseconds: 80);
}
