import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class WeighingTicketData {
  final String uuid;
  final String serial;
  final String operatorName;
  final String material;
  final String product;
  final String lot;
  final double gross;
  final double tare;
  final double net;
  final String createdAt;

  const WeighingTicketData({
    required this.uuid,
    required this.serial,
    required this.operatorName,
    required this.material,
    required this.product,
    required this.lot,
    required this.gross,
    required this.tare,
    required this.net,
    required this.createdAt,
  });
}

class TicketPrinter {
  /// Brand logo built from pure PDF vector primitives.
  /// Renders a neutral pill/capsule icon + generic wordmark in navy blue.
  static pw.Widget _brandLogo() {
    // navy blue used for pill icon and wordmark
    const navy = PdfColor.fromInt(0xFF003087);

    return pw.SizedBox(
      height: 32,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // --- Pill / capsule icon ---
          pw.CustomPaint(
            size: const PdfPoint(28, 20),
            painter: (canvas, size) {
              // Full navy ellipse (right half visible)
              canvas
                ..setFillColor(navy)
                ..drawEllipse(14, 10, 14, 10)
                ..fillPath();

              // White right half: cubic bezier approximating right semicircle
              // Control points chosen so the curve hugs the ellipse edge
              canvas
                ..setFillColor(PdfColors.white)
                ..moveTo(14, 0)
                ..curveTo(28, 0, 28, 20, 14, 20)
                ..lineTo(14, 0)
                ..closePath()
                ..fillPath();

              // Horizontal divider line (white) across full pill
              canvas
                ..setStrokeColor(PdfColors.white)
                ..setLineWidth(1.4)
                ..moveTo(1, 10)
                ..lineTo(27, 10)
                ..strokePath();
            },
          ),
          pw.SizedBox(width: 5),
          // --- Wordmark ---
          pw.Text(
            'Waste Management System',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: navy,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Document buildWeighingTicket(WeighingTicketData d) {
    final doc = pw.Document();

    // 80 mm roll = 226.77 pt wide. Keep margins tight.
    const rollWidth = PdfPageFormat.roll80;

    doc.addPage(
      pw.Page(
        pageFormat: rollWidth,
        margin: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        build: (_) {
          pw.Text rowLabel(String t) => pw.Text(
                t,
                style:
                    pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              );

          pw.Widget row(String label, String value) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(width: 68, child: rowLabel(label)),
                    pw.Expanded(
                      child: pw.Text(
                        value,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                  ],
                ),
              );

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // ── Brand logo ──────────────────────────────────────
              _brandLogo(),
              pw.SizedBox(height: 5),
              pw.Divider(thickness: 0.5),

              // ── Ticket title ─────────────────────────────────────
              pw.Text(
                'WASTE TRACKING',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'WEIGHING TICKET',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.Divider(thickness: 0.5),

              // ── Fields ───────────────────────────────────────────
              row('Date', d.createdAt),
              row('Serial', d.serial.isEmpty ? '-' : d.serial),
              row('Operator', d.operatorName.isEmpty ? '-' : d.operatorName),
              row('Material', d.material.isEmpty ? '-' : d.material),
              row('Product', d.product.isEmpty ? '-' : d.product),
              row('Lot', d.lot.isEmpty ? '-' : d.lot),
              pw.SizedBox(height: 3),

              // ── Weights ──────────────────────────────────────────
              row('Gross', '${d.gross.toStringAsFixed(3)} kg'),
              row('Tare', '${d.tare.toStringAsFixed(3)} kg'),
              row('Net', '${d.net.toStringAsFixed(3)} kg'),
              pw.Divider(thickness: 0.5),

              // ── UUID text ────────────────────────────────────────
              pw.Text(
                'ID',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 7, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4, vertical: 3),
                decoration: pw.BoxDecoration(
                  border:
                      pw.Border.all(color: PdfColors.grey600, width: 0.5),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text(
                  d.uuid,
                  style: const pw.TextStyle(fontSize: 6.5),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 6),

              // ── Code 128 barcode ─────────────────────────────────
              // Code128 encodes any ASCII string and is readable by
              // virtually every industrial/handheld scanner.
              // Width is capped to the printable area (~200 pt for 80mm roll).
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),   // ← changed from qrCode()
                  data: d.uuid,
                  width: 200,   // fits within 80mm roll (226 pt) minus margins
                  height: 52,   // thin enough to not waste paper
                  drawText: false, // UUID already shown above; skip double text
                ),
              ),
              pw.SizedBox(height: 4),

              // ── Footer ───────────────────────────────────────────
              pw.Text(
                'Stick this ticket/label to the batch container.',
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 7),
              ),
            ],
          );
        },
      ),
    );

    return doc;
  }
}