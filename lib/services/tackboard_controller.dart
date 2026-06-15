import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../models/paper.dart';
import 'paper_repository.dart';

class TackboardController extends ChangeNotifier {
  TackboardController({PaperRepository? repository})
      : _repository = repository ?? PaperRepository();

  final PaperRepository _repository;
  final Random _random = Random();
  Timer? _syncTimer;

  List<Paper> _papers = const <Paper>[];
  bool _loaded = false;
  String? _editingId;
  String? _tmuxLayoutJson;
  int _zCounter = 1;

  List<Paper> get papers => _papers;
  bool get loaded => _loaded;
  String? get editingId => _editingId;
  String get syncDirectory => _repository.syncDirectory;
  String get deviceId => _repository.deviceId;
  String? get tmuxLayoutJson => _tmuxLayoutJson;

  List<Paper> get onBoard =>
      _papers.where((paper) => !paper.crumpled).toList(growable: false);
  List<Paper> get binned =>
      _papers.where((paper) => paper.crumpled).toList(growable: false);
  bool get ballInPlay => onBoard.any((paper) => paper.balled);

  Future<void> init() async {
    await _repository.init();
    await reload();
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(syncNow());
    });
  }

  Future<void> reload() async {
    _papers = await _repository.loadPapers();
    _tmuxLayoutJson = await _repository.loadSetting('tmux_layout');
    _syncZCounter();
    _loaded = true;
    notifyListeners();
  }

  Future<void> syncNow() async {
    await _repository.syncNow();
    _papers = await _repository.loadPapers();
    _tmuxLayoutJson = await _repository.loadSetting('tmux_layout');
    _syncZCounter();
    notifyListeners();
  }

  Future<void> chooseSyncDirectory() async {
    final selected = await _repository.pickSyncDirectory();
    if (selected != null) {
      _papers = await _repository.loadPapers();
      _tmuxLayoutJson = await _repository.loadSetting('tmux_layout');
      _syncZCounter();
      notifyListeners();
    }
  }

  void startEdit(String id) {
    _editingId = id;
    notifyListeners();
  }

  void stopEdit() {
    if (_editingId == null) return;
    _editingId = null;
    notifyListeners();
  }

  Future<int> bringToFront(String id) async {
    final z = ++_zCounter;
    await updatePaper(id, (paper) => paper.move(z: z));
    return z;
  }

  Future<void> printReceipt(Size boardSize) async {
    final receipt = await createReceipt(boardSize);
    startEdit(receipt.id);
  }

  Future<ReceiptPaper> createReceipt(Size boardSize) async {
    final receipt = makeReceipt(boardSize);
    await addPaper(receipt);
    return receipt;
  }

  ReceiptPaper makeReceipt(Size boardSize) {
    final boardWidth = boardSize.width <= 0 ? 1280.0 : boardSize.width;
    final spread = max(1.0, boardWidth - 360);
    final x = (120 + _random.nextDouble() * spread)
        .clamp(40.0, max(40.0, boardWidth - receiptWidth - 40))
        .toDouble();
    final receipt = ReceiptPaper.create(
      x: x,
      y: 70 + _random.nextDouble() * 60,
      z: ++_zCounter,
    );
    return receipt;
  }

  Future<void> spawnMemo(String color, Size boardSize) async {
    final boardWidth = boardSize.width <= 0 ? 1280.0 : boardSize.width;
    final memo = MemoPaper.create(
      color: color,
      x: max(40.0,
          boardWidth / 2 - memoSize / 2 + (_random.nextDouble() * 120 - 60)),
      y: 90 + _random.nextDouble() * 60,
      z: ++_zCounter,
    );
    await addPaper(memo);
    startEdit(memo.id);
  }

  Future<void> addPaper(Paper paper) async {
    final stamped = paper.withSyncTime(DateTime.now().millisecondsSinceEpoch);
    _papers = [..._papers, stamped];
    _syncZCounter();
    notifyListeners();
    await _repository.savePaper(stamped, preserveUpdatedAt: true);
  }

  Future<void> updatePaper(
      String id, Paper Function(Paper paper) change) async {
    final index = _papers.indexWhere((paper) => paper.id == id);
    if (index < 0) return;
    final stamped = change(_papers[index])
        .withSyncTime(DateTime.now().millisecondsSinceEpoch);
    final next = [..._papers];
    next[index] = stamped;
    _papers = next;
    _syncZCounter();
    notifyListeners();
    await _repository.savePaper(stamped, preserveUpdatedAt: true);
  }

  Future<void> markBalled(String id) async {
    if (_editingId == id) _editingId = null;
    await updatePaper(id, (paper) => paper.move(balled: true, pinned: false));
  }

  Future<void> landBall(String id, {required bool hitBin}) async {
    await trashPaper(id);
  }

  Future<void> trashPaper(String id) async {
    await updatePaper(
      id,
      (paper) => paper.move(balled: false, crumpled: true, pinned: false),
    );
  }

  Future<void> clearCrumpled() async {
    final ids = binned.map((paper) => paper.id).toList(growable: false);
    if (ids.isEmpty) return;
    _papers = _papers.where((paper) => !paper.crumpled).toList(growable: false);
    notifyListeners();
    await _repository.deletePapers(ids);
  }

  Future<void> saveTmuxLayout(String json) async {
    if (_tmuxLayoutJson == json) return;
    _tmuxLayoutJson = json;
    await _repository.saveSetting('tmux_layout', json);
  }

  void _syncZCounter() {
    final maxZ = _papers.fold<int>(0, (maxZ, paper) => max(maxZ, paper.z));
    if (maxZ >= _zCounter) _zCounter = maxZ + 1;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
