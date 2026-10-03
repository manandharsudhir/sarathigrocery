import 'package:flutter/material.dart';

/// A handwritten signature as strokes of points normalized to 0..1000 on
/// both axes, so it's resolution-independent. Encoded compactly as
/// "x,y x,y|x,y ..." — a few KB, stored inline on the payment/order.
class Signature {
  const Signature(this.strokes);

  final List<List<Offset>> strokes;

  static const _scale = 1000.0;

  bool get isEmpty => strokes.every((s) => s.length < 2);

  String encode() => strokes
      .where((s) => s.isNotEmpty)
      .map((s) => s.map((p) => '${p.dx.round()},${p.dy.round()}').join(' '))
      .join('|');

  static Signature? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    return Signature([
      for (final stroke in text.split('|'))
        [
          for (final point in stroke.split(' '))
            if (point.contains(',')) Offset(double.parse(point.split(',')[0]), double.parse(point.split(',')[1])),
        ],
    ]);
  }
}

/// Paints a [Signature] into any box (same drawing on screen and in PDFs).
class SignaturePainter extends CustomPainter {
  SignaturePainter(this.signature, {this.color = Colors.black});

  final Signature signature;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in signature.strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx / Signature._scale * size.width, stroke.first.dy / Signature._scale * size.height);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx / Signature._scale * size.width, p.dy / Signature._scale * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(SignaturePainter old) => old.signature != signature;
}

class SignatureView extends StatelessWidget {
  const SignatureView({super.key, required this.signature, this.height = 80});

  final Signature signature;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8), color: Colors.white),
      child: CustomPaint(painter: SignaturePainter(signature), size: Size.infinite),
    );
  }
}

/// Draw-with-finger pad. [onChanged] gets null when cleared/empty.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, required this.onChanged, this.height = 160});

  final ValueChanged<Signature?> onChanged;
  final double height;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> _strokes = [];

  Offset _normalize(Offset local, Size size) => Offset(
        (local.dx / size.width * Signature._scale).clamp(0, Signature._scale),
        (local.dy / size.height * Signature._scale).clamp(0, Signature._scale),
      );

  void _emit() {
    final signature = Signature([for (final s in _strokes) List.of(s)]);
    widget.onChanged(signature.isEmpty ? null : signature);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final size = Size(constraints.maxWidth, widget.height);
          return GestureDetector(
            // Claim drags so the sheet/list doesn't scroll while signing.
            onPanStart: (d) => setState(() => _strokes.add([_normalize(d.localPosition, size)])),
            onPanUpdate: (d) => setState(() => _strokes.last.add(_normalize(d.localPosition, size))),
            onPanEnd: (_) => _emit(),
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outline), borderRadius: BorderRadius.circular(8), color: Colors.white),
              child: CustomPaint(painter: SignaturePainter(Signature(_strokes)), size: size, child: _strokes.isEmpty ? const Center(child: Text('Customer signs here', style: TextStyle(color: Colors.grey))) : null),
            ),
          );
        }),
        TextButton(
          onPressed: _strokes.isEmpty
              ? null
              : () {
                  setState(_strokes.clear);
                  _emit();
                },
          child: const Text('Clear'),
        ),
      ],
    );
  }
}
