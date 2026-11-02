import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'module_hub.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MadiniTrackApp());
}

class MadiniTrackApp extends StatelessWidget {
  const MadiniTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Madini Track Tanzania',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
        ),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _formKey = GlobalKey<FormState>();

  final _companyController = TextEditingController();
  final _mineController = TextEditingController();
  final _shaftController = TextEditingController();
  final _batchController = TextEditingController();
  final _bagsController = TextEditingController();
  final _weightController = TextEditingController();
  final _gradeController = TextEditingController();
  final _authorController = TextEditingController();

  String _shiftType = 'Mchana';

  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    try {
      final records = await DatabaseHelper.instance.getAllRecords();

      if (!mounted) return;

      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);
      _showMessage('Imeshindikana kusoma database: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final row = <String, dynamic>{
      'company_id': _companyController.text.trim(),
      'mine_id': _mineController.text.trim(),
      'shaft_area': _shaftController.text.trim(),
      'batch_id': _batchController.text.trim(),
      'shift_date': DateTime.now().toIso8601String().split('T')[0],
      'shift_type': _shiftType,
      'bags_count': int.parse(_bagsController.text.trim()),
      'weight_kg': double.parse(_weightController.text.trim()),
      'estimated_grade': _gradeController.text.trim().isEmpty
          ? null
          : double.parse(_gradeController.text.trim()),
      'recorded_by': _authorController.text.trim(),
      'sync_status': 'Pending',
      'created_at': DateTime.now().toIso8601String(),
    };

    try {
      await DatabaseHelper.instance.insertProductionRecord(row);

      if (!mounted) return;

      _batchController.clear();
      _bagsController.clear();
      _weightController.clear();
      _gradeController.clear();

      _showMessage('Rekodi imehifadhiwa kwenye simu.');

      await _loadRecords();
    } catch (e) {
      if (!mounted) return;

      if (e.toString().contains('UNIQUE constraint failed')) {
        _showMessage(
          'Batch ID hii tayari imetumika kwenye kampuni hii.',
        );
      } else {
        _showMessage('Hitilafu wakati wa kuhifadhi: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          final text = value?.trim() ?? '';

          if (required && text.isEmpty) {
            return 'Jaza sehemu hii';
          }

          if (text.isNotEmpty &&
              keyboardType == TextInputType.number &&
              int.tryParse(text) == null) {
            return 'Weka namba kamili';
          }

          return null;
        },
      ),
    );
  }

  Widget _decimalField(
    String label,
    TextEditingController controller, {
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          final text = value?.trim() ?? '';

          if (required && text.isEmpty) {
            return 'Jaza sehemu hii';
          }

          if (text.isNotEmpty) {
            final number = double.tryParse(text);

            if (number == null || number < 0) {
              return 'Weka namba sahihi';
            }
          }

          return null;
        },
      ),
    );
  }

  @override
  void dispose() {
    _companyController.dispose();
    _mineController.dispose();
    _shaftController.dispose();
    _batchController.dispose();
    _bagsController.dispose();
    _weightController.dispose();
    _gradeController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        _records.where((record) => record['sync_status'] == 'Pending').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Madini Track Tanzania'),
        actions: [
          IconButton(
            tooltip: 'Modules',
            icon: const Icon(Icons.apps),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ModuleHub(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecords,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Uingizaji wa Uzalishaji',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _field('Company ID', _companyController),
                          _field('Mine ID', _mineController),
                          _field('Shaft / Eneo', _shaftController),
                          _field('Batch ID', _batchController),
                          _field(
                            'Idadi ya magunia',
                            _bagsController,
                            keyboardType: TextInputType.number,
                          ),
                          _decimalField(
                            'Uzito (KG)',
                            _weightController,
                          ),
                          _decimalField(
                            'Estimated Grade (g/t)',
                            _gradeController,
                            required: false,
                          ),
                          _field('Aliyeingiza rekodi', _authorController),
                          DropdownButtonFormField<String>(
                            initialValue: _shiftType,
                            decoration: const InputDecoration(
                              labelText: 'Zamu',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Mchana',
                                child: Text('Mchana'),
                              ),
                              DropdownMenuItem(
                                value: 'Usiku',
                                child: Text('Usiku'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _shiftType = value);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _saveRecord,
                              icon: const Icon(Icons.save),
                              label: Text(
                                _saving ? 'Inahifadhi...' : 'Hifadhi Rekodi',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.cloud_off,
                  color: Colors.orange,
                ),
                title: const Text('Rekodi zinazosubiri sync'),
                trailing: Text(
                  '$pendingCount',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Rekodi Zilizohifadhiwa',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_records.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Bado hakuna rekodi.'),
                ),
              )
            else
              ..._records.map((record) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: Text('Batch: ${record['batch_id']}'),
                    subtitle: Text(
                      'Mgodi: ${record['mine_id']}\n'
                      'Uzito: ${record['weight_kg']} KG',
                    ),
                    isThreeLine: true,
                    trailing: const Text(
                      'Pending',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
