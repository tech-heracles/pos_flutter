// lib/features/sales/domain/table_claim.dart

/// A table being "open" — claimed by an operator — is tracked separately
/// from whether an order/invoice exists for it yet. Albanian fiscal rules
/// treat orders (kitchen/bar slips) and the closing invoice as distinct
/// documents; a table can be open with nothing ordered yet, one or more
/// orders sent, but no invoice until the operator closes it out.
class TableClaim {
  const TableClaim({
    required this.operatorUid,
    required this.operatorName,
    required this.customerCode,
    required this.locationCode,
  });

  final String operatorUid;
  final String operatorName;
  final String customerCode;
  final String locationCode;

  static TableClaim? fromDoc(Map<String, dynamic>? data) {
    if (data == null || data['status'] != 'occupied') return null;
    return TableClaim(
      operatorUid: data['operatorUid'] as String? ?? '',
      operatorName: data['operatorName'] as String? ?? '',
      customerCode: data['customerCode'] as String? ?? '',
      locationCode: data['locationCode'] as String? ?? '',
    );
  }
}
