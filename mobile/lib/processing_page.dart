import 'package:flutter/material.dart';
import 'database_helper.dart';

class ProcessingPage extends StatefulWidget {
  const ProcessingPage({super.key});

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage> {
  final _company = TextEditingController();
  final _batch = TextEditingController();
  final _ore = TextEditingController();
  final _gold = TextEditingController();
  final _tailings = TextEditingController();
  final _cost = TextEditingController(text: '0');
  final _operator = TextEditingController();

  List<Map<String, dynamic>> _records = [];
  bool _saving = false;
  bool _loading = false;

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadRecords() async {
    final company = _company.text.trim();
    if (company.isEmpty) {
      _message('Weka Company ID kwanza.');
      return;
    }

    setState(() => _loading = true);

    try {
      final data = await DatabaseHelper.instance.getProcessingRecords(
        company,
      );

      if (!mounted) return;
      setState(() => _records = data);
    } catch (e) {
      _message('Imeshindikana kusoma rekodi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final company = _company.text.trim();
    final batch = _batch.text.trim();
    final operator = _operator.text.trim();

    final ore = double.tryParse(_ore.text.trim());
    final gold = double.tryParse(_gold.text.trim());
    final tailings = double.tryParse(_tailings.text.trim());
    final cost = double.tryParse(_cost.text.trim());

    if (company.isEmpty ||
        batch.isEmpty ||
        operator.isEmpty ||
        ore == null ||
        ore <= 0 ||
        gold == null ||
        gold < 0 ||
        tailings == null ||
        tailings < 0 ||
        cost == null ||
        cost < 0) {
      _message('Jaza taarifa zote kwa namba sahihi.');
      return;
    }

    setState(() => _saving = true);

    try {
      await DatabaseHelper.instance.processBatch(
        companyId: company,
        batchId: batch,
        oreProcessedKg: ore,
        goldRecoveredG: gold,
        tailingsKg: tailings,
        processingCost: cost,
        processingDate: DateTime.now().toIso8601String(),
        processedBy: operator,
      );

      _ore.clear();
      _gold.clear();
      _tailings.clear();
      _cost.text = '0';

      await _loadRecords();
      _message('Rekodi ya processing imehifadhiwa.');
    } catch (e) {
      _message('Imeshindikana: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _company.dispose();
    _batch.dispose();
    _ore.dispose();
    _gold.dispose();
    _tailings.dispose();
    _cost.dispose();
    _operator.dispose();
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool decimal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Processing & Gold Recovery')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Rekodi za uchakataji wa madini',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _field('Company ID', _company),
          _field('Batch ID', _batch),
          _field('Ore iliyochakatwa (KG)', _ore, decimal: true),
          _field('Gold recovered (gramu)', _gold, decimal: true),
          _field('Tailings (KG)', _tailings, decimal: true),
          _field('Gharama za processing', _cost, decimal: true),
          _field('Aliyechakata', _operator),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save),
            label: Text(_saving ? 'Inahifadhi...' : 'Hifadhi Processing'),
          ),
          const Divider(height: 32),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Historia ya uchakataji',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: _loadRecords,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_records.isEmpty)
            const Text('Hakuna rekodi za processing bado.')
          else
            ..._records.map(
              (record) => Card(
                child: ListTile(
                  leading: const Icon(Icons.precision_manufacturing),
                  title: Text('Batch: ${record['batch_id']}'),
                  subtitle: Text(
                    'Ore: ${record['ore_processed_kg']} KG\n'
                    'Gold recovered: ${record['gold_recovered_g']} g\n'
                    'Tailings: ${record['tailings_kg']} KG\n'
                    'Gharama: ${record['processing_cost']}',
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
