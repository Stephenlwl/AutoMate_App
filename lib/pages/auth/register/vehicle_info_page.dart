import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:automate_application/widgets/progress_bar.dart';
import 'package:automate_application/widgets/custom_snackbar.dart';
import 'verification_upload_page.dart';

class VehicleInformationPage extends StatefulWidget {
  final String name, password;
  const VehicleInformationPage({
    super.key,
    required this.name,
    required this.password,
  });

  @override
  State<VehicleInformationPage> createState() => _VehicleInformationPageState();
}

class _VehicleInformationPageState extends State<VehicleInformationPage>
    with SingleTickerProviderStateMixin {
  final _vinController = TextEditingController();
  final _plateNumberController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _selectedBrand;
  String? _selectedModel;
  String? _selectedYear;
  String? _selectedSizeClass;
  String? _selectedFuelType;
  String? _displacement;

  List<String> _brands = [];
  List<String> _models = [];
  List<String> _years = [];
  List<String> _sizeClasses = [];

  bool _isLoadingBrands = true;
  bool _isLoadingModels = false;
  bool _isLoadingYears = false;
  bool _isLoadingSizeClasses = false;
  bool _isSubmitting = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF344370);
  static const Color backgroundColor = Color(0xFFFAFAFA);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color errorColor = Color(0xFFE53E3E);

  @override
  void initState() {
    super.initState();
    _fetchCarBrands();
    _setupAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _vinController.dispose();
    _plateNumberController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  /// Fetch brands
  Future<void> _fetchCarBrands() async {
    setState(() => _isLoadingBrands = true);
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('vehicles_list')
              .orderBy('createdAt', descending: true)
              .get();

      final brands =
          snapshot.docs.map((doc) => doc['make'].toString()).toSet().toList();

      brands.sort();
      setState(() => _brands = brands);
    } catch (e) {
      CustomSnackBar.show(
        context: context,
        message: 'Failed to load vehicle brands: $e',
        type: SnackBarType.error,
      );
    } finally {
      setState(() => _isLoadingBrands = false);
    }
  }

  /// Fetch models
  Future<void> _fetchCarModels(String brand) async {
    setState(() => _isLoadingModels = true);
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('vehicles_list')
              .where('make', isEqualTo: brand)
              .orderBy('createdAt', descending: true)
              .get();

      final models = <String>{};

      for (var doc in snapshot.docs) {
        final modelArray = List.from(doc['model'] ?? []);
        for (var m in modelArray) {
          final fitments =
              (m['fitments'] is List) ? List.from(m['fitments']) : [];
          final hasApproved = fitments.any((f) => f['status'] == 'approved');
          if (hasApproved) {
            models.add(m['name']);
          }
        }
      }

      setState(() {
        _models = models.toList()..sort();
        _selectedModel = null;
        _selectedYear = null;
        _years.clear();
      });
    } catch (e) {
      CustomSnackBar.show(
        context: context,
        message: 'Failed to load models for $brand',
        type: SnackBarType.error,
      );
    } finally {
      setState(() => _isLoadingModels = false);
    }
  }

  /// Fetch years
  Future<void> _fetchCarYears(String brand, String modelName) async {
    setState(() => _isLoadingYears = true);
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('vehicles_list')
              .where('make', isEqualTo: brand)
              .orderBy('createdAt', descending: true)
              .get();

      final years = <String>{};

      for (var doc in snapshot.docs) {
        final modelArray = List.from(doc['model'] ?? []);
        for (var m in modelArray) {
          if (m['name'] == modelName) {
            final fitments = List.from(m['fitments'] ?? []);
            for (var f in fitments) {
              if (f['status'] == 'approved' && f['year'] != null) {
                years.add(f['year'].toString());
              }
            }
          }
        }
      }

      setState(() {
        _years =
            years.toList()
              ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
        _selectedYear = null;
      });
    } catch (e) {
      CustomSnackBar.show(
        context: context,
        message: 'Failed to load years for $brand $modelName',
        type: SnackBarType.error,
      );
    } finally {
      setState(() => _isLoadingYears = false);
    }
  }

  Future<void> _fetchCarSizeClasses(
    String brand,
    String modelName,
    String year,
  ) async {
    setState(() => _isLoadingSizeClasses = true);
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('vehicles_list')
              .where('make', isEqualTo: brand)
              .orderBy('createdAt', descending: true)
              .get();

      final sizeClasses = <String>{};

      for (var doc in snapshot.docs) {
        final modelArray = List.from(doc['model'] ?? []);
        for (var m in modelArray) {
          if (m['name'] == modelName) {
            final fitments = List.from(m['fitments'] ?? []);
            for (var f in fitments) {
              if (f['status'] == 'approved' && f['year'] == year && f['sizeClass'] != null) {
                sizeClasses.add(f['sizeClass'].toString());
              }
            }
          }
        }
      }

      setState(() {
        _sizeClasses = sizeClasses.toList()..sort();

        if (_sizeClasses.length == 1) {
          _selectedSizeClass = _sizeClasses.first;
        } else if (_selectedSizeClass != null && !_sizeClasses.contains(_selectedSizeClass)) {
          // Reset if previous selection is no longer valid
          _selectedSizeClass = null;
        }
      });
    } catch (e) {
      CustomSnackBar.show(
        context: context,
        message: 'Failed to load size classes for $brand $modelName',
        type: SnackBarType.error,
      );
    } finally {
      setState(() => _isLoadingSizeClasses = false);
    }
  }

  Future<void> _detectDisplacementAndFuelType(String make, String model, String? year) async {
    try {
      setState(() => _isLoadingSizeClasses = true);

      final snapshot = await FirebaseFirestore.instance
          .collection('vehicles_list')
          .where('make', isEqualTo: make)
          .get();

      final sizeClasses = <String>{};
      String? foundDisplacement;
      String? foundFuelType;

      for (var doc in snapshot.docs) {
        final modelArray = List.from(doc['model'] ?? []);
        for (var m in modelArray) {
          if (m['name'] == model) {
            final fitments = List.from(m['fitments'] ?? []);
            for (var f in fitments) {
              if (f['status'] == 'approved' && f['year'] == year) {
                if (f['sizeClass'] != null) {
                  sizeClasses.add(f['sizeClass'].toString());
                }
                if (foundDisplacement == null && f['displacement'] != null) {
                  var displacement = f['displacement'].toString();
                  // Remove square brackets if displacement is an array string
                  if (displacement.startsWith('[') && displacement.endsWith(']')) {
                    displacement = displacement.substring(1, displacement.length - 1);
                  }
                  foundDisplacement = displacement;
                }
                if (foundFuelType == null && f['fuel'] != null) {
                  foundFuelType = f['fuel'].toString();
                }
              }
            }
          }
        }
      }

      setState(() {
        _sizeClasses = sizeClasses.toList()..sort();
        _displacement = foundDisplacement;
        _selectedFuelType = foundFuelType;
        if (_sizeClasses.length == 1) {
          _selectedSizeClass = _sizeClasses.first;
        }
        _isLoadingSizeClasses = false;
      });
    } catch (e) {
      setState(() => _isLoadingSizeClasses = false);
      _showErrorSnackBar('Failed to load size classes');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  String? _validateVin(String? value) {
    if (value == null || value.trim().isEmpty) return 'VIN is required';
    final clean = value.trim().toUpperCase();
    if (clean.length != 17) return 'VIN must be exactly 17 characters';
    if (!RegExp(r'^[A-HJ-NPR-Z0-9]{17}').hasMatch(clean)) {
      return 'VIN contains invalid characters (no I, O, Q)';
    }
    return null;
  }

  String? _validatePlateNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'License plate number is required';
    }
    if (value.trim().length < 3) {
      return 'License plate must be at least 3 characters';
    }
    return null;
  }

  void _handleNext() async {
    if (!_formKey.currentState!.validate()) {
      CustomSnackBar.show(
        context: context,
        message: 'Please complete all required fields',
        type: SnackBarType.error,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await Future.delayed(const Duration(milliseconds: 800));

      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder:
              (context, animation, secondaryAnimation) => VerificationPage(
                name: widget.name,
                password: widget.password,
                brand: _selectedBrand!,
                model: _selectedModel!,
                year: _selectedYear!,
                fuelType: _selectedFuelType,
                displacement: _displacement!,
                sizeClass: _selectedSizeClass!,
                vin: _vinController.text.trim().toUpperCase(),
                plateNumber: _plateNumberController.text.trim().toUpperCase(),
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeInOut),
              ),
              child: child,
            );
          },
        ),
      );
    } catch (e) {
      CustomSnackBar.show(
        context: context,
        message: 'Something went wrong. Please try again.',
        type: SnackBarType.error,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.height < 700;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: screenSize.width * 0.06,
                vertical: isSmallScreen ? 8 : 16,
              ),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(isSmallScreen),
                      SizedBox(height: isSmallScreen ? 20 : 32),
                      _buildFormCard(isSmallScreen),
                      SizedBox(height: isSmallScreen ? 20 : 32),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: surfaceColor,
      elevation: 0,
      scrolledUnderElevation: 1,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new,
            color: secondaryColor,
            size: 16,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        "Step 2 of 3",
        style: TextStyle(
          color: secondaryColor,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildHeader(bool isSmallScreen) {
    return Column(
      children: [
        // Logo
        Container(
          width: isSmallScreen ? 110 : 130,
          height: isSmallScreen ? 110 : 130,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Image.asset(
              'assets/AutoMateLogoWithoutBackground.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.directions_car_rounded,
                  size: isSmallScreen ? 24 : 32,
                  color: primaryColor,
                );
              },
            ),
          ),
        ),

        SizedBox(height: isSmallScreen ? 3 : 6),

        Text(
          'Vehicle Information',
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 24,
            fontWeight: FontWeight.w700,
            color: secondaryColor,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),

        SizedBox(height: isSmallScreen ? 4 : 8),

        Text(
          'Provide details about your car',
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),

        SizedBox(height: isSmallScreen ? 16 : 20),
        StepProgressBar(currentStep: 2),
      ],
    );
  }

  Widget _buildFormCard(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 20 : 28),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildDropdownField(
              label: 'Vehicle Make',
              value: _selectedBrand,
              items: _brands,
              isLoading: _isLoadingBrands,
              icon: Icons.directions_car_rounded,
              onChanged: (val) {
                setState(() {
                  _selectedBrand = val;
                  _selectedModel = null;
                  _selectedYear = null;
                  _selectedSizeClass = null;
                  _models.clear();
                  _years.clear();
                  _sizeClasses.clear();
                });
                if (val != null) _fetchCarModels(val);
              },
              validator: (val) => val == null ? 'Select vehicle make' : null,
            ),

            SizedBox(height: isSmallScreen ? 16 : 20),

            _buildDropdownField(
              label: 'Vehicle Model',
              value: _selectedModel,
              items: _models,
              isLoading: _isLoadingModels,
              icon: Icons.directions_car_outlined,
              onChanged: (val) {
                setState(() {
                  _selectedModel = val;
                  _selectedYear = null;
                  _years.clear();
                });
                if (val != null) _fetchCarYears(_selectedBrand!, val);
              },
              validator: (val) => val == null ? 'Select vehicle model' : null,
              enabled: _selectedBrand != null,
            ),

            SizedBox(height: isSmallScreen ? 16 : 20),

            _buildDropdownField(
              label: 'Year of Manufacture',
              value: _selectedYear,
              items: _years,
              isLoading: _isLoadingYears,
              icon: Icons.calendar_today_rounded,
              onChanged: (val) {
                setState(() {
                  _selectedYear = val;
                  _sizeClasses.clear();
                });
                if (val != null)
                  _fetchCarSizeClasses(_selectedBrand!, _selectedModel!, val);
                  _detectDisplacementAndFuelType(_selectedBrand!, _selectedModel!, val);
              },
              validator: (val) => val == null ? 'Select year' : null,
              enabled: _selectedModel != null,
            ),

            SizedBox(height: isSmallScreen ? 16 : 20),

            _buildDropdownField(
              label: 'Vehicle Size Class',
              value: _selectedSizeClass,
              items: _sizeClasses,
              isLoading: _isLoadingSizeClasses,
              icon: Icons.directions_car_outlined,
              onChanged: (val) => setState(() => _selectedSizeClass = val),
              validator: (val) => val == null ? 'Select size class' : null,
              enabled: _selectedYear != null,
            ),

            SizedBox(height: isSmallScreen ? 16 : 20),

            _buildInputField(
              controller: _vinController,
              label: 'VIN / Chassis Number',
              hint: '17-digit VIN (e.g. 1HGCM82633A004352)',
              icon: Icons.confirmation_number_outlined,
              maxLength: 17,
              validator: _validateVin,
              textCapitalization: TextCapitalization.characters,
            ),

            SizedBox(height: isSmallScreen ? 16 : 20),

            _buildInputField(
              controller: _plateNumberController,
              label: 'License Plate Number',
              hint: 'e.g. ABC1234',
              icon: Icons.local_parking_rounded,
              validator: _validatePlateNumber,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleNext(),
            ),

            SizedBox(height: isSmallScreen ? 24 : 32),
            _buildNextButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required bool isLoading,
    required IconData icon,
    required void Function(String?) onChanged,
    required String? Function(String?) validator,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: secondaryColor,
            ),
          ),
        ),
        DropdownButtonFormField<String>(
          value: value != null && items.contains(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(
            hintText:
                isLoading
                    ? 'Loading...'
                    : enabled
                    ? 'Select $label'
                    : 'Please select previous option first',
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            prefixIcon: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: primaryColor, size: 18),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: primaryColor, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: errorColor, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: errorColor, width: 2),
            ),
            filled: true,
            fillColor: enabled ? Colors.grey.shade50 : Colors.grey.shade100,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            suffixIcon:
                isLoading
                    ? Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                    )
                    : null,
          ),
          items:
              enabled && !isLoading
                  ? items
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(
                            item,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: secondaryColor,
                            ),
                          ),
                        ),
                      )
                      .toList()
                  : [],
          onChanged: enabled && !isLoading ? onChanged : null,
          validator: validator,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    int? maxLength,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction textInputAction = TextInputAction.next,
    void Function(String)? onFieldSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: secondaryColor,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          validator: validator,
          maxLength: maxLength,
          onFieldSubmitted: onFieldSubmitted,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: secondaryColor,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            prefixIcon: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: primaryColor, size: 18),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: primaryColor, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: errorColor, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: errorColor, width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            counterText: maxLength != null ? null : '',
          ),
        ),
      ],
    );
  }

  Widget _buildNextButton() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors:
              _isSubmitting
                  ? [Colors.grey.shade400, Colors.grey.shade500]
                  : [primaryColor, primaryColor.withOpacity(0.8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color:
                _isSubmitting
                    ? Colors.transparent
                    : primaryColor.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _handleNext,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child:
            _isSubmitting
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                : const Text(
                  'Continue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
      ),
    );
  }
}
