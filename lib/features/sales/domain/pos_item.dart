// lib/features/sales/domain/pos_item.dart
import 'dart:convert';

class SalesPriceEntry {
  const SalesPriceEntry({required this.priceLevel, required this.value});
  final String priceLevel;
  final num value;
}

class PosItem {
  const PosItem({
    required this.code,
    required this.description,
    required this.basePrice,
    required this.groupCode,
    required this.categoryCode,
    required this.active,
    required this.salesPrices,
  });

  final String code;
  final String description;
  final num basePrice;
  final String groupCode;
  final String categoryCode;
  final bool active;
  final List<SalesPriceEntry> salesPrices;

  factory PosItem.fromDoc(Map<String, dynamic> data) {
    return PosItem(
      code: data['Code'] as String? ?? '',
      description: (data['Description'] as String?)?.trim().isNotEmpty == true
          ? data['Description'] as String
          : (data['Code'] as String? ?? ''),
      basePrice: (data['BasePrice'] as num?) ?? 0,
      groupCode: data['GroupCode'] as String? ?? 'PA GRUPIM',
      categoryCode: data['CategoryCode'] as String? ?? 'PA KATEGORI',
      active: data['Active'] == true || data['Active'] == 1,
      salesPrices: _parseSalesPrices(data['SalesPrices']),
    );
  }

  static List<SalesPriceEntry> _parseSalesPrices(dynamic raw) {
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((e) => SalesPriceEntry(
                priceLevel: e['priceLevel'] as String? ?? '',
                value: (e['value'] as num?) ?? 0,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 3-tier resolution: price matching the selected customer's price level,
  /// else the business unit's default customer's price level, else base.
  num resolvePrice({String? selectedPriceLevel, String? defaultPriceLevel}) {
    if (selectedPriceLevel != null) {
      final match = _findPrice(selectedPriceLevel);
      if (match != null && match > 0) return match;
    }
    if (defaultPriceLevel != null) {
      final match = _findPrice(defaultPriceLevel);
      if (match != null && match > 0) return match;
    }
    return basePrice;
  }

  num? _findPrice(String priceLevel) {
    for (final entry in salesPrices) {
      if (entry.priceLevel == priceLevel) return entry.value;
    }
    return null;
  }
}
