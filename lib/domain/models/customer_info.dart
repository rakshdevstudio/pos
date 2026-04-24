class CustomerInfo {
  final String phone;
  final String? name;
  final String? studentName;
  final String? studentClass;
  final String? address;
  final String? schoolId;
  final bool isWalkIn;

  const CustomerInfo({
    required this.phone,
    this.name,
    this.studentName,
    this.studentClass,
    this.address,
    this.schoolId,
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
      if (address != null) 'address': address,
      if (schoolId != null) 'school_id': schoolId,
      'is_walk_in': false,
    };
  }

  factory CustomerInfo.fromJson(Map<String, dynamic> json) {
    if (json['is_walk_in'] == true) {
      return CustomerInfo.walkIn();
    }
    return CustomerInfo(
      phone: json['phone'] as String? ?? '',
      name: json['name'] as String?,
      studentName: json['student_name'] as String?,
      studentClass: json['student_class'] as String?,
      address: json['address'] as String?,
      schoolId: json['school_id']?.toString(), // Handle int/string safely
    );
  }
}
