import 'package:flutter/material.dart';
import 'database_helper.dart';

class BatchTrackingPage extends StatefulWidget {
  const BatchTrackingPage({super.key});

  @override
  State<BatchTrackingPage> createState() => _BatchTrackingPageState();
}

class _BatchTrackingPageState extends State<BatchTrackingPage> {
  final _companyController = TextEditingController();
  final _mineController = TextEditingController();
  final _batchController = TextEditingController();
  final _sourceController = TextEditingController();
  final _weightController = TextEditingController();
  final _userController = TextEditingController();

  List<Map<String, dynamic>> _batches = [];
  bool _loading = false;

  Future<void> _loadBatches() async {
    if (_companyController.text.trim().isEmpty) return;

    setState(() => _loading = true);

    try {
      final data = await DatabaseHelper.instance.getAllBatches(
        companyId: _companyController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _batches = data);
    } catch (e) {
      _message('Imeshindikana kusoma Batch: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _registerBatch() async {
    final company = _companyController.text.trim();
    final mine = _mineController.text.trim();
    final batch = _batchController.text.trim();
    final source = _sourceController.text.trim();
    final user = _userController.text.trim();
    final weight = double.tryParse(_weightController.text.trim());

    if (company.isEmpty ||
        mine.isEmpty ||
        batch.isEmpty ||
        source.isEmpty ||
        user.isEmpty ||
        weight == null ||
        weight <= 0) {
      _message('Jaza taarifa zote kwa usahihi.');
      return;
    }

    try {
      await DatabaseHelper.instance.insertBatch({
        'company_id': company,
        'mine_id': mine,
        'batch_id': batch,
        'source_location': source,
        'current_location': source,
        'weight_kg': weight,
        'status': 'Imechimbwa',
        'created_at': DateTime.now().toIso8601String(),
        'sync_status': 'Pending',
      });

      _batchController.clear();
      _sourceController.clear();
      _weightController.clear();

      await _loadBatches();
      _message('Batch imesajiliwa kikamilifu.');
    } catch (e) {
      _message('Batch haijasajiliwa. Hakikisha Batch ID haijatumika.');
    }
  }

  Future<void> _moveBatch(Map<String, dynamic> batch) async {
    final locationController = TextEditingController();
    final userController = TextEditingController();
    final weightController = TextEditingController(
      text: '${batch['weight_kg']}',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Hamisha Batch ${batch['batch_id']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Eneo la sasa: ${batch['current_location']}'),
              const SizedBox(height: 12),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: 'Eneo jipya',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: weightController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Uzito (KG)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: userController,
                decoration: const InputDecoration(
                  labelText: 'Aliyehamisha',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Ghairi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hamisha'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await DatabaseHelper.instance.moveBatch(
          companyId: _companyController.text.trim(),
          batchId: batch['batch_id'] as String,
          toLocation: locationController.text.trim(),
          weightKg: double.parse(weightController.text.trim()),
          movedBy: userController.text.trim(),
        );

        await _loadBatches();
        _message('Uhamisho umerekodiwa.');
      } catch (e) {
        _message('Uhamisho umeshindikana: $e');
      }
    }

    locationController.dispose();
    userController.dispose();
    weightController.dispose();
  }

  Future<void> _showHistory(Map<String, dynamic> batch) async {
    final history = await DatabaseHelper.instance.getBatchHistory(
      companyId: _companyController.text.trim(),
      batchId: batch['batch_id'] as String,
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Historia: ${batch['batch_id']}'),
        content: SizedBox(
          width: double.maxFinite,
          child: history.isEmpty
              ? const Text('Hakuna historia ya uhamisho bado.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final item = history[index];
                    return ListTile(
                      leading: const Icon(Icons.swap_horiz),
                      title: Text(
                        '${item['from_location']} → ${item['to_location']}',
                      ),
                      subtitle: Text(
                        '${item['weight_kg']} KG\n'
                        'Aliyehamisha: ${item['moved_by']}\n'
                        '${item['movement_date']}',
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Funga'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _companyController.dispose();
    _mineController.dispose();
    _batchController.dispose();
    _sourceController.dispose();
    _weightController.dispose();
    _userController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ore & Batch Tracking'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Taarifa za kampuni na mgodi',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _companyController,
            decoration: const InputDecoration(
              labelText: 'Company ID',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _loadBatches(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _mineController,
            decoration: const InputDecoration(
              labelText: 'Mine ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Sajili Batch mpya',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _batchController,
            decoration: const InputDecoration(
              labelText: 'Batch ID ya kipekee',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _sourceController,
            decoration: const InputDecoration(
              labelText: 'Eneo ilikotoka',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Uzito (KG)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _userController,
            decoration: const InputDecoration(
              labelText: 'Aliyesajili',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _registerBatch,
            icon: const Icon(Icons.add),
            label: const Text('Sajili Batch'),
          ),
          const Divider(height: 32),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Batch za kampuni',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: _loadBatches,
                icon: const Icon(Icons.refresh),
                tooltip: 'Onyesha upya',
              ),
            ],
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_batches.isEmpty)
            const Text('Hakuna Batch zilizosajiliwa.')
          else
            ..._batches.map(
              (batch) => Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text('Batch: ${batch['batch_id']}'),
                  subtitle: Text(
                    'Mgodi: ${batch['mine_id']}\n'
                    'Eneo: ${batch['current_location']}\n'
                    'Uzito: ${batch['weight_kg']} KG\n'
                    'Hali: ${batch['status']}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'move') _moveBatch(batch);
                      if (value == 'history') _showHistory(batch);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'move',
                        child: Text('Hamisha'),
                      ),
                      PopupMenuItem(
                        value: 'history',
                        child: Text('Historia'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
