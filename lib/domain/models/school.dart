class School {
  final int id;
  final String name;
  final String? logoUrl;
  final String? address;
  final String? city;

  const School({
    required this.id,
    required this.name,
    this.logoUrl,
    this.address,
    this.city,
  });

  factory School.fromJson(Map<String, dynamic> json) {
    return School(
      id: json['id'] as int,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'logo_url': logoUrl,
        'address': address,
        'city': city,
      };
}
