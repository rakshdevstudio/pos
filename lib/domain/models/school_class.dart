class SchoolClass {
  final String id;
  final String schoolId;
  final String name;
  final String? code;
  final String? slug;
  final int? sortOrder;
  final String? status;

  const SchoolClass({
    required this.id,
    required this.schoolId,
    required this.name,
    this.code,
    this.slug,
    this.sortOrder,
    this.status,
  });

  factory SchoolClass.fromJson(Map<String, dynamic> json) {
    return SchoolClass(
      id: _asString(json['id']),
      schoolId: _asString(json['school_id'] ?? json['schoolId']),
      name: _asString(json['name']),
      code: _asNullableString(json['code']),
      slug: _asNullableString(json['slug']),
      sortOrder: _asNullableInt(json['sort_order'] ?? json['sortOrder']),
      status: _asNullableString(json['status']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'school_id': schoolId,
        'name': name,
        'code': code,
        'slug': slug,
        'sort_order': sortOrder,
        'status': status,
      };

  static String _asString(dynamic value) => value?.toString() ?? '';

  static String? _asNullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _asNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
