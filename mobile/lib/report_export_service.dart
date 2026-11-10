import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class ReportExportService {
  static Future<void> shareCsv(String csv, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file
        .writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)], flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
        text: 'Ripoti ya Madini Track Tanzania');
  }

  static Future<void> sharePdf({
    required String title,
    required String period,
    required String scope,
    required String body,
  }) async {
    final doc = pw.Document();
    final lines = body.split('\n');
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('MADINI TRACK TANZANIA',
              style: const pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(title, style: const pw.TextStyle(fontSize: 13)),
          pw.Text('$period • $scope', style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(),
        ],
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Ukurasa ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8)),
      ),
      build: (_) => [
        for (final line in lines)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
          ),
      ],
    ));
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/madini_track_report.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
        text: 'Ripoti ya Madini Track Tanzania');
  }
}
