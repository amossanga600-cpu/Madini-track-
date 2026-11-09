import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'utils.dart';

class ProductionPage extends StatefulWidget {
  const ProductionPage({super.key});

  @override
  State<ProductionPage> createState() => _ProductionPageState();
}

class _ProductionPageState extends State<ProductionPage> {
  final _periods = standardPeriods();
  int _sel = 2;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = _periods[_sel];
    final rows = await DatabaseHelper.instance.getProductionRecords(
      from: p.from,
      to: p.to,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _void(Map<String, dynamic> r) async {
    final reason = await askReason(context, 'Futa rekodi ya ${r['batch_id']}?');
    if (reason == null) return;
    try {
      await DatabaseHelper.instance.voidProduction(r['uuid'] as String, reason);
      if (!mounted) return;
      snack(context, 'Rekodi imefutwa (inabaki kwenye historia).');
      await _load();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _rows.where((r) => intv(r['voided']) == 0).toList();
    final totalKg = active.fold<double>(0, (s, r) => s + dbl(r['weight_kg']));
    final totalBags = active.fold<int>(0, (s, r) => s + intv(r['bags_count']));

    return Scaffold(
      appBar: AppBar(title: const Text('Uzalishaji')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
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
                    label: 'Uzito jumla',
                    value: fmtKg(totalKg),
                    icon: Icons.scale,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    label: 'Magunia',
                    value: '$totalBags',
                    icon: Icons.shopping_bag_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_rows.isEmpty)
              const EmptyCard('Hakuna rekodi kwa kipindi hiki.')
            else
              for (final r in _rows)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: Text(
                      'Batch ${r['batch_id']}  •  ${fmtKg(dbl(r['weight_kg']))}',
                      style: intv(r['voided']) == 1 ? VoidedStyle.title : null,
                    ),
                    subtitle: Text(
                      '${shortDate(r['shift_date'])} • ${r['shift_type']} • '
                      'Magunia ${r['bags_count']}\n'
                      'Eneo: ${r['shaft_area']}'
                      '${r['estimated_grade'] == null ? '' : ' • ${fmtNum(dbl(r['estimated_grade']))} g/t'}\n'
                      'Aliyeingiza: ${r['recorded_by']}'
                      '${(r['witness'] ?? '').toString().isEmpty ? '' : ' • Shahidi: ${r['witness']}'}'
                      '${intv(r['voided']) == 1 ? '\nImefutwa: ${r['void_reason']}' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: intv(r['voided']) == 1
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (_) => _void(r),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'void',
                                child: Text('Futa kwa sababu'),
                              ),
                            ],
                          ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
