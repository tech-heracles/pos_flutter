// lib/features/pairing/domain/paired_device.dart

/// The Business Unit this device was one-time paired to. Persisted locally
/// (shared_preferences) so the device skips setup on every future open —
/// only the operator PIN login happens per shift, not the pairing flow.
class PairedDevice {
  const PairedDevice({
    required this.companyId,
    required this.companyName,
    required this.businessUnitId,
    required this.businessUnitName,
  });

  final String companyId;
  final String companyName;
  final String businessUnitId;
  final String businessUnitName;

  Map<String, String> toJson() => {
        'companyId': companyId,
        'companyName': companyName,
        'businessUnitId': businessUnitId,
        'businessUnitName': businessUnitName,
      };

  static PairedDevice? fromJson(Map<String, String>? json) {
    if (json == null) return null;
    final companyId = json['companyId'];
    final businessUnitId = json['businessUnitId'];
    if (companyId == null || businessUnitId == null) return null;
    return PairedDevice(
      companyId: companyId,
      companyName: json['companyName'] ?? '',
      businessUnitId: businessUnitId,
      businessUnitName: json['businessUnitName'] ?? '',
    );
  }
}
