// lib/features/sales/domain/ticket_line.dart
class TicketLine {
  const TicketLine({
    required this.itemCode,
    required this.description,
    required this.unitPrice,
    required this.qty,
  });

  final String itemCode;
  final String description;
  final num unitPrice;
  final num qty;

  num get lineTotal => unitPrice * qty;

  factory TicketLine.fromMap(Map<String, dynamic> data) {
    return TicketLine(
      itemCode: data['itemCode'] as String? ?? '',
      description: data['description'] as String? ?? '',
      unitPrice: (data['unitPrice'] as num?) ?? 0,
      qty: (data['qty'] as num?) ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'itemCode': itemCode,
        'description': description,
        'unitPrice': unitPrice,
        'qty': qty,
      };

  TicketLine copyWith({num? qty}) => TicketLine(
        itemCode: itemCode,
        description: description,
        unitPrice: unitPrice,
        qty: qty ?? this.qty,
      );
}
