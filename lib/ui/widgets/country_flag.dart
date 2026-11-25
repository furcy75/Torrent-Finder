import 'package:flutter/material.dart';

/// Crisp vector country flag graphic rendered natively on Windows, Linux, and Android
/// (avoids monochrome "FR/GB/ES" fallback letters on Windows emoji fonts).
class CountryFlag extends StatelessWidget {
  const CountryFlag({
    super.key,
    required this.code,
    this.width = 20,
    this.height = 14,
  });

  final String code;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final upper = code.trim().toUpperCase();
    if (upper == 'MULTI' || upper == 'ALL') {
      return Icon(Icons.public, size: height + 2, color: const Color(0xFF38BDF8));
    }
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0x55FFFFFF), width: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        size: Size(width, height),
        painter: _FlagPainter(upper),
      ),
    );
  }
}

class _FlagPainter extends CustomPainter {
  _FlagPainter(this.code);

  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..style = PaintingStyle.fill;

    switch (code) {
      case 'FR':
        // France: Blue / White / Red vertical stripes
        paint.color = const Color(0xFF002395);
        canvas.drawRect(Rect.fromLTWH(0, 0, w / 3, h), paint);
        paint.color = const Color(0xFFFFFFFF);
        canvas.drawRect(Rect.fromLTWH(w / 3, 0, w / 3, h), paint);
        paint.color = const Color(0xFFED2939);
        canvas.drawRect(Rect.fromLTWH(2 * w / 3, 0, w / 3 + 0.5, h), paint);

      case 'EN':
      case 'GB':
      case 'UK':
        // United Kingdom: Union Jack
        paint.color = const Color(0xFF012169);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);

        final whiteDiag = Paint()
          ..color = const Color(0xFFFFFFFF)
          ..strokeWidth = h * 0.24
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset.zero, Offset(w, h), whiteDiag);
        canvas.drawLine(Offset(w, 0), Offset(0, h), whiteDiag);

        final redDiag = Paint()
          ..color = const Color(0xFFC8102E)
          ..strokeWidth = h * 0.11
          ..style = PaintingStyle.stroke;
        canvas.drawLine(Offset.zero, Offset(w, h), redDiag);
        canvas.drawLine(Offset(w, 0), Offset(0, h), redDiag);

        // White cross
        paint.color = const Color(0xFFFFFFFF);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.34, w, h * 0.32), paint);
        canvas.drawRect(Rect.fromLTWH(w * 0.39, 0, w * 0.22, h), paint);

        // Red cross
        paint.color = const Color(0xFFC8102E);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.41, w, h * 0.18), paint);
        canvas.drawRect(Rect.fromLTWH(w * 0.43, 0, w * 0.14, h), paint);

      case 'ES':
        // Spain: Red / Yellow (2x) / Red + small crest accent
        paint.color = const Color(0xFFAA151B);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.25), paint);
        paint.color = const Color(0xFFF1BF00);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.25, w, h * 0.5), paint);
        paint.color = const Color(0xFFAA151B);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.75, w, h * 0.25 + 0.5), paint);
        paint.color = const Color(0xFF8B1E24);
        canvas.drawRect(Rect.fromLTWH(w * 0.24, h * 0.37, w * 0.14, h * 0.26), paint);

      case 'DE':
        // Germany: Black / Red / Gold
        paint.color = const Color(0xFF000000);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3), paint);
        paint.color = const Color(0xFFDD0000);
        canvas.drawRect(Rect.fromLTWH(0, h / 3, w, h / 3), paint);
        paint.color = const Color(0xFFFFCE00);
        canvas.drawRect(Rect.fromLTWH(0, 2 * h / 3, w, h / 3 + 0.5), paint);

      case 'IT':
        // Italy: Green / White / Red
        paint.color = const Color(0xFF009246);
        canvas.drawRect(Rect.fromLTWH(0, 0, w / 3, h), paint);
        paint.color = const Color(0xFFFFFFFF);
        canvas.drawRect(Rect.fromLTWH(w / 3, 0, w / 3, h), paint);
        paint.color = const Color(0xFFCE2B37);
        canvas.drawRect(Rect.fromLTWH(2 * w / 3, 0, w / 3 + 0.5, h), paint);

      case 'PT':
        // Portugal: Green / Red + Gold emblem
        paint.color = const Color(0xFF006600);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.4, h), paint);
        paint.color = const Color(0xFFFF0000);
        canvas.drawRect(Rect.fromLTWH(w * 0.4, 0, w * 0.6 + 0.5, h), paint);
        paint.color = const Color(0xFFFFCC00);
        canvas.drawCircle(Offset(w * 0.4, h * 0.5), h * 0.22, paint);

      case 'JA':
      case 'JP':
        // Japan: White + Crimson circle
        paint.color = const Color(0xFFFFFFFF);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
        paint.color = const Color(0xFFBC002D);
        canvas.drawCircle(Offset(w / 2, h / 2), h * 0.3, paint);

      default:
        // Neutral indigo badge fallback for other language codes
        paint.color = const Color(0xFF334155);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
        paint.color = const Color(0xFF38BDF8);
        canvas.drawCircle(Offset(w / 2, h / 2), h * 0.25, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FlagPainter oldDelegate) => oldDelegate.code != code;
}
