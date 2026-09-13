// lib/features/sales/domain/pos_customer.dart
class PosCustomer {
  const PosCustomer({
    required this.code,
    required this.description,
    required this.priceLevel,
  });

  final String code;
  final String description;
  final String priceLevel;

  factory PosCustomer.fromDoc(String id, Map<String, dynamic> data) {
    return PosCustomer(
      code: id,
      description: (data['description'] as String?)?.trim().isNotEmpty == true
          ? data['description'] as String
          : id,
      priceLevel: data['priceLevel'] as String? ?? '',
    );
  }
}
