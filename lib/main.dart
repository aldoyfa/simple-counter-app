import 'dart:io';

import 'package:flutter/material.dart';

import 'counter_record.dart';
import 'photo_service.dart';
import 'record_store.dart';
import 'upload_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    CounterRecordStore? store,
    RecordUploader? uploader,
    PhotoService? photoService,
  }) : _store = store,
       _uploader = uploader,
       _photoService = photoService;

  final CounterRecordStore? _store;
  final RecordUploader? _uploader;
  final PhotoService? _photoService;

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
        photoService: _photoService ?? DevicePhotoService(),
      ),
    );
  }
}

class EventCounterPage extends StatefulWidget {
  const EventCounterPage({
    super.key,
    required this.store,
    required this.uploader,
    required this.photoService,
  });

  final CounterRecordStore store;
  final RecordUploader uploader;
  final PhotoService photoService;

  @override
  State<EventCounterPage> createState() => _EventCounterPageState();
}

class _EventCounterPageState extends State<EventCounterPage> {
  List<CounterRecord> _records = [];
  String _staffUsername = '';
  bool _isLoading = true;
  bool _isUploading = false;
  int _uploadDone = 0;
  int _uploadTotal = 0;

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
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${category.label} added.'),
          action: SnackBarAction(
            label: 'Add photo',
            onPressed: () => _promptPhotoForRecord(record.id),
          ),
        ),
      );
  }

  Future<void> _promptPhotoForRecord(String recordId) async {
    final record = _recordById(recordId);
    if (record == null || !mounted) {
      return;
    }
    final action = await showPhotoActionSheet(context, record: record);
    if (action == null || !mounted) {
      return;
    }
    switch (action) {
      case PhotoAction.camera:
        await _attachPhoto(record, PhotoSource.camera);
      case PhotoAction.gallery:
        await _attachPhoto(record, PhotoSource.gallery);
      case PhotoAction.view:
        await openPhotoViewer(context, record);
      case PhotoAction.remove:
        await _removePhoto(record);
    }
  }

  CounterRecord? _recordById(String id) {
    for (final record in _records) {
      if (record.id == id) {
        return record;
      }
    }
    return null;
  }

  Future<CounterRecord?> _attachPhoto(
    CounterRecord record,
    PhotoSource source,
  ) async {
    final String? photoPath;
    try {
      photoPath = await widget.photoService.capturePhoto(
        source,
        recordId: record.id,
      );
    } catch (error) {
      _showMessage('Could not get the photo: $error');
      return null;
    }
    if (photoPath == null) {
      return null;
    }

    // The record may have changed while the camera was open.
    final current = _recordById(record.id);
    if (current == null || current.status == RecordStatus.uploaded) {
      await widget.photoService.deletePhoto(photoPath);
      return null;
    }

    final previousPhoto = current.photoPath;
    final updated = current.copyWith(photoPath: photoPath);
    await _replaceRecord(updated);
    if (previousPhoto != null) {
      await widget.photoService.deletePhoto(previousPhoto);
    }
    _showMessage('Photo linked to ${updated.category.label}.');
    return updated;
  }

  Future<CounterRecord?> _removePhoto(CounterRecord record) async {
    final current = _recordById(record.id);
    final photoPath = current?.photoPath;
    if (current == null || photoPath == null) {
      return null;
    }

    final updated = current.copyWith(clearPhoto: true);
    await _replaceRecord(updated);
    await widget.photoService.deletePhoto(photoPath);
    _showMessage('Photo removed.');
    return updated;
  }

  Future<void> _replaceRecord(CounterRecord updated) async {
    await _replaceRecords(
      _records.map((record) {
        return record.id == updated.id ? updated : record;
      }).toList(),
    );
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

    final uploadedAt = DateTime.now();
    final uploadBatchId = buildUploadBatchId(uploadedAt);
    setState(() {
      _isUploading = true;
      _uploadDone = 0;
      _uploadTotal = uploadableRecords.length;
    });

    // Upload one entry at a time and save progress after each, so a dropped
    // connection only affects the entry that was in flight.
    var uploadedCount = 0;
    try {
      for (final record in uploadableRecords) {
        await widget.uploader.uploadRecord(
          record,
          staffUsername: _staffUsername,
          uploadBatchId: uploadBatchId,
          uploadedAt: uploadedAt,
        );
        final current = _recordById(record.id) ?? record;
        await _replaceRecord(
          current.copyWith(
            status: RecordStatus.uploaded,
            uploadedAt: uploadedAt,
            uploadBatchId: uploadBatchId,
          ),
        );
        uploadedCount += 1;
        if (mounted) {
          setState(() {
            _uploadDone = uploadedCount;
          });
        }
      }
      _showMessage('$uploadedCount records uploaded.');
    } catch (error) {
      _showMessage(
        uploadedCount == 0
            ? error.toString()
            : '$uploadedCount of ${uploadableRecords.length} records uploaded. '
                  '$error',
      );
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
          onAttachPhoto: _attachPhoto,
          onRemovePhoto: _removePhoto,
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
                          label: Text(
                            _isUploading
                                ? 'Uploading $_uploadDone/$_uploadTotal'
                                : 'Upload',
                          ),
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
    required this.onAttachPhoto,
    required this.onRemovePhoto,
  });

  final List<CounterRecord> records;
  final Future<void> Function(CounterRecord record) onVoidRecord;
  final Future<void> Function(CounterRecord record) onRestoreRecord;
  final Future<CounterRecord?> Function(
    CounterRecord record,
    PhotoSource source,
  )
  onAttachPhoto;
  final Future<CounterRecord?> Function(CounterRecord record) onRemovePhoto;

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

  void _replaceLocalRecord(CounterRecord updated) {
    setState(() {
      _records = _records.map((existingRecord) {
        return existingRecord.id == updated.id ? updated : existingRecord;
      }).toList();
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeStatus(CounterRecord record, RecordStatus status) async {
    if (status == RecordStatus.voided) {
      await widget.onVoidRecord(record);
    } else {
      await widget.onRestoreRecord(record);
    }
    _replaceLocalRecord(record.copyWith(status: status));
    _showMessage(
      status == RecordStatus.voided
          ? 'Record voided.'
          : 'Record restored to pending.',
    );
  }

  Future<void> _handlePhoto(CounterRecord record) async {
    final action = await showPhotoActionSheet(context, record: record);
    if (action == null || !mounted) {
      return;
    }

    final CounterRecord? updated;
    switch (action) {
      case PhotoAction.camera:
        updated = await widget.onAttachPhoto(record, PhotoSource.camera);
      case PhotoAction.gallery:
        updated = await widget.onAttachPhoto(record, PhotoSource.gallery);
      case PhotoAction.remove:
        updated = await widget.onRemovePhoto(record);
      case PhotoAction.view:
        await openPhotoViewer(context, record);
        return;
    }
    if (updated != null) {
      _replaceLocalRecord(updated);
    }
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
                        final canEditPhoto =
                            record.status == RecordStatus.pending;
                        return _HistoryRecordTile(
                          record: record,
                          onPhoto: canEditPhoto || record.hasPhoto
                              ? () => _handlePhoto(record)
                              : null,
                          onVoid: record.status == RecordStatus.pending
                              ? () => _changeStatus(record, RecordStatus.voided)
                              : null,
                          onRestore: record.status == RecordStatus.voided
                              ? () =>
                                    _changeStatus(record, RecordStatus.pending)
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
    required this.onPhoto,
    required this.onVoid,
    required this.onRestore,
  });

  final CounterRecord record;
  final Future<void> Function()? onPhoto;
  final Future<void> Function()? onVoid;
  final Future<void> Function()? onRestore;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: _PhotoThumbnail(record: record, onTap: onPhoto),
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

class _PhotoThumbnail extends StatelessWidget {
  const _PhotoThumbnail({required this.record, required this.onTap});

  final CounterRecord record;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final photoPath = record.photoPath;
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: record.hasPhoto ? 'Photo options' : 'Add photo',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(
            dimension: 48,
            child: photoPath == null
                ? ColoredBox(
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.add_a_photo_outlined,
                      color: onTap == null
                          ? colorScheme.outline
                          : colorScheme.primary,
                    ),
                  )
                : Image.file(
                    File(photoPath),
                    fit: BoxFit.cover,
                    cacheWidth: 144,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
          ),
        ),
      ),
    );
  }
}

enum PhotoAction { camera, gallery, view, remove }

Future<PhotoAction?> showPhotoActionSheet(
  BuildContext context, {
  required CounterRecord record,
}) {
  final canEdit = record.status == RecordStatus.pending;
  return showModalBottomSheet<PhotoAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(record.category.label),
                subtitle: Text(_formatDateTime(record.createdAt)),
              ),
              if (canEdit) ...[
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: Text(record.hasPhoto ? 'Retake photo' : 'Take photo'),
                  onTap: () => Navigator.of(context).pop(PhotoAction.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Choose from gallery'),
                  onTap: () => Navigator.of(context).pop(PhotoAction.gallery),
                ),
              ],
              if (record.hasPhoto)
                ListTile(
                  leading: const Icon(Icons.image),
                  title: const Text('View photo'),
                  onTap: () => Navigator.of(context).pop(PhotoAction.view),
                ),
              if (canEdit && record.hasPhoto)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Remove photo'),
                  onTap: () => Navigator.of(context).pop(PhotoAction.remove),
                ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> openPhotoViewer(BuildContext context, CounterRecord record) {
  final photoPath = record.photoPath;
  if (photoPath == null) {
    return Future.value();
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(record.category.label),
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.file(
              File(photoPath),
              errorBuilder: (context, error, stackTrace) => const Text(
                'Photo file not found.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

String _formatDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)} '
      '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}:'
      '${_twoDigits(local.second)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
