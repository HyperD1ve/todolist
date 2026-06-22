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
    expect(receipt.items.single.titleKind, isNull);
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

  test('auto-completes sublist titles from child items', () {
    final receipt = ReceiptPaper.create(x: 10, y: 20, z: 1).copyWith(
      items: const [
        ListItem(
          text: 'Errands',
          level: 0,
          isTitle: true,
          struck: false,
          titleKind: 'sublist',
        ),
        ListItem(text: 'milk', level: 1, isTitle: false, struck: true),
        ListItem(text: 'bread', level: 1, isTitle: false, struck: true),
      ],
    );

    expect(receipt.items.first.struck, isTrue);
  });

  test('top-level list title round-trips with tmux window id', () {
    final receipt = ReceiptPaper.create(
      x: 10,
      y: 20,
      z: 1,
      tmuxWindowId: 'w_board_1',
    ).copyWith(
      items: const [
        ListItem(
          text: 'Today',
          level: 0,
          isTitle: true,
          struck: false,
          titleKind: 'list',
        ),
        ListItem(text: 'ship app', level: 0, isTitle: false, struck: true),
      ],
    );

    final decoded = Paper.fromJson(receipt.toJson()) as ReceiptPaper;

    expect(decoded.tmuxWindowId, 'w_board_1');
    expect(decoded.items.first.titleKind, 'list');
    expect(decoded.items.first.struck, isTrue);
  });
}
