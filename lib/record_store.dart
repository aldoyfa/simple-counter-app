import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'counter_record.dart';

abstract class CounterRecordStore {
  Future<List<CounterRecord>> loadRecords();

  Future<void> saveRecords(List<CounterRecord> records);

  Future<String> loadStaffUsername();

  Future<void> saveStaffUsername(String username);
}

class SharedPreferencesCounterRecordStore implements CounterRecordStore {
  static const _recordsKey = 'counter_records_v1';
  static const _staffUsernameKey = 'staff_username_v1';

  @override
  Future<List<CounterRecord>> loadRecords() async {
    final preferences = await SharedPreferences.getInstance();
    final encodedRecords = preferences.getString(_recordsKey);
    if (encodedRecords == null || encodedRecords.isEmpty) {
      return [];
    }

    final decodedRecords = jsonDecode(encodedRecords) as List<Object?>;
    return decodedRecords.map((record) {
      return CounterRecord.fromJson(
        Map<String, Object?>.from(record as Map<dynamic, dynamic>),
      );
    }).toList();
  }

  @override
  Future<void> saveRecords(List<CounterRecord> records) async {
    final preferences = await SharedPreferences.getInstance();
    final encodedRecords = jsonEncode(
      records.map((record) => record.toJson()).toList(),
    );
    await preferences.setString(_recordsKey, encodedRecords);
  }

  @override
  Future<String> loadStaffUsername() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_staffUsernameKey) ?? '';
  }

  @override
  Future<void> saveStaffUsername(String username) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_staffUsernameKey, username.trim());
  }
}
