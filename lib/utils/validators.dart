class Validators {
  static String? email(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }

    if (!RegExp(r'^(?=.*[a-zA-Z])(?=.*\d)').hasMatch(value)) {
      return 'Password must contain at least one letter and one number';
    }

    return null;
  }

  static String? name(String? value) {
    if (value == null || value.isEmpty) {
      return 'Name is required';
    }

    if (value.length < 2) {
      return 'Name must be at least 2 characters';
    }

    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(value)) {
      return 'Name can only contain letters and spaces';
    }

    return null;
  }

  static String? plateNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Plate number is required';
    }

    // Malaysian plate number format validation
    if (!RegExp(r'^[A-Z]{1,3}[0-9]{1,4}[A-Z]?$').hasMatch(value.toUpperCase())) {
      return 'Enter a valid Malaysian plate number';
    }

    return null;
  }

  static String? vin(String? value) {
    if (value == null || value.isEmpty) {
      return 'VIN is required';
    }

    if (value.length != 17) {
      return 'VIN must be exactly 17 characters';
    }

    if (!RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(value.toUpperCase())) {
      return 'VIN contains invalid characters';
    }

    return null;
  }

  static String? phoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Phone number is required';
    }

    // Malaysian phone number format
    if (!RegExp(r'^(\+60|60|0)[1-9][0-9]{7,9}$').hasMatch(value.replaceAll(RegExp(r'[\s-]'), ''))) {
      return 'Enter a valid Malaysian phone number';
    }

    return null;
  }
}
