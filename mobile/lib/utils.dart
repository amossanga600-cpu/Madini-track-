import 'dart:math';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Makosa ya programu (ujumbe unaonyeshwa moja kwa moja kwa mtumiaji)
// ---------------------------------------------------------------------------
class AppError implements Exception {
  final String message;
  AppError(this.message);

  @override
  String toString() => message;
}

String errText(Object e) {
  if (e is AppError) return e.message;
  final s = e.toString();
  if (s.contains('UNIQUE constraint failed')) {
    return 'Rekodi hii (au ID hii) tayari ipo.';
  }
  return s.replaceFirst('Exception: ', '');
}

// ---------------------------------------------------------------------------
// UUID, tarehe na namba
// ---------------------------------------------------------------------------
String newUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
      '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

String nowIso() => DateTime.now().toIso8601String();

String dateStr(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String todayStr() => dateStr(DateTime.now());

String nextDay(String d) {
  final dt = DateTime.tryParse(d) ?? DateTime.now();
  return dateStr(DateTime(dt.year, dt.month, dt.day + 1));
}

String shortDate(dynamic v) {
  final s = (v ?? '').toString();
  return s.length >= 10 ? s.substring(0, 10) : s;
}

double dbl(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

double? parseNum(String? s) {
  if (s == null) return null;
  final t = s.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

String fmtNum(num? v, {int decimals = 2}) {
  if (v == null) return '-';
  final fixed = v.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final neg = parts[0].startsWith('-');
  final intPart = neg ? parts[0].substring(1) : parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  final res =
      parts.length > 1 ? '${buf.toString()}.${parts[1]}' : buf.toString();
  return neg ? '-$res' : res;
}

String fmtMoney(num? v) => 'TSh ${fmtNum(v, decimals: 0)}';
String fmtKg(num? v) => '${fmtNum(v)} kg';
String fmtG(num? v) => '${fmtNum(v)} g';

// ---------------------------------------------------------------------------
// Hesabu za biashara (zinajaribiwa kwenye test/)
// ---------------------------------------------------------------------------
double gradeGpt(double goldG, double oreKg) =>
    oreKg <= 0 ? 0 : goldG / (oreKg / 1000);

double? recoveryPercent(double actualGpt, double? estimatedGpt) {
  if (estimatedGpt == null || estimatedGpt <= 0) return null;
  return actualGpt / estimatedGpt * 100;
}

double calcPay(String payType, double rate, int daysPresent) {
  if (payType == 'Siku') return rate * daysPresent;
  if (payType == 'Mwezi') return rate;
  return 0; // Mgawo: kiasi kinaingizwa kwa mkono
}

class SaleCalc {
  final double fineGold;
  final double gross;
  final double royalty;
  final double inspection;
  final double otherFees;
  final double net;

  const SaleCalc(this.fineGold, this.gross, this.royalty, this.inspection,
      this.otherFees, this.net);
}

SaleCalc calcSale({
  required double weightG,
  required double purityPct,
  required double pricePerG,
  required double royaltyPct,
  required double inspectionPct,
  double otherFees = 0,
}) {
  final fine = weightG * purityPct / 100;
  final gross = fine * pricePerG;
  final royalty = gross * royaltyPct / 100;
  final inspection = gross * inspectionPct / 100;
  final net = gross - royalty - inspection - otherFees;
  return SaleCalc(fine, gross, royalty, inspection, otherFees, net);
}

String toCsv(List<Map<String, dynamic>> rows, List<String> cols) {
  String esc(dynamic v) {
    final s = (v ?? '').toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  final b = StringBuffer()..writeln(cols.join(','));
  for (final r in rows) {
    b.writeln(cols.map((c) => esc(r[c])).join(','));
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Orodha za chaguo
// ---------------------------------------------------------------------------
const List<String> kIncomeCategories = [
  'Mauzo ya Dhahabu',
  'Mauzo Mengine',
  'Mkopo Uliopokelewa',
  'Mapato Mengine',
];

const List<String> kExpenseCategories = [
  'Mishahara',
  'Mafuta',
  'Vifaa na Zana',
  'Chakula',
  'Usafiri',
  'Kemikali',
  'Vilipuzi',
  'Matengenezo',
  'Ada na Kodi',
  'Uchakataji',
  'Mrabaha na Ada',
  'Malipo ya Deni',
  'Matumizi Mengine',
];

const List<String> kPayMethods = [
  'Pesa taslimu',
  'M-Pesa',
  'Tigo Pesa',
  'Airtel Money',
  'Benki',
  'Nyingine',
];

const List<String> kInventoryCategories = [
  'Mafuta',
  'Zana na Vifaa',
  'Kemikali',
  'Vilipuzi',
  'Chakula',
  'Nyingine',
];

List<Opt> optsOf(List<String> items) => items.map((e) => Opt(e, e)).toList();

// ---------------------------------------------------------------------------
// Vipindi vya ripoti
// ---------------------------------------------------------------------------
class Period {
  final String label;
  final String? from;
  final String? to;
  const Period(this.label, this.from, this.to);
}

List<Period> standardPeriods() {
  final now = DateTime.now();
  final today = dateStr(now);
  final weekStart = dateStr(now.subtract(Duration(days: now.weekday - 1)));
  final monthStart = dateStr(DateTime(now.year, now.month, 1));
  final prevStart = dateStr(DateTime(now.year, now.month - 1, 1));
  final prevEnd = dateStr(DateTime(now.year, now.month, 0));
  return [
    Period('Leo', today, today),
    Period('Wiki hii', weekStart, today),
    Period('Mwezi huu', monthStart, today),
    Period('Mwezi uliopita', prevStart, prevEnd),
    const Period('Yote', null, null),
  ];
}

class PeriodBar extends StatelessWidget {
  final List<Period> periods;
  final int selected;
  final ValueChanged<int> onChanged;

  const PeriodBar({
    super.key,
    required this.periods,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < periods.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(periods[i].label),
                selected: i == selected,
                onSelected: (_) => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vifaa vidogo vya UI
// ---------------------------------------------------------------------------
void snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String body, {
  String yes = 'Ndiyo',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Hapana'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Inauliza sababu (lazima) kabla ya kufuta/kubatilisha rekodi.
Future<String?> askReason(BuildContext context, String title) async {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Sababu (lazima)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Ghairi'),
        ),
        FilledButton(
          onPressed: () {
            final t = c.text.trim();
            if (t.length >= 3) Navigator.pop(ctx, t);
          },
          child: const Text('Thibitisha'),
        ),
      ],
    ),
  );
}

Future<String?> pickDateStr(BuildContext context, String initial) async {
  final init = DateTime.tryParse(initial) ?? DateTime.now();
  final d = await showDatePicker(
    context: context,
    initialDate: init,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
  return d == null ? null : dateStr(d);
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: c),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
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

class EmptyCard extends StatelessWidget {
  final String text;
  const EmptyCard(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text),
      ),
    );
  }
}

class KV extends StatelessWidget {
  final String k;
  final String v;
  final bool bold;
  const KV(this.k, this.v, {super.key, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(k, style: style)),
          const SizedBox(width: 8),
          Flexible(child: Text(v, style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class VoidedStyle {
  static const TextStyle title = TextStyle(
    decoration: TextDecoration.lineThrough,
    color: Colors.grey,
  );
}

// ---------------------------------------------------------------------------
// Fomu ya jumla inayojengwa kutoka kwenye orodha ya fields
// ---------------------------------------------------------------------------
enum FType { text, password, integer, decimal, dropdown, date, multiline }

class Opt {
  final String value;
  final String label;
  const Opt(this.value, this.label);
}

class FSpec {
  final String key;
  final String label;
  final FType type;
  final bool required;
  final List<Opt> options;
  final String? initial;
  final String? hint;

  const FSpec(
    this.key,
    this.label, {
    this.type = FType.text,
    this.required = true,
    this.options = const [],
    this.initial,
    this.hint,
  });
}

class SpecForm extends StatefulWidget {
  final List<FSpec> fields;
  final Future<void> Function(Map<String, String> values) onSubmit;
  final String submitLabel;
  final String Function(Map<String, String> values)? preview;
  final VoidCallback? onSaved;

  const SpecForm({
    super.key,
    required this.fields,
    required this.onSubmit,
    this.submitLabel = 'Hifadhi',
    this.preview,
    this.onSaved,
  });

  @override
  State<SpecForm> createState() => _SpecFormState();
}

class _SpecFormState extends State<SpecForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = {};
  final Map<String, String> _dd = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      if (f.type == FType.dropdown) {
        if (f.options.isEmpty) {
          _dd[f.key] = '';
        } else {
          final has = f.options.any((o) => o.value == f.initial);
          _dd[f.key] = has ? f.initial! : f.options.first.value;
        }
      } else {
        final ctrl = TextEditingController(
          text: f.initial ??
              (f.type == FType.date && f.required ? todayStr() : ''),
        );
        if (widget.preview != null) {
          ctrl.addListener(() {
            if (mounted) setState(() {});
          });
        }
        _c[f.key] = ctrl;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _values() {
    final m = <String, String>{};
    for (final f in widget.fields) {
      m[f.key] = f.type == FType.dropdown
          ? (_dd[f.key] ?? '')
          : _c[f.key]!.text.trim();
    }
    return m;
  }

  String? _validate(FSpec f, String? v) {
    final t = (v ?? '').trim();
    if (f.required && t.isEmpty) return 'Jaza sehemu hii';
    if (t.isEmpty) return null;
    if (f.type == FType.integer && int.tryParse(t) == null) {
      return 'Weka namba kamili';
    }
    if (f.type == FType.decimal) {
      final n = parseNum(t);
      if (n == null || n < 0) return 'Weka namba sahihi';
    }
    return null;
  }

  Future<void> _submit() async {
    for (final f in widget.fields) {
      if (f.type == FType.dropdown && f.required && f.options.isEmpty) {
        setState(
            () => _error = 'Hakuna chaguo la "${f.label}". Ongeza kwanza.');
        return;
      }
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.onSubmit(_values());
      if (!mounted) return;
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildField(FSpec f) {
    final label = f.required ? f.label : '${f.label} (hiari)';

    switch (f.type) {
      case FType.dropdown:
        if (f.options.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: f.label,
              border: const OutlineInputBorder(),
              errorText:
                  f.required ? 'Hakuna chaguo lililopo. Ongeza kwanza.' : null,
            ),
            child: const Text('-'),
          );
        }
        return DropdownButtonFormField<String>(
          initialValue: _dd[f.key],
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          items: f.options
              .map((o) => DropdownMenuItem<String>(
                    value: o.value,
                    child: Text(o.label, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _dd[f.key] = v);
          },
        );

      case FType.date:
        return TextFormField(
          controller: _c[f.key],
          readOnly: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          validator: (v) => _validate(f, v),
          onTap: () async {
            final d = await pickDateStr(context, _c[f.key]!.text);
            if (d != null) _c[f.key]!.text = d;
          },
        );

      case FType.integer:
        return TextFormField(
          controller: _c[f.key],
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: label,
            hintText: f.hint,
            border: const OutlineInputBorder(),
          ),
          validator: (v) => _validate(f, v),
        );

      case FType.decimal:
        return TextFormField(
          controller: _c[f.key],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            hintText: f.hint,
            border: const OutlineInputBorder(),
          ),
          validator: (v) => _validate(f, v),
        );

      case FType.multiline:
        return TextFormField(
          controller: _c[f.key],
          minLines: 2,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: label,
            hintText: f.hint,
            border: const OutlineInputBorder(),
          ),
          validator: (v) => _validate(f, v),
        );

      case FType.text:
        return TextFormField(
          controller: _c[f.key],
          decoration: InputDecoration(
            labelText: label,
            hintText: f.hint,
            border: const OutlineInputBorder(),
          ),
          validator: (v) => _validate(f, v),
        );

      case FType.password:
        return TextFormField(
          controller: _c[f.key],
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: label,
            hintText: f.hint,
            border: const OutlineInputBorder(),
          ),
          validator: (v) => _validate(f, v),
        );
    }
  }

  String _previewText() {
    try {
      return widget.preview!(_values());
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewText = widget.preview == null ? '' : _previewText();

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildField(f),
            ),
          if (previewText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                color: Colors.orange.shade50,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(previewText),
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Inahifadhi...' : widget.submitLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inafungua fomu kwenye bottom sheet. Inarudisha true ikihifadhiwa.
Future<bool> showSpecSheet(
  BuildContext context, {
  required String title,
  required List<FSpec> fields,
  required Future<void> Function(Map<String, String> values) onSubmit,
  String submitLabel = 'Hifadhi',
  String Function(Map<String, String> values)? preview,
  String? note,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(note),
              ),
            const SizedBox(height: 16),
            SpecForm(
              fields: fields,
              onSubmit: onSubmit,
              submitLabel: submitLabel,
              preview: preview,
              onSaved: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    ),
  );
  return r ?? false;
}

int intv(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}
