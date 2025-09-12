import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:automate_application/model/service_center_services_offer_model.dart';

class SearchServicesPage extends StatefulWidget {
  final String userId;

  const SearchServicesPage({super.key, required this.userId});

  @override
  State<SearchServicesPage> createState() => _SearchServicesPageState();
}

class AppColors {
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color primaryLight = Color(0xFFF3A169);
  static const Color primaryDark = Color(0xFFE55D00);
  static const Color secondaryColor = Color(0xFF1E293B);
  static const Color backgroundColor = Color(0xFFFAFAFA);
  static const Color cardColor = Colors.white;
  static const Color surfaceColor = Color(0xFFF8F9FA);
  static const Color accentColor = Color(0xFF06B6D4);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color borderColor = Color(0xFFE5E7EB);
}

class _SearchServicesPageState extends State<SearchServicesPage> {
  List<Map<String, dynamic>> serviceCategories = [];
  Map<String, List<ServiceCenterServiceOffer>> servicesByCategory = {};
  List<ServiceCenterServiceOffer> cartItems = [];
  String? selectedServiceCenterId;
  bool categoriesLoading = true;
  bool servicesLoading = false;
  String? expandedCategoryId;
  String carOwnerVehicleMake = '';
  String carOwnerVehicleModel = '';
  String carOwnerVehicleYear = '';
  String carOwnerVehiclePlateNo ='';

  @override
  void initState() {
    super.initState();
    _getUserVehicle();
    loadServiceCategories();
  }

  Future<void> _getUserVehicle() async {
    try {
      final doc =
      await FirebaseFirestore.instance
          .collection('car_owners')
          .doc(widget.userId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final vehicles = List<Map<String, dynamic>>.from(
          data['vehicles'] ?? [],
        );

        if (vehicles.isNotEmpty) {
          final firstVehicle = vehicles.first;
          setState(() {
            carOwnerVehicleMake = firstVehicle['brand'] ?? '';
            carOwnerVehicleModel = firstVehicle['model'] ?? '';
            carOwnerVehicleYear = firstVehicle['year']?.toString() ?? '';
            carOwnerVehiclePlateNo = firstVehicle['plate_number'] ?? '';
          });
        }
      }
    } catch (err) {
      debugPrint('Error fetching user vehicle: $err');
    }
  }

  Future<void> loadServiceCategories() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('services_categories')
          .where('active', isEqualTo: true)
          .get();

      serviceCategories = querySnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'description': data['description'] ?? '',
        };
      }).toList();

      setState(() => categoriesLoading = false);
    } catch (e) {
      debugPrint('Error loading service categories: $e');
      setState(() => categoriesLoading = false);
    }
  }

  Future<void> loadServicesForCategory(String categoryId) async {
    if (servicesByCategory.containsKey(categoryId)) return;

    setState(() => servicesLoading = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('service_center_services_offer')
          .where('categoryId', isEqualTo: categoryId)
          .where('active', isEqualTo: true);

      // Filter by vehicle make if available
      if (carOwnerVehicleMake != null && carOwnerVehicleMake!.isNotEmpty) {
        query = query.where('makes', arrayContains: carOwnerVehicleMake);
      }

      final querySnapshot = await query.get();

      List<ServiceCenterServiceOffer> services = [];

      for (var doc in querySnapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          final service = ServiceCenterServiceOffer.fromFirestore(doc.id, data);

          // filtering based on user's vehicle
          if (_isServiceCompatible(service)) {
            // Load service name from services collection
            await _loadServiceName(service);
            services.add(service);
          }
        } catch (e) {
          debugPrint('Error parsing service ${doc.id}: $e');
        }
      }

      servicesByCategory[categoryId] = services;
      setState(() => servicesLoading = false);
    } catch (e) {
      debugPrint('Error loading services for category $categoryId: $e');
      setState(() => servicesLoading = false);
    }
  }

  bool _isServiceCompatible(ServiceCenterServiceOffer service) {
    // Check if service is compatible with user's vehicle
    if (carOwnerVehicleMake != null && !service.makes.contains(carOwnerVehicleMake)) {
      return false;
    }

    if (carOwnerVehicleModel != null && service.models.isNotEmpty) {
      final makeModels = service.models[carOwnerVehicleMake];
      if (makeModels != null && !makeModels.contains(carOwnerVehicleModel)) {
        return false;
      }
    }

    if (carOwnerVehicleYear != null && service.years.isNotEmpty) {
      final makeYears = service.years[carOwnerVehicleMake];
      if (makeYears != null && !makeYears.contains(carOwnerVehicleYear)) {
        return false;
      }
    }

    // if (widget.fuelType != null && service.fuelTypes.isNotEmpty) {
    //   final makeFuelTypes = service.fuelTypes[widget.make];
    //   if (makeFuelTypes != null && !makeFuelTypes.contains(widget.fuelType)) {
    //     return false;
    //   }
    // }

    return true;
  }

  Future<void> _loadServiceName(ServiceCenterServiceOffer service) async {
    try {
      final serviceDoc = await FirebaseFirestore.instance
          .collection('services')
          .doc(service.serviceId)
          .get();

      if (serviceDoc.exists) {
        service.serviceName = serviceDoc.data()?['name'] ?? 'Unknown Service';
      }
    } catch (e) {
      debugPrint('Error loading service name: $e');
      service.serviceName = 'Unknown Service';
    }
  }

  void _addToCart(ServiceCenterServiceOffer service) {
    // Check if cart is empty or from same service center
    if (cartItems.isNotEmpty && selectedServiceCenterId != service.serviceCenterId) {
      _showServiceCenterMismatchDialog();
      return;
    }

    // Check if service already in cart
    if (cartItems.any((item) => item.id == service.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This service is already in your cart'),
          backgroundColor: AppColors.primaryColor,
        ),
      );
      return;
    }

    setState(() {
      cartItems.add(service);
      selectedServiceCenterId = service.serviceCenterId;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${service.serviceName} added to cart'),
        backgroundColor: AppColors.successColor,
        action: SnackBarAction(
          label: 'VIEW CART',
          textColor: AppColors.cardColor,
          onPressed: _showCart,
        ),
      ),
    );
  }

  void _showServiceCenterMismatchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Different Service Center'),
        content: const Text(
            'You can only book services from one service center at a time. Would you like to clear your current cart and add this service?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                cartItems.clear();
                selectedServiceCenterId = null;
              });
            },
            child: const Text('Clear Cart'),
          ),
        ],
      ),
    );
  }

  void _removeFromCart(ServiceCenterServiceOffer service) {
    setState(() {
      cartItems.removeWhere((item) => item.id == service.id);
      if (cartItems.isEmpty) {
        selectedServiceCenterId = null;
      }
    });
  }

  void _showCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildCartBottomSheet(),
    );
  }

  Widget _buildCartBottomSheet() {
    double totalPrice = cartItems.fold(0, (sum, item) => sum + item.labourPrice + item.partPrice);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Your Cart',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: cartItems.isEmpty
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_cart_outlined, size: 64, color: AppColors.textSecondary),
                    SizedBox(height: 16),
                    Text('Your cart is empty', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              )
                  : ListView.builder(
                controller: scrollController,
                itemCount: cartItems.length,
                itemBuilder: (context, index) {
                  final service = cartItems[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: ListTile(
                      title: Text(service.serviceName ?? 'Unknown Service'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(service.serviceDescription),
                          const SizedBox(height: 4),
                          Text(
                            'Duration: ${service.duration} min',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'RM ${(service.labourPrice + service.partPrice).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _removeFromCart(service),
                            icon: const Icon(Icons.remove_circle, color: AppColors.errorColor),
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (cartItems.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textSecondary.withOpacity(0.3),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total:',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'RM ${totalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primaryColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _proceedToAppointment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: AppColors.cardColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Make Appointment',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _proceedToAppointment() {
    Navigator.pop(context); // Close cart
    // Navigate to appointment booking page
    // Navigator.push(context, MaterialPageRoute(builder: (context) => AppointmentBookingPage(services: cartItems)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Proceeding to appointment booking...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryColor,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: AppColors.cardColor),
                  ),
                  const Expanded(
                    child: Text(
                      'Search Services',
                      style: TextStyle(
                        color: AppColors.cardColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Stack(
                    children: [
                      IconButton(
                        onPressed: _showCart,
                        icon: const Icon(Icons.shopping_cart, color: AppColors.cardColor),
                      ),
                      if (cartItems.isNotEmpty)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '${cartItems.length}',
                              style: const TextStyle(
                                color: AppColors.cardColor,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Vehicle Info Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: (carOwnerVehicleMake != null && carOwnerVehicleModel != null && carOwnerVehicleYear != null)
                        ? Image.network(
                      'https://cdn.imagin.studio/getImage?customer=demo&make=${carOwnerVehicleMake}&modelFamily=${carOwnerVehicleModel}&modelYear=${carOwnerVehicleYear}&angle=01',
                      height: 150,
                      width: 130,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        height: 130,
                        width: 110,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.directions_car,
                          size: 30,
                          color: AppColors.cardColor,
                        ),
                      ),
                    )
                        : Container(
                      height: 150,
                      width: 130,
                      decoration: BoxDecoration(
                        color: AppColors.cardColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.directions_car,
                        size: 40,
                        color: AppColors.cardColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your Vehicle',
                          style: TextStyle(
                            color: AppColors.cardColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          carOwnerVehiclePlateNo ?? 'No Vehicle',
                          style: const TextStyle(
                            color: AppColors.cardColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (carOwnerVehicleMake != null && carOwnerVehicleModel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${carOwnerVehicleMake} ${carOwnerVehicleModel}${carOwnerVehicleYear != null ? ' (${carOwnerVehicleYear})' : ''}',
                            style: TextStyle(
                              color: AppColors.cardColor.withOpacity(0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.cardColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.swap_horiz,
                        color: AppColors.cardColor,
                        size: 20,
                      ),
                    ),
                    onPressed: () {
                      // Navigate to vehicle selection
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Service Categories List
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.cardColor,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: categoriesLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: serviceCategories.length,
                  itemBuilder: (context, index) {
                    final category = serviceCategories[index];
                    return _buildCategoryCard(category);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
    final categoryId = category['id'];
    final isExpanded = expandedCategoryId == categoryId;
    final services = servicesByCategory[categoryId] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            title: Text(
              category['name'],
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(category['description']),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: AppColors.primaryColor,
            ),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  expandedCategoryId = null;
                } else {
                  expandedCategoryId = categoryId;
                  loadServicesForCategory(categoryId);
                }
              });
            },
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            if (servicesLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else if (services.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No compatible services found for your vehicle',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              ...services.map((service) => _buildServiceTile(service)).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildServiceTile(ServiceCenterServiceOffer service) {
    final isInCart = cartItems.any((item) => item.id == service.id);
    final totalPrice = service.labourPrice + service.partPrice;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.serviceName ?? 'Unknown Service',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (service.serviceDescription.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        service.serviceDescription,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${service.duration} min',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'RM ${totalPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: isInCart ? null : () => _addToCart(service),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isInCart ? AppColors.textSecondary : AppColors.primaryColor,
                      foregroundColor: AppColors.cardColor,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(isInCart ? 'In Cart' : 'Add to Cart'),
                  ),
                ],
              ),
            ],
          ),
          if (service.partPrice > 0 || service.labourPrice > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (service.partPrice > 0) ...[
                  Text(
                    'Parts: RM ${service.partPrice.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  if (service.labourPrice > 0) ...[
                    const SizedBox(width: 16),
                    Text(
                      'Labour: RM ${service.labourPrice.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ] else if (service.labourPrice > 0)
                  Text(
                    'Labour: RM ${service.labourPrice.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}