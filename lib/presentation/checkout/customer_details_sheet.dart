import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/constants.dart';
import '../../data/remote/api_client.dart';
import '../../data/repositories/customer_repository.dart';
import '../../domain/models/customer_info.dart';
import '../shared/widgets/illume_button.dart';

class CustomerDetailsSheet extends StatefulWidget {
  const CustomerDetailsSheet({super.key});

  @override
  State<CustomerDetailsSheet> createState() => _CustomerDetailsSheetState();
}

class _CustomerDetailsSheetState extends State<CustomerDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController(); // Parent name
  final _studentNameController = TextEditingController();
  final _addressController = TextEditingController();
  
  String? _selectedClass;
  bool _isSearching = false;
  List<CustomerInfo> _suggestions = [];
  Timer? _debounce;
  late CustomerRepository _customerRepo;

  final List<String> _classes = [
    'Pre-KG', 'LKG', 'UKG',
    'Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5',
    'Class 6', 'Class 7', 'Class 8', 'Class 9', 'Class 10',
    'Class 11', 'Class 12',
  ];

  @override
  void initState() {
    super.initState();
    _customerRepo = CustomerRepository(ApiClient());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _phoneController.dispose();
    _nameController.dispose();
    _studentNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _onPhoneChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (value.length >= 3) {
        setState(() => _isSearching = true);
        final results = await _customerRepo.searchCustomers(value);
        if (mounted) {
          setState(() {
            _suggestions = results;
            _isSearching = false;
          });
        }
      } else {
        setState(() => _suggestions = []);
      }
    });
  }

  void _selectSuggestion(CustomerInfo customer) {
    setState(() {
      _phoneController.text = customer.phone;
      _nameController.text = customer.name ?? '';
      _studentNameController.text = customer.studentName ?? '';
      _selectedClass = customer.studentClass;
      _addressController.text = customer.address ?? '';
      _suggestions = [];
    });
    HapticFeedback.lightImpact();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final info = CustomerInfo(
        phone: _phoneController.text,
        name: _nameController.text.isEmpty ? null : _nameController.text,
        studentName: _studentNameController.text,
        studentClass: _selectedClass,
        // Using address field for now, will keep it in payload if needed
        isWalkIn: false,
      );
      _customerRepo.saveRecentCustomer(info);
      Navigator.pop(context, info);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimens.radiusXXL)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppDimens.spacingXXL,
        AppDimens.spacingXXL,
        AppDimens.spacingXXL,
        MediaQuery.of(context).viewInsets.bottom + AppDimens.spacingXXL,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'CUSTOMER DETAILS',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context, CustomerInfo.walkIn()),
                    icon: const Icon(Icons.directions_walk_rounded, size: 18),
                    label: const Text('WALK-IN'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                  ),
                ],
              ),
              const SizedBox(height: AppDimens.spacingXL),
              
              // Phone Field with suggestions stack
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: const Icon(Icons.phone_android_rounded),
                      suffixIcon: _isSearching 
                        ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                        : null,
                    ),
                    onChanged: _onPhoneChanged,
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  if (_suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(AppDimens.radiusMD),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: _suggestions.map((s) => ListTile(
                          title: Text(s.studentName ?? 'Unknown Student'),
                          subtitle: Text('${s.phone} · ${s.studentClass ?? "No Class"}'),
                          onTap: () => _selectSuggestion(s),
                          dense: true,
                        )).toList(),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppDimens.spacingLG),
              
              TextFormField(
                controller: _studentNameController,
                decoration: const InputDecoration(
                  labelText: 'Student Name',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppDimens.spacingLG),
              
              DropdownButtonFormField<String>(
                value: _selectedClass,
                decoration: const InputDecoration(
                  labelText: 'Class',
                  prefixIcon: Icon(Icons.school_outlined),
                ),
                items: _classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _selectedClass = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: AppDimens.spacingLG),
              
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address (Optional)',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                maxLines: 1,
              ),
              
              const SizedBox(height: AppDimens.spacingXXL),
              IllumeButton(
                label: 'CONTINUE TO PAYMENT',
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
