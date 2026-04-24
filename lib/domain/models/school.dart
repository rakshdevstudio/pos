class School {
  final String id;
  final String name;
  final String? logoUrl;
  final String? address;
  final String? city;
  final String? branchId;

  const School({
    required this.id,
    required this.name,
    this.logoUrl,
    this.address,
    this.city,
    this.branchId,
  });

  factory School.fromJson(Map<String, dynamic> json) {
    return School(
      id: _asString(json['id']),
      name: _asString(json['name']),
      logoUrl: _asNullableString(json['logo_url']),
      address: _asNullableString(json['address']),
      city: _asNullableString(json['city']),
      branchId: _asNullableString(json['branch_id'] ?? json['branchId']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'logo_url': logoUrl,
        'address': address,
        'city': city,
        'branch_id': branchId,
      };

  static String _asString(dynamic value) => value?.toString() ?? '';

  static String? _asNullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
