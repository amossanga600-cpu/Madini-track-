import 'package:http/http.dart' as http;
import 'dart:convert';
import 'database_helper.dart';

class SyncService {
  static const String frappeApiUrl = 'https://your-frappe-server.com/api/resource/Production Record';
  static const String apiToken = 'token apikey_hapa:secret_hapa';

  static Future<void> syncRecords() async {
    final dbHelper = DatabaseHelper.instance;
    List> pendingRecords = await dbHelper.getUnsyncedRecords();
    
    if (pendingRecords.isEmpty) {
      print('Hakuna rekodi zinazosubiri kusawazishwa.');
      return;
    }

    for (var record in pendingRecords) {
      try {
        final response = await http.post(
          Uri.parse(frappeApiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': apiToken,
          },
          body: jsonEncode({
            'company_id': record['company_id'],
            'mine_id': record['mine_id'],
            'shaft_area': record['shaft_area'],
            'batch_id': record['batch_id'],
            'shift_date': record['shift_date'],
            'shift_type': record['shift_type'],
            'bags_count': record['bags_count'],
            'weight_kg': record['weight_kg'],
            'estimated_grade': record['estimated_grade'],
            'recorded_by': record['recorded_by'],
          }),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          await dbHelper.markAsSynced(record['id']);
          print('Imesawazishwa kwa mafanikio: Batch ID ${record['batch_id']}');
        } else {
          print('Imeshindwa kusawazisha Batch ID ${record['batch_id']}: ${response.body}');
        }
      } catch (e) {
        print('Hitilafu ya mtandao wakati wa kusawazisha: $e');
        break;
      }
    }
  }
}
