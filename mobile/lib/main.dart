import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'sync_service.dart';

void main() {
  runApp(const MadiniTrackApp());
}

class MadiniTrackApp extends StatelessWidget {
  const MadiniTrackApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Madini Track Tanzania',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List> _unsyncedRecords = [];
  bool _loading = false;

  final _companyController = TextEditingController(text: 'SIMO-001');
  final _mineController = TextEditingController(text: 'Mine-Iringa-A');
  final _shaftController = TextEditingController(text: 'Shaft 2');
  final _batchController = TextEditingController(text: 'BATCH-2026-001');
  final _bagsController = TextEditingController(text: '50');
  final _weightController = TextEditingController(text: '1250.5');
  final _gradeController = TextEditingController(text: '14.2');
  final _authorController = TextEditingController(text: 'Amosi Sanga');

  @override
  void initState() {
    super.initState();
    _loadUnsyncedRecords();
    _tryAutoSync(); // Jaribu kusawazisha moja kwa moja ikianza
  }

  Future<void> _loadUnsyncedRecords() async {
    setState(() => _loading = true);
    final records = await DatabaseHelper.instance.getUnsyncedRecords();
    setState(() {
      _unsyncedRecords = records;
      _loading = false;
    });
  }

  // Auto-Sync ya kimya kimya
  Future<void> _tryAutoSync() async {
    try {
      await SyncService.syncRecords();
      await _loadUnsyncedRecords();
    } catch (_) {
      // Kama hakuna mtandao, ikae kimya bila kusumbua mtumiaji
    }
  }

  Future<void> _saveRecord() async {
    Map<String, dynamic> row = {
      'company_id': _companyController.text,
      'mine_id': _mineController.text,
      'shaft_area': _shaftController.text,
      'batch_id': _batchController.text,
      'shift_date': DateTime.now().toIso8601String().split('T')[0],
      'shift_type': 'Mchana',
      'bags_count': int.tryParse(_bagsController.text) ?? 0,
      'weight_kg': double.tryParse(_weightController.text) ?? 0.0,
      'estimated_grade': double.tryParse(_gradeController.text)гө 0.0,
      'recorded_by': _authorController.text,
      'sync_status': 'Pending',
    };

    await DatabaseHelper.instance.insertRecord(row);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Imetunzwa kwenye simu! Inajaribu kutuma...')),
    );
    
    await _loadUnsyncedRecords();
    
    // Jaribu kutuma mara moja kwenye seva
    await _tryAutoSync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Madini Track Tanzania (Auto-Sync)'),
        backgroundColor: Colors.orange[800],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Uingizaji wa Uzalishaji (Offline-First)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(controller: _companyController, decoration: const InputDecoration(labelText: 'Company ID')),
                    TextField(controller: _mineController, decoration: const InputDecoration(labelText: 'Mine ID')),
                    TextField(controller: _shaftController, decoration: const InputDecoration(labelText: 'Shaft Area')),
                    TextField(controller: _batchController, decoration: const InputDecoration(labelText: 'Batch ID')),
                    TextField(controller: _bagsController, decoration: const InputDecoration(labelText: 'Idadi ya Magunia'), keyboardType: TextInputType.number),
                    TextField(controller: _weightController, decoration: const InputDecoration(labelText: 'Uzito (KG)'), keyboardType: TextInputType.number),
                    TextField(controller: _gradeController, decoration: const InputDecoration(labelText: 'Estimated Grade'), keyboardType: TextInputType.number),
                    TextField(controller: _authorController, decoration: const InputDecoration(labelText: 'Recorded By')),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _saveRecord,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Hifadhi na Tuma Kiotomatiki'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Hali ya Rekodi Zinazosubiri Mtandao (Pending)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _unsyncedRecords.isEmpty
                    ? const Card(child: Padding(padding: EdgeInsets.all(16.0), child: Text('Rekodi zote zimeshasawazishwa na seva kikamilifu!')))
                    : Column(
                        children: _unsyncedRecords.map((record) {
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.sync_problem, color: Colors.orange),
                              title: Text('Batch: ${record['batch_id']}'),
                              subtitle: Text('Mgodi: ${record['mine_id']} | Uzito: ${record['weight_kg']} KG'),
                              trailing: const Text(
                                'Pending',
                                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
          ],
        ),
      ),
    );
  }
}
