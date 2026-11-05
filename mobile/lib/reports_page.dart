import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_context.dart';
import 'database_helper.dart';
import 'db_reports.dart';
import 'utils.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _periods = standardPeriods();
  int _sel = 2;
  bool _allMines = false;
  Map<String, dynamic>? _r;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = _periods[_sel];
    final r = await DatabaseHelper.instance.buildReport(
      from: p.from,
      to: p.to,
      allMines: _allMines,
    );
    if (!mounted) return;
    setState(() {
      _r = r;
      _loading = false;
    });
  }

  String get _scopeLabel => _allMines ? 'Mgodi yote' : 'Mgodi: ${AppCtx.mine}';

  Future<void> _copyReport() async {
    final text = DatabaseHelper.instance.reportToText(
      _r!,
      periodLabel: _periods[_sel].label,
      scopeLabel: _scopeLabel,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    snack(context, 'Ripoti imenakiliwa. Bandika WhatsApp au barua pepe.');
  }

  Future<void> _copyCsv(String kind) async {
    final p = _periods[_sel];
    final csv = await DatabaseHelper.instance.exportCsv(
      kind,
      from: p.from,
      to: p.to,
      allMines: _allMines,
    );
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    snack(context, 'CSV ya $kind imenakiliwa. Bandika kwenye Excel/Sheets.');
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.orange),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          if (r != null)
            IconButton(
              tooltip: 'Nakili ripoti',
              icon: const Icon(Icons.copy_all),
              onPressed: _copyReport,
            ),
          PopupMenuButton<String>(
            tooltip: 'Nakili CSV',
            icon: const Icon(Icons.table_chart_outlined),
            onSelected: _copyCsv,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'Uzalishaji', child: Text('CSV: Uzalishaji')),
              PopupMenuItem(value: 'Uchakataji', child: Text('CSV: Uchakataji')),
              PopupMenuItem(value: 'Fedha', child: Text('CSV: Fedha')),
              PopupMenuItem(value: 'Mauzo', child: Text('CSV: Mauzo')),
              PopupMenuItem(value: 'Mishahara', child: Text('CSV: Mishahara')),
              PopupMenuItem(value: 'Batch', child: Text('CSV: Mizania ya Batch')),
            ],
          ),
        ],
      ),
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
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text('Mgodi ${AppCtx.mine}')),
                const ButtonSegment(value: true, label: Text('Migodi yote')),
              ],
              selected: {_allMines},
              onSelectionChanged: (s) {
                setState(() => _allMines = s.first);
                _load();
              },
            ),
            const SizedBox(height: 12),
            if (_loading || r == null)
              const Center(child: CircularProgressIndicator())
            else
              ..._content(r),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> r) {
    final prod = r['prod'] as Map;
    final proc = r['proc'] as Map;
    final sales = r['sales'] as Map;
    final pay = r['payroll'] as Map;
    final oreKg = dbl(proc['ore']);
    final gold = dbl(proc['gold']);
    final income = dbl(r['income']);
    final expense = dbl(r['expense']);
    final fin = r['finance_rows'] as List;
    final batches = r['batches'] as List;
    final mismatch = batches.where((b) => b['mismatch'] == true).toList();
    final low = r['low_stock'] as List;

    return [
      _section('Uzalishaji', Icons.factory_outlined, [
        KV('Rekodi', '${intv(prod['n'])}'),
        KV('Magunia', '${intv(prod['bags'])}'),
        KV('Uzito', fmtKg(dbl(prod['kg'])), bold: true),
      ]),
      _section('Uchakataji', Icons.precision_manufacturing_outlined, [
        KV('Ore iliyochakatwa', fmtKg(oreKg)),
        KV('Dhahabu iliyopatikana', fmtG(gold), bold: true),
        KV('Grade halisi', '${fmtNum(gradeGpt(gold, oreKg))} g/t'),
        KV('Mabaki', fmtKg(dbl(proc['tailings']))),
        KV('Zebaki iliyotumika', fmtG(dbl(proc['mercury']))),
        KV('Gharama', fmtMoney(dbl(proc['cost']))),
      ]),
      _section('Mauzo', Icons.sell_outlined, [
        KV('Idadi ya mauzo', '${intv(sales['n'])}'),
        KV('Dhahabu', fmtG(dbl(sales['g']))),
        KV('Jumla', fmtMoney(dbl(sales['gross']))),
        KV('Mrabaha na ada', fmtMoney(dbl(sales['fees']))),
        KV('Net', fmtMoney(dbl(sales['net'])), bold: true),
      ]),
      _section('Fedha', Icons.account_balance_wallet_outlined, [
        KV('Mapato', fmtMoney(income)),
        KV('Matumizi', fmtMoney(expense)),
        KV('Salio', fmtMoney(income - expense), bold: true),
        if (fin.isNotEmpty) const SizedBox(height: 8),
        for (final f in fin)
          KV('${f['type'] == 'Mapato' ? '+' : '-'} ${f['category']}',
              fmtMoney(dbl(f['t']))),
        const SizedBox(height: 8),
        KV('Mishahara (${intv(pay['n'])} malipo)', fmtMoney(dbl(pay['net']))),
      ]),
      _section('Dhahabu na Mizania ya Batch', Icons.diamond_outlined, [
        KV('Dhahabu iliyopo (haijauzwa)', fmtG(dbl(r['gold_balance'])), bold: true),
        KV('Batch zinazofuatiliwa', '${batches.length}'),
        if (mismatch.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Mizania ya uzito wa Batch zote ni sawa.'),
          )
        else ...[
          const SizedBox(height: 6),
          Text(
            'Tahadhari: Batch ${mismatch.length} zina tofauti ya uzito.',
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          for (final b in mismatch)
            KV('${b['batch_id']}', '${fmtNum(dbl(b['diff']))} kg'),
        ],
      ]),
      if (low.isNotEmpty)
        _section('Vifaa Vinavyokaribia Kuisha', Icons.warning_amber, [
          for (final i in low)
            KV('${i['name']}', '${fmtNum(dbl(i['stock']))} ${i['unit']}'),
        ]),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: _copyReport,
        icon: const Icon(Icons.copy_all),
        label: const Text('Nakili Ripoti (WhatsApp / Email)'),
      ),
    ];
  }
}
