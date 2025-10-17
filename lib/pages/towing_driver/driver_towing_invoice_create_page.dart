import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../widgets/custom_snackbar.dart';

class AppColors {
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color primaryLight = Color(0xFFF3A169);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color secondaryColor = Color(0xFF1E293B);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;
  static const Color surfaceColor = Color(0xFFF1F5F9);
  static const Color accentColor = Color(0xFF06B6D4);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color borderColor = Color(0xFFE2E8F0);
}

class TowingInvoiceCreatePage extends StatefulWidget {
  final String towingRequestId;
  final Map<String, dynamic> userData;
  final String customerName;

  const TowingInvoiceCreatePage({
    Key? key,
    required this.towingRequestId,
    required this.userData,
    required this.customerName,
  }) : super(key: key);

  @override
  _TowingInvoiceCreatePageState createState() => _TowingInvoiceCreatePageState();
}

class _TowingInvoiceCreatePageState extends State<TowingInvoiceCreatePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _towingRequest;
  Map<String, dynamic>? _serviceCenterInfo;
  bool _isLoading = true;
  bool _isGenerating = false;

  List<Map<String, dynamic>> _additionalServices = [];
  Map<String, dynamic> _newAdditionalService = {
    'name': '',
    'unitPrice': 0.0,
    'quantity': 1,
    'totalPrice': 0.0
  };

  bool _enableTax = true;
  double _taxRate = 0.08;

  @override
  void initState() {
    super.initState();
    _loadTowingRequestData();
  }

  Future<void> _loadTowingRequestData() async {
    try {
      final requestDoc = await _firestore
          .collection('towing_requests')
          .doc(widget.towingRequestId)
          .get();

      if (requestDoc.exists) {
        setState(() {
          _towingRequest = {'id': requestDoc.id, ...requestDoc.data()!};
        });

        await _loadServiceCenterInfo();

        if (_towingRequest?['invoiceId'] != null) {
          CustomSnackBar.show(
            context: context,
            message: 'An invoice already exists for this towing request',
            type: SnackBarType.error,
          );
          Navigator.pop(context);
          return;
        }

        if (_towingRequest?['status'] != 'ongoing') {
          CustomSnackBar.show(
            context: context,
            message: 'Cannot generate invoice. Towing request must be in "Ongoing" status',
            type: SnackBarType.error,
          );
          Navigator.pop(context);
          return;
        }

      } else {
        CustomSnackBar.show(
          context: context,
          message: 'Towing request not found',
          type: SnackBarType.error,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error loading towing request: $e');
      CustomSnackBar.show(
        context: context,
        message: 'Failed to load request data',
        type: SnackBarType.error,
      );
      Navigator.pop(context);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadServiceCenterInfo() async {
    try {
      if (_towingRequest?['serviceCenterId'] != null) {
        final scDoc = await _firestore
            .collection('service_centers')
            .doc(_towingRequest!['serviceCenterId'])
            .get();

        if (scDoc.exists) {
          setState(() {
            _serviceCenterInfo = scDoc.data();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading service center: $e');
    }
  }

  void _addAdditionalService() {
    if (_newAdditionalService['name']?.isEmpty ?? true) {
      CustomSnackBar.show(
        context: context,
        message: 'Please enter service name',
        type: SnackBarType.error,
      );
      return;
    }

    final name = _newAdditionalService['name']!;
    final quantity = _newAdditionalService['quantity'] ?? 1;
    final unitPrice = _newAdditionalService['unitPrice'] ?? 0.0;
    final totalPrice = quantity * unitPrice;

    final additionalService = {
      'name': name,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalPrice': totalPrice
    };

    setState(() {
      _additionalServices.add(additionalService);
    });

    _newAdditionalService = {
      'name': '',
      'unitPrice': 0.0,
      'quantity': 1,
      'totalPrice': 0.0
    };
  }

  void _removeAdditionalService(int index) {
    setState(() {
      _additionalServices.removeAt(index);
    });
  }

  void _updateAdditionalServiceQuantity(int index, int quantity) {
    setState(() {
      _additionalServices[index]['quantity'] = quantity;
      _additionalServices[index]['totalPrice'] = quantity * (_additionalServices[index]['unitPrice'] ?? 0.0);
    });
  }

  void _updateAdditionalServicePrice(int index, double price) {
    setState(() {
      _additionalServices[index]['unitPrice'] = price;
      _additionalServices[index]['totalPrice'] = price * (_additionalServices[index]['quantity'] ?? 1);
    });
  }

  double _calculateAdditionalServicesTotal() {
    return _additionalServices.fold(0.0, (total, service) {
      return total + (service['totalPrice'] ?? 0.0);
    });
  }

  double _calculateSubtotal() {
    final baseFee = _towingRequest?['pricingBreakdown']?['baseFee'] ?? 0.0;
    final distanceCost = _towingRequest?['pricingBreakdown']?['distanceCost'] ?? 0.0;
    final luxurySurcharge = _towingRequest?['pricingBreakdown']?['luxurySurcharge'] ?? 0.0;
    final additionalServicesTotal = _calculateAdditionalServicesTotal();

    return baseFee + distanceCost + luxurySurcharge + additionalServicesTotal;
  }

  double _calculateTaxAmount() {
    if (!_enableTax) return 0;
    return _calculateSubtotal() * _taxRate;
  }

  double _calculateTotal() {
    return _calculateSubtotal() + _calculateTaxAmount();
  }

  Future<void> _generateInvoice() async {
    if (_towingRequest == null) return;

    if (_towingRequest!['invoiceId'] != null) {
      CustomSnackBar.show(
        context: context,
        message: 'An invoice already exists for this towing request',
        type: SnackBarType.error,
      );
      return;
    }

    if (_towingRequest!['status'] != 'ongoing') {
      CustomSnackBar.show(
        context: context,
        message: 'Cannot generate invoice. Towing request must be in "Ongoing" status',
        type: SnackBarType.error,
      );
      return;
    }

    if (_towingRequest!['serviceCenterId'] == null) {
      CustomSnackBar.show(
        context: context,
        message: 'Service center information is missing',
        type: SnackBarType.error,
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final invoiceRef = _firestore.collection('towing_invoice').doc();
      final invoiceId = invoiceRef.id;

      final pricingBreakdown = _towingRequest!['pricingBreakdown'] ?? {};
      final baseFee = pricingBreakdown['baseFee'] ?? 0.0;
      final distanceCost = pricingBreakdown['distanceCost'] ?? 0.0;
      final luxurySurcharge = pricingBreakdown['luxurySurcharge'] ?? 0.0;
      final additionalServicesTotal = _calculateAdditionalServicesTotal();

      final subtotal = _calculateSubtotal();
      final taxAmount = _calculateTaxAmount();
      final totalAmount = _calculateTotal();

      final serviceCenterName = await _getServiceCenterName();

      final invoiceData = {
        'invoiceId': invoiceId,
        'towingRequestId': widget.towingRequestId,
        'serviceCenterId': _towingRequest!['serviceCenterId'],
        'userId': _towingRequest!['customerId'] ?? _towingRequest!['userId'],
        'customerInfo': {
          'name': widget.customerName ?? 'N/A',
          'email': _towingRequest!['email'] ?? 'N/A',
          'phone': _towingRequest!['contactNumber'] ?? 'N/A',
        },
        'vehicleInfo': {
          'make': _towingRequest!['vehicleInfo']?['make'],
          'model': _towingRequest!['vehicleInfo']?['model'],
          'year': _towingRequest!['vehicleInfo']?['year'],
          'plateNumber': _towingRequest!['vehicleInfo']?['plateNumber'],
          'sizeClass': _towingRequest!['vehicleInfo']?['sizeClass']
        },
        'towingDetails': {
          'towingType': _towingRequest!['towingType'],
          'distance': _towingRequest!['distance'],
          'coverageArea': _towingRequest!['coverageArea'],
          'responseTime': _towingRequest!['responseTime'],
          'estimatedDuration': _towingRequest!['estimatedDuration'],
          'description': _towingRequest!['description']
        },
        'locationInfo': {
          'pickupAddress': _towingRequest!['location']?['customer']?['address']?['full'],
          'serviceCenterAddress': _towingRequest!['serviceCenterContact']?['address'],
          'coordinates': {
            'pickup': {
              'lat': _towingRequest!['location']?['customer']?['latitude'],
              'lng': _towingRequest!['location']?['customer']?['longitude']
            }
          }
        },
        'driverInfo': _towingRequest!['driverInfo'] != null ? {
          'name': _towingRequest!['driverInfo']['name'],
          'contactNumber': _towingRequest!['driverInfo']['contactNumber'],
          'email': _towingRequest!['driverInfo']['email'],
          'vehicle': _towingRequest!['driverVehicleInfo']
        } : null,
        'additionalServices': _additionalServices,
        'baseTowingCost': baseFee,
        'distanceCost': distanceCost ?? 0.0,
        'distanceInKm': pricingBreakdown['distanceInKm'] ?? 0.0,
        'perKmRate': pricingBreakdown['perKmRate'] ?? 0.0,
        'luxurySurcharge': luxurySurcharge ?? 0.0,
        'additionalServicesTotal': additionalServicesTotal,
        'subtotal': subtotal,
        'taxAmount': taxAmount,
        'totalAmount': totalAmount,
        'pricingBreakdown': {
          'baseFee': baseFee,
          'distanceCost': distanceCost,
          'distanceInKm': pricingBreakdown['distanceInKm'] ?? 0.0,
          'perKmRate': pricingBreakdown['perKmRate'] ?? 0.0,
          'luxurySurcharge': luxurySurcharge
        },
        'payment': {
          'method': 'N/A',
          'status': 'unpaid',
          'total': totalAmount,
          'paidAt': null
        },
        'createdAt': Timestamp.now(),
        'createdBy': '$serviceCenterName - ${widget.userData['name']}' ?? 'system',
        'status': 'generated',
        'type': 'towing_invoice'
      };

      await invoiceRef.set(invoiceData);

      final towingRequestUpdate = {
        'invoiceId': invoiceId,
        'status': 'invoice_generated',
        'updatedAt': Timestamp.now(),
        'statusUpdatedBy': widget.userData['name'] ?? 'Driver',
        'totalAmount': totalAmount,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'invoice_generated',
            'timestamp': Timestamp.now(),
            'updatedBy': widget.userData['name'] ?? 'Driver',
            'notes': 'Invoice generated. Please proceed to make payment before collecting your vehicle.'
          }
        ]),
        'timestamps': {
          ..._towingRequest!['timestamps'] ?? {},
          'invoiceGeneratedAt': Timestamp.now()
        }
      };

      await _firestore.collection('towing_requests').doc(widget.towingRequestId).update(towingRequestUpdate);

      CustomSnackBar.show(
        context: context,
        message: 'Towing invoice generated successfully!',
        type: SnackBarType.success,
      );

      Navigator.pop(context);

    } catch (e) {
      debugPrint('Error generating invoice: $e');
      CustomSnackBar.show(
        context: context,
        message: 'Failed to generate invoice: ${e.toString()}',
        type: SnackBarType.error,
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<String> _getServiceCenterName() async {
    if (_towingRequest?['serviceCenterId'] == null) return 'N/A';

    try {
      final scDoc = await _firestore
          .collection('service_centers')
          .doc(_towingRequest!['serviceCenterId'])
          .get();

      if (scDoc.exists) {
        final data = scDoc.data()!;
        return data['serviceCenterInfo']?['name'] ?? data['name'] ?? 'N/A';
      }
      return 'N/A';
    } catch (e) {
      debugPrint('Error getting service center name: $e');
      return 'N/A';
    }
  }

  String _formatCurrency(double amount) {
    return 'RM ${amount.toStringAsFixed(2)}';
  }

  String _generateInvoiceNumber() {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(now);
    final random = DateTime.now().millisecondsSinceEpoch % 10000;
    return 'TOW-$dateStr-$random';
  }

  Widget _buildAdditionalServicesSection() {
    return Card(
      color: AppColors.cardColor,
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Additional Services',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
            SizedBox(height: 12),
            _buildAddServiceForm(),
            SizedBox(height: 16),
            if (_additionalServices.isEmpty)
              Text('No additional services added', style: TextStyle(color: AppColors.textMuted))
            else
              ..._additionalServices.asMap().entries.map((entry) {
                final index = entry.key;
                final service = entry.value;
                return _buildAdditionalServiceItem(service, index);
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildAddServiceForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add Additional Service', style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        TextFormField(
          decoration: InputDecoration(
            labelText: 'Service Name',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            setState(() {
              _newAdditionalService['name'] = value;
            });
          },
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                initialValue: _newAdditionalService['quantity'].toString(),
                onChanged: (value) {
                  setState(() {
                    _newAdditionalService['quantity'] = int.tryParse(value) ?? 1;
                  });
                },
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                decoration: InputDecoration(
                  labelText: 'Unit Price (RM)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) {
                  setState(() {
                    _newAdditionalService['unitPrice'] = double.tryParse(value) ?? 0.0;
                  });
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        ElevatedButton(
          onPressed: _addAdditionalService,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.successColor,
            foregroundColor: Colors.white,
          ),
          child: Text('Add Service'),
        ),
      ],
    );
  }

  Widget _buildAdditionalServiceItem(Map<String, dynamic> service, int index) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  service['name'] ?? 'Unnamed Service',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete, color: AppColors.errorColor, size: 20),
                onPressed: () => _removeAdditionalService(index),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: service['quantity'].toString(),
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final qty = int.tryParse(value) ?? 1;
                    _updateAdditionalServiceQuantity(index, qty);
                  },
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: (service['unitPrice'] ?? 0.0).toStringAsFixed(2),
                  decoration: InputDecoration(
                    labelText: 'Unit Price (RM)',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    final price = double.tryParse(value) ?? 0.0;
                    _updateAdditionalServicePrice(index, price);
                  },
                ),
              ),
              SizedBox(width: 8),
              Text(
                _formatCurrency(service['totalPrice'] ?? 0.0),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.backgroundColor,
        appBar: AppBar(
          title: Text('Create Invoice', style: TextStyle(color: Colors.white)),
          backgroundColor: AppColors.primaryColor,
        ),
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: Text('Create Towing Invoice', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primaryColor,
        elevation: 0,
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInvoiceHeader(),
          SizedBox(height: 20),
          _buildCustomerVehicleInfo(),
          SizedBox(height: 20),
          _buildAdditionalServicesSection(),
          SizedBox(height: 20),
          _buildTaxSection(),
          SizedBox(height: 20),
          _buildSummarySection(),
          SizedBox(height: 20),
          _buildActionButtons(),
          SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildTaxSection() {
    return Card(
      color: AppColors.cardColor,
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tax Configuration',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _enableTax,
                  onChanged: (value) {
                    setState(() {
                      _enableTax = value ?? true;
                    });
                  },
                ),
                Text('Apply SST (8%)'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceHeader() {
    return Card(
      color: AppColors.secondaryColor,
      elevation: 2,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                'TOWING INVOICE',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryColor,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Invoice No: ${_generateInvoiceNumber()}',
                style: TextStyle(fontSize: 16, color: AppColors.backgroundColor),
              ),
              Text(
                'Date: ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                style: TextStyle(fontSize: 14, color: AppColors.backgroundColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerVehicleInfo() {
    return Card(
      color: AppColors.cardColor,
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer & Vehicle Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
            SizedBox(height: 12),
            _buildInfoRow('Customer', widget.customerName ?? 'N/A'),
            _buildInfoRow('Contact', _towingRequest?['contactNumber'] ?? 'N/A'),
            _buildInfoRow('Vehicle', '${_towingRequest?['vehicleInfo']?['make']} ${_towingRequest?['vehicleInfo']?['model']}'),
            _buildInfoRow('Plate', _towingRequest?['vehicleInfo']?['plateNumber'] ?? 'N/A'),
            _buildInfoRow('Pickup Location', _towingRequest?['location']?['customer']?['address']?['full'] ?? 'N/A'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    return Card(
      color: AppColors.cardColor,
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pricing Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
            SizedBox(height: 12),
            _buildSummaryRow('Base Towing:', _towingRequest?['pricingBreakdown']?['baseFee'] ?? 0.0),
            _buildSummaryRow('Distance Cost:', _towingRequest?['pricingBreakdown']?['distanceCost'] ?? 0.0),
            _buildSummaryRow('Luxury Surcharge:', _towingRequest?['pricingBreakdown']?['luxurySurcharge'] ?? 0.0),
            _buildSummaryRow('Additional Services:', _calculateAdditionalServicesTotal()),
            _buildSummaryRow('Subtotal:', _calculateSubtotal(), isBold: true),
            if (_enableTax)
              _buildSummaryRow('SST (8%):', _calculateTaxAmount(), isTax: true),
            _buildSummaryRow('GRAND TOTAL:', _calculateTotal(), isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isBold = false, bool isTotal = false, bool isTax = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 16 : 14,
              color: isTax ? AppColors.errorColor : AppColors.textPrimary,
            ),
          ),
          Text(
            _formatCurrency(amount),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isTotal ? 18 : 14,
              color: isTotal ? AppColors.successColor : (isTax ? AppColors.errorColor : AppColors.primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: AppColors.textSecondary),
            ),
            child: Text('Cancel'),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _isGenerating ? null : _generateInvoice,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.successColor,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isGenerating
                ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
                : Text('Generate Invoice'),
          ),
        ),
      ],
    );
  }
}