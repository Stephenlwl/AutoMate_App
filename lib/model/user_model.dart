class CarOwner {
  final String name;
  final String email;
  final String phone;
  final String password;
  final String brand;
  final String model;
  final String year;
  final String vin;
  final String plateNumber;
  final String idImageUrl;
  final String carProofImageUrl;

  CarOwner({
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
    required this.brand,
    required this.model,
    required this.year,
    required this.vin,
    required this.plateNumber,
    required this.idImageUrl,
    required this.carProofImageUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'password': password,
      'brand': brand,
      'model': model,
      'year': year,
      'vin': vin,
      'plate_number': plateNumber,
      'verification': {
        'idImageUrl': idImageUrl,
        'carProofImageUrl': carProofImageUrl,
        'status': 'pending',
      }
    };
  }
}
