class CustomerInfo {
  final String phone;
  final String? name;
  final String? studentName;
  final String? studentClass;
  final String? grade;
  final String? className;
  final String? alternatePhone;
  final String? address;
  final String? city;
  final String? pincode;
  final String? schoolId;
  final String? branchId;
  final bool isWalkIn;

  const CustomerInfo({
    required this.phone,
    this.name,
    this.studentName,
    this.studentClass,
    this.grade,
    this.className,
    this.alternatePhone,
    this.address,
    this.city,
    this.pincode,
    this.schoolId,
    this.branchId,
    this.isWalkIn = false,
  });

  factory CustomerInfo.walkIn() {
    return const CustomerInfo(
      phone: 'Walk-In',
      isWalkIn: true,
    );
  }

  Map<String, dynamic> toJson() {
    if (isWalkIn) return {'is_walk_in': true};
    return {
      'phone': phone,
      if (name != null) 'name': name,
      if (studentName != null) 'student_name': studentName,
      if (studentClass != null) 'student_class': studentClass,
      if (grade != null) 'grade': grade,
      if (className != null) 'class_name': className,
      if (alternatePhone != null) 'alternate_phone': alternatePhone,
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (pincode != null) 'pincode': pincode,
      if (schoolId != null) 'school_id': schoolId,
      if (branchId != null) 'branch_id': branchId,
      'is_walk_in': false,
    };
  }

  factory CustomerInfo.fromJson(Map<String, dynamic> json) {
    if (json['is_walk_in'] == true) {
      return CustomerInfo.walkIn();
    }
    final student = json['student'];
    final studentMap = student is Map
        ? Map<String, dynamic>.from(student)
        : const <String, dynamic>{};

    return CustomerInfo(
      phone: _asNullableString(json['phone'] ?? json['customer_phone']) ?? '',
      name: _asNullableString(json['name'] ?? json['customer_name']),
      studentName:
          _asNullableString(json['student_name'] ?? studentMap['name']),
      studentClass: _asNullableString(
        json['student_class'] ??
            json['class_name'] ??
            studentMap['class_name'] ??
            studentMap['class'],
      ),
      grade: _asNullableString(json['grade'] ?? studentMap['grade']),
      className: _asNullableString(
        json['class_name'] ??
            json['student_class'] ??
            studentMap['class_name'] ??
            studentMap['class'],
      ),
      alternatePhone:
          _asNullableString(json['alternate_phone'] ?? json['alt_phone']),
      address: _asNullableString(json['address']),
      city: _asNullableString(json['city']),
      pincode: json['pincode']?.toString(),
      schoolId: json['school_id']?.toString(), // Handle int/string safely
      branchId: json['branch_id']?.toString(),
    );
  }

  static String? _asNullableString(dynamic value) {
    final str = value?.toString().trim() ?? '';
    return str.isEmpty ? null : str;
  }
}
