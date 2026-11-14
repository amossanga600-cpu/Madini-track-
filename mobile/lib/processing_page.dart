import 'package:flutter/material.dart';
import 'app_context.dart';
import 'database_helper.dart';
import 'evidence.dart';
import 'utils.dart';

const List<String> kProcessMethods = [
  'Gravity',
  'Amalgamation (Zebaki)',
  'CIL / Cyanide',
  'Nyingine',
];

/// Fomu ya uchakataji. Inatumika pia kutoka kwenye ukurasa wa Batch.
Future<bool> showProcessForm(BuildContext context, {String? batchId}) async {
  final db = DatabaseHelper.instance;
  final batches = await db.getAllBatches(onlyAvailable: true);

  if (batches.isEmpty) {
    if (context.mounted) {
      snack(context, 'Hakuna Batch yenye ore iliyobaki kuchakatwa.');
    }
    return false;
  }

  final estimates = <String, double?>{};
  final remaining = <String, double>{};
  for (final b in batches) {
    final id = b['batch_id'] as String;
    estimates[id] = await db.estimatedGradeForBatch(id);
    remaining[id] = dbl(b['weight_kg']);
  }
  if (!context.mounted) return false;

  final initial = (batchId != null && remaining.containsKey(batchId))
      ? batchId
      : batches.first['batch_id'] as String;

  return showSpecSheet(
    context,
    title: 'Chakata Batch',
    fields: [
      FSpec(
        'batch',
        'Batch',
        type: FType.dropdown,
        initial: initial,
        options: [
          for (final b in batches)
            Opt(
              b['batch_id'] as String,
              '${b['batch_id']} (${fmtNum(dbl(b['weight_kg']))} kg)',
            ),
        ],
      ),
      const FSpec('ore', 'Ore iliyochakatwa (KG)', type: FType.decimal),
      const FSpec('gold', 'Dhahabu iliyopatikana (gramu)', type: FType.decimal),
      const FSpec('tailings', 'Mabaki / Tailings (KG)', type: FType.decimal),
      const FSpec('purity', 'Purity ya dhahabu (%)',
          type: FType.decimal, required: false, hint: 'Mfano: 92'),
      FSpec('method', 'Njia ya uchakataji',
          type: FType.dropdown, options: optsOf(kProcessMethods)),
      const FSpec('mercury', 'Zebaki iliyotumika (gramu)',
          type: FType.decimal, required: false),
      const FSpec('cost', 'Gharama ya uchakataji (TSh)',
          type: FType.decimal, required: false),
      const FSpec('date', 'Tarehe', type: FType.date),
      FSpec('witness', 'Shahidi (mtu wa pili)',
          required: AppCtx.requireWitness),
      const FSpec('notes', 'Maelezo', type: FType.multiline, required: false),
    ],
    note:
        'Uzito wa Batch utapunguzwa kiotomatiki kulingana na ore iliyochakatwa.',
    preview: (v) {
      final ore = parseNum(v['ore']);
      final gold = parseNum(v['gold']);
      if (ore == null || ore <= 0 || gold == null) return '';
      final actual = gradeGpt(gold, ore);
      final est = estimates[v['batch']];
      final rec = recoveryPercent(actual, est);
      final left = (remaining[v['batch']] ?? 0) - ore;
      final b = StringBuffer('Grade halisi: ${fmtNum(actual)} g/t');
      if (est != null && rec != null) {
        b.write('\nMakadirio: ${fmtNum(est)} g/t  •  Dhahabu halisi/makadirio: '
            '${fmtNum(rec, decimals: 0)}%');
        if (rec < AppCtx.minRecoveryPercent) {
          b.write('\n⚠ Chini ya kiwango cha tahadhari '
              '(${fmtNum(AppCtx.minRecoveryPercent, decimals: 0)}%).');
        }
      }
      b.write('\nUtakachobaki kwenye Batch: ${fmtNum(left < 0 ? 0 : left)} kg');
      return b.toString();
    },
    onSubmit: (v) async {
      await db.processBatch(
        batchId: v['batch']!,
        oreProcessedKg: parseNum(v['ore'])!,
        goldRecoveredG: parseNum(v['gold'])!,
        tailingsKg: parseNum(v['tailings'])!,
        processingCost: parseNum(v['cost']) ?? 0,
        processingDate: v['date']!,
        method: v['method'],
        purityPercent: parseNum(v['purity']),
        mercuryG: parseNum(v['mercury']),
        witness: v['witness'],
        notes: (v['notes'] ?? '').isEmpty ? null : v['notes'],
      );
    },
  );
}

class ProcessingPage extends StatefulWidget {
  const ProcessingPage({super.key});

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage> {
  final _periods = standardPeriods();
  int _sel = 2;
  List<Map<String, dynamic>> _rows = [];
  final Map<String, double?> _est = {};
  double _goldBalance = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final p = _periods[_sel];
    final rows = await db.getProcessingRecords(from: p.from, to: p.to);
    _est.clear();
    for (final r in rows) {
      final id = r['batch_id'] as String;
      if (!_est.containsKey(id)) _est[id] = await db.estimatedGradeForBatch(id);
    }
    final bal = await db.goldBalance();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _goldBalance = bal;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final ok = await showProcessForm(context);
    if (ok) {
      if (!mounted) return;
      snack(context, 'Uchakataji umehifadhiwa.');
      await _load();
    }
  }

  Future<void> _void(Map<String, dynamic> r) async {
    final reason =
        await askReason(context, 'Futa uchakataji wa ${r['batch_id']}?');
    if (reason == null) return;
    try {
      await DatabaseHelper.instance.voidProcessing(r['uuid'] as String, reason);
      if (!mounted) return;
      snack(context, 'Uchakataji umefutwa na uzito umerudishwa kwenye Batch.');
      await _load();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _rows.where((r) => intv(r['voided']) == 0).toList();
    final totalGold =
        active.fold<double>(0, (s, r) => s + dbl(r['gold_recovered_g']));
    final totalOre =
        active.fold<double>(0, (s, r) => s + dbl(r['ore_processed_kg']));

    return Scaffold(
      appBar: AppBar(title: const Text('Processing & Gold Recovery')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.precision_manufacturing_outlined),
        label: const Text('Chakata'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            PeriodBar(
              periods: _periods,
              selected: _sel,
              onChanged: (i) {
                setState(() => _sel = i);
                _load();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Dhahabu kipindi hiki',
                    value: fmtG(totalGold),
                    icon: Icons.diamond_outlined,
                    color: Colors.amber.shade800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    label: 'Grade wastani',
                    value: '${fmtNum(gradeGpt(totalGold, totalOre))} g/t',
                    icon: Icons.analytics_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading:
                    const Icon(Icons.savings_outlined, color: Colors.orange),
                title: const Text('Dhahabu iliyopo (haijauzwa)'),
                trailing: Text(
                  fmtG(_goldBalance),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_rows.isEmpty)
              const EmptyCard('Hakuna uchakataji kwa kipindi hiki.')
            else
              for (final r in _rows) _tile(r),
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> r) {
    final voided = intv(r['voided']) == 1;
    final ore = dbl(r['ore_processed_kg']);
    final gold = dbl(r['gold_recovered_g']);
    final actual = gradeGpt(gold, ore);
    final rec = recoveryPercent(actual, _est[r['batch_id']]);
    final low = rec != null && rec < AppCtx.minRecoveryPercent;

    return Card(
      child: ListTile(
        leading: Icon(
          low && !voided
              ? Icons.warning_amber
              : Icons.precision_manufacturing_outlined,
          color: low && !voided ? Colors.red : null,
        ),
        title: Text(
          'Batch ${r['batch_id']}  •  ${fmtG(gold)}',
          style: voided ? VoidedStyle.title : null,
        ),
        subtitle: Text(
          '${shortDate(r['processing_date'])} • Ore ${fmtKg(ore)} • '
          'Mabaki ${fmtKg(dbl(r['tailings_kg']))}\n'
          'Grade ${fmtNum(actual)} g/t'
          '${rec == null ? '' : ' • ${fmtNum(rec, decimals: 0)}% ya makadirio'}'
          '${r['purity_percent'] == null ? '' : ' • Purity ${fmtNum(dbl(r['purity_percent']), decimals: 1)}%'}\n'
          '${(r['method'] ?? '').toString().isEmpty ? '' : '${r['method']} • '}'
          'Gharama ${fmtMoney(dbl(r['processing_cost']))}\n'
          'Aliyeingiza: ${r['processed_by']}'
          '${(r['witness'] ?? '').toString().isEmpty ? '' : ' • Shahidi: ${r['witness']}'}'
          '${voided ? '\nImefutwa: ${r['void_reason']}' : ''}',
        ),
        isThreeLine: true,
        trailing: voided
            ? null
            : PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'photo') {
                    showAttachSheet(
                        context, 'processing_records', r['uuid'] as String);
                  } else {
                    _void(r);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'photo',
                      child: Text('Piga picha (scale/dhahabu)')),
                  PopupMenuItem(value: 'void', child: Text('Futa kwa sababu')),
                ],
              ),
      ),
    );
  }
}
