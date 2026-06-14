import 'dart:convert';
import 'dart:math';

const receiptWidth = 230.0;
const receiptMinHeight = 320.0;
const receiptMaxHeight = 560.0;
const memoSize = 210.0;
const ballSize = 96.0;

const memoColors = <String, int>{
  'red': 0xffef6f6f,
  'green': 0xff8fd17a,
  'blue': 0xff7db4ef,
};

const ballVariants = <String>['ball1', 'ball2', 'ball3'];
const bgVariants = <String>['crumpled1', 'crumpled2'];
const memoColorNames = <String>['red', 'green', 'blue'];

String newPaperId() {
  final random = Random.secure();
  final now = DateTime.now().microsecondsSinceEpoch;
  final tail = List<int>.generate(8, (_) => random.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'p_${now}_$tail';
}

String pickString(List<String> values) {
  return values[Random().nextInt(values.length)];
}

class ListItem {
  const ListItem({
    required this.text,
    required this.level,
    required this.isTitle,
    required this.struck,
  });

  final String text;
  final int level;
  final bool isTitle;
  final bool struck;

  ListItem copyWith({
    String? text,
    int? level,
    bool? isTitle,
    bool? struck,
  }) {
    return ListItem(
      text: text ?? this.text,
      level: level ?? this.level,
      isTitle: isTitle ?? this.isTitle,
      struck: struck ?? this.struck,
    );
  }

  factory ListItem.fromJson(Object? value) {
    final map = value is Map ? value : const <String, Object?>{};
    return ListItem(
      text: map['text']?.toString() ?? '',
      level: _intValue(map['level'], 0),
      isTitle: map['isTitle'] == true,
      struck: map['struck'] == true,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'text': text,
      'level': level,
      'isTitle': isTitle,
      'struck': struck,
    };
  }
}

class StrokePoint {
  const StrokePoint({required this.x, required this.y});

  final double x;
  final double y;

  factory StrokePoint.fromJson(Object? value) {
    final map = value is Map ? value : const <String, Object?>{};
    return StrokePoint(
      x: _doubleValue(map['x'], 0),
      y: _doubleValue(map['y'], 0),
    );
  }

  Map<String, Object?> toJson() => {'x': x, 'y': y};
}

class Stroke {
  const Stroke({required this.color, required this.points});

  final String color;
  final List<StrokePoint> points;

  factory Stroke.fromJson(Object? value) {
    final map = value is Map ? value : const <String, Object?>{};
    final rawPoints = map['points'];
    return Stroke(
      color: map['color']?.toString() ?? '#2a2a2a',
      points: rawPoints is List
          ? rawPoints.map(StrokePoint.fromJson).toList(growable: false)
          : const <StrokePoint>[],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'color': color,
      'points': points.map((p) => p.toJson()).toList(growable: false),
    };
  }
}

sealed class Paper {
  const Paper({
    required this.id,
    required this.x,
    required this.y,
    required this.z,
    required this.pinned,
    required this.balled,
    required this.crumpled,
    required this.ball,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final double x;
  final double y;
  final int z;
  final bool pinned;
  final bool balled;
  final bool crumpled;
  final String ball;
  final int createdAt;
  final int updatedAt;

  String get kind;

  Paper withSyncTime(int updatedAt);

  Paper move({
    double? x,
    double? y,
    int? z,
    bool? pinned,
    bool? balled,
    bool? crumpled,
    int? updatedAt,
  });

  Map<String, Object?> toJson();

  String toJsonString() => jsonEncode(toJson());

  static Paper fromJson(Object? value) {
    final map = value is Map ? value : const <String, Object?>{};
    if (map['kind'] == 'memo') return MemoPaper.fromJson(map);
    return ReceiptPaper.fromJson(map);
  }

  static Paper fromJsonString(String source) {
    return Paper.fromJson(jsonDecode(source));
  }
}

class ReceiptPaper extends Paper {
  const ReceiptPaper({
    required super.id,
    required super.x,
    required super.y,
    required super.z,
    required super.pinned,
    required super.balled,
    required super.crumpled,
    required super.ball,
    required super.createdAt,
    required super.updatedAt,
    required this.bg,
    required this.bgScale,
    required this.bgX,
    required this.bgY,
    required this.height,
    required this.items,
    required this.draft,
    required this.draftLevel,
  });

  final String bg;
  final double bgScale;
  final double bgX;
  final double bgY;
  final double height;
  final List<ListItem> items;
  final String draft;
  final int draftLevel;

  factory ReceiptPaper.create({required double x, required double y, required int z}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = Random();
    return ReceiptPaper(
      id: newPaperId(),
      x: x,
      y: y,
      z: z,
      pinned: false,
      balled: false,
      crumpled: false,
      ball: pickString(ballVariants),
      createdAt: now,
      updatedAt: now,
      bg: pickString(bgVariants),
      bgScale: 1.1 + random.nextDouble() * 1.2,
      bgX: random.nextInt(101).toDouble(),
      bgY: random.nextInt(101).toDouble(),
      height: receiptMinHeight +
          random.nextDouble() * (receiptMaxHeight - receiptMinHeight),
      items: const <ListItem>[],
      draft: '',
      draftLevel: 0,
    );
  }

  factory ReceiptPaper.fromJson(Map<dynamic, dynamic> map) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rawItems = map['items'];
    return ReceiptPaper(
      id: map['id']?.toString() ?? newPaperId(),
      x: _doubleValue(map['x'], 60),
      y: _doubleValue(map['y'], 60),
      z: _intValue(map['z'], 1),
      pinned: map['pinned'] == true,
      balled: map['balled'] == true,
      crumpled: map['crumpled'] == true,
      ball: _stringChoice(map['ball'], ballVariants, 'ball1'),
      createdAt: _intValue(map['createdAt'], now),
      updatedAt: _intValue(map['updatedAt'], _intValue(map['createdAt'], now)),
      bg: _stringChoice(map['bg'], bgVariants, 'crumpled1'),
      bgScale: _doubleValue(map['bgScale'], 1.4),
      bgX: _doubleValue(map['bgX'], 50),
      bgY: _doubleValue(map['bgY'], 50),
      height: _doubleValue(map['height'], 400),
      items: rawItems is List
          ? rawItems.map(ListItem.fromJson).toList(growable: false)
          : const <ListItem>[],
      draft: map['draft']?.toString() ?? '',
      draftLevel: _intValue(map['draftLevel'], 0),
    );
  }

  ReceiptPaper copyWith({
    double? x,
    double? y,
    int? z,
    bool? pinned,
    bool? balled,
    bool? crumpled,
    String? ball,
    int? createdAt,
    int? updatedAt,
    String? bg,
    double? bgScale,
    double? bgX,
    double? bgY,
    double? height,
    List<ListItem>? items,
    String? draft,
    int? draftLevel,
  }) {
    return ReceiptPaper(
      id: id,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      pinned: pinned ?? this.pinned,
      balled: balled ?? this.balled,
      crumpled: crumpled ?? this.crumpled,
      ball: ball ?? this.ball,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      bg: bg ?? this.bg,
      bgScale: bgScale ?? this.bgScale,
      bgX: bgX ?? this.bgX,
      bgY: bgY ?? this.bgY,
      height: height ?? this.height,
      items: items ?? this.items,
      draft: draft ?? this.draft,
      draftLevel: draftLevel ?? this.draftLevel,
    );
  }

  @override
  String get kind => 'receipt';

  @override
  ReceiptPaper withSyncTime(int updatedAt) => copyWith(updatedAt: updatedAt);

  @override
  ReceiptPaper move({
    double? x,
    double? y,
    int? z,
    bool? pinned,
    bool? balled,
    bool? crumpled,
    int? updatedAt,
  }) {
    return copyWith(
      x: x,
      y: y,
      z: z,
      pinned: pinned,
      balled: balled,
      crumpled: crumpled,
      updatedAt: updatedAt,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind,
      'bg': bg,
      'bgScale': bgScale,
      'bgX': bgX,
      'bgY': bgY,
      'height': height,
      'x': x,
      'y': y,
      'z': z,
      'pinned': pinned,
      'balled': balled,
      'crumpled': crumpled,
      'ball': ball,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'draft': draft,
      'draftLevel': draftLevel,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class MemoPaper extends Paper {
  const MemoPaper({
    required super.id,
    required super.x,
    required super.y,
    required super.z,
    required super.pinned,
    required super.balled,
    required super.crumpled,
    required super.ball,
    required super.createdAt,
    required super.updatedAt,
    required this.color,
    required this.size,
    required this.text,
    required this.strokes,
  });

  final String color;
  final double size;
  final String text;
  final List<Stroke> strokes;

  factory MemoPaper.create({
    required String color,
    required double x,
    required double y,
    required int z,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return MemoPaper(
      id: newPaperId(),
      x: x,
      y: y,
      z: z,
      pinned: false,
      balled: false,
      crumpled: false,
      ball: pickString(ballVariants),
      createdAt: now,
      updatedAt: now,
      color: _stringChoice(color, memoColorNames, 'red'),
      size: memoSize,
      text: '',
      strokes: const <Stroke>[],
    );
  }

  factory MemoPaper.fromJson(Map<dynamic, dynamic> map) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rawStrokes = map['strokes'];
    return MemoPaper(
      id: map['id']?.toString() ?? newPaperId(),
      x: _doubleValue(map['x'], 60),
      y: _doubleValue(map['y'], 60),
      z: _intValue(map['z'], 1),
      pinned: map['pinned'] == true,
      balled: map['balled'] == true,
      crumpled: map['crumpled'] == true,
      ball: _stringChoice(map['ball'], ballVariants, 'ball1'),
      createdAt: _intValue(map['createdAt'], now),
      updatedAt: _intValue(map['updatedAt'], _intValue(map['createdAt'], now)),
      color: _stringChoice(map['color'], memoColorNames, 'red'),
      size: _doubleValue(map['size'], memoSize),
      text: map['text']?.toString() ?? '',
      strokes: rawStrokes is List
          ? rawStrokes.map(Stroke.fromJson).toList(growable: false)
          : const <Stroke>[],
    );
  }

  MemoPaper copyWith({
    double? x,
    double? y,
    int? z,
    bool? pinned,
    bool? balled,
    bool? crumpled,
    String? ball,
    int? createdAt,
    int? updatedAt,
    String? color,
    double? size,
    String? text,
    List<Stroke>? strokes,
  }) {
    return MemoPaper(
      id: id,
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      pinned: pinned ?? this.pinned,
      balled: balled ?? this.balled,
      crumpled: crumpled ?? this.crumpled,
      ball: ball ?? this.ball,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      color: color ?? this.color,
      size: size ?? this.size,
      text: text ?? this.text,
      strokes: strokes ?? this.strokes,
    );
  }

  @override
  String get kind => 'memo';

  @override
  MemoPaper withSyncTime(int updatedAt) => copyWith(updatedAt: updatedAt);

  @override
  MemoPaper move({
    double? x,
    double? y,
    int? z,
    bool? pinned,
    bool? balled,
    bool? crumpled,
    int? updatedAt,
  }) {
    return copyWith(
      x: x,
      y: y,
      z: z,
      pinned: pinned,
      balled: balled,
      crumpled: crumpled,
      updatedAt: updatedAt,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind,
      'color': color,
      'size': size,
      'text': text,
      'strokes': strokes.map((stroke) => stroke.toJson()).toList(growable: false),
      'x': x,
      'y': y,
      'z': z,
      'pinned': pinned,
      'balled': balled,
      'crumpled': crumpled,
      'ball': ball,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

double _doubleValue(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _intValue(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _stringChoice(Object? value, List<String> choices, String fallback) {
  final string = value?.toString();
  if (string != null && choices.contains(string)) return string;
  return fallback;
}
