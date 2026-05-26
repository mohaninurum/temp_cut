import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/overlay_item.dart';

class ManualEditorState {
  final List<OverlayItem> baseMedia;
  final Duration backgroundDuration;
  final List<OverlayItem> overlays;
  final bool isPlaying;
  final Duration currentTime;
  final String? selectedOverlayId;
  final double baseVideoScale;
  final double baseVideoRotation;
  final Offset baseVideoPosition;

  const ManualEditorState({
    this.baseMedia = const [],
    this.backgroundDuration = Duration.zero,
    required this.overlays,
    this.isPlaying = false,
    this.currentTime = Duration.zero,
    this.selectedOverlayId,
    this.baseVideoScale = 1.0,
    this.baseVideoRotation = 0.0,
    this.baseVideoPosition = Offset.zero,
  });

  factory ManualEditorState.initial() {
    return const ManualEditorState(
      baseMedia: [],
      backgroundDuration: Duration.zero,
      overlays: [],
      isPlaying: false,
      currentTime: Duration.zero,
      selectedOverlayId: null,
      baseVideoScale: 1.0,
      baseVideoRotation: 0.0,
      baseVideoPosition: Offset.zero,
    );
  }

  ManualEditorState copyWith({
    List<OverlayItem>? baseMedia,
    Duration? backgroundDuration,
    List<OverlayItem>? overlays,
    bool? isPlaying,
    Duration? currentTime,
    String? selectedOverlayId,
    bool clearSelectedOverlayId = false,
    double? baseVideoScale,
    double? baseVideoRotation,
    Offset? baseVideoPosition,
  }) {
    return ManualEditorState(
      baseMedia: baseMedia ?? this.baseMedia,
      backgroundDuration: backgroundDuration ?? this.backgroundDuration,
      overlays: overlays ?? this.overlays,
      isPlaying: isPlaying ?? this.isPlaying,
      currentTime: currentTime ?? this.currentTime,
      selectedOverlayId: clearSelectedOverlayId ? null : (selectedOverlayId ?? this.selectedOverlayId),
      baseVideoScale: baseVideoScale ?? this.baseVideoScale,
      baseVideoRotation: baseVideoRotation ?? this.baseVideoRotation,
      baseVideoPosition: baseVideoPosition ?? this.baseVideoPosition,
    );
  }
}

class ManualEditorStateNotifier extends StateNotifier<ManualEditorState> {
  ManualEditorStateNotifier() : super(ManualEditorState.initial());

  void addBaseMedia(OverlayItem media) {
    final newBaseMedia = [...state.baseMedia, media];
    _updateBaseMediaAndDuration(newBaseMedia);
  }

  void updateBaseMedia(OverlayItem updatedMedia) {
    final newBaseMedia = state.baseMedia.map((item) {
      if (item.id == updatedMedia.id) return updatedMedia;
      return item;
    }).toList();
    _updateBaseMediaAndDuration(newBaseMedia);
  }

  void _updateBaseMediaAndDuration(List<OverlayItem> baseMedia) {
    Duration currentStart = Duration.zero;
    final List<OverlayItem> alignedMedia = [];

    for (var item in baseMedia) {
      final duration = item.endTime - item.startTime;
      alignedMedia.add(item.copyWith(
        startTime: currentStart,
        endTime: currentStart + duration,
      ));
      currentStart += duration;
    }

    state = state.copyWith(
      baseMedia: alignedMedia,
      backgroundDuration: currentStart,
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
}

final manualEditorProvider = StateNotifierProvider<ManualEditorStateNotifier, ManualEditorState>((ref) {
  return ManualEditorStateNotifier();
});
