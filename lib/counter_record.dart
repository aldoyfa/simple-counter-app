enum CounterCategory {
  maleCash('male_cash', 'Male Cash'),
  maleQris('male_qris', 'Male QRIS'),
  femaleCash('female_cash', 'Female Cash'),
  femaleQris('female_qris', 'Female QRIS');

  const CounterCategory(this.value, this.label);

  final String value;
  final String label;

  static CounterCategory fromValue(String value) {
    return CounterCategory.values.firstWhere(
      (category) => category.value == value,
      orElse: () => throw ArgumentError('Unknown counter category: $value'),
    );
  }
}

enum RecordStatus {
  pending('pending', 'Pending'),
  uploaded('uploaded', 'Uploaded'),
  voided('voided', 'Voided');

  const RecordStatus(this.value, this.label);

  final String value;
  final String label;

  static RecordStatus fromValue(String value) {
    return RecordStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => throw ArgumentError('Unknown record status: $value'),
    );
  }
}

class CounterRecord {
  const CounterRecord({
    required this.id,
    required this.category,
    required this.createdAt,
    required this.status,
    this.uploadedAt,
    this.uploadBatchId,
  });

  final String id;
  final CounterCategory category;
  final DateTime createdAt;
  final RecordStatus status;
  final DateTime? uploadedAt;
  final String? uploadBatchId;

  bool get isActive => status != RecordStatus.voided;

  bool get isUploadable => status == RecordStatus.pending;

  CounterRecord copyWith({
    CounterCategory? category,
    DateTime? createdAt,
    RecordStatus? status,
    DateTime? uploadedAt,
    String? uploadBatchId,
  }) {
    return CounterRecord(
      id: id,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      uploadBatchId: uploadBatchId ?? this.uploadBatchId,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'category': category.value,
      'createdAt': createdAt.toIso8601String(),
      'status': status.value,
      'uploadedAt': uploadedAt?.toIso8601String(),
      'uploadBatchId': uploadBatchId,
    };
  }

  Map<String, Object> toUploadJson() {
    return {
      'id': id,
      'category': category.value,
      'categoryLabel': category.label,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CounterRecord.fromJson(Map<String, Object?> json) {
    return CounterRecord(
      id: json['id'] as String,
      category: CounterCategory.fromValue(json['category'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: RecordStatus.fromValue(json['status'] as String),
      uploadedAt: json['uploadedAt'] == null
          ? null
          : DateTime.parse(json['uploadedAt'] as String),
      uploadBatchId: json['uploadBatchId'] as String?,
    );
  }
}

Map<CounterCategory, int> countActiveByCategory(List<CounterRecord> records) {
  return {
    for (final category in CounterCategory.values)
      category: records
          .where((record) => record.category == category && record.isActive)
          .length,
  };
}

List<CounterRecord> pendingUploadRecords(List<CounterRecord> records) {
  return records.where((record) => record.isUploadable).toList();
}
