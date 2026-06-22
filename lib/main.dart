import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'models/paper.dart';
import 'services/tackboard_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TackboardApp());
}

class TackboardApp extends StatefulWidget {
  const TackboardApp({super.key});

  @override
  State<TackboardApp> createState() => _TackboardAppState();
}

class _TackboardAppState extends State<TackboardApp> {
  late final TackboardController controller;

  @override
  void initState() {
    super.initState();
    controller = TackboardController();
    unawaited(controller.init());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tackboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff7b4a23)),
        fontFamily: 'Courier',
        useMaterial3: true,
      ),
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => TackboardHome(controller: controller),
        ),
      ),
    );
  }
}

class TackboardHome extends StatefulWidget {
  const TackboardHome({required this.controller, super.key});

  final TackboardController controller;

  @override
  State<TackboardHome> createState() => _TackboardHomeState();
}

class _TackboardHomeState extends State<TackboardHome> {
  bool showBin = false;
  bool tmuxMode = false;
  int confettiKey = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final importantMobile = size.width / max(1, size.height) <= 0.8;
        if (importantMobile && showBin) showBin = false;

        if (tmuxMode) {
          return TmuxSessionView(
            controller: widget.controller,
            boardSize: size,
            onDetach: () => setState(() => tmuxMode = false),
          );
        }

        return Stack(
          children: [
            TackboardSurface(
              controller: widget.controller,
              boardSize: size,
              importantMobile: importantMobile,
              onOpenBin: () => setState(() => showBin = true),
              onOpenTmux: () {
                widget.controller.stopEdit();
                setState(() => tmuxMode = true);
              },
              onConfetti: () => setState(() => confettiKey++),
            ),
            if (showBin && !importantMobile)
              BinScreen(
                balls: widget.controller.binned,
                onLeave: () => setState(() => showBin = false),
                onClear: () {
                  unawaited(widget.controller.clearCrumpled());
                },
              ),
            if (confettiKey > 0) ConfettiBurst(key: ValueKey(confettiKey)),
          ],
        );
      },
    );
  }
}

class TackboardSurface extends StatelessWidget {
  const TackboardSurface({
    required this.controller,
    required this.boardSize,
    required this.importantMobile,
    required this.onOpenBin,
    required this.onOpenTmux,
    required this.onConfetti,
    super.key,
  });

  final TackboardController controller;
  final Size boardSize;
  final bool importantMobile;
  final VoidCallback onOpenBin;
  final VoidCallback onOpenTmux;
  final VoidCallback onConfetti;

  @override
  Widget build(BuildContext context) {
    final visible = importantMobile
        ? controller.onBoard
            .where(
              (paper) =>
                  !paper.balled &&
                  ((paper is ReceiptPaper && paper.pinned) ||
                      (paper is MemoPaper && paper.color == 'red')),
            )
            .toList(growable: false)
        : controller.onBoard;
    final ordered = [...visible]
      ..sort((a, b) => _displayZ(a).compareTo(_displayZ(b)));

    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/tackboard.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => controller.stopEdit(),
            ),
          ),
          if (importantMobile)
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 28, 14, 34),
              child: Column(
                children: [
                  for (final paper in ordered) ...[
                    _MobilePaper(
                      paper: paper,
                      editing: controller.editingId == paper.id,
                      onStartEdit: controller.startEdit,
                      onStopEdit: controller.stopEdit,
                      onChanged: (next) {
                        unawaited(
                            controller.updatePaper(paper.id, (_) => next));
                      },
                    ),
                    const SizedBox(height: 22),
                  ],
                ],
              ),
            )
          else ...[
            for (final paper
                in ordered.where((paper) => paper.id != controller.editingId))
              PaperHost(
                key: ValueKey(paper.id),
                paper: paper,
                editing: controller.editingId == paper.id,
                boardSize: boardSize,
                onStartEdit: controller.startEdit,
                onStopEdit: controller.stopEdit,
                onBringToFront: controller.bringToFront,
                onChanged: (next) {
                  unawaited(controller.updatePaper(paper.id, (_) => next));
                },
                onBall: controller.markBalled,
                onLand: (id, hitBin) async {
                  await controller.landBall(id, hitBin: hitBin);
                  if (hitBin) onConfetti();
                },
              ),
            ReceiptPrinter(
              onPrint: () {
                unawaited(controller.printReceipt(boardSize));
              },
            ),
            PostItBoard(
              onPick: (color) {
                unawaited(controller.spawnMemo(color, boardSize));
              },
            ),
            PaperBin(
              count: controller.binned.length,
              alert: controller.ballInPlay,
              onOpen: onOpenBin,
            ),
            SyncStrip(controller: controller),
            Positioned(
              top: 12,
              left: 12,
              child: _SmallButton(label: 'tmux', onTap: onOpenTmux),
            ),
            if (controller.editingId != null)
              Positioned.fill(
                child: GestureDetector(
                  onTap: controller.stopEdit,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(color: const Color(0x5920140a)),
                  ),
                ),
              ),
            for (final paper
                in ordered.where((paper) => paper.id == controller.editingId))
              PaperHost(
                key: ValueKey(paper.id),
                paper: paper,
                editing: true,
                boardSize: boardSize,
                onStartEdit: controller.startEdit,
                onStopEdit: controller.stopEdit,
                onBringToFront: controller.bringToFront,
                onChanged: (next) {
                  unawaited(controller.updatePaper(paper.id, (_) => next));
                },
                onBall: controller.markBalled,
                onLand: (id, hitBin) async {
                  await controller.landBall(id, hitBin: hitBin);
                  if (hitBin) onConfetti();
                },
              ),
          ],
          if (importantMobile && controller.editingId != null)
            Positioned(
              top: 12,
              right: 12,
              child: _SmallButton(label: 'exit', onTap: controller.stopEdit),
            ),
        ],
      ),
    );
  }
}

class _MobilePaper extends StatelessWidget {
  const _MobilePaper({
    required this.paper,
    required this.editing,
    required this.onStartEdit,
    required this.onStopEdit,
    required this.onChanged,
  });

  final Paper paper;
  final bool editing;
  final ValueChanged<String> onStartEdit;
  final VoidCallback onStopEdit;
  final ValueChanged<Paper> onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => onStartEdit(paper.id),
        child: paper is ReceiptPaper
            ? ReceiptView(
                receipt: paper as ReceiptPaper,
                editing: editing,
                mobile: true,
                onStopEdit: onStopEdit,
                onChanged: onChanged,
              )
            : MemoView(
                memo: paper as MemoPaper,
                editing: editing,
                mobile: true,
                onStopEdit: onStopEdit,
                onChanged: onChanged,
              ),
      ),
    );
  }
}

class PaperHost extends StatefulWidget {
  const PaperHost({
    required this.paper,
    required this.editing,
    required this.boardSize,
    required this.onStartEdit,
    required this.onStopEdit,
    required this.onBringToFront,
    required this.onChanged,
    required this.onBall,
    required this.onLand,
    super.key,
  });

  final Paper paper;
  final bool editing;
  final Size boardSize;
  final ValueChanged<String> onStartEdit;
  final VoidCallback onStopEdit;
  final Future<int> Function(String id) onBringToFront;
  final ValueChanged<Paper> onChanged;
  final Future<void> Function(String id) onBall;
  final Future<void> Function(String id, bool hitBin) onLand;

  @override
  State<PaperHost> createState() => _PaperHostState();
}

class _PaperHostState extends State<PaperHost>
    with SingleTickerProviderStateMixin {
  static const dragThreshold = 5.0;
  static const pinZone = 36.0;
  static const longPress = Duration(seconds: 3);
  static const ballGravity = 3000.0;
  static const maxThrow = 3200.0;
  static const velocityWindow = Duration(milliseconds: 90);

  late Offset pos;
  late Ticker ticker;
  Timer? crumbleTimer;
  bool down = false;
  bool dragging = false;
  bool heldBall = false;
  Offset start = Offset.zero;
  Offset latestPointer = Offset.zero;
  Duration latestPointerTime = Duration.zero;
  Offset velocity = Offset.zero;
  final List<_PointerSample> ballSamples = <_PointerSample>[];
  double rotation = 0;
  double spin = 0;

  double get width => widget.paper is ReceiptPaper
      ? receiptWidth
      : (widget.paper as MemoPaper).size;
  double get height => widget.paper is ReceiptPaper
      ? (widget.paper as ReceiptPaper).height
      : width;

  @override
  void initState() {
    super.initState();
    pos = Offset(widget.paper.x, widget.paper.y);
    ticker = createTicker(_tick);
  }

  @override
  void didUpdateWidget(covariant PaperHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!dragging && !heldBall && !ticker.isTicking) {
      pos = Offset(widget.paper.x, widget.paper.y);
    }
  }

  @override
  void dispose() {
    crumbleTimer?.cancel();
    ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.paper.balled
        ? BallView(ball: widget.paper.ball)
        : widget.paper is ReceiptPaper
            ? ReceiptView(
                receipt: widget.paper as ReceiptPaper,
                editing: widget.editing,
                onStopEdit: widget.onStopEdit,
                onChanged: widget.onChanged,
              )
            : MemoView(
                memo: widget.paper as MemoPaper,
                editing: widget.editing,
                onStopEdit: widget.onStopEdit,
                onChanged: widget.onChanged,
              );

    final focus = _focusTransform();
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: widget.paper.balled ? ballSize : width,
      height: widget.paper.balled ? ballSize : height,
      child: Listener(
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerCancel,
        child: Transform(
          alignment:
              widget.paper.balled ? Alignment.center : Alignment.topCenter,
          transform: Matrix4.identity()
            ..translateByDouble(focus.dx, focus.dy, 0, 1)
            ..scaleByDouble(focus.scale, focus.scale, focus.scale, 1)
            ..rotateZ(widget.editing ? 0 : rotation + spin),
          child: MouseRegion(
            cursor: widget.editing
                ? SystemMouseCursors.basic
                : widget.paper.balled
                    ? SystemMouseCursors.grab
                    : SystemMouseCursors.grab,
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: child),
                  if (widget.paper.pinned && !widget.paper.balled)
                    const PinClip(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ({double dx, double dy, double scale}) _focusTransform() {
    if (!widget.editing) return (dx: 0, dy: 0, scale: 1);
    final scaleTarget = widget.paper is ReceiptPaper ? 1.5 : 2.1;
    final fit = min((widget.boardSize.width * 0.92) / width,
        (widget.boardSize.height * 0.92) / height);
    final scale = min(scaleTarget, fit);
    final dx = widget.boardSize.width / 2 - (pos.dx + width / 2);
    final dy = widget.boardSize.height / 2 - (pos.dy + height / 2);
    return (dx: dx, dy: dy, scale: scale);
  }

  void _pointerDown(PointerDownEvent event) {
    if (widget.editing) return;
    down = true;
    dragging = false;
    heldBall = widget.paper.balled;
    start = event.position;
    latestPointer = event.position;
    latestPointerTime = event.timeStamp;
    ballSamples.clear();
    velocity = Offset.zero;
    unawaited(widget.onBringToFront(widget.paper.id));

    ticker.stop();
    if (widget.paper.balled) {
      _sampleBall(event);
      return;
    }
    crumbleTimer = Timer(longPress, _becomeBall);
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!down) return;
    latestPointer = event.position;
    latestPointerTime = event.timeStamp;
    if (event.buttons == 0) {
      _reset();
      return;
    }
    if (heldBall || widget.paper.balled) {
      _sampleBall(event);
      return;
    }

    final delta = event.position - start;
    if (!dragging && delta.distance > dragThreshold) {
      dragging = true;
      crumbleTimer?.cancel();
    }
    if (dragging) {
      setState(() {
        pos = Offset(event.position.dx - width / 2, event.position.dy);
        rotation = (event.delta.dx / 70).clamp(-0.28, 0.28);
      });
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (!down) return;
    crumbleTimer?.cancel();
    down = false;

    if (heldBall || widget.paper.balled) {
      _sampleBall(event);
      _launchBall();
      return;
    }

    if (!dragging) {
      widget.onStartEdit(widget.paper.id);
      return;
    }

    dragging = false;
    final pinned = event.position.dy <= pinZone;
    final nextPos = Offset(pos.dx, pinned ? 8 : pos.dy);
    setState(() {
      pos = nextPos;
      rotation = 0;
    });
    widget.onChanged(
        widget.paper.move(x: nextPos.dx, y: nextPos.dy, pinned: pinned));
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (heldBall || widget.paper.balled) {
      _launchBall();
    }
    _reset();
  }

  void _reset() {
    down = false;
    dragging = false;
    heldBall = false;
    crumbleTimer?.cancel();
  }

  void _becomeBall() {
    if (!mounted || widget.paper.balled) return;
    crumbleTimer?.cancel();
    ballSamples.clear();
    velocity = Offset.zero;
    setState(() {
      heldBall = true;
      rotation = 0;
      spin = 0;
      pos = latestPointer - const Offset(ballSize / 2, ballSize / 2);
    });
    unawaited(widget.onBall(widget.paper.id));
  }

  void _sampleBall(PointerEvent event) {
    latestPointer = event.position;
    latestPointerTime = event.timeStamp;
    final staleSamples = ballSamples.isEmpty ||
        event.timeStamp.inMicroseconds - ballSamples.last.micros >
            velocityWindow.inMicroseconds;
    if (staleSamples && event is PointerMoveEvent && event.delta.distance > 0) {
      ballSamples.clear();
      final previousTime = event.timeStamp - const Duration(milliseconds: 16);
      _recordBallSample(
        event.position - event.delta,
        previousTime.isNegative ? Duration.zero : previousTime,
      );
    }
    _recordBallSample(event.position, event.timeStamp);
    setState(() {
      pos = event.position - const Offset(ballSize / 2, ballSize / 2);
    });
  }

  void _recordBallSample(Offset pointerPosition, Duration timeStamp) {
    final sample = _PointerSample(
      position: pointerPosition - const Offset(ballSize / 2, ballSize / 2),
      micros: timeStamp.inMicroseconds,
    );
    if (ballSamples.isNotEmpty &&
        (sample.position - ballSamples.last.position).distance <= 0.25) {
      return;
    }
    ballSamples.add(sample);
    while (ballSamples.length > 8) {
      ballSamples.removeAt(0);
    }
  }

  void _launchBall() {
    heldBall = false;
    velocity = _throwVelocity();
    if (!ticker.isTicking) ticker.start();
  }

  Offset _throwVelocity() {
    if (ballSamples.length < 2) return Offset.zero;
    final latest = ballSamples.last;
    var reference = latest;
    for (var i = ballSamples.length - 2; i >= 0; i--) {
      final sample = ballSamples[i];
      if (latest.micros - sample.micros > velocityWindow.inMicroseconds) {
        break;
      }
      reference = sample;
    }
    if (identical(reference, latest)) return Offset.zero;
    final dt = max(0.001, (latest.micros - reference.micros) / 1000000);
    final raw = (latest.position - reference.position) / dt;
    final speed = raw.distance;
    return speed > maxThrow ? raw * (maxThrow / speed) : raw;
  }

  void _tick(Duration elapsed) {
    const dt = 1 / 60;
    velocity = Offset(velocity.dx, velocity.dy + ballGravity * dt);
    setState(() {
      spin += velocity.dx * dt * 0.004;
      pos += velocity * dt;
    });
    final center = pos + const Offset(ballSize / 2, ballSize / 2);
    final hitBin = center.dx >= -20 &&
        center.dx <= 240 &&
        center.dy >= widget.boardSize.height - 200;
    final offscreen = pos.dy > widget.boardSize.height + 140 ||
        pos.dx < -180 ||
        pos.dx > widget.boardSize.width + 180;
    if (hitBin || offscreen) {
      ticker.stop();
      unawaited(widget.onLand(widget.paper.id, hitBin));
    }
  }
}

class _PointerSample {
  const _PointerSample({required this.position, required this.micros});

  final Offset position;
  final int micros;
}

class ReceiptView extends StatefulWidget {
  const ReceiptView({
    required this.receipt,
    required this.editing,
    required this.onStopEdit,
    required this.onChanged,
    this.mobile = false,
    super.key,
  });

  final ReceiptPaper receipt;
  final bool editing;
  final bool mobile;
  final VoidCallback onStopEdit;
  final ValueChanged<Paper> onChanged;

  @override
  State<ReceiptView> createState() => _ReceiptViewState();
}

class _ReceiptViewState extends State<ReceiptView> {
  final textFocusNode = FocusNode();
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller.text = widget.receipt.draft;
  }

  @override
  void didUpdateWidget(covariant ReceiptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.receipt.draft) {
      controller.text = widget.receipt.draft;
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
    }
    if (widget.editing && !oldWidget.editing) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => textFocusNode.requestFocus());
    }
  }

  @override
  void dispose() {
    textFocusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final height = widget.mobile && widget.editing
        ? min(receipt.height, MediaQuery.sizeOf(context).height - 72)
        : receipt.height;

    return Focus(
      onKeyEvent: _key,
      child: Container(
        width: widget.mobile
            ? min(receiptWidth, MediaQuery.sizeOf(context).width - 28)
            : receiptWidth,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/${receipt.bg}.jpg'),
            fit: BoxFit.cover,
            alignment:
                Alignment((receipt.bgX - 50) / 50, (receipt.bgY - 50) / 50),
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x59000000), blurRadius: 10, offset: Offset(2, 6))
          ],
          border: widget.editing
              ? Border.all(color: const Color(0x88405ac8), width: 2)
              : null,
        ),
        child: SingleChildScrollView(
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xff222222),
              fontSize: 19,
              height: 1.5,
              fontFamily: 'Courier',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < receipt.items.length; i++)
                  GestureDetector(
                    onTap: widget.editing ? () => _strike(i) : null,
                    child: Padding(
                      padding:
                          EdgeInsets.only(left: receipt.items[i].level * 18),
                      child: Text(
                        receipt.items[i].isTitle
                            ? receipt.items[i].text
                            : '- ${receipt.items[i].text}',
                        softWrap: true,
                        style: TextStyle(
                          fontWeight: receipt.items[i].isTitle
                              ? FontWeight.w700
                              : FontWeight.w400,
                          decoration: TextDecoration.combine([
                            if (receipt.items[i].isTitle)
                              TextDecoration.underline,
                            if (receipt.items[i].struck)
                              TextDecoration.lineThrough,
                          ]),
                          color: receipt.items[i].struck
                              ? const Color(0x88222222)
                              : const Color(0xff222222),
                        ),
                      ),
                    ),
                  ),
                if (widget.editing || receipt.draft.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(left: receipt.draftLevel * 18),
                    child: TextField(
                      controller: controller,
                      focusNode: textFocusNode,
                      maxLines: null,
                      readOnly: !widget.editing,
                      enableInteractiveSelection: widget.editing,
                      decoration: const InputDecoration.collapsed(hintText: ''),
                      style: const TextStyle(
                          fontSize: 19, height: 1.5, fontFamily: 'Courier'),
                      onChanged: _draftChanged,
                      onSubmitted: (_) => _commitDraft(),
                    ),
                  ),
                if (widget.editing &&
                    receipt.items.isEmpty &&
                    receipt.draft.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'type... Enter = item · Shift+Enter = title · Tab = sub-list · no deleting',
                      style: TextStyle(fontSize: 12, color: Color(0x88222222)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !widget.editing) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _commitListTitle();
        return KeyEventResult.handled;
      }
      _commitDraft();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        widget.onChanged(widget.receipt
            .copyWith(draftLevel: max(0, widget.receipt.draftLevel - 1)));
      } else {
        final text = widget.receipt.draft.trim();
        if (text.isNotEmpty) {
          widget.onChanged(
            widget.receipt.copyWith(
              items: [
                ...widget.receipt.items,
                ListItem(
                    text: text,
                    level: widget.receipt.draftLevel,
                    isTitle: true,
                    struck: false,
                    titleKind: 'sublist'),
              ],
              draft: '',
              draftLevel: widget.receipt.draftLevel + 1,
            ),
          );
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onStopEdit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _draftChanged(String value) {
    if (value.length < widget.receipt.draft.length) {
      controller.text = widget.receipt.draft;
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      return;
    }
    widget.onChanged(widget.receipt.copyWith(draft: value));
  }

  void _commitDraft() {
    final text = widget.receipt.draft.trim();
    if (text.isEmpty) return;
    widget.onChanged(
      widget.receipt.copyWith(
        items: [
          ...widget.receipt.items,
          ListItem(
              text: text,
              level: widget.receipt.draftLevel,
              isTitle: false,
              struck: false),
        ],
        draft: '',
      ),
    );
  }

  void _commitListTitle() {
    if (widget.receipt.items.isNotEmpty || widget.receipt.draftLevel != 0) {
      return;
    }
    final text = widget.receipt.draft.trim();
    if (text.isEmpty) return;
    widget.onChanged(
      widget.receipt.copyWith(
        items: [
          ListItem(
            text: text,
            level: 0,
            isTitle: true,
            struck: false,
            titleKind: 'list',
          ),
        ],
        draft: '',
      ),
    );
  }

  void _strike(int index) {
    final item = widget.receipt.items[index];
    if (item.isTitle || item.struck) return;
    final items = [...widget.receipt.items];
    items[index] = item.copyWith(struck: true);
    widget.onChanged(widget.receipt.copyWith(items: items));
  }
}

class MemoView extends StatefulWidget {
  const MemoView({
    required this.memo,
    required this.editing,
    required this.onStopEdit,
    required this.onChanged,
    this.mobile = false,
    super.key,
  });

  final MemoPaper memo;
  final bool editing;
  final bool mobile;
  final VoidCallback onStopEdit;
  final ValueChanged<Paper> onChanged;

  @override
  State<MemoView> createState() => _MemoViewState();
}

class _MemoViewState extends State<MemoView> {
  static const pen = '#2a2a2a';
  final controller = TextEditingController();
  final textFocusNode = FocusNode();
  List<StrokePoint>? drawing;

  @override
  void initState() {
    super.initState();
    controller.text = widget.memo.text;
  }

  @override
  void didUpdateWidget(covariant MemoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.memo.text) {
      controller.text = widget.memo.text;
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
    }
    if (widget.editing && !oldWidget.editing) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => textFocusNode.requestFocus());
    }
  }

  @override
  void dispose() {
    controller.dispose();
    textFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memo = widget.memo;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onStopEdit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        width: memo.size,
        height: memo.size,
        decoration: BoxDecoration(
          color: Color(memoColors[memo.color] ?? memoColors['red']!),
          boxShadow: const [
            BoxShadow(
                color: Color(0x4d000000), blurRadius: 10, offset: Offset(2, 6))
          ],
          border: widget.editing
              ? Border.all(color: const Color(0x88405ac8), width: 2)
              : null,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: controller,
                focusNode: textFocusNode,
                readOnly: !widget.editing,
                enableInteractiveSelection: widget.editing,
                maxLines: null,
                decoration: const InputDecoration.collapsed(hintText: ''),
                style: const TextStyle(
                    fontSize: 32,
                    height: 1.35,
                    fontFamily: 'Courier',
                    color: Color(0xff222222)),
                onChanged: (value) =>
                    widget.onChanged(memo.copyWith(text: value)),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: DoodlePainter(strokes: memo.strokes, active: drawing),
              ),
            ),
            if (widget.editing)
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _drawDown,
                  onPointerMove: _drawMove,
                  onPointerUp: (_) => _drawUp(),
                  onPointerCancel: (_) => _drawUp(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _drawDown(PointerDownEvent event) {
    textFocusNode.requestFocus();
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(event.position);
    setState(() => drawing = [StrokePoint(x: local.dx, y: local.dy)]);
  }

  void _drawMove(PointerMoveEvent event) {
    if (drawing == null) return;
    final box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(event.position);
    setState(
        () => drawing = [...drawing!, StrokePoint(x: local.dx, y: local.dy)]);
  }

  void _drawUp() {
    final points = drawing;
    setState(() => drawing = null);
    if (points == null || points.isEmpty) return;
    widget.onChanged(widget.memo.copyWith(
        strokes: [...widget.memo.strokes, Stroke(color: pen, points: points)]));
  }
}

class DoodlePainter extends CustomPainter {
  DoodlePainter({required this.strokes, this.active});

  final List<Stroke> strokes;
  final List<StrokePoint>? active;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in [
      ...strokes,
      if (active != null) Stroke(color: '#2a2a2a', points: active!)
    ]) {
      final paint = Paint()
        ..color = _hex(stroke.color)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < stroke.points.length; i++) {
        final point = stroke.points[i];
        if (i == 0) {
          path.moveTo(point.x, point.y);
        } else {
          path.lineTo(point.x, point.y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DoodlePainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.active != active;
  }
}

class BallView extends StatelessWidget {
  const BallView({required this.ball, super.key});

  final String ball;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/$ball.png',
      width: ballSize,
      height: ballSize,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

class PinClip extends StatelessWidget {
  const PinClip({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: -14,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 26,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xff8a8f98), width: 3),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xffd9dde3), Color(0xffaab0b9), Color(0xffc7ccd3)],
            ),
          ),
        ),
      ),
    );
  }
}

class ReceiptPrinter extends StatefulWidget {
  const ReceiptPrinter({required this.onPrint, super.key});

  final VoidCallback onPrint;

  @override
  State<ReceiptPrinter> createState() => _ReceiptPrinterState();
}

class _ReceiptPrinterState extends State<ReceiptPrinter> {
  bool hover = false;
  bool emerging = false;

  @override
  Widget build(BuildContext context) {
    const width = 280.0;
    const height = width * 461 / 541;
    return Positioned(
      right: 28,
      bottom: 0,
      width: width,
      height: height,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        offset: Offset(0, hover || emerging ? 0.30 : 0.62),
        child: MouseRegion(
          onEnter: (_) => setState(() => hover = true),
          onExit: (_) => setState(() => hover = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _print,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Image.asset(
                  'assets/receipt_printer.png',
                  width: width,
                  height: height,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
                if (emerging)
                  Positioned(
                    left: 65,
                    bottom: height - 78,
                    width: 150,
                    height: 150,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.2, end: 1),
                      duration: const Duration(milliseconds: 650),
                      onEnd: () {
                        if (!mounted) return;
                        setState(() => emerging = false);
                        widget.onPrint();
                      },
                      builder: (context, value, child) => Transform.scale(
                        alignment: Alignment.bottomCenter,
                        scaleY: value,
                        child: child,
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xfffbfbf7),
                          boxShadow: [
                            BoxShadow(
                                color: Color(0x40000000),
                                blurRadius: 8,
                                offset: Offset(0, -3))
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _print() {
    if (emerging) return;
    setState(() => emerging = true);
  }
}

class PostItBoard extends StatefulWidget {
  const PostItBoard({required this.onPick, super.key});

  final ValueChanged<String> onPick;

  @override
  State<PostItBoard> createState() => _PostItBoardState();
}

class _PostItBoardState extends State<PostItBoard> {
  bool hover = false;
  bool open = false;

  @override
  Widget build(BuildContext context) {
    const width = 240.0;
    const height = width * 654 / 275;
    final slide = open
        ? 0.14
        : hover
            ? 0.52
            : 0.80;
    return Positioned(
      right: 320,
      bottom: 0,
      width: width,
      height: height,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        offset: Offset(0, slide),
        child: MouseRegion(
          onEnter: (_) => setState(() => hover = true),
          onExit: (_) => setState(() => hover = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => open = !open),
            child: Container(
              decoration: BoxDecoration(
                image: const DecorationImage(
                    image: AssetImage('assets/cardboard_bg.jpg'),
                    fit: BoxFit.fill),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 16,
                      offset: Offset(0, -6))
                ],
              ),
              child: Stack(
                children: [
                  AnimatedOpacity(
                    opacity: open ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: SizedBox.expand(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 70),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            for (final color in memoColorNames) ...[
                              GestureDetector(
                                onTap: () {
                                  widget.onPick(color);
                                  setState(() => open = false);
                                },
                                child: Transform.rotate(
                                  angle: -0.035,
                                  child: Container(
                                    width: 96,
                                    height: 96,
                                    color: Color(memoColors[color]!),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!open)
                    Positioned(
                      top: 8,
                      left: 0,
                      right: 0,
                      child: AnimatedOpacity(
                        opacity: hover ? 0.9 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Center(
                          child: Text('post-its',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xff5a4632))),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PaperBin extends StatefulWidget {
  const PaperBin(
      {required this.count,
      required this.onOpen,
      this.alert = false,
      super.key});

  final int count;
  final bool alert;
  final VoidCallback onOpen;

  @override
  State<PaperBin> createState() => _PaperBinState();
}

class _PaperBinState extends State<PaperBin> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    const width = 150.0;
    const height = width * 857 / 718;
    return Positioned(
      left: 28,
      bottom: 0,
      width: width,
      height: height,
      child: MouseRegion(
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onOpen,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            offset: Offset(0, hover || widget.alert ? 0.30 : 0.55),
            child: Stack(
              children: [
                Image.asset('assets/paperbin_side.png',
                    width: width, height: height, fit: BoxFit.contain),
                if (widget.count > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 22, minHeight: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                          color: const Color(0xffc0392b),
                          borderRadius: BorderRadius.circular(11)),
                      child: Center(
                        child: Text(
                          '${widget.count}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BinScreen extends StatelessWidget {
  const BinScreen(
      {required this.balls,
      required this.onLeave,
      required this.onClear,
      super.key});

  final List<Paper> balls;
  final VoidCallback onLeave;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xff2b2b2b),
      child: Stack(
        children: [
          Center(
            child: Image.asset(
              'assets/paperbin_top.png',
              width: min(MediaQuery.sizeOf(context).width,
                      MediaQuery.sizeOf(context).height) *
                  0.9,
              fit: BoxFit.contain,
            ),
          ),
          for (final ball in balls) BinBall(ball: ball),
          Positioned(
            top: 20,
            left: 20,
            child: Row(
              children: [
                _SmallButton(label: '< Leave', onTap: onLeave),
                const SizedBox(width: 12),
                _SmallButton(
                    label: 'Clear trash',
                    onTap: balls.isEmpty ? null : onClear,
                    danger: true),
              ],
            ),
          ),
          if (balls.isEmpty)
            const Center(
              child: Text('The bin is empty.',
                  style: TextStyle(color: Color(0xbbeeeeee))),
            ),
        ],
      ),
    );
  }
}

class BinBall extends StatefulWidget {
  const BinBall({required this.ball, super.key});

  final Paper ball;

  @override
  State<BinBall> createState() => _BinBallState();
}

class _BinBallState extends State<BinBall> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final offset = _scatter(widget.ball.id, MediaQuery.sizeOf(context));
    return Positioned(
      left: MediaQuery.sizeOf(context).width / 2 + offset.dx - 45,
      top: MediaQuery.sizeOf(context).height / 2 + offset.dy - 45,
      width: open ? 260 : 90,
      height: open ? 380 : 90,
      child: GestureDetector(
        onLongPressStart: (_) => setState(() => open = true),
        onLongPressEnd: (_) => setState(() => open = false),
        child: open
            ? _PaperPreview(paper: widget.ball)
            : BallView(ball: widget.ball.ball),
      ),
    );
  }
}

class _PaperPreview extends StatelessWidget {
  const _PaperPreview({required this.paper});

  final Paper paper;

  @override
  Widget build(BuildContext context) {
    if (paper is ReceiptPaper) {
      final receipt = paper as ReceiptPaper;
      return Center(
        child: ReceiptView(
          receipt: receipt,
          editing: false,
          onStopEdit: () {},
          onChanged: (_) {},
        ),
      );
    }
    final memo = paper as MemoPaper;
    return Center(
      child: MemoView(
        memo: memo,
        editing: false,
        onStopEdit: () {},
        onChanged: (_) {},
      ),
    );
  }
}

class SyncStrip extends StatelessWidget {
  const SyncStrip({required this.controller, super.key});

  final TackboardController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      right: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xeefbf8e8),
          border: Border.all(color: const Color(0xaa362618), width: 2),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 240,
                child: Text(
                  controller.syncDirectory,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xff3d2b1b)),
                ),
              ),
              const SizedBox(width: 8),
              _SmallButton(
                label: 'Sync',
                onTap: () {
                  unawaited(controller.syncNow());
                },
              ),
              const SizedBox(width: 6),
              _SmallButton(
                label: 'Folder',
                onTap: () {
                  unawaited(controller.chooseSyncDirectory());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton(
      {required this.label, required this.onTap, this.danger = false});

  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: onTap == null
            ? const Color(0xff999999)
            : danger
                ? const Color(0xffc0392b)
                : const Color(0xfff5f5f0),
        foregroundColor: danger ? Colors.white : const Color(0xff2d2418),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xff333333), width: 2),
        ),
        textStyle: const TextStyle(
            fontFamily: 'Courier', fontWeight: FontWeight.w700, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Text(label),
    );
  }
}

class TmuxSessionView extends StatefulWidget {
  const TmuxSessionView({
    required this.controller,
    required this.boardSize,
    required this.onDetach,
    super.key,
  });

  final TackboardController controller;
  final Size boardSize;
  final VoidCallback onDetach;

  @override
  State<TmuxSessionView> createState() => _TmuxSessionViewState();
}

class _TmuxSessionViewState extends State<TmuxSessionView> {
  final focusNode = FocusNode();
  final List<_TmuxWindow> windows = <_TmuxWindow>[];
  int currentWindow = 0;
  int chooserIndex = 0;
  int windowSerial = 2;
  int paneSerial = 1;
  bool prefix = false;
  bool chooserOpen = false;
  bool renaming = false;
  bool helpOpen = false;
  bool trashWindowClosed = false;
  bool restoredLayout = false;
  String renameDraft = '';
  String message = 'attached';
  String? lastPersistedLayout;

  List<ReceiptPaper> get receipts => widget.controller.onBoard
      .whereType<ReceiptPaper>()
      .where((paper) => !paper.balled)
      .toList(growable: false);

  List<MemoPaper> get memos => widget.controller.onBoard
      .whereType<MemoPaper>()
      .where((paper) => paper.text.trim().isNotEmpty)
      .toList(growable: false);

  _TmuxWindow get activeWindow {
    _syncSessionWithPapers();
    currentWindow = currentWindow.clamp(0, windows.length - 1);
    return windows[currentWindow];
  }

  @override
  void initState() {
    super.initState();
    _restorePersistedLayout();
    _syncSessionWithPapers();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => focusNode.requestFocus());
  }

  @override
  void didUpdateWidget(covariant TmuxSessionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _restorePersistedLayout();
    _syncSessionWithPapers();
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _restorePersistedLayout();
    _syncSessionWithPapers();
    final entries = _chooserEntries();
    if (entries.isNotEmpty) {
      chooserIndex = chooserIndex.clamp(0, entries.length - 1);
    }

    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: _key,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: focusNode.requestFocus,
        child: Container(
          color: const Color(0xff080b08),
          child: Stack(
            children: [
              Column(
                children: [
                  TmuxAlertTicker(memos: memos),
                  Expanded(child: _buildWindow(activeWindow)),
                  _TmuxStatusBar(
                    windows: windows,
                    current: currentWindow,
                    prefix: prefix,
                    renaming: renaming,
                    message: message,
                    renameDraft: renameDraft,
                    onSelect: (index) {
                      setState(() => currentWindow = index);
                      _persistLayout();
                    },
                  ),
                ],
              ),
              if (chooserOpen) _buildChooser(entries),
              if (helpOpen) _buildHelp(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWindow(_TmuxWindow window) {
    if (window.trash) return _buildTrashWindow();
    final root = window.root;
    if (root == null) {
      return _TmuxEmptyPane(
        title: window.name,
        active: true,
        onTap: focusNode.requestFocus,
      );
    }
    return _buildNode(window, root);
  }

  Widget _buildNode(_TmuxWindow window, _TmuxNode node) {
    final pane = node.pane;
    if (pane != null) {
      return _TmuxReceiptPane(
        pane: pane,
        receipt: _receiptFor(pane.paperId),
        active: pane.id == window.activePaneId,
        onTap: () {
          setState(() {
            window.activePaneId = pane.id;
            _ensureSelectableItem(pane, _receiptFor(pane.paperId));
            message = 'pane ${pane.label}';
          });
          _persistLayout();
          focusNode.requestFocus();
        },
        onStrike: (receipt, index) => _strikeItem(receipt, index),
        onSelectItem: (index) {
          setState(() {
            pane.selectedItemIndex = index;
            window.activePaneId = pane.id;
            message = 'item ${index + 1}';
          });
          _persistLayout();
          focusNode.requestFocus();
        },
      );
    }
    final children = [
      for (final child in node.children)
        Expanded(child: _buildNode(window, child)),
    ];
    return node.splitAxis == Axis.horizontal
        ? Row(children: children)
        : Column(children: children);
  }

  Widget _buildTrashWindow() {
    final binned = widget.controller.binned;
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xff060906),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('trash', style: _tmuxTitleStyle),
          const SizedBox(height: 10),
          Expanded(
            child: binned.isEmpty
                ? const Center(
                    child: Text('The bin is empty.',
                        style: TextStyle(
                            color: Color(0xff779977),
                            fontFamily: 'Courier',
                            fontSize: 16)),
                  )
                : ListView.builder(
                    itemCount: binned.length,
                    itemBuilder: (context, index) {
                      final paper = binned[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '${index + 1}. ${_paperTitle(paper)}',
                          style: const TextStyle(
                              color: Color(0xffc7f9c7),
                              fontFamily: 'Courier',
                              fontSize: 15),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChooser(List<_TmuxChooserEntry> entries) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xcc000000),
        child: Center(
          child: Container(
            width: min(760, MediaQuery.sizeOf(context).width * 0.86),
            height: min(520, MediaQuery.sizeOf(context).height * 0.76),
            decoration: BoxDecoration(
              color: const Color(0xff101610),
              border: Border.all(color: const Color(0xff76d676), width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: const Color(0xff76d676),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: const Text('windows',
                      style: TextStyle(
                          color: Color(0xff071007),
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? const Center(
                          child: Text('no windows', style: _tmuxDimStyle))
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            final selected = index == chooserIndex;
                            return GestureDetector(
                              onTap: () => _openChooserEntry(entry),
                              child: Container(
                                color: selected
                                    ? const Color(0xff234723)
                                    : Colors.transparent,
                                padding: EdgeInsets.only(
                                  left: entry.pane == null ? 12 : 36,
                                  right: 12,
                                  top: 6,
                                  bottom: 6,
                                ),
                                child: Text(
                                  entry.label,
                                  style: TextStyle(
                                    color: selected
                                        ? const Color(0xffffffff)
                                        : const Color(0xffc7f9c7),
                                    fontFamily: 'Courier',
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  color: const Color(0xff0b110b),
                  child: const Text('Enter open   x kill   Esc close',
                      style: _tmuxDimStyle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHelp() {
    const lines = [
      'C-b d detach to tackboard',
      'C-b w window tree',
      'C-b c new window/list',
      'C-b % split right',
      'C-b " split down',
      'C-b x kill pane/window',
      'C-b , rename window',
      'C-b n / p next / previous',
      'C-b arrows select pane',
      'Up / Down select list item',
      'C-b Space clears selected item',
      'Enter commits typed text',
      'Tab makes a sub-list title',
    ];
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => helpOpen = false),
        child: Container(
          color: const Color(0xcc000000),
          child: Center(
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xff101610),
                border: Border.all(color: const Color(0xff76d676), width: 2),
              ),
              child: Text(lines.join('\n'), style: _tmuxPaneStyle),
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (renaming) return _renameKey(event);
    if (chooserOpen) return _chooserKey(event);
    if (helpOpen) {
      setState(() => helpOpen = false);
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed &&
        key == LogicalKeyboardKey.keyB) {
      setState(() {
        prefix = true;
        message = 'prefix';
      });
      return KeyEventResult.handled;
    }
    if (prefix) {
      if (_isModifierKey(key)) return KeyEventResult.handled;
      _prefixKey(event);
      return KeyEventResult.handled;
    }
    return _editKey(event);
  }

  KeyEventResult _renameKey(KeyDownEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        renaming = false;
        message = 'rename cancelled';
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final name = renameDraft.trim();
      if (name.isNotEmpty) activeWindow.name = name;
      setState(() {
        renaming = false;
        message = 'renamed ${activeWindow.name}';
      });
      _persistLayout();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (renameDraft.isNotEmpty) {
        setState(() => renameDraft =
            renameDraft.substring(0, max(0, renameDraft.length - 1)));
      }
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        character.codeUnitAt(0) >= 32) {
      setState(() => renameDraft += character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _chooserKey(KeyDownEvent event) {
    final entries = _chooserEntries();
    if (entries.isEmpty) {
      setState(() => chooserOpen = false);
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.keyW) {
      setState(() => chooserOpen = false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyJ) {
      setState(() => chooserIndex = min(entries.length - 1, chooserIndex + 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyK) {
      setState(() => chooserIndex = max(0, chooserIndex - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyX) {
      _killChooserEntry(entries[chooserIndex]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _openChooserEntry(entries[chooserIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  void _prefixKey(KeyDownEvent event) {
    final key = event.logicalKey;
    setState(() => prefix = false);
    if (key == LogicalKeyboardKey.keyD) {
      widget.onDetach();
    } else if (key == LogicalKeyboardKey.keyW) {
      setState(() {
        chooserOpen = true;
        chooserIndex = 0;
        message = 'choose-window';
      });
    } else if (key == LogicalKeyboardKey.keyC) {
      _newWindow();
    } else if (_matchesPercent(event)) {
      _split(Axis.horizontal);
    } else if (_matchesDoubleQuote(event)) {
      _split(Axis.vertical);
    } else if (key == LogicalKeyboardKey.keyX) {
      _killActive();
    } else if (key == LogicalKeyboardKey.comma) {
      setState(() {
        renaming = true;
        renameDraft = activeWindow.name;
        message = 'rename-window';
      });
    } else if (key == LogicalKeyboardKey.keyN) {
      _selectWindow(currentWindow + 1);
    } else if (key == LogicalKeyboardKey.keyP) {
      _selectWindow(currentWindow - 1);
    } else if (key == LogicalKeyboardKey.keyO ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      _selectPane(1);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _selectPane(-1);
    } else if (key == LogicalKeyboardKey.space) {
      _clearSelectedReceiptItem();
    } else if (_matchesQuestion(event)) {
      setState(() => helpOpen = true);
    } else {
      setState(() => message = 'unknown prefix');
    }
  }

  bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.capsLock;
  }

  KeyEventResult _editKey(KeyDownEvent event) {
    final window = activeWindow;
    if (window.trash) return KeyEventResult.handled;
    final pane = window.activePane;
    final receipt = _receiptFor(pane?.paperId);
    if (pane == null || receipt == null) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _selectReceiptItem(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _selectReceiptItem(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _commitReceiptDraft(receipt);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _changeReceipt(receipt,
            receipt.copyWith(draftLevel: max(0, receipt.draftLevel - 1)));
      } else {
        _commitReceiptTitle(receipt);
      }
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        character.codeUnitAt(0) >= 32) {
      _changeReceipt(
          receipt, receipt.copyWith(draft: receipt.draft + character));
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  void _syncSessionWithPapers() {
    _restorePersistedLayout();
    var changed = false;
    final liveIds = receipts.map((paper) => paper.id).toSet();
    if (windows.isEmpty) {
      final grouped = _receiptsByWindow(receipts);
      if (grouped.isEmpty) {
        windows.add(_TmuxWindow(id: 'w_text', name: 'text'));
      } else {
        for (final entry in grouped.entries) {
          windows.add(
            _TmuxWindow(
              id: entry.key,
              name: _windowNameForId(entry.key),
              panes: [
                for (final receipt in entry.value)
                  _TmuxPane(id: _nextPaneId(), paperId: receipt.id),
              ],
            ),
          );
        }
      }
      windows.add(_TmuxWindow(id: 'w_trash', name: 'trash', trash: true));
      changed = true;
    }

    for (final window in windows.where((window) => !window.trash)) {
      for (final pane in window.panes) {
        _tagReceiptWindow(pane.paperId, window.id);
        _ensureSelectableItem(pane, _receiptFor(pane.paperId));
      }
      final before = window.panes.length;
      final stalePanes = window.panes
          .where(
              (pane) => pane.paperId != null && !liveIds.contains(pane.paperId))
          .toList(growable: false);
      for (final pane in stalePanes) {
        window.removePane(pane);
      }
      if (window.panes.length != before) changed = true;
      if (window.activePaneId == null ||
          !window.panes.any((pane) => pane.id == window.activePaneId)) {
        final nextActivePaneId =
            window.panes.isNotEmpty ? window.panes.first.id : null;
        if (window.activePaneId != nextActivePaneId) {
          window.activePaneId = nextActivePaneId;
          changed = true;
        }
      }
    }

    final panePaperIds = windows
        .expand((window) => window.panes)
        .map((pane) => pane.paperId)
        .whereType<String>()
        .toSet();
    final missing = receipts
        .where((receipt) => !panePaperIds.contains(receipt.id))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      final grouped = _receiptsByWindow(missing);
      for (final entry in grouped.entries) {
        final target = _windowForReceiptGroup(entry.key);
        for (final receipt in entry.value) {
          target.addPane(_TmuxPane(id: _nextPaneId(), paperId: receipt.id));
          _tagReceiptWindow(receipt.id, target.id);
        }
      }
      changed = true;
    }

    final beforeWindowCount = windows.length;
    windows.removeWhere(
      (window) => !window.trash && window.panes.isEmpty && windows.length > 1,
    );
    if (windows.length != beforeWindowCount) changed = true;
    if (!windows.any((window) => !window.trash)) {
      windows.insert(0, _TmuxWindow(id: 'w_text', name: 'text'));
      changed = true;
    }
    if (!trashWindowClosed && !windows.any((window) => window.trash)) {
      windows.add(_TmuxWindow(id: 'w_trash', name: 'trash', trash: true));
      changed = true;
    }
    if (trashWindowClosed &&
        widget.controller.binned.isNotEmpty &&
        !windows.any((window) => window.trash)) {
      trashWindowClosed = false;
      windows.add(_TmuxWindow(id: 'w_trash', name: 'trash', trash: true));
      changed = true;
    }
    final nextCurrent = currentWindow.clamp(0, windows.length - 1);
    if (nextCurrent != currentWindow) {
      currentWindow = nextCurrent;
      changed = true;
    }
    unawaited(widget.controller.clearPendingTackboardTmuxWindow());
    if (changed) _persistLayout();
  }

  Future<void> _newWindow() async {
    final serial = windowSerial++;
    final windowId = 'w_$serial';
    final receipt =
        widget.controller.makeReceipt(widget.boardSize, tmuxWindowId: windowId);
    setState(() {
      final window = _TmuxWindow(
        id: windowId,
        name: 'text-$serial',
        panes: [_TmuxPane(id: _nextPaneId(), paperId: receipt.id)],
      );
      windows.insert(
          max(0, windows.length - (_hasTrashWindow ? 1 : 0)), window);
      currentWindow = windows.indexOf(window);
      message = 'new-window ${window.name}';
    });
    _persistLayout();
    await widget.controller.addPaper(receipt);
  }

  Future<void> _split(Axis axis) async {
    final window = activeWindow;
    if (window.trash) {
      setState(() => message = 'cannot split trash');
      return;
    }
    final receipt = widget.controller
        .makeReceipt(widget.boardSize, tmuxWindowId: window.id);
    setState(() {
      final pane = _TmuxPane(id: _nextPaneId(), paperId: receipt.id);
      window.splitActivePane(axis, pane);
      message = axis == Axis.horizontal ? 'split right' : 'split down';
    });
    _persistLayout();
    await widget.controller.addPaper(receipt);
  }

  void _killActive() {
    final window = activeWindow;
    if (window.trash) {
      setState(() {
        trashWindowClosed = true;
        windows.remove(window);
        currentWindow = max(0, currentWindow - 1);
        message = 'trash window killed';
      });
      _persistLayout();
      return;
    }
    final pane = window.activePane;
    if (pane == null) {
      _killWindow(window);
      _persistLayout();
      return;
    }
    _killPane(window, pane);
  }

  void _killPane(_TmuxWindow window, _TmuxPane pane) {
    setState(() {
      window.removePane(pane);
      if (pane.paperId != null) {
        trashWindowClosed = false;
        if (!windows.any((candidate) => candidate.trash)) {
          windows.add(_TmuxWindow(id: 'w_trash', name: 'trash', trash: true));
        }
        unawaited(widget.controller.trashPaper(pane.paperId!));
      }
      if (window.panes.isEmpty) {
        _killWindow(window, quiet: true);
      }
      message = 'killed pane ${pane.label}';
    });
    _persistLayout();
  }

  void _killWindow(_TmuxWindow window, {bool quiet = false}) {
    if (window.trash) {
      trashWindowClosed = true;
      windows.remove(window);
      return;
    }
    for (final pane in window.panes) {
      if (pane.paperId != null) {
        trashWindowClosed = false;
        unawaited(widget.controller.trashPaper(pane.paperId!));
      }
    }
    windows.remove(window);
    if (!windows.any((candidate) => !candidate.trash)) {
      windows.insert(0, _TmuxWindow(id: 'w_text', name: 'text'));
    }
    if (!windows.any((candidate) => candidate.trash)) {
      windows.add(_TmuxWindow(id: 'w_trash', name: 'trash', trash: true));
    }
    currentWindow = currentWindow.clamp(0, windows.length - 1);
    if (!quiet) message = 'killed window ${window.name}';
  }

  void _openChooserEntry(_TmuxChooserEntry entry) {
    setState(() {
      currentWindow = windows.indexOf(entry.window);
      if (entry.pane != null) entry.window.activePaneId = entry.pane!.id;
      chooserOpen = false;
      message = entry.label;
    });
    _persistLayout();
  }

  void _killChooserEntry(_TmuxChooserEntry entry) {
    if (entry.pane != null) {
      _killPane(entry.window, entry.pane!);
    } else {
      setState(() => _killWindow(entry.window));
      _persistLayout();
    }
    setState(() {
      chooserOpen = true;
      final entries = _chooserEntries();
      chooserIndex =
          entries.isEmpty ? 0 : chooserIndex.clamp(0, entries.length - 1);
    });
  }

  void _selectWindow(int index) {
    final next = index < 0
        ? windows.length - 1
        : index >= windows.length
            ? 0
            : index;
    setState(() {
      currentWindow = next;
      message = windows[next].name;
    });
    _persistLayout();
  }

  void _selectPane(int delta) {
    final window = activeWindow;
    if (window.trash || window.panes.isEmpty) return;
    final current = max(
        0, window.panes.indexWhere((pane) => pane.id == window.activePaneId));
    final next = (current + delta) % window.panes.length;
    setState(() {
      window.activePaneId =
          window.panes[next < 0 ? window.panes.length - 1 : next].id;
      message = 'pane ${window.activePane!.label}';
    });
    _persistLayout();
  }

  Map<String, List<ReceiptPaper>> _receiptsByWindow(List<ReceiptPaper> source) {
    final groups = <String, List<ReceiptPaper>>{};
    for (final receipt in source) {
      final id = receipt.tmuxWindowId;
      final windowId = id == null || id.isEmpty ? 'w_text' : id;
      groups.putIfAbsent(windowId, () => <ReceiptPaper>[]).add(receipt);
    }
    return groups;
  }

  _TmuxWindow _windowForReceiptGroup(String windowId) {
    for (final window in windows) {
      if (!window.trash && window.id == windowId) return window;
    }
    final window = _TmuxWindow(id: windowId, name: _windowNameForId(windowId));
    windows.insert(max(0, windows.length - (_hasTrashWindow ? 1 : 0)), window);
    return window;
  }

  void _tagReceiptWindow(String? paperId, String windowId) {
    final receipt = _receiptFor(paperId);
    if (receipt == null || receipt.tmuxWindowId == windowId) return;
    unawaited(
      widget.controller.updatePaper(
        receipt.id,
        (_) => receipt.copyWith(tmuxWindowId: windowId),
      ),
    );
  }

  String _windowNameForId(String id) {
    if (id == 'w_text') return 'text';
    final numeric = RegExp(r'^w_(\d+)$').firstMatch(id);
    if (numeric != null) return 'text-${numeric.group(1)}';
    return 'text-${windowSerial++}';
  }

  void _commitReceiptDraft(ReceiptPaper receipt) {
    final text = receipt.draft.trim();
    if (text.isEmpty) return;
    _changeReceipt(
      receipt,
      receipt.copyWith(
        items: [
          ...receipt.items,
          ListItem(
              text: text,
              level: receipt.draftLevel,
              isTitle: false,
              struck: false),
        ],
        draft: '',
      ),
    );
  }

  void _commitReceiptTitle(ReceiptPaper receipt) {
    final text = receipt.draft.trim();
    if (text.isEmpty) return;
    _changeReceipt(
      receipt,
      receipt.copyWith(
        items: [
          ...receipt.items,
          ListItem(
              text: text,
              level: receipt.draftLevel,
              isTitle: true,
              struck: false,
              titleKind: 'sublist'),
        ],
        draft: '',
        draftLevel: receipt.draftLevel + 1,
      ),
    );
  }

  void _strikeItem(ReceiptPaper receipt, int index) {
    if (index < 0 || index >= receipt.items.length) return;
    final item = receipt.items[index];
    if (item.isTitle || item.struck) return;
    final items = [...receipt.items];
    items[index] = item.copyWith(struck: true);
    _changeReceipt(receipt, receipt.copyWith(items: items));
  }

  void _selectReceiptItem(int delta) {
    final window = activeWindow;
    if (window.trash) return;
    final pane = window.activePane;
    final receipt = _receiptFor(pane?.paperId);
    if (pane == null || receipt == null) return;
    final selectable = _selectableItemIndexes(receipt);
    if (selectable.isEmpty) {
      setState(() => message = 'no clearable items');
      return;
    }
    final current = selectable.contains(pane.selectedItemIndex)
        ? selectable.indexOf(pane.selectedItemIndex)
        : 0;
    final next = (current + delta) % selectable.length;
    setState(() {
      pane.selectedItemIndex =
          selectable[next < 0 ? selectable.length - 1 : next];
      message = 'item ${pane.selectedItemIndex + 1}';
    });
    _persistLayout();
  }

  void _clearSelectedReceiptItem() {
    final window = activeWindow;
    if (window.trash) return;
    final pane = window.activePane;
    final receipt = _receiptFor(pane?.paperId);
    if (pane == null || receipt == null) return;
    final selected = _ensureSelectableItem(pane, receipt);
    if (selected == null) {
      setState(() => message = 'no clearable items');
      return;
    }
    _strikeItem(receipt, selected);
    setState(() => message = 'cleared item ${selected + 1}');
    _persistLayout();
  }

  int? _ensureSelectableItem(_TmuxPane pane, ReceiptPaper? receipt) {
    if (receipt == null) return null;
    final selectable = _selectableItemIndexes(receipt);
    if (selectable.isEmpty) return null;
    if (!selectable.contains(pane.selectedItemIndex)) {
      pane.selectedItemIndex = selectable.first;
    }
    return pane.selectedItemIndex;
  }

  List<int> _selectableItemIndexes(ReceiptPaper receipt) {
    return [
      for (var i = 0; i < receipt.items.length; i++)
        if (!receipt.items[i].isTitle) i,
    ];
  }

  void _changeReceipt(ReceiptPaper receipt, ReceiptPaper next) {
    unawaited(widget.controller.updatePaper(receipt.id, (_) => next));
  }

  void _restorePersistedLayout() {
    final source = widget.controller.tmuxLayoutJson;
    if (source == null || source.isEmpty) {
      restoredLayout = true;
      return;
    }
    if (restoredLayout && source == lastPersistedLayout) return;
    restoredLayout = true;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return;
      final rawWindows = decoded['windows'];
      if (rawWindows is! List) return;
      final restoredWindows = rawWindows
          .whereType<Map>()
          .map(_TmuxWindow.fromJson)
          .where((window) => window != null)
          .cast<_TmuxWindow>()
          .toList(growable: false);
      if (restoredWindows.isEmpty) return;
      windows
        ..clear()
        ..addAll(restoredWindows);
      currentWindow = _intFromJson(decoded['currentWindow'], 0);
      windowSerial = max(2, _intFromJson(decoded['windowSerial'], 2));
      paneSerial = max(1, _intFromJson(decoded['paneSerial'], 1));
      trashWindowClosed = decoded['trashWindowClosed'] == true;
      lastPersistedLayout = source;
    } catch (_) {
      // Fall back to a fresh tmux layout if an older setting is malformed.
    }
  }

  void _persistLayout() {
    if (!widget.controller.loaded) return;
    final encoded = jsonEncode({
      'schema': 1,
      'currentWindow': currentWindow,
      'windowSerial': windowSerial,
      'paneSerial': paneSerial,
      'trashWindowClosed': trashWindowClosed,
      'windows':
          windows.map((window) => window.toJson()).toList(growable: false),
    });
    if (encoded == lastPersistedLayout) return;
    lastPersistedLayout = encoded;
    unawaited(widget.controller.saveTmuxLayout(encoded));
  }

  List<_TmuxChooserEntry> _chooserEntries() {
    final entries = <_TmuxChooserEntry>[];
    for (var i = 0; i < windows.length; i++) {
      final window = windows[i];
      entries.add(_TmuxChooserEntry.window(window, '$i: ${window.name}'));
      for (var p = 0; p < window.panes.length; p++) {
        final pane = window.panes[p];
        entries.add(
          _TmuxChooserEntry.pane(
            window,
            pane,
            'pane $p  ${_paperTitle(_receiptFor(pane.paperId))}',
          ),
        );
      }
    }
    return entries;
  }

  ReceiptPaper? _receiptFor(String? id) {
    if (id == null) return null;
    for (final paper in widget.controller.onBoard) {
      if (paper is ReceiptPaper && paper.id == id) return paper;
    }
    return null;
  }

  bool get _hasTrashWindow => windows.any((window) => window.trash);

  String _nextPaneId() => 'p_${paneSerial++}';

  bool _matchesPercent(KeyDownEvent event) {
    return event.character == '%' ||
        event.logicalKey == LogicalKeyboardKey.percent ||
        (HardwareKeyboard.instance.isShiftPressed &&
            (event.logicalKey == LogicalKeyboardKey.digit5 ||
                event.physicalKey == PhysicalKeyboardKey.digit5));
  }

  bool _matchesDoubleQuote(KeyDownEvent event) {
    return event.character == '"' ||
        event.logicalKey == LogicalKeyboardKey.quote ||
        (HardwareKeyboard.instance.isShiftPressed &&
            (event.logicalKey == LogicalKeyboardKey.quoteSingle ||
                event.physicalKey == PhysicalKeyboardKey.quote));
  }

  bool _matchesQuestion(KeyDownEvent event) {
    return event.character == '?' ||
        event.logicalKey == LogicalKeyboardKey.question ||
        (HardwareKeyboard.instance.isShiftPressed &&
            (event.logicalKey == LogicalKeyboardKey.slash ||
                event.physicalKey == PhysicalKeyboardKey.slash));
  }
}

class _TmuxWindow {
  _TmuxWindow({
    required this.id,
    required this.name,
    this.trash = false,
    List<_TmuxPane>? panes,
    _TmuxNode? root,
  }) : root = root ?? _TmuxNode.fromPanes(panes ?? const <_TmuxPane>[]) {
    activePaneId = this.panes.isNotEmpty ? this.panes.first.id : null;
  }

  final String id;
  String name;
  final bool trash;
  _TmuxNode? root;
  String? activePaneId;

  List<_TmuxPane> get panes => root?.panes() ?? const <_TmuxPane>[];

  static _TmuxWindow? fromJson(Map<dynamic, dynamic> map) {
    final id = map['id']?.toString();
    final name = map['name']?.toString();
    if (id == null || name == null) return null;
    final rawPanes = map['panes'];
    final rawRoot = map['root'];
    final window = _TmuxWindow(
      id: id,
      name: name,
      trash: map['trash'] == true,
      root: rawRoot is Map ? _TmuxNode.fromJson(rawRoot) : null,
      panes: rawRoot is Map
          ? null
          : rawPanes is List
              ? rawPanes
                  .whereType<Map>()
                  .map(_TmuxPane.fromJson)
                  .where((pane) => pane != null)
                  .cast<_TmuxPane>()
                  .toList(growable: false)
              : const <_TmuxPane>[],
    );
    final activePaneId = map['activePaneId']?.toString();
    if (activePaneId != null &&
        window.panes.any((pane) => pane.id == activePaneId)) {
      window.activePaneId = activePaneId;
    }
    return window;
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'trash': trash,
      'activePaneId': activePaneId,
      'root': root?.toJson(),
    };
  }

  _TmuxPane? get activePane {
    for (final pane in panes) {
      if (pane.id == activePaneId) return pane;
    }
    return panes.isEmpty ? null : panes.first;
  }

  void addPane(_TmuxPane pane) {
    root = root == null
        ? _TmuxNode.pane(pane)
        : _TmuxNode.split(Axis.horizontal, [root!, _TmuxNode.pane(pane)]);
    activePaneId = pane.id;
  }

  void splitActivePane(Axis axis, _TmuxPane pane) {
    if (activePaneId == null || root == null) {
      addPane(pane);
      return;
    }
    final split = root!.splitPane(activePaneId!, axis, pane);
    if (split == null) {
      addPane(pane);
      return;
    }
    root = split;
    activePaneId = pane.id;
  }

  void removePane(_TmuxPane pane) {
    root = root?.removePane(pane.id);
    activePaneId = panes.any((candidate) => candidate.id == activePaneId)
        ? activePaneId
        : panes.isNotEmpty
            ? panes.last.id
            : null;
  }
}

class _TmuxNode {
  const _TmuxNode.pane(this.pane)
      : splitAxis = null,
        children = const <_TmuxNode>[];

  const _TmuxNode.split(this.splitAxis, this.children) : pane = null;

  final _TmuxPane? pane;
  final Axis? splitAxis;
  final List<_TmuxNode> children;

  static _TmuxNode? fromPanes(List<_TmuxPane> panes) {
    if (panes.isEmpty) return null;
    if (panes.length == 1) return _TmuxNode.pane(panes.first);
    return _TmuxNode.split(
      Axis.horizontal,
      panes.map(_TmuxNode.pane).toList(growable: false),
    );
  }

  static _TmuxNode? fromJson(Map<dynamic, dynamic> map) {
    if (map['type'] == 'pane') {
      final rawPane = map['pane'];
      if (rawPane is! Map) return null;
      final pane = _TmuxPane.fromJson(rawPane);
      return pane == null ? null : _TmuxNode.pane(pane);
    }
    if (map['type'] == 'split') {
      final rawChildren = map['children'];
      if (rawChildren is! List) return null;
      final children = rawChildren
          .whereType<Map>()
          .map(_TmuxNode.fromJson)
          .where((node) => node != null)
          .cast<_TmuxNode>()
          .toList(growable: false);
      if (children.isEmpty) return null;
      if (children.length == 1) return children.first;
      final axis = map['axis'] == 'vertical' ? Axis.vertical : Axis.horizontal;
      return _TmuxNode.split(axis, children);
    }
    return null;
  }

  List<_TmuxPane> panes() {
    final pane = this.pane;
    if (pane != null) return [pane];
    return [
      for (final child in children) ...child.panes(),
    ];
  }

  _TmuxNode? splitPane(String targetPaneId, Axis axis, _TmuxPane newPane) {
    final pane = this.pane;
    if (pane != null) {
      if (pane.id != targetPaneId) return null;
      return _TmuxNode.split(axis, [
        _TmuxNode.pane(pane),
        _TmuxNode.pane(newPane),
      ]);
    }
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final next = child.splitPane(targetPaneId, axis, newPane);
      if (next == null) continue;
      final updated = [...children];
      updated[i] = next;
      return _TmuxNode.split(splitAxis!, updated);
    }
    return null;
  }

  _TmuxNode? removePane(String targetPaneId) {
    final pane = this.pane;
    if (pane != null) return pane.id == targetPaneId ? null : this;
    final kept = <_TmuxNode>[];
    for (final child in children) {
      final next = child.removePane(targetPaneId);
      if (next != null) kept.add(next);
    }
    if (kept.isEmpty) return null;
    if (kept.length == 1) return kept.first;
    return _TmuxNode.split(splitAxis!, kept);
  }

  Map<String, Object?> toJson() {
    final pane = this.pane;
    if (pane != null) {
      return {'type': 'pane', 'pane': pane.toJson()};
    }
    return {
      'type': 'split',
      'axis': splitAxis == Axis.vertical ? 'vertical' : 'horizontal',
      'children':
          children.map((child) => child.toJson()).toList(growable: false),
    };
  }
}

class _TmuxPane {
  _TmuxPane({
    required this.id,
    required this.paperId,
    this.selectedItemIndex = 0,
  });

  final String id;
  final String? paperId;
  int selectedItemIndex;
  String get label => id.replaceFirst('p_', '');

  static _TmuxPane? fromJson(Map<dynamic, dynamic> map) {
    final id = map['id']?.toString();
    if (id == null) return null;
    return _TmuxPane(
      id: id,
      paperId: map['paperId']?.toString(),
      selectedItemIndex: _intFromJson(map['selectedItemIndex'], 0),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'paperId': paperId,
        'selectedItemIndex': selectedItemIndex,
      };
}

class _TmuxChooserEntry {
  const _TmuxChooserEntry.window(this.window, this.label) : pane = null;
  const _TmuxChooserEntry.pane(this.window, this.pane, this.label);

  final _TmuxWindow window;
  final _TmuxPane? pane;
  final String label;
}

class _TmuxReceiptPane extends StatelessWidget {
  const _TmuxReceiptPane({
    required this.pane,
    required this.receipt,
    required this.active,
    required this.onTap,
    required this.onStrike,
    required this.onSelectItem,
  });

  final _TmuxPane pane;
  final ReceiptPaper? receipt;
  final bool active;
  final VoidCallback onTap;
  final void Function(ReceiptPaper receipt, int index) onStrike;
  final ValueChanged<int> onSelectItem;

  @override
  Widget build(BuildContext context) {
    final receipt = this.receipt;
    final pinned = receipt?.pinned ?? false;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: active ? const Color(0xff0d160d) : const Color(0xff080d08),
          border: Border.all(
            color: pinned
                ? const Color(0xffff4d4d)
                : active
                    ? const Color(0xffd8ff78)
                    : const Color(0xff315931),
            width: pinned ? 3 : (active ? 2 : 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: active ? const Color(0xffd8ff78) : const Color(0xff315931),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                'pane ${pane.label}  ${_paperTitle(receipt)}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active
                      ? const Color(0xff081008)
                      : const Color(0xffd7fbd7),
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: receipt == null
                  ? const _TmuxEmptyPaneBody()
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (var i = 0; i < receipt.items.length; i++)
                          GestureDetector(
                            onTap: receipt.items[i].isTitle
                                ? null
                                : () {
                                    onSelectItem(i);
                                    onStrike(receipt, i);
                                  },
                            child: Container(
                              color: active &&
                                      !receipt.items[i].isTitle &&
                                      pane.selectedItemIndex == i
                                  ? const Color(0xff1d351d)
                                  : Colors.transparent,
                              padding: EdgeInsets.only(
                                left: receipt.items[i].level * 18,
                                right: 6,
                                top: 1,
                                bottom: 5,
                              ),
                              child: Text(
                                receipt.items[i].isTitle
                                    ? receipt.items[i].text
                                    : '- ${receipt.items[i].text}',
                                style: _tmuxPaneStyle.copyWith(
                                  color: receipt.items[i].struck
                                      ? const Color(0xff638263)
                                      : const Color(0xffc7f9c7),
                                  fontWeight: receipt.items[i].isTitle
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  decoration: receipt.items[i].struck
                                      ? TextDecoration.lineThrough
                                      : receipt.items[i].isTitle
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding:
                              EdgeInsets.only(left: receipt.draftLevel * 18),
                          child: Text('> ${receipt.draft}',
                              style: _tmuxPaneStyle.copyWith(
                                  color: const Color(0xffffffff))),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TmuxEmptyPane extends StatelessWidget {
  const _TmuxEmptyPane({
    required this.title,
    required this.active,
    required this.onTap,
  });

  final String title;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xff080d08),
          border: Border.all(color: const Color(0xff315931), width: 1),
        ),
        child: Column(
          children: [
            Container(
              color: const Color(0xff315931),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(title, style: _tmuxPaneStyle),
            ),
            const Expanded(child: _TmuxEmptyPaneBody()),
          ],
        ),
      ),
    );
  }
}

class _TmuxEmptyPaneBody extends StatelessWidget {
  const _TmuxEmptyPaneBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('no list', style: _tmuxDimStyle),
    );
  }
}

class TmuxAlertTicker extends StatefulWidget {
  const TmuxAlertTicker({required this.memos, super.key});

  final List<MemoPaper> memos;

  @override
  State<TmuxAlertTicker> createState() => _TmuxAlertTickerState();
}

class _TmuxAlertTickerState extends State<TmuxAlertTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.memos.isEmpty
        ? 'post-it alerts: --'
        : widget.memos
            .map((memo) => memo.text.trim().replaceAll('\n', ' / '))
            .join('   |   ');
    return Container(
      height: 32,
      color: const Color(0xffd8ff78),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ClipRect(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                final width = constraints.maxWidth;
                return Transform.translate(
                  offset: Offset(width - controller.value * width * 2, 0),
                  child: child,
                );
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$text   |   $text',
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    color: Color(0xff071007),
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TmuxStatusBar extends StatelessWidget {
  const _TmuxStatusBar({
    required this.windows,
    required this.current,
    required this.prefix,
    required this.renaming,
    required this.message,
    required this.renameDraft,
    required this.onSelect,
  });

  final List<_TmuxWindow> windows;
  final int current;
  final bool prefix;
  final bool renaming;
  final String message;
  final String renameDraft;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      color: const Color(0xff315931),
      child: Row(
        children: [
          for (var i = 0; i < windows.length; i++)
            GestureDetector(
              onTap: () => onSelect(i),
              child: Container(
                color: i == current
                    ? const Color(0xffd8ff78)
                    : const Color(0xff315931),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: Text(
                  '$i:${windows[i].name}',
                  style: TextStyle(
                    color: i == current
                        ? const Color(0xff071007)
                        : const Color(0xffd7fbd7),
                    fontFamily: 'Courier',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              renaming
                  ? 'rename: $renameDraft'
                  : prefix
                      ? 'C-b'
                      : message,
              style: const TextStyle(
                color: Color(0xffffffff),
                fontFamily: 'Courier',
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _tmuxTitleStyle = TextStyle(
  color: Color(0xffd8ff78),
  fontFamily: 'Courier',
  fontWeight: FontWeight.w700,
  fontSize: 18,
);

const _tmuxPaneStyle = TextStyle(
  color: Color(0xffc7f9c7),
  fontFamily: 'Courier',
  fontSize: 15,
  height: 1.35,
);

const _tmuxDimStyle = TextStyle(
  color: Color(0xff779977),
  fontFamily: 'Courier',
  fontSize: 14,
);

String _paperTitle(Paper? paper) {
  if (paper == null) return 'empty';
  if (paper is MemoPaper) {
    final text = paper.text.trim().replaceAll('\n', ' ');
    return text.isEmpty ? '${paper.color} memo' : text;
  }
  final receipt = paper as ReceiptPaper;
  for (final item in receipt.items) {
    if (item.text.trim().isNotEmpty) return item.text.trim();
  }
  return receipt.draft.trim().isEmpty
      ? 'untitled receipt'
      : receipt.draft.trim();
}

int _intFromJson(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final List<_ConfettiBit> bits;

  @override
  void initState() {
    super.initState();
    final random = Random();
    bits = List.generate(28, (i) {
      final angle = pi * (0.15 + random.nextDouble() * 0.7);
      final dist = 80 + random.nextDouble() * 160;
      return _ConfettiBit(
        color: [
          0xffef6f6f,
          0xff8fd17a,
          0xff7db4ef,
          0xfff4d35e,
          0xffd291ff,
          0xffffffff
        ][i % 6],
        dx: cos(angle) * dist * (random.nextBool() ? -1 : 1),
        dy: -sin(angle) * dist - random.nextDouble() * 60,
        spin: random.nextDouble() * 720 - 360,
        seed: random.nextDouble(),
      );
    });
    controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300))
      ..forward();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final origin = Offset(110, MediaQuery.sizeOf(context).height - 120);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = Curves.easeOut.transform(controller.value);
          return Stack(
            children: [
              for (final bit in bits)
                Positioned(
                  left: origin.dx + bit.seed * 40 - 20 + bit.dx * t,
                  top:
                      origin.dy + bit.seed * 30 - 15 + bit.dy * t + 180 * t * t,
                  child: Transform.rotate(
                    angle: bit.spin * pi / 180 * t,
                    child: Container(
                        width: 8, height: 12, color: Color(bit.color)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ConfettiBit {
  const _ConfettiBit({
    required this.color,
    required this.dx,
    required this.dy,
    required this.spin,
    required this.seed,
  });

  final int color;
  final double dx;
  final double dy;
  final double spin;
  final double seed;
}

Offset _scatter(String id, Size size) {
  final a = _rand01(id) * pi * 2;
  final radius = sqrt(_rand01('$id#r')) * min(size.width, size.height) * 0.3;
  return Offset(cos(a) * radius, sin(a) * radius);
}

double _rand01(String seed) {
  var h = 2166136261;
  for (final code in seed.codeUnits) {
    h ^= code;
    h = (h * 16777619) & 0xffffffff;
  }
  return h / 4294967296;
}

Color _hex(String value) {
  final clean = value.replaceFirst('#', '');
  final parsed = int.tryParse(clean, radix: 16) ?? 0x2a2a2a;
  return Color(0xff000000 | parsed);
}

int _displayZ(Paper paper) {
  if (paper.balled) return 40000 + paper.z;
  if (paper.pinned) return 9000 + paper.z;
  return paper.z;
}
