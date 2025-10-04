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
        final data = invoiceSnapshot.data() as Map<String, dynamic>;
        setState(() {
          invoiceData = data;
        });

        await _loadServiceCenterData(data['serviceCenterId']);
      } else {
        if (widget.serviceBookingId.isNotEmpty) {
          QuerySnapshot querySnapshot = await FirebaseFirestore.instance
              .collection('service_invoice')
              .where('serviceBookingId', isEqualTo: widget.serviceBookingId)
              .get();

          if (querySnapshot.docs.isNotEmpty) {
            final data = querySnapshot.docs.first.data() as Map<String, dynamic>;
            setState(() {
              invoiceData = data;
            });
            await _loadServiceCenterData(data['serviceCenterId']);
          }
        }
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

  String _getServiceCenterInfo(String key) {
    if (serviceCenterData == null) return 'N/A';

    final serviceCenterInfo = serviceCenterData!['serviceCenterInfo'];
    final serviceCenterAdminEmail = serviceCenterData!['adminInfo'];

    if (serviceCenterInfo is Map<String, dynamic> && serviceCenterInfo.containsKey(key)) {
      return serviceCenterInfo[key]?.toString() ?? 'N/A';
    }

    if (serviceCenterAdminEmail is Map<String, dynamic> && serviceCenterAdminEmail.containsKey(key)) {
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
    if (addressLine2 != null && addressLine2.isNotEmpty) addressParts.add(addressLine2);
    if (city.isNotEmpty) addressParts.add(city);
    if (state.isNotEmpty) addressParts.add(state);
    if (postalCode.isNotEmpty) addressParts.add(postalCode);

    return addressParts.join(', ');
  }

  void _printInvoice() async {
    setState(() {
      isPrinting = true;
    });

    try {
      await _generatePdf();
    } catch (e) {
      print('Print error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Printing failed: $e')),
      );
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
        pageFormat: PdfPageFormat.a4,
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
      padding: pw.EdgeInsets.all(30),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildPdfHeader(),
          pw.SizedBox(height: 25),
          _buildPdfCustomerVehicleInfo(),
          pw.SizedBox(height: 20),
          _buildPdfServicesTable(),
          pw.SizedBox(height: 20),
          _buildPdfPaymentSummary(),
          pw.SizedBox(height: 25),
          _buildPdfFooter(),
        ],
      ),
    );
  }

  pw.Widget _buildPdfHeader() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              _getServiceCenterInfo('name').toUpperCase(),
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              _getFormattedAddress(),
              style: pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Phone: ${_getServiceCenterInfo('serviceCenterPhoneNo')}',
              style: pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Email: ${_getServiceCenterInfo('email')}',
              style: pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Container(
              padding: pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue800,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'SERVICE INVOICE',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Invoice #: ${invoiceData?['invoiceId'] ?? ''}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Date: ${_formatDate(invoiceData?['createdAt'])}',
              style: pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildPdfCustomerVehicleInfo() {
    final customerInfo = invoiceData?['customerInfo'] ?? {};
    final vehicleInfo = invoiceData?['vehicleInfo'] ?? {};
    final mileage = invoiceData?['mileage'] ?? {};

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'CUSTOMER INFORMATION',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 8),
              _buildPdfInfoRow('Name', customerInfo['name'] ?? ''),
              _buildPdfInfoRow('Email', customerInfo['email'] ?? ''),
              _buildPdfInfoRow('Phone', customerInfo['phone'] ?? ''),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'VEHICLE INFORMATION',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 8),
              _buildPdfInfoRow('Vehicle', '${vehicleInfo['make'] ?? ''} ${vehicleInfo['model'] ?? ''}'),
              _buildPdfInfoRow('Year', vehicleInfo['year'] ?? ''),
              _buildPdfInfoRow('Plate', vehicleInfo['plateNumber'] ?? ''),
              _buildPdfInfoRow('VIN', vehicleInfo['vin'] ?? ''),
              _buildPdfInfoRow('Mileage', '${mileage['beforeService'] ?? ''} → ${mileage['afterService'] ?? ''} km'),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPdfInfoRow(String label, String value) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 80,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isNotEmpty ? value : 'N/A',
              style: pw.TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfServicesTable() {
    final allServices = [
      ...(invoiceData?['bookedServices'] ?? []),
      ...(invoiceData?['packageServices'] ?? []),
      ...(invoiceData?['additionalServices'] ?? []),
    ];

    final parts = invoiceData?['usedParts'] ?? [];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
      columnWidths: {
        0: pw.FlexColumnWidth(4),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(1.5),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Text(
                'SERVICE/PART DESCRIPTION',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Text(
                'LABOUR FEE',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Text(
                'PARTS FEE',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Text(
                'TOTAL',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        ),
        // Services
        ...allServices.map((service) => pw.TableRow(
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    service['serviceName'] ?? service['packageName'] ?? 'Service',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.normal),
                  ),
                  if (service['duration'] != null)
                    pw.Text(
                      'Duration: ${service['duration']} mins',
                      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                    ),
                ],
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Text(
                'RM ${_formatPrice(service['labourPrice'] ?? 0)}',
                style: pw.TextStyle(fontSize: 10),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Text(
                'RM ${_formatPrice(service['partPrice'] ?? 0)}',
                style: pw.TextStyle(fontSize: 10),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Text(
                'RM ${_formatPrice(service['totalPrice'] ?? service['fixedPrice'] ?? 0)}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        )).toList(),
        // Parts
        ...parts.map((part) => pw.TableRow(
          children: [
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Text(
                'Part: ${part['name']}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.normal),
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Text(
                '-',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Text(
                'RM ${_formatPrice(part['cost'] ?? 0)}',
                style: pw.TextStyle(fontSize: 10),
                textAlign: pw.TextAlign.right,
              ),
            ),
            pw.Padding(
              padding: pw.EdgeInsets.all(12),
              child: pw.Text(
                'RM ${_formatPrice(part['cost'] ?? 0)}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        )).toList(),
      ],
    );
  }

  pw.Widget _buildPdfPaymentSummary() {
    final payment = invoiceData?['payment'] ?? {};
    final total = (payment['total'] ?? 0).toDouble();

    final bookedServicesTotal = _calculateServicesTotal(invoiceData?['bookedServices'] ?? []);
    final packageServicesTotal = _calculateServicesTotal(invoiceData?['packageServices'] ?? []);
    final additionalServicesTotal = _calculateServicesTotal(invoiceData?['additionalServices'] ?? []);
    final partsTotal = _calculatePartsTotal(invoiceData?['usedParts'] ?? []);

    final servicesSubtotal = bookedServicesTotal + packageServicesTotal + additionalServicesTotal;

    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PAYMENT SUMMARY',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
            ),
          ),
          pw.SizedBox(height: 12),
          _buildPdfSummaryRow('Services Subtotal', servicesSubtotal),
          _buildPdfSummaryRow('Parts Subtotal', partsTotal),
          pw.Divider(color: PdfColors.grey400, height: 20),
          _buildPdfSummaryRow('Total Amount', total, isTotal: true),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Payment Method:',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                payment['method']?.toString().toUpperCase() ?? 'N/A',
                style: pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Payment Status:',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.Container(
                padding: pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: _getPdfStatusColor(payment['status']),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  payment['status']?.toString().toUpperCase() ?? 'N/A',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                ),
              ),
            ],
          ),
          if (payment['paidAt'] != null) ...[
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Paid At:',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  _formatDate(payment['paidAt']),
                  style: pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildPdfSummaryRow(String label, double amount, {bool isTotal = false}) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: isTotal ? 12 : 10,
              fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            'RM ${_formatPrice(amount)}',
            style: pw.TextStyle(
              fontSize: isTotal ? 14 : 10,
              fontWeight: pw.FontWeight.bold,
              color: isTotal ? PdfColors.green700 : PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfFooter() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Thank you for your business!',
              style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'For inquiries, please contact: ${_getServiceCenterInfo('serviceCenterPhoneNo')}',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Authorized Signature',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
            pw.Container(
              width: 120,
              height: 1,
              color: PdfColors.black,
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              _getServiceCenterInfo('name'),
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }

  PdfColor _getPdfStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'paid':
        return PdfColors.green;
      case 'pending':
        return PdfColors.orange;
      default:
        return PdfColors.grey;
    }
  }

  Widget _buildInvoiceHeader() {
    final customerInfo = invoiceData?['customerInfo'] ?? {};

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getServiceCenterInfo('name').toUpperCase(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[800],
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        _getFormattedAddress(),
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Phone: ${_getServiceCenterInfo('serviceCenterPhoneNo')}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Email: ${_getServiceCenterInfo('email')}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue[800],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'SERVICE INVOICE',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Invoice #: ${invoiceData?['invoiceId'] ?? 'N/A'}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Date: ${_formatDate(invoiceData?['createdAt'])}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 16),
            Divider(color: Colors.grey[300]),
            SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildInfoSection(
                    'CUSTOMER INFORMATION',
                    [
                      _buildInfoRow('Name', customerInfo['name'] ?? 'N/A'),
                      _buildInfoRow('Email', customerInfo['email'] ?? 'N/A'),
                      _buildInfoRow('Phone', customerInfo['phone'] ?? 'N/A'),
                    ],
                  ),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: _buildVehicleInfoSection(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.blue[800],
          ),
        ),
        SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleInfoSection() {
    final vehicleInfo = invoiceData?['vehicleInfo'] ?? {};
    final mileage = invoiceData?['mileage'] ?? {};

    return _buildInfoSection(
      'VEHICLE INFORMATION',
      [
        _buildInfoRow('Vehicle', '${vehicleInfo['make'] ?? ''} ${vehicleInfo['model'] ?? ''}'),
        _buildInfoRow('Year', vehicleInfo['year'] ?? ''),
        _buildInfoRow('Plate', vehicleInfo['plateNumber'] ?? ''),
        _buildInfoRow('VIN', vehicleInfo['vin'] ?? ''),
        _buildInfoRow('Mileage', '${mileage['beforeService'] ?? ''} → ${mileage['afterService'] ?? ''} km'),
      ],
    );
  }

  Widget _buildServicesTable() {
    final allServices = [
      ...(invoiceData?['bookedServices'] ?? []),
      ...(invoiceData?['packageServices'] ?? []),
      ...(invoiceData?['additionalServices'] ?? []),
    ];

    final parts = invoiceData?['usedParts'] ?? [];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SERVICE DETAILS',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            SizedBox(height: 16),
            // Table Header
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        'SERVICE/PART DESCRIPTION',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'LABOUR FEE',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'PARTS FEE',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'TOTAL',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 8),
            // Services
            ...allServices.map((service) => _buildServiceTableRow(service)).toList(),
            // Parts
            ...parts.map((part) => _buildPartTableRow(part)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceTableRow(Map<String, dynamic> service) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service['serviceName'] ?? service['packageName'] ?? 'Service',
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                ),
                if (service['duration'] != null)
                  Text(
                    'Duration: ${service['duration']} mins',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'RM ${_formatPrice(service['labourPrice'] ?? 0)}',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'RM ${_formatPrice(service['partPrice'] ?? 0)}',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'RM ${_formatPrice(service['totalPrice'] ?? service['fixedPrice'] ?? 0)}',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartTableRow(Map<String, dynamic> part) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'Part: ${part['name']}',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '-',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'RM ${_formatPrice(part['cost'] ?? 0)}',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'RM ${_formatPrice(part['cost'] ?? 0)}',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSummary() {
    final payment = invoiceData?['payment'] ?? {};
    final total = (payment['total'] ?? 0).toDouble();

    final bookedServicesTotal = _calculateServicesTotal(invoiceData?['bookedServices'] ?? []);
    final packageServicesTotal = _calculateServicesTotal(invoiceData?['packageServices'] ?? []);
    final additionalServicesTotal = _calculateServicesTotal(invoiceData?['additionalServices'] ?? []);
    final partsTotal = _calculatePartsTotal(invoiceData?['usedParts'] ?? []);

    final servicesSubtotal = bookedServicesTotal + packageServicesTotal + additionalServicesTotal;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PAYMENT SUMMARY',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            SizedBox(height: 16),
            _buildSummaryRow('Services Subtotal', servicesSubtotal),
            _buildSummaryRow('Parts Subtotal', partsTotal),
            Divider(),
            _buildSummaryRow('Total Amount', total, isTotal: true),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildPaymentDetailRow('Payment Method', payment['method']?.toString().toUpperCase() ?? 'N/A'),
                  _buildPaymentDetailRow('Payment Status', payment['status']?.toString().toUpperCase() ?? 'N/A'),
                  if (payment['paidAt'] != null)
                    _buildPaymentDetailRow('Paid At', _formatDate(payment['paidAt'])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            'RM ${_formatPrice(amount)}',
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: FontWeight.bold,
              color: isTotal ? Colors.green[700] : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  double _calculateServicesTotal(List<dynamic> services) {
    return services.fold(0.0, (sum, service) {
      final price = service['totalPrice'] ?? service['fixedPrice'] ?? 0;
      return sum + (price is int ? price.toDouble() : price);
    });
  }

  double _calculatePartsTotal(List<dynamic> parts) {
    return parts.fold(0.0, (sum, part) {
      final cost = part['cost'] ?? 0;
      return sum + (cost is int ? cost.toDouble() : cost);
    });
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
      return DateFormat('dd MMM yyyy, hh:mm a').format(date);
    } catch (e) {
      return 'Invalid Date';
    }
  }

  String _formatPrice(dynamic price) {
    if (price == null) return '0.00';
    final amount = price is int ? price.toDouble() : price;
    return NumberFormat('#,##0.00').format(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Service Invoice'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          if (!isLoading && invoiceData != null)
            IconButton(
              icon: Icon(isPrinting ? Icons.print_disabled : Icons.print),
              onPressed: isPrinting ? null : _printInvoice,
              tooltip: 'Print Invoice',
            ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : invoiceData == null
          ? Center(child: Text('Invoice not found'))
          : SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInvoiceHeader(),
            SizedBox(height: 20),
            _buildServicesTable(),
            SizedBox(height: 20),
            _buildPaymentSummary(),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}