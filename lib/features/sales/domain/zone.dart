// lib/features/sales/domain/zone.dart
class ZoneTable {
  const ZoneTable({required this.id, required this.name});
  final String id;
  final String name;

  factory ZoneTable.fromMap(Map<String, dynamic> data) => ZoneTable(
        id: data['id'] as String? ?? '',
        name: data['name'] as String? ?? '',
      );
}

class Zone {
  const Zone({required this.id, required this.name, required this.tables});
  final String id;
  final String name;
  final List<ZoneTable> tables;

  factory Zone.fromMap(Map<String, dynamic> data) => Zone(
        id: data['id'] as String? ?? '',
        name: data['name'] as String? ?? '',
        tables: (data['tables'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ZoneTable.fromMap)
            .toList(),
      );
}
