// lib/features/pairing/data/pairing_repository.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/paired_device.dart';

typedef NamedOption = ({String id, String name});

const _kCompanyId = 'paired_companyId';
const _kCompanyName = 'paired_companyName';
const _kBusinessUnitId = 'paired_businessUnitId';
const _kBusinessUnitName = 'paired_businessUnitName';

class PairingRepository {
  PairingRepository(this._functions);
  final FirebaseFunctions _functions;

  Future<List<NamedOption>> listCompanies() async {
    final callable = _functions.httpsCallable('listCompaniesForSetup');
    final result = await callable.call<Map<String, dynamic>>();
    final companies = result.data['companies'] as List<dynamic>? ?? [];
    return companies
        .map((c) => (id: c['id'] as String, name: c['name'] as String))
        .toList();
  }

  Future<List<NamedOption>> listBusinessUnits(String companyId) async {
    final callable = _functions.httpsCallable('listBusinessUnitsForSetup');
    final result = await callable.call<Map<String, dynamic>>({'companyId': companyId});
    final units = result.data['businessUnits'] as List<dynamic>? ?? [];
    return units
        .map((u) => (id: u['id'] as String, name: u['name'] as String))
        .toList();
  }

  Future<void> requestPairing({
    required String companyId,
    required String businessUnitId,
  }) async {
    final callable = _functions.httpsCallable('requestPosPairing');
    await callable.call<Map<String, dynamic>>({
      'companyId': companyId,
      'businessUnitId': businessUnitId,
    });
  }

  Future<void> verifyPairing({
    required String companyId,
    required String businessUnitId,
    required String code,
  }) async {
    final callable = _functions.httpsCallable('verifyPosPairing');
    await callable.call<Map<String, dynamic>>({
      'companyId': companyId,
      'businessUnitId': businessUnitId,
      'code': code,
    });
  }

  Future<PairedDevice?> loadPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final companyId = prefs.getString(_kCompanyId);
    final businessUnitId = prefs.getString(_kBusinessUnitId);
    if (companyId == null || businessUnitId == null) return null;
    return PairedDevice(
      companyId: companyId,
      companyName: prefs.getString(_kCompanyName) ?? '',
      businessUnitId: businessUnitId,
      businessUnitName: prefs.getString(_kBusinessUnitName) ?? '',
    );
  }

  Future<void> savePairedDevice(PairedDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCompanyId, device.companyId);
    await prefs.setString(_kCompanyName, device.companyName);
    await prefs.setString(_kBusinessUnitId, device.businessUnitId);
    await prefs.setString(_kBusinessUnitName, device.businessUnitName);
  }

  Future<void> clearPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCompanyId);
    await prefs.remove(_kCompanyName);
    await prefs.remove(_kBusinessUnitId);
    await prefs.remove(_kBusinessUnitName);
  }
}
