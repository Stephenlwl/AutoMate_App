import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

class ServiceReceiptPage extends StatefulWidget {
  final String receiptId;
  final String serviceBookingId;

  const ServiceReceiptPage({
    Key? key,
    required this.receiptId,
    this.serviceBookingId = '',
  }) : super(key: key);

  @override
  _ServiceReceiptPageState createState() => _ServiceReceiptPageState();
}

class _ServiceReceiptPageState extends State<ServiceReceiptPage> {
  Map<String, dynamic>? receiptData;
  Map<String, dynamic>? serviceCenterData;
  bool isLoading = true;
  bool isPrinting = false;

  @override
  void initState() {
    super.initState();
    _loadReceiptData();
  }

  Future<void> _loadReceiptData() async {
    try {
      DocumentSnapshot receiptSnapshot =
          await FirebaseFirestore.instance
              .collection('service_receipts')
              .doc(widget.receiptId)
              .get();

      if (receiptSnapshot.exists) {
        final data = receiptSnapshot.data() as Map<String, dynamic>;
        setState(() {
          receiptData = data;
        });
        await _loadServiceCenterData(data['serviceCenterId']);
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (error) {
      print('Error loading receipt: $error');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _loadServiceCenterData(String serviceCenterId) async {
    try {
      DocumentSnapshot serviceCenterSnapshot =
          await FirebaseFirestore.instance
              .collection('service_centers')
              .doc(serviceCenterId)
              .get();

      if (serviceCenterSnapshot.exists) {
        setState(() {
          serviceCenterData =
              serviceCenterSnapshot.data() as Map<String, dynamic>;
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
        ...(receiptData?['bookedServices'] ?? []),
        ...(receiptData?['packageServices'] ?? []),
        ...(receiptData?['additionalServices'] ?? []),
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
        ...(receiptData?['usedParts'] ?? []),
        ...(receiptData?['standaloneParts'] ?? []),
      ];
      final allServices = [
        ...(receiptData?['bookedServices'] ?? []),
        ...(receiptData?['packageServices'] ?? []),
        ...(receiptData?['additionalServices'] ?? []),
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
          final serviceName = service['serviceName'] ?? 'Unknown Service';

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

  int _getTotalServices() {
    try {
      return _getLabourItems().length;
    } catch (e) {
      print('Error in _getTotalServices: $e');
      return 0;
    }
  }

  int _getTotalParts() {
    try {
      return _getPartsItems().length;
    } catch (e) {
      print('Error in _getTotalParts: $e');
      return 0;
    }
  }

  String _getPaymentMethodDisplay(String? method) {
    switch (method?.toLowerCase()) {
      case 'cash':
        return 'CASH';
      case 'card':
        return 'CARD';
      case 'online':
        return 'ONLINE TRANSFER';
      case 'touchngo':
        return 'Touch \'n Go';
      case 'boost':
        return 'Boost';
      case 'grabpay':
        return 'GrabPay';
      default:
        return method?.toUpperCase() ?? 'N/A';
    }
  }

  String _getPaymentStatusDisplay(String? status) {
    switch (status?.toLowerCase()) {
      case 'paid':
        return 'PAID';
      case 'pending':
        return 'PENDING';
      case 'failed':
        return 'FAILED';
      case 'unpaid':
        return 'UNPAID';
      default:
        return status?.toUpperCase() ?? 'N/A';
    }
  }

  double _getLabourSubtotal() {
    return receiptData?['labourSubtotal']?.toDouble() ??
        _getLabourItems().fold(
          0.0,
          (sum, item) => sum + (item['amount'] as double),
        );
  }

  double _getPartsSubtotal() {
    return receiptData?['partsSubtotal']?.toDouble() ??
        _getPartsItems().fold(
          0.0,
          (sum, item) => sum + (item['amount'] as double),
        );
  }

  double _getSubtotal() {
    return receiptData?['subtotal']?.toDouble() ??
        _getLabourSubtotal() + _getPartsSubtotal();
  }

  double _getTaxAmount() {
    return receiptData?['taxAmount']?.toDouble() ?? 0.0;
  }

  double _getTotalAmount() {
    return receiptData?['totalAmount']?.toDouble() ?? 0.0;
  }

  double _getAmountPaid() {
    return receiptData?['amountPaid']?.toDouble() ?? _getTotalAmount();
  }

  double _getChangeAmount() {
    final amountPaid = _getAmountPaid();
    final totalAmount = _getTotalAmount();
    return amountPaid > totalAmount ? amountPaid - totalAmount : 0.0;
  }

  double _getBalanceDue() {
    final amountPaid = _getAmountPaid();
    final totalAmount = _getTotalAmount();
    return amountPaid < totalAmount ? totalAmount - amountPaid : 0.0;
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

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else {
        return 'Invalid Time';
      }
      return DateFormat('hh:mm a').format(date);
    } catch (e) {
      return 'Invalid Time';
    }
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '0.00';
    final amount = price is int ? price.toDouble() : price;
    return NumberFormat('#,##0.00').format(amount);
  }

  // PDF Printing
  void _printReceipt() async {
    setState(() {
      isPrinting = true;
    });

    try {
      await _generatePdf();
    } catch (e) {
      print('Print error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Printing failed: $e')));
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
          _buildPdfReceiptDetails(),
          pw.SizedBox(height: 8),
          _buildPdfCustomerVehicleInfo(),
          pw.SizedBox(height: 8),
          _buildPdfServicesTable(),
          pw.SizedBox(height: 8),
          _buildPdfTotals(),
          pw.SizedBox(height: 8),
          _buildPdfPaymentInfo(),
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

  pw.Widget _buildPdfReceiptDetails() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'RECEIPT NO: ${receiptData?['receiptId'] ?? receiptData?['id'] ?? ''}',
              style: pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'INVOICE NO: ${receiptData?['invoiceId'] ?? ''}',
              style: pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'DATE ISSUED: ${_formatDateTime(receiptData?['issuedAt'])}',
              style: pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'BOOKING NO: ${receiptData?['serviceBookingId'] ?? ''}',
              style: pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildPdfCustomerVehicleInfo() {
    final customerInfo = receiptData?['customerInfo'] ?? {};
    final vehicleInfo = receiptData?['vehicleInfo'] ?? {};

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
        _buildPdfTotalRow('AMOUNT PAID:', _getAmountPaid(), isPaid: true),
        if (_getChangeAmount() > 0)
          _buildPdfTotalRow(
            'CHANGE AMOUNT:',
            _getChangeAmount(),
            isChange: true,
          ),
        if (_getBalanceDue() > 0)
          _buildPdfTotalRow('BALANCE DUE:', _getBalanceDue(), isBalance: true),
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
    bool isPaid = false,
    bool isChange = false,
    bool isBalance = false,
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
              color:
                  isTax
                      ? PdfColors.red
                      : (isTotal
                          ? PdfColors.green
                          : (isPaid
                              ? PdfColors.blue
                              : (isBalance ? PdfColors.red : PdfColors.black))),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfPaymentInfo() {
    final payment = receiptData?['payment'] ?? {};

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'PAYMENT INFORMATION',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Payment Method:', style: pw.TextStyle(fontSize: 8)),
            pw.Text(
              _getPaymentMethodDisplay(payment['method']),
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Status:', style: pw.TextStyle(fontSize: 8)),
            pw.Text(
              _getPaymentStatusDisplay(receiptData?['status']),
              style: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.green,
              ),
            ),
          ],
        ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Paid At:', style: pw.TextStyle(fontSize: 8)),
            pw.Text(
              _formatTime(payment['paidAt']),
              style: pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
        if (payment['transactionId'] != null) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            'Transaction ID: ${payment['transactionId']}',
            style: pw.TextStyle(fontSize: 7),
          ),
        ],
        pw.Divider(thickness: 0.5),
      ],
    );
  }

  pw.Widget _buildPdfFooter() {
    return pw.Column(
      children: [
        pw.Text(
          '** OFFICIAL RECEIPT - PLEASE RETAIN FOR YOUR RECORDS **',
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
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            pw.Column(
              children: [
                pw.Container(width: 60, height: 1, color: PdfColors.black),
                pw.Text(
                  'Customer\'s Signature',
                  style: pw.TextStyle(fontSize: 7),
                ),
              ],
            ),
            pw.Column(
              children: [
                pw.Container(width: 60, height: 1, color: PdfColors.black),
                pw.Text(
                  'Authorized Signature',
                  style: pw.TextStyle(fontSize: 7),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // Mobile UI Widgets
  Widget _buildReceiptHeader() {
    return Card(
      margin: EdgeInsets.all(16),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primaryColor.withOpacity(0.9),
              AppColors.primaryColor.withOpacity(0.6),
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

  Widget _buildReceiptDetails() {
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
                      'RECEIPT NO',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      receiptData?['receiptId']?.toString().substring(0, 8) ??
                          '',
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
                      _formatDateTime(receiptData?['issuedAt']),
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
                      'INVOICE NO',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      receiptData?['invoiceId']?.toString().substring(0, 8) ??
                          '',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BOOKING NO',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      receiptData?['serviceBookingId']?.toString().substring(
                            0,
                            8,
                          ) ??
                          '',
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
    final customerInfo = receiptData?['customerInfo'] ?? {};
    final vehicleInfo = receiptData?['vehicleInfo'] ?? {};

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
            // Customer Info
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
            // Vehicle Info
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
                  Text(
                    'Mileage: ${receiptData?['mileage']?['afterService'] ?? 0} km',
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
            _buildTotalRow('GRAND AMOUNT', _getTotalAmount(), isTotal: true),
            _buildTotalRow('PAID AMOUNT', _getAmountPaid(), isPaid: true),
            if (_getChangeAmount() > 0)
              _buildTotalRow(
                'CHANGE AMOUNT',
                _getChangeAmount(),
                isChange: true,
              ),
            if (_getBalanceDue() > 0)
              _buildTotalRow('BALANCE DUE', _getBalanceDue(), isBalance: true),
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
    bool isPaid = false,
    bool isChange = false,
    bool isBalance = false,
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
              fontWeight:
                  isBold || isTotal ? FontWeight.bold : FontWeight.normal,
              color: isBalance ? Colors.red : Colors.black,
            ),
          ),
          Text(
            'RM ${_formatPrice(amount)}',
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: FontWeight.bold,
              color:
                  isTax
                      ? Colors.red
                      : (isTotal
                          ? Colors.green
                          : (isPaid
                              ? AppColors.primaryColor
                              : (isBalance ? Colors.red : Colors.black))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInformation() {
    final payment = receiptData?['payment'] ?? {};

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
              'PAYMENT INFORMATION',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            _buildInfoRow(
              'Payment Method',
              _getPaymentMethodDisplay(payment['method']),
            ),
            _buildInfoRow(
              'Payment Status',
              _getPaymentStatusDisplay(receiptData?['status']),
              status: true,
            ),
            _buildInfoRow('Paid At', _formatTime(payment['paidAt'])),
            if (payment['transactionId'] != null)
              _buildInfoRow('Transaction ID', payment['transactionId']),
            if (payment['notes'] != null)
              _buildInfoRow('Notes', payment['notes']),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool status = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          if (status)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  Widget _buildServiceSummary() {
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
              'SERVICE SUMMARY',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            _buildSummaryRow('Services Completed', '${_getTotalServices()}'),
            _buildSummaryRow('Parts Used', '${_getTotalParts()}'),
            _buildSummaryRow(
              'Service Date',
              _formatDateTime(receiptData?['issuedAt']),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Service Advisor',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  receiptData?['issuedBy'],
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
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
              Icons.receipt,
              'Please keep this receipt for warranty claims',
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
              onPressed: isPrinting ? null : _printReceipt,
              icon: Icon(isPrinting ? Icons.print_disabled : Icons.print),
              label: Text(isPrinting ? 'PRINTING...' : 'PRINT RECEIPT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
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
            'No receipt found',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            'The requested receipt could not be found',
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
        title: Text('OFFICIAL RECEIPT'),
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: Colors.white,
      ),
      body:
          isLoading
              ? Center(child: CircularProgressIndicator())
              : receiptData == null
              ? _buildEmptyState()
              : SingleChildScrollView(
                child: Column(
                  children: [
                    _buildReceiptHeader(),
                    _buildReceiptDetails(),
                    _buildCustomerVehicleInfo(),
                    _buildServicesBreakdown(),
                    _buildTotalsSection(),
                    _buildPaymentInformation(),
                    _buildServiceSummary(),
                    _buildImportantNotes(),
                    _buildActionButtons(),
                    SizedBox(height: 20),
                  ],
                ),
              ),
    );
  }
}
