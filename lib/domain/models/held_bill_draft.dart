import 'cart_item.dart';
import 'customer_info.dart';

class HeldBillDraft {
  final String id;
  final String label;
  final String schoolId;
  final String? schoolName;
  final String? classId;
  final String? className;
  final String selectedGender;
  final List<CartItem> items;
  final double discountValue;
  final bool isPercentDiscount;
  final CustomerInfo? customer;
  final DateTime createdAt;
  final DateTime updatedAt;

  const HeldBillDraft({
    required this.id,
    required this.label,
    required this.schoolId,
    this.schoolName,
    this.classId,
    this.className,
    required this.selectedGender,
    this.items = const [],
    this.discountValue = 0,
    this.isPercentDiscount = false,
    this.customer,
    required this.createdAt,
    required this.updatedAt,
  });

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal =>
      items.fold<double>(0, (sum, item) => sum + item.lineTotal);

  double get discountAmount {
    if (discountValue <= 0) {
      return 0;
    }
    if (isPercentDiscount) {
      return subtotal * (discountValue / 100);
    }
    return discountValue;
  }

  double get total => (subtotal - discountAmount).clamp(0, double.infinity);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'school_id': schoolId,
        'school_name': schoolName,
        'class_id': classId,
        'class_name': className,
        'selected_gender': selectedGender,
        'items': items.map((item) => item.toJson()).toList(),
        'discount_value': discountValue,
        'is_percent_discount': isPercentDiscount,
        'customer': customer?.toJson(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory HeldBillDraft.fromJson(Map<String, dynamic> json) {
    final itemsJson = (json['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    final customerJson = json['customer'];

    return HeldBillDraft(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Draft Bill',
      schoolId: json['school_id']?.toString() ?? '',
      schoolName: _asNullableString(json['school_name']),
      classId: _asNullableString(json['class_id']),
      className: _asNullableString(json['class_name']),
      selectedGender: json['selected_gender']?.toString() ?? 'All',
      items: itemsJson.map(CartItem.fromJson).toList(),
      discountValue: _asDouble(json['discount_value']),
      isPercentDiscount: json['is_percent_discount'] == true,
      customer: customerJson is Map<String, dynamic>
          ? CustomerInfo.fromJson(customerJson)
          : null,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static double _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _asNullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
