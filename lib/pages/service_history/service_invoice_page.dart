import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ServiceInvoicePage extends StatefulWidget {
  final String invoiceId;
  final String serviceBookingId;

  const ServiceInvoicePage({
    Key? key,
    required this.invoiceId,
    this.serviceBookingId = '',
  }) : super(key: key);

  @override
  _ServiceInvoicePageState createState() => _ServiceInvoicePageState();
}

class _ServiceInvoicePageState extends State<ServiceInvoicePage> {
  Map<String, dynamic>? invoiceData;
  Map<String, dynamic>? serviceCenterData;
  bool isLoading = true;
  bool isPrinting = false;

  @override
  void initState() {
    super.initState();
    _loadInvoiceData();
  }

  Future<void> _loadInvoiceData() async {
    try {
      DocumentSnapshot invoiceSnapshot = await FirebaseFirestore.instance
          .collection('service_invoice')
          .doc(widget.invoiceId)
          .get();

      if (invoiceSnapshot.exists) {
        final data = invoiceSnapshot.data() as Map<String, dynamic>? ?? {};
        setState(() {
          invoiceData = data;
        });
        await _loadServiceCenterData(data['serviceCenterId']);
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (error) {
      print('Error loading invoice: $error');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadServiceCenterData(String serviceCenterId) async {
    try {
      DocumentSnapshot serviceCenterSnapshot = await FirebaseFirestore.instance
          .collection('service_centers')
          .doc(serviceCenterId)
          .get();

      if (serviceCenterSnapshot.exists) {
        setState(() {
          serviceCenterData = serviceCenterSnapshot.data() as Map<String, dynamic>;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (error) {
      print('Error loading service center: $error');
      setState(() {
        isLoading = false;
      });
    }
  }

  // Helper methods
  String _getServiceCenterInfo(String key) {
    if (serviceCenterData == null) return 'N/A';

    final serviceCenterInfo = serviceCenterData!['serviceCenterInfo'];
    final serviceCenterAdminEmail = serviceCenterData!['adminInfo'];

    if (serviceCenterInfo is Map<String, dynamic> &&
        serviceCenterInfo.containsKey(key)) {
      return serviceCenterInfo[key]?.toString() ?? 'N/A';
    }

    if (serviceCenterAdminEmail is Map<String, dynamic> &&
        serviceCenterAdminEmail.containsKey(key)) {
      return serviceCenterAdminEmail[key]?.toString() ?? 'N/A';
    }

    final directValue = serviceCenterData![key];
    if (directValue != null) return directValue.toString();

    return 'N/A';
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else {
        return 'Invalid Date';
      }
      return DateFormat('dd MMM yyyy').format(date);
    } catch (e) {
      return 'Invalid Date';
    }
  }

  String _getFormattedAddress() {
    if (serviceCenterData == null) return 'N/A';

    final serviceCenterInfo = serviceCenterData!['serviceCenterInfo'];
    if (serviceCenterInfo is! Map<String, dynamic>) return 'N/A';

    final address = serviceCenterInfo['address'];
    if (address is! Map<String, dynamic>) return 'N/A';

    final addressLine1 = address['addressLine1']?.toString() ?? '';
    final addressLine2 = address['addressLine2']?.toString();
    final city = address['city']?.toString() ?? '';
    final state = address['state']?.toString() ?? '';
    final postalCode = address['postalCode']?.toString() ?? '';

    List<String> addressParts = [];
    if (addressLine1.isNotEmpty) addressParts.add(addressLine1);
    if (addressLine2 != null && addressLine2.isNotEmpty)
      addressParts.add(addressLine2);
    if (city.isNotEmpty) addressParts.add(city);
    if (state.isNotEmpty) addressParts.add(state);
    if (postalCode.isNotEmpty) addressParts.add(postalCode);

    return addressParts.join(', ');
  }

  List<Map<String, dynamic>> _getLabourItems() {
    try {
      final allServices = [
        ...(invoiceData?['bookedServices'] ?? []),
        ...(invoiceData?['packageServices'] ?? []),
        ...(invoiceData?['additionalServices'] ?? []),
      ];

      List<Map<String, dynamic>> labourItems = [];

      for (var service in allServices) {
        if (service is Map<String, dynamic>) {
          final labourPrice = (service['labourPrice'] ?? 0).toDouble();
          if (labourPrice > 0) {
            labourItems.add({
              'description':
              service['serviceName'] ?? service['packageName'] ?? 'Service',
              'quantity': 1,
              'unitPrice': labourPrice,
              'amount': labourPrice,
            });
          }
        }
      }

      return labourItems;
    } catch (e) {
      print('Error in _getLabourItems: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> _getPartsItems() {
    try {
      final parts = [
        ...(invoiceData?['usedParts'] ?? []),
        ...(invoiceData?['standaloneParts'] ?? []),
      ];
      final allServices = [
        ...(invoiceData?['bookedServices'] ?? []),
        ...(invoiceData?['packageServices'] ?? []),
        ...(invoiceData?['additionalServices'] ?? []),
      ];

      List<Map<String, dynamic>> partsItems = [];

      for (var part in parts) {
        if (part is Map<String, dynamic>) {
          partsItems.add({
            'description': 'Part: ${part['name'] ?? 'Unknown Part'}',
            'quantity': part['quantity'] ?? 1,
            'unitPrice': part['unitPrice'] ?? 0.0,
            'amount': part['amount'],
          });
        }
      }

      for (var service in allServices) {
        if (service is Map<String, dynamic>) {
          final serviceName = service['serviceName'] ?? service['parts']['description'] ?? 'Unknown Service';

          final servicePartsData = service['parts'];
          List<dynamic> serviceParts = [];

          if (servicePartsData is List) {
            serviceParts = servicePartsData;
          } else if (servicePartsData is Map<String, dynamic>) {
            serviceParts = [servicePartsData];
          }

          for (var part in serviceParts) {
            if (part is Map<String, dynamic>) {
              partsItems.add({
                'description': '${serviceName} - ${part['name'] ?? 'Part'}',
                'quantity': part['quantity'] ?? 1,
                'unitPrice': part['unitPrice'] ?? 0.0,
                'amount': part['amount'] ?? 0.0,
              });
            }
          }
        }
      }
      return partsItems;
    } catch (e) {
      print('Error in _getPartsItems: $e');
      return [];
    }
  }

  bool _hasParts() {
    try {
      return _getPartsItems().isNotEmpty;
    } catch (e) {
      print('Error in _hasParts: $e');
      return false;
    }
  }

  double _getLabourSubtotal() {
    return _getLabourItems().fold(
      0.0,
          (sum, item) {
        final amount = item['amount'];
        if (amount == null) return sum;

        // Safely convert to double
        if (amount is int) {
          return sum + amount.toDouble();
        } else if (amount is double) {
          return sum + amount;
        } else if (amount is String) {
          return sum + (double.tryParse(amount) ?? 0.0);
        }
        return sum;
      },
    );
  }

  double _getPartsSubtotal() {
    return _getPartsItems().fold(
      0.0,
          (sum, item) {
        final amount = item['amount'];
        if (amount == null) return sum;

        // Safely convert to double
        if (amount is int) {
          return sum + amount.toDouble();
        } else if (amount is double) {
          return sum + amount;
        } else if (amount is String) {
          return sum + (double.tryParse(amount) ?? 0.0);
        }
        return sum;
      },
    );
  }

  double _getSubtotal() {
    return _getLabourSubtotal() + _getPartsSubtotal();
  }

  double _getTaxAmount() {
    final payment = invoiceData?['payment'] ?? {};
    final subtotal = _getSubtotal();
    final total = (payment['total'] ?? 0).toDouble();
    return total - subtotal;
  }

  double _getTotalAmount() {
    final payment = invoiceData?['payment'] ?? {};
    final total = payment['total'];

    if (total == null) return 0.0;

    // Safely convert to double
    if (total is int) {
      return total.toDouble();
    } else if (total is double) {
      return total;
    } else if (total is String) {
      return double.tryParse(total) ?? 0.0;
    }
    return 0.0;
  }

  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else {
        return 'Invalid Date';
      }
      return DateFormat('dd/MM/yyyy, hh:mm a').format(date);
    } catch (e) {
      return 'Invalid Date';
    }
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '0.00';
    final amount = price is int ? price.toDouble() : price;
    return NumberFormat('#,##0.00').format(amount);
  }

  // PDF Generation
  void _printInvoice() async {
    setState(() {
      isPrinting = true;
    });

    try {
      await _generatePdf();
    } catch (e) {
      print('Print error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Printing failed: $e')));
    } finally {
      setState(() {
        isPrinting = false;
      });
    }
  }

  Future<void> _generatePdf() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          300 * PdfPageFormat.mm,
        ),
        margin: pw.EdgeInsets.all(8),
        build: (pw.Context context) {
          return _buildPdfContent();
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  pw.Widget _buildPdfContent() {
    return pw.Container(
      padding: pw.EdgeInsets.all(8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildPdfHeader(),
          pw.SizedBox(height: 8),
          _buildPdfInvoiceDetails(),
          pw.SizedBox(height: 8),
          _buildPdfCustomerVehicleInfo(),
          pw.SizedBox(height: 8),
          _buildPdfServicesTable(),
          pw.SizedBox(height: 8),
          _buildPdfTotals(),
          pw.SizedBox(height: 8),
          _buildPdfFooter(),
        ],
      ),
    );
  }

  pw.Widget _buildPdfHeader() {
    return pw.Column(
      children: [
        pw.Text(
          _getServiceCenterInfo('name').toUpperCase(),
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _getFormattedAddress(),
          style: pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        ),
        pw.Text(
          'Tel: ${_getServiceCenterInfo('serviceCenterPhoneNo')}',
          style: pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        ),
        pw.Divider(thickness: 1),
      ],
    );
  }

  pw.Widget _buildPdfInvoiceDetails() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'INVOICE NO: ${invoiceData?['invoiceId'] ?? invoiceData?['id'] ?? ''}',
              style: pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'BOOKING NO: ${invoiceData?['serviceBookingId'] ?? ''}',
              style: pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'DATE ISSUED: ${_formatDateTime(invoiceData?['createdAt'])}',
              style: pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildPdfCustomerVehicleInfo() {
    final customerInfo = invoiceData?['customerInfo'] ?? {};
    final vehicleInfo = invoiceData?['vehicleInfo'] ?? {};

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Customer Name: ${customerInfo['name'] ?? 'N/A'}',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Tel: ${customerInfo['phone'] ?? 'N/A'}',
          style: pw.TextStyle(fontSize: 8),
        ),
        pw.Text(
          'Vehicle: ${vehicleInfo['make'] ?? ''} ${vehicleInfo['model'] ?? ''}',
          style: pw.TextStyle(fontSize: 8),
        ),
        pw.Text(
          'Plate Number: ${vehicleInfo['plateNumber'] ?? 'N/A'}',
          style: pw.TextStyle(fontSize: 8),
        ),
        pw.Divider(thickness: 0.5),
      ],
    );
  }

  pw.Widget _buildPdfServicesTable() {
    final labourItems = _getLabourItems();
    final partsItems = _getPartsItems();

    return pw.Column(
      children: [
        // Table Header
        pw.Row(
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Text(
                'DESCRIPTION',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                'UNIT',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                'RM',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
        pw.Divider(thickness: 0.5),

        // Labour Section
        if (labourItems.isNotEmpty) ...[
          pw.Row(
            children: [
              pw.Text(
                'LABOUR CHARGES',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          ...labourItems
              .map(
                (item) => pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    item['description'],
                    style: pw.TextStyle(fontSize: 8),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    '${item['quantity']}',
                    style: pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    _formatPrice(item['amount']),
                    style: pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          )
              .toList(),
          pw.SizedBox(height: 4),
        ],

        // Parts Section
        if (_hasParts()) ...[
          pw.Row(
            children: [
              pw.Text(
                'PARTS & MATERIALS',
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          ...partsItems
              .map(
                (item) => pw.Row(
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    item['description'],
                    style: pw.TextStyle(fontSize: 8),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    '${item['quantity']}',
                    style: pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    _formatPrice(item['amount']),
                    style: pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
          )
              .toList(),
        ],
        pw.Divider(thickness: 0.5),
      ],
    );
  }

  pw.Widget _buildPdfTotals() {
    return pw.Column(
      children: [
        _buildPdfTotalRow('Labour Subtotal:', _getLabourSubtotal()),
        _buildPdfTotalRow('Parts Subtotal:', _getPartsSubtotal()),
        _buildPdfTotalRow('Subtotal:', _getSubtotal(), isBold: true),
        if (_getTaxAmount() > 0)
          _buildPdfTotalRow('SST (8%):', _getTaxAmount(), isTax: true),
        _buildPdfTotalRow('TOTAL AMOUNT:', _getTotalAmount(), isTotal: true),
        pw.Divider(thickness: 0.5),
      ],
    );
  }

  pw.Widget _buildPdfTotalRow(
      String label,
      double amount, {
        bool isBold = false,
        bool isTotal = false,
        bool isTax = false,
      }) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight:
              isBold || isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            'RM ${_formatPrice(amount)}',
            style: pw.TextStyle(
              fontSize: isTotal ? 10 : 8,
              fontWeight: pw.FontWeight.bold,
              color: isTax ? PdfColors.red : (isTotal ? PdfColors.green : PdfColors.black),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfFooter() {
    return pw.Column(
      children: [
        pw.Text(
          '** OFFICIAL INVOICE - PLEASE PAY BEFORE SERVICE **',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Thank you for your business!',
          style: pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        ),
        pw.Text(
          'For inquiries, please contact our service center',
          style: pw.TextStyle(fontSize: 7),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }

  // Mobile UI Widgets - Matching Receipt Style
  Widget _buildInvoiceHeader() {
    return Card(
      margin: EdgeInsets.all(16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue[800]!.withOpacity(0.9),
              Colors.blue[800]!.withOpacity(0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              _getServiceCenterInfo('name').toUpperCase(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              _getFormattedAddress(),
              style: TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4),
            Text(
              'Tel: ${_getServiceCenterInfo('serviceCenterPhoneNo')}',
              style: TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceDetails() {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INVOICE NO',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      invoiceData?['invoiceId']?.toString().substring(0, 8) ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'ISSUED AT',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      _formatDateTime(invoiceData?['createdAt']),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BOOKING NO',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      invoiceData?['serviceBookingId']?.toString().substring(0, 8) ?? '',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerVehicleInfo() {
    final customerInfo = invoiceData?['customerInfo'] ?? {};
    final vehicleInfo = invoiceData?['vehicleInfo'] ?? {};

    return Card(
      margin: EdgeInsets.all(16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.person, color: Colors.blue),
              title: Text(
                'CUSTOMER INFORMATION',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 8),
                  Text(
                    'Name: ${customerInfo['name'] ?? 'N/A'}',
                    style: TextStyle(fontSize: 14),
                  ),
                  Text(
                    'Phone: ${customerInfo['phone'] ?? 'N/A'}',
                    style: TextStyle(fontSize: 14),
                  ),
                  Text(
                    'Email: ${customerInfo['email'] ?? 'N/A'}',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.directions_car, color: Colors.green),
              title: Text(
                'VEHICLE INFORMATION',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 8),
                  Text(
                    '${vehicleInfo['make']} ${vehicleInfo['model']} (${vehicleInfo['year']})',
                    style: TextStyle(fontSize: 14),
                  ),
                  Text(
                    'Plate Number: ${vehicleInfo['plateNumber'] ?? 'N/A'}',
                    style: TextStyle(fontSize: 14),
                  ),
                  Text(
                    'Chassis No: ${vehicleInfo['vin'] ?? 'N/A'}',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServicesBreakdown() {
    final labourItems = _getLabourItems();
    final partsItems = _getPartsItems();

    return Card(
      margin: EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'SERVICES',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            // Labour Section
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue[50],
              child: Text(
                'LABOUR CHARGES',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
            ),
            if (labourItems.isEmpty)
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No Labour Charge',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ...labourItems.map((item) => _buildServiceItemRow(item)).toList(),

            // Parts Section
            if (_hasParts()) ...[
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.orange[50],
                child: Text(
                  'PARTS & MATERIALS',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
              ),
              ...partsItems.map((item) => _buildServiceItemRow(item)).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildServiceItemRow(Map<String, dynamic> item) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['description'], style: TextStyle(fontSize: 14)),
                SizedBox(height: 4),
                Text(
                  'Unit: ${item['quantity']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              'RM ${_formatPrice(item['amount'])}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsSection() {
    return Card(
      margin: EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'PRICING SUMMARY',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            _buildTotalRow('Labour Subtotal', _getLabourSubtotal()),
            _buildTotalRow('Parts Subtotal', _getPartsSubtotal()),
            Divider(),
            _buildTotalRow('Subtotal', _getSubtotal(), isBold: true),
            if (_getTaxAmount() > 0)
              _buildTotalRow('SST (8%)', _getTaxAmount(), isTax: true),
            _buildTotalRow('TOTAL AMOUNT', _getTotalAmount(), isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(
      String label,
      double amount, {
        bool isBold = false,
        bool isTotal = false,
        bool isTax = false,
      }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            'RM ${_formatPrice(amount)}',
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: FontWeight.bold,
              color: isTax ? Colors.red : (isTotal ? Colors.green : Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantyInfo() {
    final warranty = invoiceData?['warranty'] ?? {};
    final labourWarranty = warranty['labour'] ?? {};
    final partsWarranty = warranty['parts'] ?? {};

    final hasLabourWarranty = (labourWarranty['days'] as int? ?? 0) > 0;
    final hasPartsWarranty = (partsWarranty['days'] as int? ?? 0) > 0;

    if (!hasLabourWarranty && !hasPartsWarranty) {
      return Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'No warranty provided for this service',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WARRANTY INFORMATION',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
            ),
          ),
          SizedBox(height: 12),
          if (hasLabourWarranty)
            _buildWarrantyItem('Labour Warranty:', labourWarranty),
          if (hasPartsWarranty)
            _buildWarrantyItem('Parts Warranty:', partsWarranty),
          if (warranty['generalTerms'] != null)
            _buildWarrantyDetail('Terms:', warranty['generalTerms']),
          if (warranty['exclusions'] != null)
            _buildWarrantyDetail('Exclusions:', warranty['exclusions']),
        ],
      ),
    );
  }

  Widget _buildWarrantyItem(String label, Map<String, dynamic> warranty) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label ${warranty['days']} days (until ${_formatDate(warranty['endDate'])})',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                if (warranty['notes'] != null)
                  Text(
                    warranty['notes'],
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantyDetail(String label, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info, color: Colors.orange, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text('$label $text', style: TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildServiceMaintenance() {
    final serviceMaintenances = invoiceData?['serviceMaintenances'] ?? [];

    if (serviceMaintenances.isEmpty || serviceMaintenances is! List) {
      return SizedBox.shrink(); // Hide if no maintenance data
    }

    return Card(
      margin: EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              child: Text(
                'NEXT SERVICE REMINDER',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: serviceMaintenances.map<Widget>((maintenance) {
                  final serviceType = (maintenance['serviceType'] as String? ?? '')
                      .replaceAll('_', ' ');
                  final nextServiceMileage = maintenance['nextServiceMileage'] ?? '';
                  final nextServiceDate = maintenance['nextServiceDate'];

                  return Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          serviceType.isNotEmpty ? serviceType : 'Service',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Next service at $nextServiceMileage km or by ${_formatDate(nextServiceDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportantNotes() {
    return Card(
      margin: EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'IMPORTANT NOTES',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            _buildNoteItem(
              Icons.payment,
              'Please make payment before service begins',
            ),
            _buildNoteItem(
              Icons.receipt,
              'This is an official invoice for service estimation',
            ),
            _buildNoteItem(
              Icons.phone,
              'For inquiries, please contact our service center',
            ),
            _buildNoteItem(Icons.favorite, 'Thank you for your business!'),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteItem(IconData icon, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: isPrinting ? null : _printInvoice,
              icon: Icon(isPrinting ? Icons.print_disabled : Icons.print),
              label: Text(isPrinting ? 'PRINTING...' : 'PRINT INVOICE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No invoice found',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'The requested invoice could not be found',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('OFFICIAL INVOICE'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : invoiceData == null
          ? _buildEmptyState()
          : SingleChildScrollView(
        child: Column(
          children: [
            _buildInvoiceHeader(),
            _buildInvoiceDetails(),
            _buildCustomerVehicleInfo(),
            _buildServicesBreakdown(),
            _buildTotalsSection(),
            _buildWarrantyInfo(),
            _buildServiceMaintenance(),
            _buildImportantNotes(),
            _buildActionButtons(),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}