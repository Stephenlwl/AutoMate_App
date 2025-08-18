import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:automate_application/widgets/progress_bar.dart';
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

class _VehicleInformationPageState extends State<VehicleInformationPage> {
  final _vinController = TextEditingController();
  final _plateNumberController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _selectedBrand;
  String? _selectedModel;
  String? _selectedYear;

  List<String> _brands = [];
  List<String> _models = [];
  List<String> _years = [];

  static const orange = Color(0xFFFF6B00);

  @override
  void initState() {
    super.initState();
    fetchCarBrands();
  }

  Future<void> fetchCarBrands() async {
    final url = Uri.parse(
      "https://public.opendatasoft.com/api/records/1.0/search/?dataset=all-vehicles-model&q=&facet=make",
    );
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    final List<String> brands =
        (data['facet_groups'][0]['facets'] as List)
            .map<String>((e) => e['name'].toString())
            .toList();
    setState(() => _brands = brands);
  }

  Future<void> fetchCarModels(String brand) async {
    final url = Uri.parse(
      "https://public.opendatasoft.com/api/records/1.0/search/?dataset=all-vehicles-model&q=&facet=model&refine.make=$brand",
    );
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    final List<String> models =
        (data['facet_groups'][0]['facets'] as List)
            .map<String>((e) => e['name'].toString())
            .toList();
    setState(() {
      _models = models;
      _selectedModel = null;
      _selectedYear = null;
    });
  }

  Future<void> fetchCarYears(String brand, String model) async {
    final url = Uri.parse(
      "https://public.opendatasoft.com/api/records/1.0/search/?dataset=all-vehicles-model&q=&facet=year&refine.make=$brand&refine.model=$model",
    );
    final response = await http.get(url);
    final data = jsonDecode(response.body);
    final List<String> years =
        (data['facet_groups'][0]['facets'] as List)
            .map<String>((e) => e['name'].toString())
            .toList();
    setState(() {
      _years = years;
      _selectedYear = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("Step 2: Vehicle Information")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Center(
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/AutoMateLogoWithoutBackground.png',
                        height: 100,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Create Your AutoMate Account',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: orange,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text("Let's get you started in 3 steps"),
                      const SizedBox(height: 12),
                      StepProgressBar(currentStep: 2),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                DropdownButtonFormField<String>(
                  value: _selectedBrand,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Make',
                    prefixIcon: Icon(Icons.directions_car),
                    border: OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items:
                      _brands
                          .map(
                            (b) => DropdownMenuItem(
                              value: b,
                              child: Text(b, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedBrand = val;
                      _selectedModel = null;
                      _selectedYear = null;
                      fetchCarModels(val!);
                    });
                  },
                  validator:
                      (val) => val == null ? 'Please select a brand' : null,
                ),
                const SizedBox(height: 14),

                DropdownButtonFormField<String>(
                  value: _selectedModel,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Model',
                    prefixIcon: Icon(Icons.directions_car_filled),
                    border: OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items:
                      _models
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(m, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedModel = val;
                      _selectedYear = null;
                      fetchCarYears(_selectedBrand!, val!);
                    });
                  },
                  validator:
                      (val) => val == null ? 'Please select a model' : null,
                ),
                const SizedBox(height: 14),

                DropdownButtonFormField<String>(
                  value: _selectedYear,
                  decoration: const InputDecoration(
                    labelText: 'Year of Manufacture',
                    prefixIcon: Icon(Icons.calendar_today),
                    border: OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items:
                      _years
                          .map(
                            (y) => DropdownMenuItem(
                              value: y,
                              child: Text(y, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    setState(() => _selectedYear = val);
                  },
                  validator:
                      (val) => val == null ? 'Please select a year' : null,
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _vinController,
                  decoration: const InputDecoration(
                    labelText: 'VIN / Chassis Number',
                    hintText: 'e.g. 1HGCM82633A004352',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                    border: OutlineInputBorder(),
                    helperText:
                        'Enter full 17-digit Vehicle Identification Number (Chassis Number)',
                  ),
                  maxLength: 17,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'VIN is required';
                    } else if (value.length != 17) {
                      return 'VIN must be 17 characters';
                    } else if (!RegExp(
                      r'^[A-HJ-NPR-Z0-9]{17}$',
                    ).hasMatch(value.toUpperCase())) {
                      return 'VIN must be alphanumeric (no I, O, Q)';
                    }
                    return null;
                  },
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _plateNumberController,
                  decoration: const InputDecoration(
                    labelText: 'License Plate Number',
                    prefixIcon: Icon(Icons.confirmation_number),
                    border: OutlineInputBorder(),
                  ),
                  validator:
                      (v) =>
                          v == null || v.trim().isEmpty
                              ? 'Enter plate number'
                              : null,
                ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => VerificationPage(
                                  name: widget.name,
                                  password: widget.password,
                                  brand: _selectedBrand!,
                                  model: _selectedModel!,
                                  year: _selectedYear!,
                                  vin: _vinController.text.trim(),
                                  plateNumber:
                                      _plateNumberController.text.trim(),
                                ),
                          ),
                        );
                      }
                    },
                    child: const Text("Next"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
