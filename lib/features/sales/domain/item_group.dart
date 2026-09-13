// lib/features/sales/domain/item_group.dart
class ItemGroup {
  const ItemGroup({required this.code, required this.description});
  final String code;
  final String description;

  factory ItemGroup.fromDoc(String id, Map<String, dynamic> data) {
    return ItemGroup(
      code: id,
      description: (data['description'] as String?)?.trim().isNotEmpty == true
          ? data['description'] as String
          : id,
    );
  }
}
