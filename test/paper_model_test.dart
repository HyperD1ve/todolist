import 'package:flutter_test/flutter_test.dart';
import 'package:tackboard/models/paper.dart';

void main() {
  test('normalizes older receipt JSON', () {
    final paper = Paper.fromJson({
      'id': 'r1',
      'items': [
        {'text': 'milk'},
      ],
    });

    expect(paper, isA<ReceiptPaper>());
    final receipt = paper as ReceiptPaper;
    expect(receipt.id, 'r1');
    expect(receipt.bg, 'crumpled1');
    expect(receipt.items.single.text, 'milk');
    expect(receipt.items.single.level, 0);
    expect(receipt.items.single.struck, isFalse);
  });

  test('round-trips memo strokes', () {
    final memo = MemoPaper.create(color: 'blue', x: 10, y: 20, z: 3).copyWith(
      text: 'hello',
      strokes: const [
        Stroke(
          color: '#2a2a2a',
          points: [StrokePoint(x: 1, y: 2), StrokePoint(x: 3, y: 4)],
        ),
      ],
    );

    final decoded = Paper.fromJson(memo.toJson());

    expect(decoded, isA<MemoPaper>());
    final decodedMemo = decoded as MemoPaper;
    expect(decodedMemo.color, 'blue');
    expect(decodedMemo.text, 'hello');
    expect(decodedMemo.strokes.single.points.last.x, 3);
  });
}
