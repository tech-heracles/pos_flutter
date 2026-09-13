// lib/features/sales/domain/ticket_line.dart
class TicketLine {
  const TicketLine({
    required this.itemCode,
    required this.description,
    required this.unitPrice,
    required this.qty,
    this.roundNumber = 0,
  });

  final String itemCode;
  final String description;
  final num unitPrice;
  final num qty;

  /// 0 = still pending (not yet sent to kitchen/bar). Once a round is sent
  /// via [Ticket.currentRound], pending lines get stamped with that round's
  /// number and are locked — a later tap on the same item starts a new
  /// pending line rather than reopening the sent one.
  final int roundNumber;

  num get lineTotal => unitPrice * qty;
  bool get isPending => roundNumber == 0;

  factory TicketLine.fromMap(Map<String, dynamic> data) {
    return TicketLine(
      itemCode: data['itemCode'] as String? ?? '',
      description: data['description'] as String? ?? '',
      unitPrice: (data['unitPrice'] as num?) ?? 0,
      qty: (data['qty'] as num?) ?? 0,
      roundNumber: (data['roundNumber'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'itemCode': itemCode,
        'description': description,
        'unitPrice': unitPrice,
        'qty': qty,
        'roundNumber': roundNumber,
      };

  TicketLine copyWith({num? qty, int? roundNumber}) => TicketLine(
        itemCode: itemCode,
        description: description,
        unitPrice: unitPrice,
        qty: qty ?? this.qty,
        roundNumber: roundNumber ?? this.roundNumber,
      );
}
