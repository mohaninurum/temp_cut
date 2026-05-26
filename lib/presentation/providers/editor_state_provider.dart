import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/video_template.dart';

/// Represents the entire state of the template editor.
class EditorState {
  /// The currently loaded template.
  final VideoTemplate? activeTemplate;
  
  /// A mapping between a [TemplateSlot]'s ID and the local file path of the user's selected asset.
  final Map<String, String> filledSlotAssets;

  /// Optional custom audio selected by the user to override the template's default audio.
  final String? customAudioPath;

  /// Creates an instance of [EditorState].
  const EditorState({
    this.activeTemplate,
    required this.filledSlotAssets,
    this.customAudioPath,
  });

  /// Provides the default, initial state of the editor.
  factory EditorState.initial() {
    return const EditorState(
      activeTemplate: null,
      filledSlotAssets: {},
      customAudioPath: null,
    );
  }

  /// Creates a copy of this state with the provided fields replaced with new values.
  EditorState copyWith({
    VideoTemplate? activeTemplate,
    Map<String, String>? filledSlotAssets,
    String? customAudioPath,
  }) {
    return EditorState(
      activeTemplate: activeTemplate ?? this.activeTemplate,
      filledSlotAssets: filledSlotAssets ?? this.filledSlotAssets,
      customAudioPath: customAudioPath ?? this.customAudioPath,
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
    );
  }

  /// Clears the active template.
  void clearTemplate() {
    state = const EditorState(
      activeTemplate: null,
      filledSlotAssets: {},
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
    
    state = state.copyWith(
      filledSlotAssets: updatedMap,
    );
  }
}

/// The main provider for the [EditorStateNotifier] to be used within the UI.
final editorStateProvider = StateNotifierProvider<EditorStateNotifier, EditorState>((ref) {
  return EditorStateNotifier();
});
