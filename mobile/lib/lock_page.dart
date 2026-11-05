import 'package:flutter/material.dart';
import 'app_context.dart';
import 'database_helper.dart';

/// Hash rahisi ya PIN yenye chumvi (salt). Ni kizuizi cha kufungua app,
/// si usimbaji wa data ndani ya database.
String hashPin(String pin, String salt) {
  var h = 0xcbf29ce484222325;
  final input = '$salt:$pin';
  for (var round = 0; round < 5000; round++) {
    for (final u in input.codeUnits) {
      h ^= u;
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
    }
  }
  return h.toRadixString(16);
}

Future<void> savePin(String pin) async {
  final salt = DateTime.now().microsecondsSinceEpoch.toString();
  final db = DatabaseHelper.instance;
  await db.setSetting('pin_salt', salt);
  await db.setSetting('pin_hash', hashPin(pin, salt));
  AppCtx.hasPin = true;
}

Future<void> removePin() async {
  final db = DatabaseHelper.instance;
  await db.deleteSetting('pin_salt');
  await db.deleteSetting('pin_hash');
  AppCtx.hasPin = false;
}

Future<bool> verifyPin(String pin) async {
  final db = DatabaseHelper.instance;
  final salt = await db.getSetting('pin_salt');
  final hash = await db.getSetting('pin_hash');
  if (salt == null || hash == null) return true;
  return hashPin(pin, salt) == hash;
}

/// Inafunika app kwa PIN ikiwa imewekwa, na kufunga tena baada ya app
/// kukaa nyuma kwa zaidi ya dakika moja.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  late bool _locked;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    _locked = AppCtx.hasPin;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final p = _pausedAt;
      if (AppCtx.hasPin &&
          p != null &&
          DateTime.now().difference(p).inSeconds > 60) {
        setState(() => _locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locked && AppCtx.hasPin) {
      return LockScreen(onUnlock: () => setState(() => _locked = false));
    }
    return widget.child;
  }
}

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlock;
  const LockScreen({super.key, required this.onUnlock});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pin = TextEditingController();
  String? _error;
  int _fails = 0;
  DateTime? _blockedUntil;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final b = _blockedUntil;
    if (b != null && DateTime.now().isBefore(b)) {
      setState(() => _error = 'Subiri kidogo kabla ya kujaribu tena.');
      return;
    }

    final ok = await verifyPin(_pin.text.trim());
    if (!mounted) return;

    if (ok) {
      widget.onUnlock();
      return;
    }

    _fails++;
    _pin.clear();
    if (_fails >= 5) {
      _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
      _fails = 0;
      setState(() => _error = 'Umekosea mara nyingi. Subiri sekunde 30.');
    } else {
      setState(() => _error = 'PIN si sahihi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Colors.orange),
                const SizedBox(height: 12),
                Text('Madini Track',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 8,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Weka PIN',
                      border: const OutlineInputBorder(),
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _submit, child: const Text('Fungua')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
