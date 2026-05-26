import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/overlay_item.dart';

class ManualEditorState {
  final String? backgroundAssetPath;
  final Duration backgroundDuration;
  final List<OverlayItem> overlays;

  const ManualEditorState({
    this.backgroundAssetPath,
    this.backgroundDuration = const Duration(seconds: 15), // Default max duration for images
    required this.overlays,
  });

  factory ManualEditorState.initial() {
    return const ManualEditorState(
      backgroundAssetPath: null,
      backgroundDuration: Duration(seconds: 15),
      overlays: [],
    );
  }

  ManualEditorState copyWith({
    String? backgroundAssetPath,
    Duration? backgroundDuration,
    List<OverlayItem>? overlays,
  }) {
    return ManualEditorState(
      backgroundAssetPath: backgroundAssetPath ?? this.backgroundAssetPath,
      backgroundDuration: backgroundDuration ?? this.backgroundDuration,
      overlays: overlays ?? this.overlays,
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
}

final manualEditorProvider = StateNotifierProvider<ManualEditorStateNotifier, ManualEditorState>((ref) {
  return ManualEditorStateNotifier();
});
