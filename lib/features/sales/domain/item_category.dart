// lib/features/sales/domain/item_category.dart
class ItemCategory {
  const ItemCategory({
    required this.code,
    required this.description,
    required this.groupCodes,
  });

  final String code;
  final String description;
  final List<String> groupCodes;

  factory ItemCategory.fromDoc(String id, Map<String, dynamic> data) {
    return ItemCategory(
      code: id,
      description: (data['description'] as String?)?.trim().isNotEmpty == true
          ? data['description'] as String
          : id,
      groupCodes: (data['groupCodes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}
