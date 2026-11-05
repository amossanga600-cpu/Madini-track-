import 'package:flutter/material.dart';
import 'app_context.dart';
import 'database_helper.dart';
import 'db_modules.dart';
import 'utils.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _periods = standardPeriods();
  int _sel = 2;
  List<Map<String, dynamic>> _rows = [];
  double _balance = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final p = _periods[_sel];
    final rows = await db.getSales(from: p.from, to: p.to);
    final bal = await db.goldBalance();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _balance = bal;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final ok = await showSpecSheet(
      context,
      title: 'Rekodi Mauzo ya Dhahabu',
      note: 'Dhahabu iliyopo: ${fmtG(_balance)}. Mrabaha ${fmtNum(AppCtx.royaltyPercent)}% '
          'na ada ya ukaguzi ${fmtNum(AppCtx.inspectionPercent)}% '
          '(unaweza kubadilisha kwenye Mipangilio).',
      fields: [
        const FSpec('date', 'Tarehe ya mauzo', type: FType.date),
        const FSpec('buyer', 'Mnunuzi'),
        const FSpec('license', 'Namba ya leseni ya mnunuzi', required: false),
        const FSpec('weight', 'Uzito wa dhahabu (gramu)', type: FType.decimal),
        const FSpec('purity', 'Purity (%)',
            type: FType.decimal, initial: '90'),
        const FSpec('price', 'Bei kwa gramu ya dhahabu safi (TSh)',
            type: FType.decimal),
        const FSpec('fees', 'Ada nyingine (TSh)',
            type: FType.decimal, required: false, initial: '0'),
        FSpec('method', 'Njia ya malipo',
            type: FType.dropdown, options: optsOf(kPayMethods)),
        const FSpec('reference', 'Namba ya risiti / rejea', required: false),
        FSpec('witness', 'Shahidi (mtu wa pili)', required: AppCtx.requireWitness),
        const FSpec('notes', 'Maelezo', type: FType.multiline, required: false),
      ],
      preview: (v) {
        final w = parseNum(v['weight']);
        final pu = parseNum(v['purity']);
        final pr = parseNum(v['price']);
        if (w == null || pu == null || pr == null || w <= 0 || pu <= 0) return '';
        final c = calcSale(
          weightG: w,
          purityPct: pu,
          pricePerG: pr,
          royaltyPct: AppCtx.royaltyPercent,
          inspectionPct: AppCtx.inspectionPercent,
          otherFees: parseNum(v['fees']) ?? 0,
        );
        return 'Dhahabu safi: ${fmtG(c.fineGold)}\n'
            'Jumla: ${fmtMoney(c.gross)}\n'
            'Mrabaha: ${fmtMoney(c.royalty)} • Ukaguzi: ${fmtMoney(c.inspection)}\n'
            'Utakachopokea (net): ${fmtMoney(c.net)}';
      },
      onSubmit: (v) => DatabaseHelper.instance.recordSale(
        saleDate: v['date']!,
        buyer: v['buyer']!,
        buyerLicense: v['license']!.isEmpty ? null : v['license'],
        weightG: parseNum(v['weight'])!,
        purityPct: parseNum(v['purity'])!,
        pricePerG: parseNum(v['price'])!,
        otherFees: parseNum(v['fees']) ?? 0,
        method: v['method']!,
        reference: v['reference']!.isEmpty ? null : v['reference'],
        witness: v['witness'],
        notes: v['notes']!.isEmpty ? null : v['notes'],
      ),
    );
    if (ok) {
      if (!mounted) return;
      snack(context, 'Mauzo yamehifadhiwa na kuingizwa kwenye Fedha.');
      await _load();
    }
  }

  Future<void> _void(Map<String, dynamic> s) async {
    final reason = await askReason(context, 'Futa mauzo ya ${s['buyer']}?');
    if (reason == null) return;
    try {
      await DatabaseHelper.instance.voidSale(s['uuid'] as String, reason);
      if (!mounted) return;
      snack(context, 'Mauzo yamefutwa na miamala yake ya Fedha.');
      await _load();
    } catch (e) {
      if (mounted) snack(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _rows.where((r) => intv(r['voided']) == 0).toList();
    final g = active.fold<double>(0, (s, r) => s + dbl(r['gold_weight_g']));
    final net = active.fold<double>(0, (s, r) => s + dbl(r['net_amount']));

    return Scaffold(
      appBar: AppBar(title: const Text('Mauzo')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.sell_outlined),
        label: const Text('Mauzo'),
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
                    label: 'Dhahabu iliyouzwa',
                    value: fmtG(g),
                    icon: Icons.diamond_outlined,
                    color: Colors.amber.shade800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    label: 'Net iliyopokelewa',
                    value: fmtMoney(net),
                    icon: Icons.payments_outlined,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.savings_outlined, color: Colors.orange),
                title: const Text('Dhahabu iliyopo (haijauzwa)'),
                trailing: Text(fmtG(_balance),
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_rows.isEmpty)
              const EmptyCard('Hakuna mauzo kwa kipindi hiki.')
            else
              for (final s in _rows)
                Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.sell_outlined),
                    title: Text(
                      '${s['buyer']}  •  ${fmtG(dbl(s['gold_weight_g']))}',
                      style: intv(s['voided']) == 1 ? VoidedStyle.title : null,
                    ),
                    subtitle: Text(
                      '${shortDate(s['sale_date'])} • Net ${fmtMoney(dbl(s['net_amount']))}',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      KV('Purity', '${fmtNum(dbl(s['purity_percent']))}%'),
                      KV('Bei kwa gramu', fmtMoney(dbl(s['price_per_g']))),
                      KV('Jumla', fmtMoney(dbl(s['gross_amount']))),
                      KV('Mrabaha (${fmtNum(dbl(s['royalty_percent']))}%)',
                          fmtMoney(dbl(s['royalty_amount']))),
                      KV('Ukaguzi (${fmtNum(dbl(s['inspection_percent']))}%)',
                          fmtMoney(dbl(s['inspection_amount']))),
                      KV('Ada nyingine', fmtMoney(dbl(s['other_fees']))),
                      KV('Net', fmtMoney(dbl(s['net_amount'])), bold: true),
                      KV('Malipo', '${s['payment_method'] ?? ''}'),
                      if ((s['buyer_license'] ?? '').toString().isNotEmpty)
                        KV('Leseni ya mnunuzi', '${s['buyer_license']}'),
                      if ((s['reference'] ?? '').toString().isNotEmpty)
                        KV('Rejea', '${s['reference']}'),
                      KV('Aliyeingiza', '${s['created_by'] ?? ''}'),
                      if ((s['witness'] ?? '').toString().isNotEmpty)
                        KV('Shahidi', '${s['witness']}'),
                      if (intv(s['voided']) == 1)
                        KV('Imefutwa', '${s['void_reason']}')
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => _void(s),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Futa kwa sababu'),
                          ),
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
