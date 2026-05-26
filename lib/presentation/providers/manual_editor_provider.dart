import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/overlay_item.dart';

class ManualEditorState {
  final String? backgroundAssetPath;
  final Duration backgroundDuration;
  final List<OverlayItem> overlays;
  final bool isPlaying;
  final Duration currentTime;
  final String? selectedOverlayId;
  final double baseVideoScale;
  final double baseVideoRotation;
  final Offset baseVideoPosition;
  final Duration baseVideoTrimStart;
  final Duration baseVideoTrimEnd;

  const ManualEditorState({
    this.backgroundAssetPath,
    this.backgroundDuration = const Duration(seconds: 15),
    required this.overlays,
    this.isPlaying = false,
    this.currentTime = Duration.zero,
    this.selectedOverlayId,
    this.baseVideoScale = 1.0,
    this.baseVideoRotation = 0.0,
    this.baseVideoPosition = Offset.zero,
    this.baseVideoTrimStart = Duration.zero,
    this.baseVideoTrimEnd = const Duration(seconds: 15),
  });

  factory ManualEditorState.initial() {
    return const ManualEditorState(
      backgroundAssetPath: null,
      backgroundDuration: Duration(seconds: 15),
      overlays: [],
      isPlaying: false,
      currentTime: Duration.zero,
      selectedOverlayId: null,
      baseVideoScale: 1.0,
      baseVideoRotation: 0.0,
      baseVideoPosition: Offset.zero,
      baseVideoTrimStart: Duration.zero,
      baseVideoTrimEnd: Duration(seconds: 15),
    );
  }

  ManualEditorState copyWith({
    String? backgroundAssetPath,
    Duration? backgroundDuration,
    List<OverlayItem>? overlays,
    bool? isPlaying,
    Duration? currentTime,
    String? selectedOverlayId,
    bool clearSelectedOverlayId = false,
    double? baseVideoScale,
    double? baseVideoRotation,
    Offset? baseVideoPosition,
    Duration? baseVideoTrimStart,
    Duration? baseVideoTrimEnd,
  }) {
    return ManualEditorState(
      backgroundAssetPath: backgroundAssetPath ?? this.backgroundAssetPath,
      backgroundDuration: backgroundDuration ?? this.backgroundDuration,
      overlays: overlays ?? this.overlays,
      isPlaying: isPlaying ?? this.isPlaying,
      currentTime: currentTime ?? this.currentTime,
      selectedOverlayId: clearSelectedOverlayId ? null : (selectedOverlayId ?? this.selectedOverlayId),
      baseVideoScale: baseVideoScale ?? this.baseVideoScale,
      baseVideoRotation: baseVideoRotation ?? this.baseVideoRotation,
      baseVideoPosition: baseVideoPosition ?? this.baseVideoPosition,
      baseVideoTrimStart: baseVideoTrimStart ?? this.baseVideoTrimStart,
      baseVideoTrimEnd: baseVideoTrimEnd ?? this.baseVideoTrimEnd,
    );
  }
}

class ManualEditorStateNotifier extends StateNotifier<ManualEditorState> {
  ManualEditorStateNotifier() : super(ManualEditorState.initial());

  void setBackgroundAsset(String path, {Duration? duration}) {
    state = state.copyWith(
      backgroundAssetPath: path,
      backgroundDuration: duration,
    );
  }

  void addOverlay(OverlayItem overlay) {
    state = state.copyWith(
      overlays: [...state.overlays, overlay],
    );
  }

  void updateOverlay(OverlayItem updatedOverlay) {
    state = state.copyWith(
      overlays: state.overlays.map((item) {
        if (item.id == updatedOverlay.id) {
          return updatedOverlay;
        }
        return item;
      }).toList(),
    );
  }

  void removeOverlay(String id) {
    state = state.copyWith(
      overlays: state.overlays.where((item) => item.id != id).toList(),
    );
  }

  void setPlaying(bool playing) {
    state = state.copyWith(isPlaying: playing);
  }

  void setCurrentTime(Duration time) {
    state = state.copyWith(currentTime: time);
  }

  void setSelectedOverlay(String? id) {
    state = state.copyWith(selectedOverlayId: id, clearSelectedOverlayId: id == null);
  }

  void clearSelection() {
    state = state.copyWith(clearSelectedOverlayId: true);
  }

  void updateBaseVideo({double? scale, double? rotation, Offset? position}) {
    state = state.copyWith(
      baseVideoScale: scale ?? state.baseVideoScale,
      baseVideoRotation: rotation ?? state.baseVideoRotation,
      baseVideoPosition: position ?? state.baseVideoPosition,
    );
  }

  void updateBaseVideoTrim(Duration start, Duration end) {
    state = state.copyWith(
      baseVideoTrimStart: start,
      baseVideoTrimEnd: end,
      // also update backgroundDuration so the timeline scales correctly
      backgroundDuration: end - start,
    );
  }
}

final manualEditorProvider = StateNotifierProvider<ManualEditorStateNotifier, ManualEditorState>((ref) {
  return ManualEditorStateNotifier();
});
