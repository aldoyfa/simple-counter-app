import 'package:flutter/material.dart';

import 'counter_record.dart';
import 'record_store.dart';
import 'upload_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, CounterRecordStore? store, RecordUploader? uploader})
    : _store = store,
      _uploader = uploader;

  final CounterRecordStore? _store;
  final RecordUploader? _uploader;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Changing Room Counter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: EventCounterPage(
        store: _store ?? SharedPreferencesCounterRecordStore(),
        uploader: _uploader ?? AppsScriptRecordUploader(),
      ),
    );
  }
}

class EventCounterPage extends StatefulWidget {
  const EventCounterPage({
    super.key,
    required this.store,
    required this.uploader,
  });

  final CounterRecordStore store;
  final RecordUploader uploader;

  @override
  State<EventCounterPage> createState() => _EventCounterPageState();
}

class _EventCounterPageState extends State<EventCounterPage> {
  List<CounterRecord> _records = [];
  String _staffUsername = '';
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await widget.store.loadRecords();
    final staffUsername = await widget.store.loadStaffUsername();
    if (!mounted) {
      return;
    }
    setState(() {
      _records = records;
      _staffUsername = staffUsername;
      _isLoading = false;
    });
  }

  Future<void> _addRecord(CounterCategory category) async {
    final now = DateTime.now();
    final record = CounterRecord(
      id: '${now.microsecondsSinceEpoch}-${category.value}',
      category: category,
      createdAt: now,
      status: RecordStatus.pending,
    );
    await _replaceRecords([..._records, record]);
  }

  Future<void> _undoLastTap() async {
    final latestPending = _latestPendingRecord();
    if (latestPending == null) {
      _showMessage('There are no pending records to undo.');
      return;
    }

    await _voidRecord(latestPending);
    _showMessage('Last tap voided.');
  }

  CounterRecord? _latestPendingRecord() {
    final pending = _records.where((record) => record.isUploadable).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return pending.isEmpty ? null : pending.first;
  }

  Future<void> _voidRecord(CounterRecord record) async {
    await _setRecordStatus(record, RecordStatus.voided);
  }

  Future<void> _restoreRecord(CounterRecord record) async {
    await _setRecordStatus(record, RecordStatus.pending);
  }

  Future<void> _setRecordStatus(
    CounterRecord record,
    RecordStatus status,
  ) async {
    await _replaceRecords(
      _records.map((existingRecord) {
        if (existingRecord.id != record.id) {
          return existingRecord;
        }
        return existingRecord.copyWith(status: status);
      }).toList(),
    );
  }

  Future<void> _uploadPendingRecords() async {
    if (_staffUsername.trim().isEmpty) {
      _showMessage('Enter the staff username before uploading.');
      await _editStaffUsername();
      return;
    }

    final uploadableRecords = pendingUploadRecords(_records);
    if (uploadableRecords.isEmpty) {
      _showMessage('There are no pending records to upload.');
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final result = await widget.uploader.upload(
        uploadableRecords,
        staffUsername: _staffUsername,
      );
      final uploadedIds = uploadableRecords.map((record) => record.id).toSet();
      await _replaceRecords(
        _records.map((record) {
          if (!uploadedIds.contains(record.id)) {
            return record;
          }
          return record.copyWith(
            status: RecordStatus.uploaded,
            uploadedAt: result.uploadedAt,
            uploadBatchId: result.uploadBatchId,
          );
        }).toList(),
      );
      _showMessage('${uploadableRecords.length} records uploaded.');
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _replaceRecords(List<CounterRecord> records) async {
    await widget.store.saveRecords(records);
    if (!mounted) {
      return;
    }
    setState(() {
      _records = records;
    });
  }

  Future<void> _editStaffUsername() async {
    var editedUsername = _staffUsername;
    final username = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Staff username'),
          content: TextFormField(
            key: const Key('staffUsernameField'),
            initialValue: _staffUsername,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Username',
              hintText: 'Enter staff username',
            ),
            onChanged: (value) {
              editedUsername = value;
            },
            onFieldSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(editedUsername),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (username == null) {
      return;
    }

    final trimmedUsername = username.trim();
    await widget.store.saveStaffUsername(trimmedUsername);
    if (!mounted) {
      return;
    }
    setState(() {
      _staffUsername = trimmedUsername;
    });
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => HistoryPage(
          records: _records,
          onVoidRecord: _voidRecord,
          onRestoreRecord: _restoreRecord,
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final totals = countActiveByCategory(_records);
    final pendingCount = _records
        .where((record) => record.status == RecordStatus.pending)
        .length;
    final uploadedCount = _records
        .where((record) => record.status == RecordStatus.uploaded)
        .length;
    final voidedCount = _records
        .where((record) => record.status == RecordStatus.voided)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Changing Room Counter'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _openHistory,
            tooltip: 'Records history',
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SummaryBar(
                    pendingCount: pendingCount,
                    uploadedCount: uploadedCount,
                    voidedCount: voidedCount,
                  ),
                  const SizedBox(height: 12),
                  _StaffUsernamePanel(
                    username: _staffUsername,
                    onEdit: _editStaffUsername,
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: MediaQuery.sizeOf(context).width >= 700
                        ? 4
                        : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.95,
                    children: [
                      for (final category in CounterCategory.values)
                        _CounterTile(
                          category: category,
                          count: totals[category] ?? 0,
                          onTap: () => _addRecord(category),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: pendingCount == 0 ? null : _undoLastTap,
                          icon: const Icon(Icons.undo),
                          label: const Text('Undo last tap'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: pendingCount == 0 || _isUploading
                              ? null
                              : _uploadPendingRecords,
                          icon: _isUploading
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload),
                          label: Text(_isUploading ? 'Uploading' : 'Upload'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _StaffUsernamePanel extends StatelessWidget {
  const _StaffUsernamePanel({required this.username, required this.onEdit});

  final String username;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final displayName = username.isEmpty ? 'Not set' : username;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        leading: const Icon(Icons.person),
        title: const Text('Staff username'),
        subtitle: Text(displayName),
        trailing: IconButton(
          onPressed: onEdit,
          tooltip: 'Edit staff username',
          icon: const Icon(Icons.edit),
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.pendingCount,
    required this.uploadedCount,
    required this.voidedCount,
  });

  final int pendingCount;
  final int uploadedCount;
  final int voidedCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatusPill(label: 'Pending', value: pendingCount),
        _StatusPill(label: 'Uploaded', value: uploadedCount),
        _StatusPill(label: 'Voided', value: voidedCount),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          '$label: $value',
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}

class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.category,
    required this.count,
    required this.onTap,
  });

  final CounterCategory category;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Add ${category.label}',
      child: Material(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  category.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  '$count',
                  key: Key('count-${category.value}'),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Icon(Icons.add_circle, color: colorScheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    required this.records,
    required this.onVoidRecord,
    required this.onRestoreRecord,
  });

  final List<CounterRecord> records;
  final Future<void> Function(CounterRecord record) onVoidRecord;
  final Future<void> Function(CounterRecord record) onRestoreRecord;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  CounterCategory? _categoryFilter;
  RecordStatus? _statusFilter;
  late List<CounterRecord> _records;

  @override
  void initState() {
    super.initState();
    _records = widget.records;
  }

  @override
  Widget build(BuildContext context) {
    final filteredRecords = _records.where((record) {
      final matchesCategory =
          _categoryFilter == null || record.category == _categoryFilter;
      final matchesStatus =
          _statusFilter == null || record.status == _statusFilter;
      return matchesCategory && matchesStatus;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Records History')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  DropdownMenu<CounterCategory?>(
                    key: const Key('categoryFilter'),
                    initialSelection: _categoryFilter,
                    label: const Text('Category'),
                    onSelected: (value) {
                      setState(() {
                        _categoryFilter = value;
                      });
                    },
                    dropdownMenuEntries: [
                      const DropdownMenuEntry(
                        value: null,
                        label: 'All categories',
                      ),
                      for (final category in CounterCategory.values)
                        DropdownMenuEntry(
                          value: category,
                          label: category.label,
                        ),
                    ],
                  ),
                  DropdownMenu<RecordStatus?>(
                    key: const Key('statusFilter'),
                    initialSelection: _statusFilter,
                    label: const Text('Status'),
                    onSelected: (value) {
                      setState(() {
                        _statusFilter = value;
                      });
                    },
                    dropdownMenuEntries: [
                      const DropdownMenuEntry(
                        value: null,
                        label: 'All statuses',
                      ),
                      for (final status in RecordStatus.values)
                        DropdownMenuEntry(value: status, label: status.label),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: filteredRecords.isEmpty
                  ? const Center(child: Text('No records found.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemBuilder: (context, index) {
                        final record = filteredRecords[index];
                        return _HistoryRecordTile(
                          record: record,
                          onVoid: record.status == RecordStatus.pending
                              ? () async {
                                  await widget.onVoidRecord(record);
                                  setState(() {
                                    _records = _records.map((existingRecord) {
                                      if (existingRecord.id != record.id) {
                                        return existingRecord;
                                      }
                                      return existingRecord.copyWith(
                                        status: RecordStatus.voided,
                                      );
                                    }).toList();
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Record voided.'),
                                      ),
                                    );
                                  }
                                }
                              : null,
                          onRestore: record.status == RecordStatus.voided
                              ? () async {
                                  await widget.onRestoreRecord(record);
                                  setState(() {
                                    _records = _records.map((existingRecord) {
                                      if (existingRecord.id != record.id) {
                                        return existingRecord;
                                      }
                                      return existingRecord.copyWith(
                                        status: RecordStatus.pending,
                                      );
                                    }).toList();
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Record restored to pending.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              : null,
                        );
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemCount: filteredRecords.length,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRecordTile extends StatelessWidget {
  const _HistoryRecordTile({
    required this.record,
    required this.onVoid,
    required this.onRestore,
  });

  final CounterRecord record;
  final Future<void> Function()? onVoid;
  final Future<void> Function()? onRestore;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(record.category.label),
        subtitle: Text(_formatDateTime(record.createdAt)),
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Chip(label: Text(record.status.label)),
            if (onVoid != null)
              TextButton(onPressed: onVoid, child: const Text('Void')),
            if (onRestore != null)
              TextButton(onPressed: onRestore, child: const Text('Restore')),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}:'
      '${_twoDigits(local.second)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
