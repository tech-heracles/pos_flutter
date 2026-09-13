// lib/features/sales/domain/pos_location.dart
class PosLocation {
  const PosLocation({required this.code, required this.description});
  final String code;
  final String description;

  factory PosLocation.fromDoc(String id, Map<String, dynamic> data) {
    return PosLocation(
      code: id,
      description: (data['description'] as String?)?.trim().isNotEmpty == true
          ? data['description'] as String
          : id,
    );
  }
}
