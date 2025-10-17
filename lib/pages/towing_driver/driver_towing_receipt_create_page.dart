import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

class TowingReceiptCreatePage extends StatefulWidget {
  final String? receiptId;
  final String? invoiceId;
  final Map<String, dynamic> userData;
  final String? customerName;
  final String? adminName;
  final bool? isPaymentMode;

  const TowingReceiptCreatePage({
    Key? key,
    this.receiptId,
    this.invoiceId,
    required this.userData,
    this.customerName,
    this.adminName,
    this.isPaymentMode = false,
  }) : super(key: key);

  @override
  _TowingReceiptCreatePageState createState() => _TowingReceiptCreatePageState();
}

class _TowingReceiptCreatePageState extends State<TowingReceiptCreatePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _receiptData;
  Map<String, dynamic>? _invoiceData;
  Map<String, dynamic>? _towingRequest;
  Map<String, dynamic>? _serviceCenterInfo;
  bool _isLoading = true;
  bool _isReceiptMode = true;
// Payment State Variables
  String _paymentMethod = 'cash';
  double _amountPaid = 0.0;
  String _paymentNotes = '';
  bool _processingPayment = false;

  // E-Wallet properties
  String _ewalletProvider = '';
  String _ewalletTransactionId = '';
  String _ewalletReference = '';
  String _ewalletPhone = '';

  // Card properties
  String _cardNumber = '';
  String _cardExpiry = '';
  String _cardCVV = '';
  String _cardAuthCode = '';
  String _cardTerminalId = '';

  // Bank transfer properties
  String _bankName = '';
  String _bankReference = '';
  String _bankTransactionDate = '';
  double _bankAmount = 0.0;

  // Cash properties
  double _cashTendered = 0.0;
  double _cashChange = 0.0;

  @override
  void initState() {
    super.initState();
    _isReceiptMode = !(widget.isPaymentMode ?? false);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      if (widget.receiptId != null) {
        _isReceiptMode = true;
        await _loadReceiptData();
      } else if (widget.invoiceId != null) {
        _isReceiptMode = false;
        await _loadInvoiceData();
      } else {
        CustomSnackBar.show(
          context: context,
          message: 'No receipt or invoice ID provided',
          type: SnackBarType.error,
        );
        Navigator.pop(context);
        return;
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      CustomSnackBar.show(
        context: context,
        message: 'Failed to load data',
        type: SnackBarType.error,
      );
      Navigator.pop(context);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadReceiptData() async {
    final receiptDoc = await _firestore
        .collection('towing_receipts')
        .doc(widget.receiptId)
        .get();

    if (receiptDoc.exists) {
      setState(() {
        _receiptData = {'id': receiptDoc.id, ...receiptDoc.data()!};
      });

      if (_receiptData?['towingRequestId'] != null) {
        await _loadTowingRequest(_receiptData!['towingRequestId']);
      }
      if (_receiptData?['serviceCenterId'] != null) {
        await _loadServiceCenterInfo(_receiptData!['serviceCenterId']);
      }
    } else {
      throw Exception('Receipt not found');
    }
  }

  Future<void> _loadInvoiceData() async {
    final invoiceDoc = await _firestore
        .collection('towing_invoice')
        .doc(widget.invoiceId)
        .get();

    if (invoiceDoc.exists) {
      setState(() {
        _invoiceData = {'id': invoiceDoc.id, ...invoiceDoc.data()!};
      });

      if (_invoiceData?['towingRequestId'] != null) {
        await _loadTowingRequest(_invoiceData!['towingRequestId']);
      }
      if (_invoiceData?['serviceCenterId'] != null) {
        await _loadServiceCenterInfo(_invoiceData!['serviceCenterId']);
      }
    } else {
      throw Exception('Invoice not found');
    }
  }

  Future<void> _loadTowingRequest(String requestId) async {
    try {
      final requestDoc = await _firestore
          .collection('towing_requests')
          .doc(requestId)
          .get();

      if (requestDoc.exists) {
        setState(() {
          _towingRequest = {'id': requestDoc.id, ...requestDoc.data()!};
        });
      }
    } catch (e) {
      debugPrint('Error loading towing request: $e');
    }
  }

  Future<void> _loadServiceCenterInfo(String scId) async {
    try {
      final scDoc = await _firestore
          .collection('service_centers')
          .doc(scId)
          .get();

      if (scDoc.exists) {
        setState(() {
          _serviceCenterInfo = scDoc.data();
        });
      }
    } catch (e) {
      debugPrint('Error loading service center: $e');
    }
  }

  Future<void> _processPayment() async {
    if (_amountPaid <= 0) {
      CustomSnackBar.show(
        context: context,
        message: 'Please enter a valid payment amount',
        type: SnackBarType.error,
      );
      return;
    }

    if (!_validatePaymentDetails()) {
      return;
    }

    final totalAmount = (_invoiceData?['totalAmount'] ?? 0).toDouble();
    final isFullPayment = _amountPaid >= totalAmount;
    final remainingBalance = totalAmount - _amountPaid;

    if (!isFullPayment) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Partial Payment'),
          content: Text(
            'This is a partial payment of ${_formatCurrency(_amountPaid)}. '
                'Balance due: ${_formatCurrency(remainingBalance)}. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
              ),
              child: Text('Continue'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() {
      _processingPayment = true;
    });

    try {
      await _generateReceipt();

      CustomSnackBar.show(
        context: context,
        message: isFullPayment
            ? 'Payment processed successfully! Receipt generated.'
            : 'Partial payment processed. Balance due: ${_formatCurrency(remainingBalance)}',
        type: SnackBarType.success,
      );

      setState(() {
        _isReceiptMode = true;
      });

    } catch (e) {
      debugPrint('Error processing payment: $e');
      CustomSnackBar.show(
        context: context,
        message: 'Failed to process payment. Please try again.',
        type: SnackBarType.error,
      );
    } finally {
      setState(() {
        _processingPayment = false;
      });
    }
  }

  bool _validatePaymentDetails() {
    switch (_paymentMethod) {
      case 'ewallet':
        if (_ewalletProvider.isEmpty || _ewalletTransactionId.isEmpty) {
          CustomSnackBar.show(
            context: context,
            message: 'Please fill in all required e-wallet details',
            type: SnackBarType.error,
          );
          return false;
        }
        break;
      case 'card':
        if (_cardNumber.isEmpty || _cardExpiry.isEmpty || _cardCVV.isEmpty) {
          CustomSnackBar.show(
            context: context,
            message: 'Please fill in all required card details',
            type: SnackBarType.error,
          );
          return false;
        }
        if (_cardNumber.length != 16) {
          CustomSnackBar.show(
            context: context,
            message: 'Please enter a valid 16-digit card number',
            type: SnackBarType.error,
          );
          return false;
        }
        if (_cardCVV.length != 3) {
          CustomSnackBar.show(
            context: context,
            message: 'Please enter a valid 3-digit CVV',
            type: SnackBarType.error,
          );
          return false;
        }
        break;
      case 'bank_transfer':
        if (_bankName.isEmpty || _bankReference.isEmpty || _bankTransactionDate.isEmpty) {
          CustomSnackBar.show(
            context: context,
            message: 'Please fill in all required bank transfer details',
            type: SnackBarType.error,
          );
          return false;
        }
        break;
      case 'cash':
        if (_cashTendered < _amountPaid) {
          CustomSnackBar.show(
            context: context,
            message: 'Cash tendered must be greater than or equal to amount paid',
            type: SnackBarType.error,
          );
          return false;
        }
        break;
    }
    return true;
  }

  // Future<void> _updatePaymentStatus() async {
  //
  // }

  void _addPaymentMethodDetails(Map<String, dynamic> updateObject) {
    switch (_paymentMethod) {
      case 'card':
        updateObject['payment.cardLastFour'] = _cardNumber.substring(_cardNumber.length - 4);
        updateObject['payment.transactionId'] = _generateTransactionId();
        updateObject['payment.authorizationCode'] = _cardAuthCode;
        updateObject['payment.terminalId'] = _cardTerminalId;
        break;
      case 'ewallet':
        updateObject['payment.ewalletProvider'] = _ewalletProvider;
        updateObject['payment.ewalletTransactionId'] = _ewalletTransactionId;
        updateObject['payment.ewalletReference'] = _ewalletReference;
        updateObject['payment.ewalletPhone'] = _ewalletPhone;
        break;
      case 'bank_transfer':
        updateObject['payment.bankName'] = _bankName;
        updateObject['payment.bankReference'] = _bankReference;
        updateObject['payment.bankTransactionDate'] = _bankTransactionDate;
        updateObject['payment.bankAmount'] = _bankAmount;
        break;
      case 'cash':
        updateObject['payment.cashTendered'] = _cashTendered;
        updateObject['payment.cashChange'] = _cashChange;
        break;
    }
  }

  Future<void> _generateReceipt() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final totalAmount = (_invoiceData?['totalAmount'] ?? 0).toDouble();
      final isFullPayment = _amountPaid >= totalAmount;
      final paymentStatus = isFullPayment ? 'paid' : 'partial';
      final receiptRef = firestore.collection('towing_receipts').doc();
      final receiptId = receiptRef.id;

      final receiptData = <String, dynamic>{
        'receiptId': receiptId,
        'invoiceId': widget.invoiceId,
        'towingRequestId': _invoiceData?['towingRequestId'],
        'serviceCenterId': _invoiceData?['serviceCenterId'],
        'userId': _invoiceData?['userId'],


        'customerInfo': _invoiceData?['customerInfo'] ?? {
          'name': widget.customerName ?? 'N/A',
          'email': _towingRequest?['customer']?['email'] ?? _towingRequest?['email'],
          'phone': _towingRequest?['customer']?['phone'] ?? _towingRequest?['contactNumber'],
        },
        'vehicleInfo': _invoiceData?['vehicleInfo'] ?? {
          'make': _towingRequest?['vehicleInfo']?['make'],
          'model': _towingRequest?['vehicleInfo']?['model'],
          'year': _towingRequest?['vehicleInfo']?['year'],
          'plateNumber': _towingRequest?['vehicleInfo']?['plateNumber'],
          'sizeClass': _towingRequest?['vehicleInfo']?['sizeClass'],
        },

        'baseTowingCost': _invoiceData?['pricingBreakdown']?['baseFee'] ?? 0,
        'distanceCost': _invoiceData?['pricingBreakdown']?['distanceCost'] ?? 0,
        'additionalServicesTotal': _invoiceData?['additionalServicesTotal'] ?? 0,
        'subtotal': _invoiceData?['subtotal'] ?? 0,
        'taxAmount': _invoiceData?['taxAmount'] ?? 0,
        'totalAmount': totalAmount,
        'amountPaid': _amountPaid,
        'balanceDue': max(0, totalAmount - _amountPaid),

        'payment': {
          'method': _paymentMethod,
          'status': paymentStatus,
          'paidAt': Timestamp.now(),
          'notes': _paymentNotes,
          'amountPaid': _amountPaid,
          'balanceDue': max(0, totalAmount - _amountPaid),
        },

        'issuedAt': Timestamp.now(),
        'issuedBy': '${_serviceCenterInfo?['serviceCenterInfo']?['name'] ?? 'Service Center'} - ${widget.adminName ?? 'system'}',
        'type': isFullPayment ? 'final_receipt' : 'partial_receipt',
        'status': paymentStatus,
      };

      final requestStatus = isFullPayment ? 'completed' : 'pending_payment';

      // Update invoice with payment details
      final invoiceUpdate = <String, dynamic>{
        'payment.method': _paymentMethod,
        'payment.status': paymentStatus,
        'payment.paidAt': Timestamp.now(),
        'payment.amountPaid': _amountPaid,
        'payment.notes': _paymentNotes,
        'payment.balanceDue': max(0, totalAmount - _amountPaid),
        'status': paymentStatus,
        'updatedAt': Timestamp.now(),
      };

      _addPaymentMethodDetails(invoiceUpdate);

      await _firestore
          .collection('towing_invoice')
          .doc(widget.invoiceId)
          .update(invoiceUpdate);

      final requestUpdate = <String, dynamic>{
        'receiptId': receiptId,
        'status': requestStatus,
        'payment.method': _paymentMethod,
        'payment.status': paymentStatus,
        'payment.total': _amountPaid,
        'payment.taxAmount': _invoiceData?['taxAmount'] ?? 0,
        'payment.additionalFees': _invoiceData?['additionalServicesTotal'] ?? 0,
        'payment.paidAt': Timestamp.now(),
        'payment.balanceDue': max(0, totalAmount - _amountPaid),
        'updatedAt': Timestamp.now(),
        'statusUpdatedBy': widget.adminName ?? 'system',
        'totalAmount': totalAmount,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'completed',
            'timestamp': Timestamp.now(),
            'updatedBy': widget.userData['name'] ?? 'Driver',
            'notes': 'Fully payment of RM ${_amountPaid} received. Towing Service completed'
          }
        ]),
        'timestamps': {
          ..._towingRequest!['timestamps'] ?? {},
          'invoiceGeneratedAt': Timestamp.now()
        }
      };

      await _firestore
          .collection('towing_requests')
          .doc(_invoiceData?['towingRequestId'])
          .update(requestUpdate);

      setState(() {
        _receiptData = receiptData;
      });
      await receiptRef.set(receiptData);

      debugPrint('Receipt generated successfully locally');

    } catch (e, stackTrace) {
      debugPrint('Error in _generateReceipt: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  String _generateTransactionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(10000);
    return 'TXN-$timestamp-$random';
  }


  void _onPaymentMethodChange() {
    setState(() {
      _ewalletProvider = '';
      _ewalletTransactionId = '';
      _ewalletReference = '';
      _ewalletPhone = '';
      _cardNumber = '';
      _cardExpiry = '';
      _cardCVV = '';
      _cardAuthCode = '';
      _cardTerminalId = '';
      _bankName = '';
      _bankReference = '';
      _bankTransactionDate = '';
      _bankAmount = 0.0;
      _cashTendered = 0.0;
      _cashChange = 0.0;
    });
  }

  void _onAmountPaidChange() {
    setState(() {
      if (_paymentMethod == 'cash') {
        _cashTendered = _amountPaid;
        _calculateCashChange();
      }
      if (_paymentMethod == 'bank_transfer') {
        _bankAmount = _amountPaid;
      }
    });
  }

  void _calculateCashChange() {
    setState(() {
      if (_paymentMethod == 'cash' && _cashTendered > 0) {
        _cashChange = max(0, _cashTendered - _amountPaid);
      } else {
        _cashChange = 0;
      }
    });
  }

  String _getPaymentButtonText() {
    if (_amountPaid <= 0) return 'Process Payment';

    final totalAmount = (_invoiceData?['totalAmount'] ?? 0).toDouble();
    final remainingBalance = totalAmount - _amountPaid;

    if (_amountPaid >= totalAmount) {
      return 'Settle Balance (${_formatCurrency(remainingBalance)})';
    } else {
      return 'Process Payment (${_formatCurrency(_amountPaid)})';
    }
  }

  double _getRemainingBalance() {
    final totalAmount = (_invoiceData?['totalAmount'] ?? 0).toDouble();
    final previousPaid = (_invoiceData?['payment']?['amountPaid'] ?? 0).toDouble();
    return max(0, totalAmount - previousPaid);
  }

  Map<String, dynamic>? get _data => _isReceiptMode ? _receiptData : _invoiceData;
  String get _documentId => _isReceiptMode
      ? (_receiptData?['receiptId'] ?? _receiptData?['id'])
      : (_invoiceData?['invoiceId'] ?? _invoiceData?['id']);
  String get _title => 'Towing Receipt';

  String _formatCurrency(dynamic amount) {
    final num value = amount is num ? amount : (double.tryParse(amount.toString()) ?? 0.0);
    return 'RM ${value.toStringAsFixed(2)}';
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    final date = timestamp.toDate();
    return DateFormat('dd MMM yyyy').format(date);
  }

  String _formatDateTime(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    final date = timestamp.toDate();
    return DateFormat('dd MMM yyyy - hh:mm a').format(date);
  }

  String _getPaymentMethodDisplay(String method) {
    final methodMap = {
      'cash': 'Cash',
      'card': 'Credit/Debit Card',
      'ewallet': 'E-Wallet',
      'bank_transfer': 'Bank Transfer',
      'N/A': 'Not Paid',
    };
    return methodMap[method] ?? method;
  }

  String _getPaymentStatusDisplay(String status) {
    final statusMap = {
      'paid': 'Paid',
      'partial': 'Partial Payment',
      'unpaid': 'Unpaid',
      'generated': 'Invoice Generated',
    };
    return statusMap[status] ?? status;
  }

  Color _getPaymentStatusColor(String status) {
    switch (status) {
      case 'paid':
        return AppColors.successColor;
      case 'partial':
        return AppColors.warningColor;
      case 'unpaid':
      case 'generated':
        return AppColors.errorColor;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.backgroundColor,
        appBar: AppBar(
          title: Text(_title, style: TextStyle(color: Colors.white)),
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
        title: Text(_title, style: TextStyle(color: Colors.white)),
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
        children: [
          if (!_isReceiptMode) _buildPaymentForm(),
          if (_isReceiptMode) ...[
            _buildHeader(),
            SizedBox(height: 20),
            _buildCustomerVehicleInfo(),
            SizedBox(height: 20),
            _buildPaymentSummary(),
            SizedBox(height: 20),
            _buildFooter(),
            SizedBox(height: 20),
          ],
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      color: AppColors.secondaryColor,
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              'TOWING SERVICE RECEIPT',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryColor,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '${_isReceiptMode ? 'Receipt' : 'Invoice'} No: ${_documentId ?? 'N/A'}',
              style: TextStyle(fontSize: 16, color: AppColors.backgroundColor),
            ),
            Text(
              'Date: ${_formatDate(_data?['issuedAt'] ?? _data?['createdAt'])}',
              style: TextStyle(fontSize: 14, color: AppColors.backgroundColor),
            ),
            Text(
              'Request No: ${_data?['towingRequestId'] ?? 'N/A'}',
              style: TextStyle(fontSize: 14, color: AppColors.backgroundColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentForm() {
    final totalAmount = (_invoiceData?['totalAmount'] ?? 0).toDouble();
    final remainingBalance = _getRemainingBalance();

    return Column(
      children: [
        Card(
          color: AppColors.cardColor,
          elevation: 2,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondaryColor,
                  ),
                ),
                SizedBox(height: 16),

                // Amount Due Summary
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderColor),
                  ),
                  child: Column(
                    children: [
                      _buildPaymentDetailRow('Total Amount:', _formatCurrency(totalAmount)),
                      _buildPaymentDetailRow('Remaining Balance:', _formatCurrency(remainingBalance)),
                    ],
                  ),
                ),
                SizedBox(height: 16),

                // Payment Method Selection
                DropdownButtonFormField<String>(
                  value: _paymentMethod,
                  decoration: InputDecoration(
                    labelText: 'Payment Method',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'card', child: Text('Credit/Debit Card')),
                    DropdownMenuItem(value: 'ewallet', child: Text('E-Wallet')),
                    DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _paymentMethod = value!;
                      _onPaymentMethodChange();
                    });
                  },
                ),
                SizedBox(height: 16),

                // Amount Paid
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'Amount Paid',
                    border: OutlineInputBorder(),
                    prefixText: 'RM ',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setState(() {
                      _amountPaid = double.tryParse(value) ?? 0.0;
                      _onAmountPaidChange();
                    });
                  },
                ),
                SizedBox(height: 16),

                // Payment Method Specific Fields
                _buildPaymentMethodFields(),
                SizedBox(height: 16),

                // Payment Notes
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'Payment Notes (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  onChanged: (value) => _paymentNotes = value,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 20),
      ],
    );
  }

  Widget _buildPaymentMethodFields() {
    switch (_paymentMethod) {
      case 'cash':
        return Column(
          children: [
            TextFormField(
              decoration: InputDecoration(
                labelText: 'Cash Tendered',
                border: OutlineInputBorder(),
                prefixText: 'RM ',
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                setState(() {
                  _cashTendered = double.tryParse(value) ?? 0.0;
                  _calculateCashChange();
                });
              },
            ),
            SizedBox(height: 8),
            if (_cashChange > 0)
              Text(
                'Change: ${_formatCurrency(_cashChange)}',
                style: TextStyle(
                  color: AppColors.successColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        );

      case 'card':
        return Column(
          children: [
            TextFormField(
              decoration: InputDecoration(
                labelText: 'Card Number',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              maxLength: 16,
              onChanged: (value) => _cardNumber = value,
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Expiry Date (MM/YY)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => _cardExpiry = value,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    decoration: InputDecoration(
                      labelText: 'CVV',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 3,
                    onChanged: (value) => _cardCVV = value,
                  ),
                ),
              ],
            ),
          ],
        );

      case 'ewallet':
        return Column(
          children: [
            TextFormField(
              decoration: InputDecoration(
                labelText: 'E-Wallet Provider',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _ewalletProvider = value,
            ),
            SizedBox(height: 8),
            TextFormField(
              decoration: InputDecoration(
                labelText: 'Transaction ID',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _ewalletTransactionId = value,
            ),
            SizedBox(height: 8),
            TextFormField(
              decoration: InputDecoration(
                labelText: 'Reference Number',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _ewalletReference = value,
            ),
          ],
        );

      case 'bank_transfer':
        return Column(
          children: [
            TextFormField(
              decoration: InputDecoration(
                labelText: 'Bank Name',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _bankName = value,
            ),
            SizedBox(height: 8),
            TextFormField(
              decoration: InputDecoration(
                labelText: 'Reference Number',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _bankReference = value,
            ),
            SizedBox(height: 8),
            TextFormField(
              decoration: InputDecoration(
                labelText: 'Transaction Date',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => _bankTransactionDate = value,
            ),
          ],
        );

      default:
        return SizedBox.shrink();
    }
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
            _buildInfoRow('Customer Name', widget.customerName ?? 'N/A'),
            _buildInfoRow('Contact Number', _data?['customerInfo']?['phone'] ?? _towingRequest?['contactNumber'] ?? 'N/A'),
            _buildInfoRow('Email', _data?['customerInfo']?['email'] ?? _towingRequest?['email'] ?? 'N/A'),
            _buildInfoRow('Vehicle', '${_data?['vehicleInfo']?['make'] ?? _towingRequest?['vehicleInfo']?['make'] ?? ''} '
                '${_data?['vehicleInfo']?['model'] ?? _towingRequest?['vehicleInfo']?['model'] ?? ''} '
                '(${_data?['vehicleInfo']?['year'] ?? _towingRequest?['vehicleInfo']?['year'] ?? 'N/A'})'),
            _buildInfoRow('Plate Number', _data?['vehicleInfo']?['plateNumber'] ?? _towingRequest?['vehicleInfo']?['plateNumber'] ?? 'N/A'),
            _buildInfoRow('Vehicle Class', _data?['vehicleInfo']?['sizeClass'] ?? _towingRequest?['vehicleInfo']?['sizeClass'] ?? 'N/A'),
            _buildInfoRow('Towing Type', _data?['towingDetails']?['towingType'] ?? _towingRequest?['towingType'] ?? 'Standard'),
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

  Widget _buildPaymentSummary() {
    final paymentStatus = _data?['payment']?['status'] ?? _data?['status'] ?? 'unpaid';
    final totalAmount = (_data?['totalAmount'] ?? 0).toDouble();
    final amountPaid = (_data?['amountPaid'] ?? _data?['payment']?['amountPaid'] ?? 0).toDouble();
    final balanceDue = (_data?['balanceDue'] ?? _data?['payment']?['balanceDue'] ?? (totalAmount - amountPaid)).toDouble();

    return Card(
      color: AppColors.cardColor,
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
            SizedBox(height: 12),

            _buildChargeRow('Base Towing Service', _data?['baseTowingCost'] ?? _data?['pricingBreakdown']?['baseFee'] ?? 0),
            if (((_data?['distanceCost'] ?? _data?['pricingBreakdown']?['distanceCost'] ?? 0) as num).toDouble() > 0)
              _buildChargeRow('Distance Charge', _data?['distanceCost'] ?? _data?['pricingBreakdown']?['distanceCost'] ?? 0),
            if (((_data?['luxurySurcharge'] ?? _data?['pricingBreakdown']?['luxurySurcharge'] ?? 0) as num).toDouble() > 0)
              _buildChargeRow('Luxury Surcharge', _data?['luxurySurcharge'] ?? _data?['pricingBreakdown']?['luxurySurcharge'] ?? 0),
            if (((_data?['additionalServicesTotal'] ?? 0) as num).toDouble() > 0)
              _buildChargeRow('Additional Services', _data?['additionalServicesTotal'] ?? 0),

            Divider(thickness: 1),
            _buildChargeRow('Subtotal', _data?['subtotal'] ?? 0, isBold: true),

            if (((_data?['taxAmount'] ?? 0) as num).toDouble() > 0)
              _buildChargeRow('SST (8%)', _data?['taxAmount'] ?? 0, isTax: true),

            Divider(thickness: 2),
            _buildChargeRow('TOTAL AMOUNT', totalAmount, isTotal: true),

            SizedBox(height: 16),

            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment Details',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  _buildPaymentDetailRow('Amount Paid:', _formatCurrency(amountPaid)),
                  _buildPaymentDetailRow('Balance Due:', _formatCurrency(balanceDue)),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Status: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 20),
                      Chip(
                        label: Text(_getPaymentStatusDisplay(paymentStatus)),
                        backgroundColor: _getPaymentStatusColor(paymentStatus).withOpacity(0.1),
                        labelStyle: TextStyle(color: _getPaymentStatusColor(paymentStatus)),
                      ),
                    ],
                  ),
                  _buildPaymentDetailRow('Method:', _getPaymentMethodDisplay(_data?['payment']?['method'] ?? 'N/A')),
                  if (_data?['payment']?['paidAt'] != null)
                    _buildPaymentDetailRow('Paid Date:', _formatDateTime(_data?['payment']?['paidAt'])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChargeRow(String description, dynamic amount, {bool isBold = false, bool isTotal = false, bool isTax = false}) {
    final double amountValue = amount is double ? amount :
    amount is int ? amount.toDouble() :
    (double.tryParse(amount.toString()) ?? 0.0);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              description,
              style: TextStyle(
                fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.normal,
                color: isTax ? AppColors.errorColor : AppColors.textPrimary,
                fontSize: isTotal ? 16 : 14,
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              _formatCurrency(amountValue),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isTotal ? 18 : 14,
                color: isTotal ? AppColors.successColor : (isTax ? AppColors.errorColor : AppColors.primaryColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Card(
      color: AppColors.cardColor,
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Service Center Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
            SizedBox(height: 12),
            if (_serviceCenterInfo != null) ...[
              Text(
                _serviceCenterInfo?['serviceCenterInfo']?['name'] ??
                    _serviceCenterInfo?['name'] ?? 'Service Center',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 4),
              Text(_serviceCenterInfo?['serviceCenterInfo']?['address']?['addressLine1'] ?? ''),
              Text(
                '${_serviceCenterInfo?['serviceCenterInfo']?['address']?['postalCode'] ?? ''} '
                    '${_serviceCenterInfo?['serviceCenterInfo']?['address']?['city'] ?? ''}, '
                    '${_serviceCenterInfo?['serviceCenterInfo']?['address']?['state'] ?? ''}',
              ),
              SizedBox(height: 4),
              Text('Tel: ${_serviceCenterInfo?['serviceCenterInfo']?['serviceCenterPhoneNo'] ?? ''}'),
              if (_serviceCenterInfo?['adminInfo']?['email'] != null)
                Text('Email: ${_serviceCenterInfo?['adminInfo']?['email']}'),
            ] else
              Text('Service center information not available', style: TextStyle(color: AppColors.textMuted)),

            SizedBox(height: 16),
            Divider(),
            SizedBox(height: 8),
            Text(
              'Thank you for choosing our towing service!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primaryColor,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'For any inquiries, please contact our customer service.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (!_isReceiptMode) {
      return Column(
        children: [
          if (_processingPayment)
            CircularProgressIndicator(color: AppColors.primaryColor),
          if (!_processingPayment)
            ElevatedButton(
              onPressed: _processPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: Size(double.infinity, 50),
              ),
              child: Text(_getPaymentButtonText()),
            ),
          SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              minimumSize: Size(double.infinity, 50),
              side: BorderSide(color: AppColors.textSecondary),
            ),
            child: Text('Cancel'),
          ),
        ],
      );
    } else {
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
              child: Text('Close'),
            ),
          ),
        ],
      );
    }
  }
}
