import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? C.surface,
        borderRadius: BorderRadius.circular(24),
        border: color == null ? Border.all(color: C.line) : null,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap, child: card),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class CatIcon extends StatelessWidget {
  const CatIcon(this.category, {super.key, this.size = 42});
  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = catOf(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size / 2.8)),
      child: Icon(c.icon, color: c.color, size: size * 0.5),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.bg = C.soft, this.fg = C.ink, this.icon});
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
        Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Avatar do José Pinto.
class JoseAvatar extends StatelessWidget {
  const JoseAvatar({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: C.lime, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text('JP',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.36, color: C.ink, letterSpacing: -0.5)),
    );
  }
}

class TxTile extends StatelessWidget {
  const TxTile(this.tx, {super.key, this.onTap});
  final Tx tx;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sign = tx.isIncome ? '+ ' : '- ';
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CatIcon(tx.category),
      title: Text(tx.description, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Row(children: [
        Flexible(child: Text(tx.category, style: const TextStyle(color: C.muted, fontSize: 13))),
        if (tx.source == 'nubank') ...[
          const SizedBox(width: 6),
          const Pill('Nubank', bg: Color(0xFFF1E6FF), fg: Color(0xFF820AD1)),
        ],
        if (tx.source == 'jose') ...[
          const SizedBox(width: 6),
          const Pill('José', bg: C.lime, fg: C.ink),
        ],
      ]),
      trailing: Text(
        '$sign${brl(tx.amount)}',
        style: TextStyle(fontWeight: FontWeight.w700, color: tx.isIncome ? C.green : C.ink),
      ),
    );
  }
}

/// Rosquinha de gastos por categoria.
class Donut extends StatelessWidget {
  const Donut({super.key, required this.values, this.size = 150, this.center});
  final Map<String, double> values;
  final double size;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size.square(size), painter: _DonutPainter(values)),
        if (center != null) center!,
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values);
  final Map<String, double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.values.fold(0.0, (s, v) => s + v);
    final rect = Rect.fromLTWH(10, 10, size.width - 20, size.height - 20);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.butt;
    if (total <= 0) {
      paint.color = C.soft;
      canvas.drawArc(rect, 0, 2 * pi, false, paint);
      return;
    }
    var start = -pi / 2;
    const gap = 0.03;
    for (final e in values.entries) {
      final sweep = (e.value / total) * 2 * pi;
      paint.color = catOf(e.key).color;
      canvas.drawArc(rect, start + gap / 2, max(0.001, sweep - gap), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.values != values;
}

class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, this.color = C.ink});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(0.0, 1.0);
    final barColor = value >= 1 ? C.red : (value >= 0.8 ? C.amber : color);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 10,
        child: Stack(children: [
          Container(color: C.soft),
          FractionallySizedBox(widthFactor: v, child: Container(color: barColor)),
        ]),
      ),
    );
  }
}

/// Texto com suporte simples a **negrito** (o Gemini adora usar).
class RichMd extends StatelessWidget {
  const RichMd(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium!;
    final clean = text.replaceAll(RegExp(r'^#+\s*', multiLine: true), '').replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');
    final spans = <TextSpan>[];
    final parts = clean.split('**');
    for (var i = 0; i < parts.length; i++) {
      spans.add(TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null));
    }
    return Text.rich(TextSpan(style: base.copyWith(height: 1.45), children: spans));
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

String friendlyError(Object e) {
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

/// Converte qualquer coisa (num, "800", "R$ 1.200,50") em double.
double asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v == null) return 0;
  var s = '$v'.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(s) ?? 0;
}
