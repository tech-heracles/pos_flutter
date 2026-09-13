// lib/features/sales/domain/ticket.dart
import 'ticket_line.dart';

enum TicketStatus { open, completed, cancelled }

TicketStatus _statusFromString(String? value) {
  switch (value) {
    case 'completed':
      return TicketStatus.completed;
    case 'cancelled':
      return TicketStatus.cancelled;
    default:
      return TicketStatus.open;
  }
}

class Ticket {
  const Ticket({
    required this.id,
    required this.status,
    required this.label,
    required this.customerCode,
    required this.locationCode,
    required this.lines,
    required this.operatorUid,
    required this.operatorName,
    this.tableId,
    this.zoneId,
    this.currentRound = 0,
  });

  final String id;
  final TicketStatus status;
  final String label;
  final String customerCode;
  final String locationCode;
  final List<TicketLine> lines;
  final String operatorUid;
  final String operatorName;

  /// Set only in BAR/RESTAURANT (tables) mode — ties this ticket to a table
  /// so it can queue several sent rounds before one summary invoice closes
  /// it out via completeTicket.
  final String? tableId;
  final String? zoneId;
  final int currentRound;

  num get total => lines.fold<num>(0, (sum, l) => sum + l.lineTotal);
  bool get hasPendingLines => lines.any((l) => l.isPending);

  factory Ticket.fromDoc(String id, Map<String, dynamic> data) {
    return Ticket(
      id: id,
      status: _statusFromString(data['status'] as String?),
      label: data['label'] as String? ?? id,
      customerCode: data['customerCode'] as String? ?? '',
      locationCode: data['locationCode'] as String? ?? '',
      lines: (data['lines'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TicketLine.fromMap)
          .toList(),
      operatorUid: data['operatorUid'] as String? ?? '',
      operatorName: data['operatorName'] as String? ?? '',
      tableId: data['tableId'] as String?,
      zoneId: data['zoneId'] as String?,
      currentRound: (data['currentRound'] as num?)?.toInt() ?? 0,
    );
  }
}
