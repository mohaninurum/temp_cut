import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/video_template.dart';
import '../../domain/models/overlay_item.dart';

/// Represents the entire state of the template editor.
class EditorState {
  /// The currently loaded template.
  final VideoTemplate? activeTemplate;
  
  /// A mapping between a [TemplateSlot]'s ID and the local file path of the user's selected asset.
  final Map<String, String> filledSlotAssets;

  /// A mapping between a [TemplateSlot]'s ID and the selected transition out of this slot.
  final Map<String, String> slotTransitions;

  /// Custom overlays added by the user (Text, Image, etc).
  final List<OverlayItem> overlays;

  /// Optional custom audio selected by the user to override the template's default audio.
  final String? customAudioPath;

  /// The ID of the currently selected template slot, if any.
  final String? selectedSlotId;

  /// Creates an instance of [EditorState].
  const EditorState({
    this.activeTemplate,
    required this.filledSlotAssets,
    this.slotTransitions = const {},
    this.overlays = const [],
    this.customAudioPath,
    this.selectedSlotId,
  });

  /// Provides the default, initial state of the editor.
  factory EditorState.initial() {
    return const EditorState(
      activeTemplate: null,
      filledSlotAssets: {},
      slotTransitions: {},
      overlays: [],
      customAudioPath: null,
      selectedSlotId: null,
    );
  }

  /// Creates a copy of this state with the provided fields replaced with new values.
  EditorState copyWith({
    VideoTemplate? activeTemplate,
    Map<String, String>? filledSlotAssets,
    Map<String, String>? slotTransitions,
    List<OverlayItem>? overlays,
    String? customAudioPath,
    String? selectedSlotId,
    bool clearSelection = false,
  }) {
    return EditorState(
      activeTemplate: activeTemplate ?? this.activeTemplate,
      filledSlotAssets: filledSlotAssets ?? this.filledSlotAssets,
      slotTransitions: slotTransitions ?? this.slotTransitions,
      overlays: overlays ?? this.overlays,
      customAudioPath: customAudioPath ?? this.customAudioPath,
      selectedSlotId: clearSelection ? null : (selectedSlotId ?? this.selectedSlotId),
    );
  }
}

/// A StateNotifier that acts as the single source of truth for the Video Editor.
class EditorStateNotifier extends StateNotifier<EditorState> {
  EditorStateNotifier() : super(EditorState.initial());

  /// Sets an active template.
  /// Also clears any previously filled slot assets.
  void loadTemplate(VideoTemplate template) {
    state = state.copyWith(
      activeTemplate: template,
      filledSlotAssets: {},
      slotTransitions: {},
    );
  }

  /// Clears the active template.
  void clearTemplate() {
    state = const EditorState(
      activeTemplate: null,
      filledSlotAssets: {},
      slotTransitions: {},
      customAudioPath: null,
    );
  }

  /// Sets a custom audio path to override the template's default audio.
  void setCustomAudio(String path) {
    state = state.copyWith(customAudioPath: path);
  }

  /// Associates a local asset file path with a specific template slot ID.
  void fillTemplateSlot(String slotId, String assetPath) {
    final updatedMap = Map<String, String>.from(state.filledSlotAssets);
    updatedMap[slotId] = assetPath;
    
    state = state.copyWith(
      filledSlotAssets: updatedMap,
    );
  }

  /// Fills multiple template slots sequentially.
  void batchFillSlots(List<String> slotIds, List<String> assetPaths) {
    final updatedMap = Map<String, String>.from(state.filledSlotAssets);
    
    // Match each selected asset to the next available slot ID sequentially
    for (int i = 0; i < slotIds.length && i < assetPaths.length; i++) {
      updatedMap[slotIds[i]] = assetPaths[i];
    }
    
    state = state.copyWith(
      filledSlotAssets: updatedMap,
    );
  }

  /// Removes an asset from a previously filled template slot.
  void removeTemplateSlot(String slotId) {
    final updatedMap = Map<String, String>.from(state.filledSlotAssets);
    updatedMap.remove(slotId);
    
    final updatedTransitions = Map<String, String>.from(state.slotTransitions);
    updatedTransitions.remove(slotId);
    
    state = state.copyWith(
      filledSlotAssets: updatedMap,
      slotTransitions: updatedTransitions,
    );
  }

  /// Sets the transition animation for a specific slot.
  void setSlotTransition(String slotId, String transitionName) {
    final updatedTransitions = Map<String, String>.from(state.slotTransitions);
    updatedTransitions[slotId] = transitionName;
    
    state = state.copyWith(
      slotTransitions: updatedTransitions,
    );
  }

  /// Sets the currently selected slot.
  void setSelectedSlot(String? slotId) {
    if (slotId == null) {
      state = state.copyWith(clearSelection: true);
    } else {
      state = state.copyWith(selectedSlotId: slotId);
    }
  }

  /// Clears the current selection.
  void clearSelection() {
    state = state.copyWith(clearSelection: true);
  }

  /// Adds a new overlay to the editor.
  void addOverlay(OverlayItem item) {
    state = state.copyWith(overlays: [...state.overlays, item]);
  }

  /// Updates an existing overlay.
  void updateOverlay(OverlayItem item) {
    state = state.copyWith(
      overlays: state.overlays.map((o) => o.id == item.id ? item : o).toList(),
    );
  }

  /// Removes an overlay from the editor.
  void removeOverlay(String id) {
    state = state.copyWith(
      overlays: state.overlays.where((o) => o.id != id).toList(),
    );
    if (state.selectedSlotId == id) {
      clearSelection();
    }
  }
}

/// The main provider for the [EditorStateNotifier] to be used within the UI.
final editorStateProvider = StateNotifierProvider<EditorStateNotifier, EditorState>((ref) {
  return EditorStateNotifier();
});
