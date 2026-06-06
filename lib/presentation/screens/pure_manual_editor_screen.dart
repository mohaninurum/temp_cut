import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:get_thumbnail_video/index.dart';

import '../../domain/models/overlay_item.dart';
import '../providers/manual_editor_provider.dart';
import '../widgets/editable_overlay_item.dart';

class PureManualEditorScreen extends ConsumerStatefulWidget {
  const PureManualEditorScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PureManualEditorScreen> createState() =>
      _PureManualEditorScreenState();
}

class _PureManualEditorScreenState
    extends ConsumerState<PureManualEditorScreen> {
  final Map<String, VideoPlayerController> _baseVideoControllers = {};
  Timer? _timer;

  // Dragging state for smooth timeline updates
  Duration? _dragInitialStartTime;
  Duration? _dragInitialEndTime;
  Duration? _dragInitialMediaStartTime;
  double _dragAccumulator = 0.0;
  String? _activeBaseMediaId;

  Size _canvasSize = Size.zero;

  final ScrollController _timelineScrollController = ScrollController();
  bool _isScrollingTimeline = false;
  static const double _pixelsPerSecond = 50.0;
  bool _isReady = false;
  bool _isEditingText = false;
  bool _isVideoMuted = false;

  // Variables for tracking base media gestures
  double _baseMediaStartScale = 1.0;
  double _baseMediaStartRotation = 0.0;
  Offset _baseMediaStartPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _timelineScrollController.addListener(_onTimelineScroll);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          _isReady = true;
        });
      }
    });
  }

  void _onTimelineScroll() {
    if (_isScrollingTimeline) {
      final offset = _timelineScrollController.offset;
      final timeInMs = (offset / _pixelsPerSecond) * 1000.0;
      if (timeInMs >= 0) {
        final state = ref.read(manualEditorProvider);
        final maxMs = state.backgroundDuration.inMilliseconds.toDouble();
        final clampedTimeMs = timeInMs.clamp(0.0, maxMs);
        final currentDuration = Duration(milliseconds: clampedTimeMs.toInt());
        ref.read(manualEditorProvider.notifier).setCurrentTime(currentDuration);

        // Find active base media
        final activeMedia = _getActiveBaseMedia(state, currentDuration);
        if (activeMedia != null) {
          _activeBaseMediaId = activeMedia.id;
          if (activeMedia.type == OverlayType.mainVideo) {
            final controller = _baseVideoControllers[activeMedia.id];
            if (controller != null && !controller.value.isPlaying) {
              // Calculate local time within this media
              final localTimeMs =
                  currentDuration.inMilliseconds -
                  activeMedia.startTime.inMilliseconds + activeMedia.mediaStartTime.inMilliseconds;
              controller.seekTo(Duration(milliseconds: localTimeMs));
            }
          }
        }
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _baseVideoControllers.values) {
      controller.dispose();
    }
    _timer?.cancel();
    _timelineScrollController.dispose();
    super.dispose();
  }

  OverlayItem? _getActiveBaseMedia(ManualEditorState state, Duration time) {
    if (state.baseMedia.isEmpty) return null;
    try {
      return state.baseMedia.firstWhere(
        (m) => time >= m.startTime && time < m.endTime,
      );
    } catch (e) {
      return state
          .baseMedia
          .last; // Fallback to last if time is exactly at the end
    }
  }

  Future<void> _pickBackgroundMedia() async {
    final picker = ImagePicker();
    final media = await picker.pickMedia();

    if (media != null) {
      final isVideo =
          media.path.toLowerCase().endsWith('.mp4') ||
          media.path.toLowerCase().endsWith('.mov');

      final state = ref.read(manualEditorProvider);
      final startTime = state.backgroundDuration;
      final newId = const Uuid().v4();

      if (isVideo) {
        final controller = VideoPlayerController.file(File(media.path));
        try {
          await controller.initialize();
          controller.setVolume(_isVideoMuted ? 0.0 : 1.0);
          _baseVideoControllers[newId] = controller;

          final duration = controller.value.duration;
          ref
              .read(manualEditorProvider.notifier)
              .addBaseMedia(
                OverlayItem(
                  id: newId,
                  type: OverlayType.mainVideo,
                  value: media.path,
                  startTime: startTime,
                  endTime: startTime + duration,
                ),
              );

          // Seek to the start of the newly added video
          ref.read(manualEditorProvider.notifier).setCurrentTime(startTime);
          _activeBaseMediaId = newId;
          controller.seekTo(Duration.zero);
        } catch (e) {
          debugPrint('Error initializing video: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Could not load video: The format might be unsupported or too many videos are loaded.',
                ),
              ),
            );
          }
          controller.dispose();
        }
      } else {
        ref
            .read(manualEditorProvider.notifier)
            .addBaseMedia(
              OverlayItem(
                id: newId,
                type: OverlayType.mainImage,
                value: media.path,
                startTime: startTime,
                endTime: startTime + const Duration(seconds: 6),
              ),
            );
        // Seek to the start of the newly added image
        ref.read(manualEditorProvider.notifier).setCurrentTime(startTime);
        _activeBaseMediaId = newId;
      }
    }
  }

  Future<void> _replaceBaseMedia(OverlayItem item) async {
    final picker = ImagePicker();
    final media = await picker.pickMedia();

    if (media != null) {
      final isVideo =
          media.path.toLowerCase().endsWith('.mp4') ||
          media.path.toLowerCase().endsWith('.mov');

      // Dispose old controller if it was a video
      if (item.type == OverlayType.mainVideo) {
        final oldCtrl = _baseVideoControllers[item.id];
        _baseVideoControllers.remove(item.id);
        // Only dispose if no other segment is sharing this controller
        if (oldCtrl != null && !_baseVideoControllers.values.contains(oldCtrl)) {
          oldCtrl.dispose();
        }
      }

      if (isVideo) {
        final controller = VideoPlayerController.file(File(media.path));
        try {
          await controller.initialize();
          controller.setVolume(_isVideoMuted ? 0.0 : 1.0);
          _baseVideoControllers[item.id] = controller;

          final duration = controller.value.duration;
          ref
              .read(manualEditorProvider.notifier)
              .updateBaseMedia(
                item.copyWith(
                  type: OverlayType.mainVideo,
                  value: media.path,
                  endTime: item.startTime + duration, // new duration
                ),
              );

          // Seek to the start of the newly replaced video
          ref
              .read(manualEditorProvider.notifier)
              .setCurrentTime(item.startTime);
          _activeBaseMediaId = item.id;
          controller.seekTo(Duration.zero);
        } catch (e) {
          debugPrint('Error initializing replacement video: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Could not load replacement video: format might be unsupported.',
                ),
              ),
            );
          }
          controller.dispose();
        }
      } else {
        ref
            .read(manualEditorProvider.notifier)
            .updateBaseMedia(
              item.copyWith(
                type: OverlayType.mainImage,
                value: media.path,
                endTime:
                    item.startTime +
                    const Duration(seconds: 6), // default image duration
              ),
            );
        // Seek to the start of the newly replaced image
        ref.read(manualEditorProvider.notifier).setCurrentTime(item.startTime);
        _activeBaseMediaId = item.id;
      }
    }
  }

  void _splitSelectedMedia() {
    final state = ref.read(manualEditorProvider);
    final selectedId = state.selectedOverlayId;
    if (selectedId == null) return;

    final currentTime = state.currentTime;

    // Check if it's base media
    final baseMediaIndex = state.baseMedia.indexWhere((o) => o.id == selectedId);
    if (baseMediaIndex != -1) {
      final item = state.baseMedia[baseMediaIndex];
      // Only split if playhead is strictly inside the clip
      if (currentTime > item.startTime && currentTime < item.endTime) {
        final duration1 = currentTime - item.startTime;
        final duration2 = item.endTime - currentTime;

        final newId = const Uuid().v4();
        final newItem = item.copyWith(
          id: newId,
          startTime: currentTime,
          endTime: currentTime + duration2,
          mediaStartTime: item.mediaStartTime + duration1,
        );

        final updatedOldItem = item.copyWith(
          endTime: item.startTime + duration1,
        );

        if (item.type == OverlayType.mainVideo) {
          if (_baseVideoControllers.containsKey(item.id)) {
            _baseVideoControllers[newId] = _baseVideoControllers[item.id]!;
          }
        }

        final newList = List<OverlayItem>.from(state.baseMedia);
        newList[baseMediaIndex] = updatedOldItem;
        newList.insert(baseMediaIndex + 1, newItem);

        ref.read(manualEditorProvider.notifier).setBaseMedia(newList);
      }
    } else {
      // Check if it's overlay
      final overlayIndex = state.overlays.indexWhere((o) => o.id == selectedId);
      if (overlayIndex != -1) {
        final item = state.overlays[overlayIndex];
        if (currentTime > item.startTime && currentTime < item.endTime) {
          final newId = const Uuid().v4();
          final duration1 = currentTime - item.startTime;
          final duration2 = item.endTime - currentTime;
          
          final newItem = item.copyWith(
            id: newId,
            startTime: currentTime,
            endTime: currentTime + duration2,
            mediaStartTime: item.mediaStartTime + duration1,
          );
          
          final updatedOldItem = item.copyWith(
            endTime: item.startTime + duration1,
          );

          ref.read(manualEditorProvider.notifier).updateOverlay(updatedOldItem);
          ref.read(manualEditorProvider.notifier).addOverlay(newItem);
        }
      }
    }
  }

  void _togglePlayback(ManualEditorState state) {
    if (state.isPlaying) {
      _timer?.cancel();
      for (var controller in _baseVideoControllers.values) {
        controller.pause();
      }
      ref.read(manualEditorProvider.notifier).setPlaying(false);
    } else {
      Duration startPlayTime = state.currentTime;
      // If we are at the end, restart from the beginning
      if (startPlayTime >= state.backgroundDuration - const Duration(milliseconds: 33)) {
        startPlayTime = Duration.zero;
        ref.read(manualEditorProvider.notifier).setCurrentTime(startPlayTime);
        for (var controller in _baseVideoControllers.values) {
          controller.seekTo(Duration.zero);
        }
        if (state.baseMedia.isNotEmpty) {
          _activeBaseMediaId = state.baseMedia.first.id;
        }
      }

      final activeMedia = _getActiveBaseMedia(state, startPlayTime);
      if (activeMedia != null && activeMedia.type == OverlayType.mainVideo) {
        final controller = _baseVideoControllers[activeMedia.id];
        final localTimeMs = startPlayTime.inMilliseconds - activeMedia.startTime.inMilliseconds + activeMedia.mediaStartTime.inMilliseconds;
        controller?.seekTo(Duration(milliseconds: localTimeMs));
        controller?.play();
      }
      ref.read(manualEditorProvider.notifier).setPlaying(true);

      _timer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final currentState = ref.read(manualEditorProvider);
        final maxDuration = currentState.backgroundDuration;

        Duration newTime =
            currentState.currentTime + const Duration(milliseconds: 33);

        // Keep video controllers in sync
        final currentActiveMedia = _getActiveBaseMedia(currentState, newTime);
        if (currentActiveMedia != null) {
          if (currentActiveMedia.id != _activeBaseMediaId) {
            // Crossed a clip boundary
            if (_activeBaseMediaId != null) {
              _baseVideoControllers[_activeBaseMediaId!]?.pause();
            }
            _activeBaseMediaId = currentActiveMedia.id;
            if (currentActiveMedia.type == OverlayType.mainVideo) {
              final newController =
                  _baseVideoControllers[currentActiveMedia.id];
              newController?.seekTo(currentActiveMedia.mediaStartTime);
              if (currentState.isPlaying) newController?.play();
            }
          }
        }

        if (newTime >= maxDuration || newTime.isNegative) {
          newTime = Duration.zero;
          timer.cancel();
          for (var controller in _baseVideoControllers.values) {
            controller.pause();
            controller.seekTo(Duration.zero);
          }
          if (currentState.baseMedia.isNotEmpty) {
            _activeBaseMediaId = currentState.baseMedia.first.id;
          }
          ref.read(manualEditorProvider.notifier).setPlaying(false);
        }
        ref.read(manualEditorProvider.notifier).setCurrentTime(newTime);

        if (!_isScrollingTimeline && _timelineScrollController.hasClients) {
          final targetOffset =
              (newTime.inMilliseconds / 1000.0) * _pixelsPerSecond;
          _timelineScrollController.jumpTo(targetOffset);
        }
      });
    }
  }

  void _addTextOverlay() {
    String input = 'New Text';
    final state = ref.read(manualEditorProvider);

    final textOverlays = state.overlays.where(
      (o) => o.type == OverlayType.text,
    );
    Duration startTime = Duration.zero;
    if (textOverlays.isNotEmpty) {
      startTime = textOverlays
          .map((o) => o.endTime)
          .reduce((a, b) => a > b ? a : b);
    }

    Duration endTime = startTime + const Duration(seconds: 3);
    if (endTime > state.backgroundDuration) {
      endTime = state.backgroundDuration;
      if (startTime >= state.backgroundDuration) {
        startTime = state.backgroundDuration - const Duration(seconds: 3);
        if (startTime.isNegative) startTime = Duration.zero;
      }
    }

    ref
        .read(manualEditorProvider.notifier)
        .addOverlay(
          OverlayItem(
            id: const Uuid().v4(),
            type: OverlayType.text,
            value: input,
            position: const Offset(100, 200),
            startTime: startTime,
            endTime: endTime,
          ),
        );
  }

  Future<void> _addImageOverlay() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final state = ref.read(manualEditorProvider);

      final imageOverlays = state.overlays.where(
        (o) => o.type == OverlayType.image,
      );
      Duration startTime = Duration.zero;
      if (imageOverlays.isNotEmpty) {
        startTime = imageOverlays
            .map((o) => o.endTime)
            .reduce((a, b) => a > b ? a : b);
      }

      Duration endTime = startTime + const Duration(seconds: 3);
      if (endTime > state.backgroundDuration && state.backgroundDuration > Duration.zero) {
        endTime = state.backgroundDuration;
        if (startTime >= state.backgroundDuration) {
          startTime = state.backgroundDuration - const Duration(seconds: 3);
          if (startTime.isNegative) startTime = Duration.zero;
        }
      }

      ref
          .read(manualEditorProvider.notifier)
          .addOverlay(
            OverlayItem(
              id: const Uuid().v4(),
              type: OverlayType.image,
              value: pickedFile.path,
              position: const Offset(100, 200),
              scale: 1.0,
              startTime: startTime,
              endTime: endTime,
            ),
          );
    }
  }

  Future<void> _addAudioOverlay() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result != null && result.files.single.path != null) {
      if (!_isVideoMuted) {
        setState(() {
          _isVideoMuted = true;
          for (var controller in _baseVideoControllers.values) {
            controller.setVolume(0.0);
          }
        });
      }
      final state = ref.read(manualEditorProvider);

      final audioOverlays = state.overlays.where(
        (o) => o.type == OverlayType.audio,
      );
      Duration startTime = Duration.zero;
      if (audioOverlays.isNotEmpty) {
        startTime = audioOverlays
            .map((o) => o.endTime)
            .reduce((a, b) => a > b ? a : b);
      }

      Duration endTime = startTime + const Duration(seconds: 10);
      if (endTime > state.backgroundDuration && state.backgroundDuration > Duration.zero) {
        endTime = state.backgroundDuration;
        if (startTime >= state.backgroundDuration) {
          startTime = state.backgroundDuration - const Duration(seconds: 10);
          if (startTime.isNegative) startTime = Duration.zero;
        }
      }

      ref
          .read(manualEditorProvider.notifier)
          .addOverlay(
            OverlayItem(
              id: const Uuid().v4(),
              type: OverlayType.audio,
              value: result.files.single.path!,
              startTime: startTime,
              endTime: endTime,
            ),
          );
    }
  }

  Widget _buildTextCustomizer(String itemId) {
    return _TextCustomizerWidget(itemId: itemId);
  }

  Widget _buildTrackIconRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool hasCoverButton = false,
  }) {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (hasCoverButton)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.edit, size: 10, color: Colors.white),
                  Text(
                    'Cover',
                    style: TextStyle(color: Colors.white, fontSize: 8),
                  ),
                ],
              ),
            ),
          GestureDetector(
            onTap: onTap,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(icon, color: Colors.white54, size: 22),
                if (label.isNotEmpty)
                  Positioned(
                    right: -6,
                    bottom: -4,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 40, color: Colors.white10),
        ],
      ),
    );
  }

  Widget _buildTrackContentRow(Widget trackContent, double width) {
    return SizedBox(width: width, child: trackContent);
  }

  Widget _buildEmptyTrackPlaceholder(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white24, fontSize: 11),
      ),
    );
  }

  Widget _buildOverlayTrack(
    List<OverlayItem> items,
    double maxMs,
    ManualEditorState state,
    String emptyText, {
    bool isBaseTrack = false,
  }) {
    if (items.isEmpty) {
      return _buildEmptyTrackPlaceholder(emptyText);
    }

    return SizedBox(
      height: 42,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = constraints.maxWidth;
          return Stack(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 1),
                height: 40,
                color: const Color(0xFF1E1E1E),
              ),
              for (final item in items)
                _buildTrackItem(item, maxMs, trackWidth, state),

              if (isBaseTrack && items.length > 1)
                for (int i = 0; i < items.length - 1; i++)
                  _buildTransitionButton(items[i], maxMs, trackWidth, state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTransitionButton(
    OverlayItem currentItem,
    double maxMs,
    double trackWidth,
    ManualEditorState state,
  ) {
    final safeMaxMs = maxMs > 0 ? maxMs : 1.0;
    final endPx = (currentItem.endTime.inMilliseconds / safeMaxMs) * trackWidth;

    // Check if it has a transition (using animationOut temporarily)
    final hasTransition = currentItem.animationOut != 'None';

    return Positioned(
      left: endPx - 12, // Center the 24x24 button
      top: 9, // Center vertically in 40px height
      width: 24,
      height: 24,
      child: GestureDetector(
        onTap: () {
          _showTransitionBottomSheet(currentItem);
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.black, width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2)],
          ),
          child: Center(
            child: Icon(
              hasTransition ? Icons.compare : Icons.add,
              size: 16,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackItem(
    OverlayItem item,
    double maxMs,
    double trackWidth,
    ManualEditorState state,
  ) {
    final safeMaxMs = maxMs > 0 ? maxMs : 1.0;
    final startPx = (item.startTime.inMilliseconds / safeMaxMs) * trackWidth;
    final endPx = (item.endTime.inMilliseconds / safeMaxMs) * trackWidth;
    final width = endPx - startPx;
    final isSelected = state.selectedOverlayId == item.id;

    final durationSeconds =
        (item.endTime.inMilliseconds - item.startTime.inMilliseconds) / 1000.0;
    final durationText = '${durationSeconds.toStringAsFixed(2)}s';

    return Positioned(
      top: 1,
      left: startPx.clamp(0, trackWidth),
      width: width.clamp(0, trackWidth - startPx),
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                ref
                    .read(manualEditorProvider.notifier)
                    .setSelectedOverlay(item.id);
              },
              onHorizontalDragStart: (details) {
                _dragInitialStartTime = item.startTime;
                _dragInitialEndTime = item.endTime;
                _dragAccumulator = 0.0;
              },
              onHorizontalDragUpdate: (details) {
                if (_dragInitialStartTime == null ||
                    _dragInitialEndTime == null)
                  return;
                _dragAccumulator += details.delta.dx;
                final deltaMs = (_dragAccumulator / trackWidth) * maxMs;
                final duration =
                    _dragInitialEndTime!.inMilliseconds -
                    _dragInitialStartTime!.inMilliseconds;

                int newStartMs =
                    _dragInitialStartTime!.inMilliseconds + deltaMs.toInt();
                int newEndMs =
                    _dragInitialEndTime!.inMilliseconds + deltaMs.toInt();

                if (newStartMs < 0) {
                  newStartMs = 0;
                  newEndMs = duration;
                } else if (newEndMs > maxMs) {
                  newEndMs = maxMs.toInt();
                  newStartMs = newEndMs - duration;
                }

                final isBaseMedia =
                    item.type == OverlayType.mainVideo ||
                    item.type == OverlayType.mainImage;
                final updatedItem = item.copyWith(
                  startTime: Duration(milliseconds: newStartMs),
                  endTime: Duration(milliseconds: newEndMs),
                );

                if (isBaseMedia) {
                  ref
                      .read(manualEditorProvider.notifier)
                      .updateBaseMedia(updatedItem);
                } else {
                  ref
                      .read(manualEditorProvider.notifier)
                      .updateOverlay(updatedItem);
                }
              },
              onHorizontalDragEnd: (_) {
                _dragInitialStartTime = null;
                _dragInitialEndTime = null;
              },
              child: Container(
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (item.type == OverlayType.mainVideo ||
                                item.type == OverlayType.mainImage
                            ? const Color(0xFF004D40)
                            : const Color(0xFF004D40)) // Dark teal
                      : Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                  border: isSelected
                      ? Border.all(
                          color:
                              (item.type == OverlayType.mainVideo ||
                                  item.type == OverlayType.mainImage
                              ? Colors.yellowAccent
                              : Colors.cyanAccent),
                          width: 1.5,
                        )
                      : Border.all(color: Colors.white, width: 1),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.type == OverlayType.image || item.type == OverlayType.mainImage)
                      Image.file(
                        File(item.value),
                        fit: BoxFit.cover,
                        alignment: Alignment.centerLeft,
                      ),
                    if (item.type == OverlayType.mainVideo && _baseVideoControllers[item.id]?.value.isInitialized == true)
                      _VideoFilmstrip(
                        videoPath: item.value,
                        durationMs: (item.endTime - item.startTime).inMilliseconds,
                      ),
                    if (item.type == OverlayType.image || item.type == OverlayType.mainImage || item.type == OverlayType.mainVideo)
                      Container(color: Colors.black45),
                    Center(
                      child: isSelected
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  (item.type == OverlayType.emoji || item.type == OverlayType.text)
                                      ? item.value
                                      : (item.type == OverlayType.mainVideo
                                            ? 'Video'
                                            : (item.type == OverlayType.mainImage
                                                  ? 'Image'
                                                  : (item.type == OverlayType.image
                                                        ? 'Image'
                                                        : (item.type == OverlayType.audio
                                                              ? 'Audio'
                                                              : 'Unknown')))),
                                  style: TextStyle(
                                    color:
                                        (item.type == OverlayType.mainVideo ||
                                            item.type == OverlayType.mainImage)
                                        ? Colors.yellowAccent
                                        : Colors.cyanAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  durationText,
                                  style: TextStyle(
                                    color:
                                        (item.type == OverlayType.mainVideo ||
                                            item.type == OverlayType.mainImage)
                                        ? Colors.yellowAccent
                                        : Colors.cyanAccent,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              (item.type == OverlayType.emoji || item.type == OverlayType.text)
                                  ? item.value
                                  : (item.type == OverlayType.mainVideo
                                        ? 'Video'
                                        : (item.type == OverlayType.mainImage
                                              ? 'Image'
                                              : (item.type == OverlayType.image
                                                    ? 'Image'
                                                    : (item.type == OverlayType.audio
                                                          ? 'Audio'
                                                          : 'Unknown')))),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Left Handle
          Positioned(
            left: isSelected ? 0 : -10,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                _dragInitialStartTime = item.startTime;
                _dragInitialMediaStartTime = item.mediaStartTime;
                _dragAccumulator = 0.0;
              },
              onHorizontalDragUpdate: (details) {
                if (_dragInitialStartTime == null || _dragInitialMediaStartTime == null) return;
                _dragAccumulator += details.delta.dx;
                final deltaMs = (_dragAccumulator / trackWidth) * maxMs;
                final clampedStart =
                    (_dragInitialStartTime!.inMilliseconds + deltaMs.toInt())
                        .clamp(0, item.endTime.inMilliseconds - 500);

                final actualDeltaMs = clampedStart - _dragInitialStartTime!.inMilliseconds;

                final isBaseMedia =
                    item.type == OverlayType.mainVideo ||
                    item.type == OverlayType.mainImage;
                final updatedItem = item.copyWith(
                  startTime: Duration(milliseconds: clampedStart),
                  mediaStartTime: Duration(milliseconds: _dragInitialMediaStartTime!.inMilliseconds + actualDeltaMs),
                );

                if (isBaseMedia) {
                  ref
                      .read(manualEditorProvider.notifier)
                      .updateBaseMedia(updatedItem);
                } else {
                  ref
                      .read(manualEditorProvider.notifier)
                      .updateOverlay(updatedItem);
                }
              },
              onHorizontalDragEnd: (_) => _dragInitialStartTime = null,
              child: Container(
                width: 16,
                decoration: isSelected
                    ? BoxDecoration(
                        color:
                            (item.type == OverlayType.mainVideo ||
                                item.type == OverlayType.mainImage)
                            ? Colors.yellowAccent
                            : Colors.cyanAccent,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(3),
                        ),
                      )
                    : const BoxDecoration(color: Colors.transparent),
                child: Center(
                  child: Icon(
                    isSelected
                        ? Icons.keyboard_arrow_left
                        : Icons.drag_indicator,
                    size: isSelected ? 16 : 12,
                    color: isSelected ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // Right Handle
          Positioned(
            right: isSelected ? 0 : -10,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                _dragInitialEndTime = item.endTime;
                _dragAccumulator = 0.0;
              },
              onHorizontalDragUpdate: (details) {
                if (_dragInitialEndTime == null) return;
                _dragAccumulator += details.delta.dx;
                final deltaMs = (_dragAccumulator / trackWidth) * maxMs;
                final clampedEnd =
                    (_dragInitialEndTime!.inMilliseconds + deltaMs.toInt())
                        .clamp(
                          item.startTime.inMilliseconds + 500,
                          state.backgroundDuration.inMilliseconds,
                        );

                final isBaseMedia =
                    item.type == OverlayType.mainVideo ||
                    item.type == OverlayType.mainImage;
                final updatedItem = item.copyWith(
                  endTime: Duration(milliseconds: clampedEnd),
                );

                if (isBaseMedia) {
                  ref
                      .read(manualEditorProvider.notifier)
                      .updateBaseMedia(updatedItem);
                } else {
                  ref
                      .read(manualEditorProvider.notifier)
                      .updateOverlay(updatedItem);
                }
              },
              onHorizontalDragEnd: (_) => _dragInitialEndTime = null,
              child: Container(
                width: 16,
                decoration: isSelected
                    ? BoxDecoration(
                        color:
                            (item.type == OverlayType.mainVideo ||
                                item.type == OverlayType.mainImage)
                            ? Colors.yellowAccent
                            : Colors.cyanAccent,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      )
                    : const BoxDecoration(color: Colors.transparent),
                child: Center(
                  child: Icon(
                    isSelected
                        ? Icons.keyboard_arrow_right
                        : Icons.drag_indicator,
                    size: isSelected ? 16 : 12,
                    color: isSelected ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineGrid(ManualEditorState state) {
    final maxMs = state.backgroundDuration.inMilliseconds.toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final halfWidth = screenWidth / 2;
        final timelineWidth = maxMs > 0
            ? (maxMs / 1000.0) * _pixelsPerSecond
            : screenWidth;

        // The tracks column
        final tracksColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            _buildTrackContentRow(
              _buildOverlayTrack(
                state.overlays
                    .where((o) => o.type == OverlayType.audio)
                    .toList(),
                maxMs,
                state,
                'Tap to add music',
              ),
              timelineWidth,
            ),
            _buildTrackContentRow(
              _buildOverlayTrack(
                state.overlays
                    .where((o) => o.type == OverlayType.text)
                    .toList(),
                maxMs,
                state,
                'Tap to add subtitle',
              ),
              timelineWidth,
            ),
            _buildTrackContentRow(
              _buildOverlayTrack(
                state.overlays
                    .where(
                      (o) =>
                          o.type == OverlayType.emoji ||
                          o.type == OverlayType.image,
                    )
                    .toList(),
                maxMs,
                state,
                'Tap to add sticker / PiP',
              ),
              timelineWidth,
            ),
            _buildTrackContentRow(
              state.baseMedia.isNotEmpty
                  ? _buildOverlayTrack(
                      state.baseMedia,
                      maxMs,
                      state,
                      'Tap to add video',
                      isBaseTrack: true,
                    )
                  : _buildEmptyTrackPlaceholder('Tap to add video'),
              timelineWidth,
            ),
            _buildTrackContentRow(
              _buildEmptyTrackPlaceholder(''),
              timelineWidth,
            ),
          ],
        );

        final iconsColumn = Column(
          children: [
            const SizedBox(height: 10),
            _buildTrackIconRow(
              icon: Icons.music_note,
              label: '+',
              onTap: _addAudioOverlay,
            ),
            _buildTrackIconRow(
              icon: Icons.title,
              label: '+',
              onTap: _addTextOverlay,
            ),
            _buildTrackIconRow(
              icon: Icons.image,
              label: '+',
              onTap: _addImageOverlay,
            ),
            _buildTrackIconRow(
              icon: Icons.video_library,
              label: '+',
              hasCoverButton: true,
              onTap: _pickBackgroundMedia,
            ),
            _buildTrackIconRow(
              icon: _isVideoMuted ? Icons.volume_off : Icons.volume_up,
              label: '',
              onTap: () {
                setState(() {
                  _isVideoMuted = !_isVideoMuted;
                  for (var controller in _baseVideoControllers.values) {
                    controller.setVolume(_isVideoMuted ? 0.0 : 1.0);
                  }
                });
              },
            ),
          ],
        );

        return SingleChildScrollView(
          child: Stack(
            children: [
              // Scrollable Timeline
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () =>
                    ref.read(manualEditorProvider.notifier).clearSelection(),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is UserScrollNotification) {
                      final isScrolling =
                          notification.direction != ScrollDirection.idle;
                      if (isScrolling && !_isScrollingTimeline) {
                        _isScrollingTimeline = true;
                        if (state.isPlaying) {
                          _togglePlayback(
                            state,
                          ); // Pause playback on manual drag
                        }
                      } else if (!isScrolling) {
                        _isScrollingTimeline = false;
                      }
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _timelineScrollController,
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      width: timelineWidth + screenWidth,
                      padding: EdgeInsets.symmetric(horizontal: halfWidth),
                      child: tracksColumn,
                    ),
                  ),
                ),
              ),

              // Sticky Icons
              AnimatedBuilder(
                animation: _timelineScrollController,
                builder: (context, child) {
                  double offset = 0.0;
                  if (_timelineScrollController.hasClients) {
                    offset = _timelineScrollController.offset;
                  }
                  double leftPos = halfWidth - offset - 70;
                  if (leftPos < 0) leftPos = 0; // Stick to left edge

                  return Positioned(
                    left: leftPos,
                    top: 0,
                    bottom: 0,
                    width: 70,
                    child: Container(
                      color: const Color(
                        0xFF1E1E1E,
                      ), // Solid background hides track underneath
                      child: child,
                    ),
                  );
                },
                child: iconsColumn,
              ),

              // Playhead (Vertical White Line)
              Positioned(
                left: halfWidth,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: Colors.white),
              ),

              // Timestamp Text above playhead
              Positioned(
                left: halfWidth + 8,
                top: 2,
                child: Text(
                  '${(state.currentTime.inMilliseconds / 1000.0).toStringAsFixed(2)}s / ${(maxMs / 1000.0).toStringAsFixed(2)}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageToolbar(OverlayItem item) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF1E64CC), // CapCut blue
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildToolbarActionMini(Icons.sync, 'Replace', () async {
              final picker = ImagePicker();
              final pickedFile = await picker.pickImage(
                source: ImageSource.gallery,
              );
              if (pickedFile != null) {
                ref
                    .read(manualEditorProvider.notifier)
                    .updateOverlay(item.copyWith(value: pickedFile.path));
              }
            }),
            _buildToolbarActionMini(Icons.animation, 'Motion', () {
              _showMotionBottomSheet(context, item);
            }),
            _buildToolbarActionMini(Icons.diamond_outlined, 'Keyframe', () {}),
            _buildToolbarActionMini(Icons.show_chart, 'Curve', () {}),
            _buildToolbarActionMini(Icons.lock_outline, 'Lock', () {}),
            _buildToolbarActionMini(Icons.copy, 'Duplicate', () {
              // duplicate logic
            }),
            _buildToolbarActionMini(Icons.delete_outline, 'Delete', () {
              ref.read(manualEditorProvider.notifier).removeOverlay(item.id);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTextToolbar(OverlayItem item) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF008B8B), // Teal
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildToolbarActionMini(Icons.edit_square, 'Edit', () {
              setState(() {
                _isEditingText = true;
              });
            }),
            _buildToolbarActionMini(Icons.animation, 'Motion', () {
              _showMotionBottomSheet(context, item);
            }),
            _buildToolbarActionMini(Icons.diamond_outlined, 'Keyframe', () {}),
            _buildToolbarActionMini(Icons.show_chart, 'Curve', () {}),
            _buildToolbarActionMini(Icons.lock_outline, 'Lock', () {}),
            _buildToolbarActionMini(Icons.copy, 'Duplicate', () {
              // duplicate logic
            }),
            _buildToolbarActionMini(Icons.delete_outline, 'Delete', () {
              ref.read(manualEditorProvider.notifier).removeOverlay(item.id);
            }),
          ],
        ),
      ),
    );
  }

  void _showMotionBottomSheet(BuildContext context, OverlayItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E), // Dark background
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext context) {
        int selectedTabIndex = 0;
        final tabs = ['In', 'Out', 'Loop'];

        final animations = [
          {'name': 'None', 'icon': Icons.block},
          {'name': 'Fade', 'icon': Icons.compare_arrows},
          {'name': 'Scale', 'icon': Icons.fit_screen},
          {'name': 'Spin', 'icon': Icons.rotate_right},
          {'name': 'Slide', 'icon': Icons.arrow_downward},
          {'name': 'Reveal', 'icon': Icons.ad_units},
          {'name': 'Gradient', 'icon': Icons.gradient},
        ];

        return StatefulBuilder(
          builder: (context, setState) {
            // Read latest item state
            final currentState = ref.watch(manualEditorProvider);
            final currentItem = currentState.overlays.firstWhere(
              (o) => o.id == item.id,
              orElse: () => item,
            );

            String selectedAnimation = 'None';
            if (selectedTabIndex == 0)
              selectedAnimation = currentItem.animationIn;
            else if (selectedTabIndex == 1)
              selectedAnimation = currentItem.animationOut;
            else if (selectedTabIndex == 2)
              selectedAnimation = currentItem.animationLoop;

            void updateAnimationState(String newAnim) {
              OverlayItem updated = currentItem;
              if (selectedTabIndex == 0)
                updated = updated.copyWith(animationIn: newAnim);
              else if (selectedTabIndex == 1)
                updated = updated.copyWith(animationOut: newAnim);
              else if (selectedTabIndex == 2)
                updated = updated.copyWith(animationLoop: newAnim);

              ref.read(manualEditorProvider.notifier).updateOverlay(updated);

              // Trigger preview by seeking slightly before start and playing
              if (newAnim != 'None') {
                final state = ref.read(manualEditorProvider);
                if (selectedTabIndex == 0 || selectedTabIndex == 2) {
                  ref
                      .read(manualEditorProvider.notifier)
                      .setCurrentTime(currentItem.startTime);

                  final activeMedia = _getActiveBaseMedia(
                    state,
                    currentItem.startTime,
                  );
                  if (activeMedia != null &&
                      activeMedia.type == OverlayType.mainVideo) {
                    final controller = _baseVideoControllers[activeMedia.id];
                    final localTime =
                        currentItem.startTime.inMilliseconds -
                        activeMedia.startTime.inMilliseconds +
                        activeMedia.mediaStartTime.inMilliseconds;
                    controller?.seekTo(Duration(milliseconds: localTime));
                  }
                } else {
                  final outStart =
                      currentItem.endTime -
                      Duration(
                        milliseconds: (currentItem.animationDuration * 1000)
                            .toInt(),
                      );
                  final seekTime = outStart.isNegative
                      ? Duration.zero
                      : outStart;
                  ref
                      .read(manualEditorProvider.notifier)
                      .setCurrentTime(seekTime);

                  final activeMedia = _getActiveBaseMedia(state, seekTime);
                  if (activeMedia != null &&
                      activeMedia.type == OverlayType.mainVideo) {
                    final controller = _baseVideoControllers[activeMedia.id];
                    final localTime =
                        seekTime.inMilliseconds -
                        activeMedia.startTime.inMilliseconds +
                        activeMedia.mediaStartTime.inMilliseconds;
                    controller?.seekTo(Duration(milliseconds: localTime));
                  }
                }
                if (!ref.read(manualEditorProvider).isPlaying) {
                  _togglePlayback(ref.read(manualEditorProvider));
                }
              }
            }

            void updateDurationState(double newDuration) {
              final updated = currentItem.copyWith(
                animationDuration: newDuration,
              );
              ref.read(manualEditorProvider.notifier).updateOverlay(updated);
            }

            return Container(
              height: 250,
              child: Column(
                children: [
                  // Tabs
                  Container(
                    height: 50,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(tabs.length, (index) {
                        final isSelected = selectedTabIndex == index;
                        return GestureDetector(
                          onTap: () => setState(() => selectedTabIndex = index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tabs[index],
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white54,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 16,
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    height: 2,
                                    width: 16,
                                    color: Colors.white,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Animations List
                  SizedBox(
                    height: 85,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: animations.length,
                      itemBuilder: (context, index) {
                        final anim = animations[index];
                        final isSelected = selectedAnimation == anim['name'];
                        return GestureDetector(
                          onTap: () =>
                              updateAnimationState(anim['name'] as String),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Column(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isSelected
                                        ? Border.all(
                                            color: Colors.yellow,
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                  child: Icon(
                                    anim['icon'] as IconData,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  anim['name'] as String,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white54,
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const Spacer(),

                  // Duration Slider
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const Text(
                          'Duration',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SliderTheme(
                            data: const SliderThemeData(
                              trackHeight: 2,
                              thumbShape: RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                            ),
                            child: Slider(
                              value: currentItem.animationDuration.clamp(
                                0.1,
                                3.0,
                              ),
                              min: 0.1,
                              max: 3.0,
                              activeColor: Colors.yellow,
                              inactiveColor: Colors.white24,
                              onChanged: updateDurationState,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${currentItem.animationDuration.toStringAsFixed(1)}s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Bottom Actions
                  Container(
                    height: 50,
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.white10, width: 1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: () {
                            if (ref.read(manualEditorProvider).isPlaying) {
                              _togglePlayback(ref.read(manualEditorProvider));
                            }
                            Navigator.pop(context);
                          },
                        ),
                        Row(
                          children: const [
                            Icon(
                              Icons.done_all,
                              color: Colors.white70,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Apply to all',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: () {
                            if (ref.read(manualEditorProvider).isPlaying) {
                              _togglePlayback(ref.read(manualEditorProvider));
                            }
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showTransitionBottomSheet(OverlayItem currentItem) {
    // Pause if playing
    if (ref.read(manualEditorProvider).isPlaying) {
      _togglePlayback(ref.read(manualEditorProvider));
    }

    final transitions = [
      {'name': 'None', 'icon': Icons.not_interested},
      {'name': 'Black', 'icon': Icons.stop},
      {'name': 'White', 'icon': Icons.stop_circle},
      {'name': 'Vertical', 'icon': Icons.unfold_more},
      {'name': 'Horizontal', 'icon': Icons.unfold_less},
      {'name': 'Blur', 'icon': Icons.blur_on},
      {'name': 'Circle', 'icon': Icons.panorama_fish_eye},
      {'name': 'Wipe Right', 'icon': Icons.switch_right},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        String localSelectedTransition = currentItem.animationOut;
        double localDuration = currentItem.animationDuration;

        return StatefulBuilder(
          builder: (context, setState) {
            void selectTransition(String name) {
              setState(() {
                localSelectedTransition = name;
              });
              ref
                  .read(manualEditorProvider.notifier)
                  .updateBaseMedia(currentItem.copyWith(
                    animationOut: name, 
                    animationDuration: localDuration
                  ));
            }

            void updateDuration(double val) {
              setState(() {
                localDuration = val;
              });
              ref
                  .read(manualEditorProvider.notifier)
                  .updateBaseMedia(
                    currentItem.copyWith(
                      animationOut: localSelectedTransition, 
                      animationDuration: val
                    ),
                  );
            }

            return Container(
              height: 350,
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  const Center(
                    child: Text(
                      'Base',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Transitions List
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: transitions.length,
                      itemBuilder: (context, index) {
                        final t = transitions[index];
                        final isSelected =
                            localSelectedTransition == t['name'] ||
                            (t['name'] == 'None' &&
                                localSelectedTransition == '');

                        return GestureDetector(
                          onTap: () => selectTransition(t['name'] as String),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Column(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isSelected
                                        ? Border.all(
                                            color: Colors.yellow,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: Icon(
                                    t['icon'] as IconData,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white54,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  t['name'] as String,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const Spacer(),

                  // Duration Slider
                  if (localSelectedTransition != 'None' &&
                      localSelectedTransition != '')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          const Text(
                            'Duration',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SliderTheme(
                              data: const SliderThemeData(
                                trackHeight: 2,
                                thumbShape: RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: RoundSliderOverlayShape(
                                  overlayRadius: 12,
                                ),
                              ),
                              child: Slider(
                                value: localDuration.clamp(
                                  0.1,
                                  3.0,
                                ),
                                min: 0.1,
                                max: 3.0,
                                activeColor: Colors.yellow,
                                inactiveColor: Colors.white24,
                                onChanged: updateDuration,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '${localDuration.toStringAsFixed(1)}s',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Bottom Actions
                  Container(
                    height: 50,
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.white10, width: 1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Row(
                          children: const [
                            Icon(
                              Icons.done_all,
                              color: Colors.white70,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Apply to all',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 24,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTransitionOverlay(ManualEditorState state) {
    if (state.baseMedia.length < 2) return const SizedBox.shrink();

    final currSec = state.currentTime.inMilliseconds / 1000.0;

    for (int i = 0; i < state.baseMedia.length - 1; i++) {
      final item = state.baseMedia[i];
      if (item.animationOut == 'None' || item.animationOut == '') continue;

      final tDuration = item.animationDuration; // duration of transition
      final halfD = tDuration / 2;
      final endSec = item.endTime.inMilliseconds / 1000.0;

      // Check if current time is within the transition window around the boundary
      if (currSec >= endSec - halfD && currSec <= endSec + halfD) {
        // Progress from 0.0 to 1.0 throughout the transition window
        double progress = (currSec - (endSec - halfD)) / tDuration;

        // Opacity peaks at 1.0 at exactly `endSec` (boundary), and is 0.0 at edges
        double opacity = 1.0 - ((progress - 0.5).abs() * 2);
        opacity = opacity.clamp(0.0, 1.0);

        if (item.animationOut == 'Black') {
          return Container(color: Colors.black.withOpacity(opacity));
        } else if (item.animationOut == 'White') {
          return Container(color: Colors.white.withOpacity(opacity));
        } else if (item.animationOut == 'Vertical') {
          return Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: FractionallySizedBox(
                  heightFactor: (opacity / 2).clamp(0.0, 1.0),
                  widthFactor: 1.0,
                  child: Container(color: Colors.black),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: (opacity / 2).clamp(0.0, 1.0),
                  widthFactor: 1.0,
                  child: Container(color: Colors.black),
                ),
              ),
            ],
          );
        } else if (item.animationOut == 'Horizontal') {
          return Stack(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: (opacity / 2).clamp(0.0, 1.0),
                  heightFactor: 1.0,
                  child: Container(color: Colors.black),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: (opacity / 2).clamp(0.0, 1.0),
                  heightFactor: 1.0,
                  child: Container(color: Colors.black),
                ),
              ),
            ],
          );
        } else if (item.animationOut == 'Blur') {
          double blurAmount = opacity * 20.0; // max blur of 20
          return BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
            child: Container(color: Colors.transparent),
          );
        } else if (item.animationOut == 'Circle') {
          return LayoutBuilder(
            builder: (context, constraints) {
              double maxDim = constraints.maxHeight > constraints.maxWidth 
                  ? constraints.maxHeight * 1.5 
                  : constraints.maxWidth * 1.5;
              double holeSize = maxDim * (1.0 - opacity);
              double borderWidth = maxDim; // large enough to cover the screen

              return Center(
                child: Container(
                  width: holeSize + borderWidth * 2,
                  height: holeSize + borderWidth * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.black,
                      width: borderWidth,
                    ),
                  ),
                ),
              );
            },
          );
        } else if (item.animationOut == 'Wipe Right') {
          return Stack(
            children: [
              Align(
                alignment: progress < 0.5 ? Alignment.centerLeft : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: (progress < 0.5 ? progress * 2 : (1.0 - progress) * 2).clamp(0.0, 1.0),
                  heightFactor: 1.0,
                  child: Container(color: Colors.black),
                ),
              ),
            ],
          );
        }
      }
    }

    return const SizedBox.shrink();
  }

  Widget _buildMainVideoToolbar(OverlayItem item) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFFFCC00), // CapCut yellow
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildToolbarActionMini(
              Icons.sync,
              'Replace',
              () => _replaceBaseMedia(item),
              color: Colors.black,
            ),
            _buildToolbarActionMini(
              Icons.content_cut,
              'Trim',
              () => _splitSelectedMedia(),
              color: Colors.black,
            ),
            _buildToolbarActionMini(
              Icons.diamond_outlined,
              'Keyframe',
              () {},
              color: Colors.black,
            ),
            _buildToolbarActionMini(
              Icons.show_chart,
              'Curve',
              () {},
              color: Colors.black,
            ),
            _buildToolbarActionMini(
              Icons.lock_outline,
              'Lock',
              () {},
              color: Colors.black,
            ),
            _buildToolbarActionMini(
              Icons.copy,
              'Duplicate',
              () {},
              color: Colors.black,
            ),
            _buildToolbarActionMini(Icons.delete_outline, 'Delete', () {
              // Handle main video delete if needed, or just clear selection
              ref.read(manualEditorProvider.notifier).clearSelection();
            }, color: Colors.black),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarActionMini(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color color = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarIcon(IconData icon, String label, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(
        backgroundColor: Color(0xFF181818),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final state = ref.watch(manualEditorProvider);
    final guidelines = ref.watch(guidelineProvider);

    OverlayItem? selectedOverlay;
    if (state.selectedOverlayId != null) {
      final allItems = [...state.baseMedia, ...state.overlays];
      final matches = allItems.where((o) => o.id == state.selectedOverlayId);
      if (matches.isNotEmpty) {
        selectedOverlay = matches.first;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF181818),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181818),
        elevation: 0,
        leadingWidth: 100,
        leading: Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.arrow_back_ios,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            IconButton(
              icon: const Icon(
                Icons.help_outline,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () {},
            ),
          ],
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.crop_square, color: Colors.white, size: 16),
            SizedBox(width: 4),
            Text(
              'Original',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined, color: Colors.white),
            onPressed: () {},
          ),
          Container(
            margin: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.blueAccent,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.ios_share, color: Colors.white, size: 18),
          ),
        ],
      ),
      body: Column(
        children: [
          // Canvas Area
          Expanded(
            flex: 4,
            child: Center(
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (_canvasSize !=
                        Size(constraints.maxWidth, constraints.maxHeight)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _canvasSize = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                      });
                    }
                    return ClipRect(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () => ref
                            .read(manualEditorProvider.notifier)
                            .clearSelection(),
                        child: Container(
                          color: Colors.black,
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              Builder(
                                builder: (context) {
                                  final activeMedia = _getActiveBaseMedia(
                                    state,
                                    state.currentTime,
                                  );
                                  if (activeMedia == null) {
                                    return const Center(
                                      child: Text(
                                        'Tap + to Add Media',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 14,
                                        ),
                                      ),
                                    );
                                  }

                                  final isVideo =
                                      activeMedia.type == OverlayType.mainVideo;
                                  final controller = isVideo
                                      ? _baseVideoControllers[activeMedia.id]
                                      : null;

                                  return Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => ref
                                          .read(manualEditorProvider.notifier)
                                          .setSelectedOverlay(activeMedia.id),
                                      onScaleStart: (details) {
                                        if (state.selectedOverlayId == null) return;
                                        if (state.selectedOverlayId == activeMedia.id) {
                                          _baseMediaStartScale = activeMedia.scale;
                                          _baseMediaStartRotation = activeMedia.rotation;
                                          _baseMediaStartPosition = activeMedia.position;
                                        } else {
                                          try {
                                            final selectedOverlay = state.overlays.firstWhere((o) => o.id == state.selectedOverlayId);
                                            _baseMediaStartScale = selectedOverlay.scale;
                                            _baseMediaStartRotation = selectedOverlay.rotation;
                                            _baseMediaStartPosition = selectedOverlay.position;
                                          } catch (_) {}
                                        }
                                      },
                                      onScaleUpdate: (details) {
                                        if (state.selectedOverlayId == null) return;
                                        
                                        final newScale = (_baseMediaStartScale * details.scale).clamp(0.1, 5.0);
                                        final newRotation = _baseMediaStartRotation + details.rotation;
                                        final newPosition = _baseMediaStartPosition + details.focalPointDelta;
                                        
                                        _baseMediaStartPosition = newPosition;

                                        if (state.selectedOverlayId == activeMedia.id) {
                                          ref.read(manualEditorProvider.notifier).updateBaseMedia(
                                            activeMedia.copyWith(
                                              scale: newScale,
                                              rotation: newRotation,
                                              position: newPosition,
                                            )
                                          );
                                        } else {
                                          try {
                                            final selectedOverlay = state.overlays.firstWhere((o) => o.id == state.selectedOverlayId);
                                            ref.read(manualEditorProvider.notifier).updateOverlay(
                                              selectedOverlay.copyWith(
                                                scale: newScale,
                                                rotation: newRotation,
                                                position: newPosition,
                                              )
                                            );
                                          } catch (_) {}
                                        }
                                      },
                                      child: Transform.translate(
                                        offset: activeMedia.position,
                                        child: Transform.rotate(
                                          angle: activeMedia.rotation,
                                          child: Transform.scale(
                                            scale: activeMedia.scale,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                SizedBox.expand(
                                                  child: isVideo
                                                      ? (controller != null &&
                                                                controller
                                                                    .value
                                                                    .isInitialized
                                                          ? FittedBox(
                                                              fit: BoxFit.cover,
                                                              child: SizedBox(
                                                                width: controller
                                                                    .value
                                                                    .size
                                                                    .width,
                                                                height: controller
                                                                    .value
                                                                    .size
                                                                    .height,
                                                                child: VideoPlayer(
                                                                  controller,
                                                                ),
                                                              ),
                                                            )
                                                          : const Center(
                                                              child:
                                                                  CircularProgressIndicator(),
                                                            ))
                                                      : Image.file(
                                                          File(activeMedia.value),
                                                          fit: BoxFit.cover,
                                                        ),
                                                ),
                                                if (state.selectedOverlayId ==
                                                    activeMedia.id)
                                                  Positioned.fill(
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        border: Border.all(
                                                          color: Colors.white,
                                                          width: 1.5,
                                                        ),
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
                                },
                              ),

                              // Transition Overlay (Base Track)
                              Positioned.fill(
                                child: _buildTransitionOverlay(state),
                              ),

                              if (guidelines['v'] == true)
                                Positioned(
                                  left: constraints.maxWidth / 2,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 1,
                                    decoration: const BoxDecoration(
                                      color: Colors.pinkAccent,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.pink,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (guidelines['h'] == true)
                                Positioned(
                                  top: constraints.maxHeight / 2,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    height: 1,
                                    decoration: const BoxDecoration(
                                      color: Colors.pinkAccent,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.pink,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              for (final overlay in state.overlays)
                                EditableOverlayItemWidget(
                                  key: ValueKey(overlay.id),
                                  item: overlay,
                                  canvasSize: _canvasSize,
                                  currentPlaybackTime: state.currentTime,
                                  isSelected:
                                      state.selectedOverlayId == overlay.id,
                                  onEditTap: () => ref
                                      .read(manualEditorProvider.notifier)
                                      .setSelectedOverlay(overlay.id),
                                  onUpdate: (updatedItem) => ref
                                      .read(manualEditorProvider.notifier)
                                      .updateOverlay(updatedItem),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Playback Controls
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(state.currentTime.inMilliseconds / 1000).toStringAsFixed(1)}s / ${(state.backgroundDuration.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                  const SizedBox(width: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.skip_previous,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () {},
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: Icon(
                          state.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                        onPressed: () => _togglePlayback(state),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(
                          Icons.skip_next,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () {},
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.content_copy,
                          color: Colors.white70,
                          size: 18,
                        ),
                        onPressed: () {},
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(
                          Icons.undo,
                          color: Colors.white70,
                          size: 18,
                        ),
                        onPressed: () {},
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(
                          Icons.redo,
                          color: Colors.white70,
                          size: 18,
                        ),
                        onPressed: () {},
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (selectedOverlay != null &&
              (selectedOverlay.type == OverlayType.mainVideo ||
                  selectedOverlay.type == OverlayType.mainImage))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildMainVideoToolbar(selectedOverlay),
            )
          else if (selectedOverlay != null)
            if (selectedOverlay.type == OverlayType.image ||
                selectedOverlay.type == OverlayType.emoji)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: _buildImageToolbar(selectedOverlay),
              )
            else if (selectedOverlay.type == OverlayType.text)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: _buildTextToolbar(selectedOverlay),
              ),
          if (_isEditingText && selectedOverlay != null && selectedOverlay.type == OverlayType.text)
            Expanded(flex: 2, child: _TextCustomizerWidget(
              itemId: selectedOverlay.id,
              onClose: () {
                setState(() {
                  _isEditingText = false;
                });
              },
            ))
          else
            Expanded(flex: 2, child: _buildTimelineGrid(state)),

          // Bottom Toolbar
          Container(
            height: 60,
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white10, width: 1)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildToolbarIcon(Icons.color_lens_outlined, 'Filter'),
                  _buildToolbarIcon(Icons.content_cut, 'Trim', onTap: () => _splitSelectedMedia()),
                  _buildToolbarIcon(Icons.auto_awesome, 'FX'),
                  _buildToolbarIcon(Icons.call_split, 'Split', onTap: () => _splitSelectedMedia()),
                  _buildToolbarIcon(Icons.speed, 'Speed'),
                  _buildToolbarIcon(Icons.volume_up_outlined, 'Volume'),
                  _buildToolbarIcon(Icons.blur_linear, 'Fade'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextCustomizerWidget extends ConsumerStatefulWidget {
  final String itemId;
  final VoidCallback? onClose;
  const _TextCustomizerWidget({Key? key, required this.itemId, this.onClose}) : super(key: key);

  @override
  ConsumerState<_TextCustomizerWidget> createState() => _TextCustomizerWidgetState();
}

class _TextCustomizerWidgetState extends ConsumerState<_TextCustomizerWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final item = ref.read(manualEditorProvider).overlays.firstWhere((o) => o.id == widget.itemId);
    _controller = TextEditingController(text: item.value);
    // Select all text by default so typing replaces it
    if (_controller.text.isNotEmpty) {
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualEditorProvider);
    final item = state.overlays.firstWhere((o) => o.id == widget.itemId, orElse: () => state.overlays.first);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: const Color(0xFF181818),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Edit Text',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (widget.onClose != null) {
                      widget.onClose!();
                    } else {
                      ref.read(manualEditorProvider.notifier).setSelectedOverlay(null);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Done', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Enter text here',
                hintStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
              ),
              onChanged: (val) {
                ref.read(manualEditorProvider.notifier).updateOverlay(item.copyWith(value: val));
              },
              onSubmitted: (_) {
                if (widget.onClose != null) {
                  widget.onClose!();
                } else {
                  ref.read(manualEditorProvider.notifier).setSelectedOverlay(null);
                  Navigator.pop(context);
                }
              },
            ),
            const SizedBox(height: 16),
            const Text('Style', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: TextStyleMode.values.map((mode) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(
                        mode.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      selectedColor: Colors.blueAccent,
                      backgroundColor: Colors.grey[900],
                      selected: item.textStyleMode == mode,
                      onSelected: (selected) {
                        if (selected) {
                          ref.read(manualEditorProvider.notifier).updateOverlay(item.copyWith(textStyleMode: mode));
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Align:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.format_align_left,
                    color: item.textAlign == TextAlign.left ? Colors.blueAccent : Colors.white,
                  ),
                  onPressed: () => ref.read(manualEditorProvider.notifier).updateOverlay(item.copyWith(textAlign: TextAlign.left)),
                ),
                IconButton(
                  icon: Icon(
                    Icons.format_align_center,
                    color: item.textAlign == TextAlign.center ? Colors.blueAccent : Colors.white,
                  ),
                  onPressed: () => ref.read(manualEditorProvider.notifier).updateOverlay(item.copyWith(textAlign: TextAlign.center)),
                ),
                IconButton(
                  icon: Icon(
                    Icons.format_align_right,
                    color: item.textAlign == TextAlign.right ? Colors.blueAccent : Colors.white,
                  ),
                  onPressed: () => ref.read(manualEditorProvider.notifier).updateOverlay(item.copyWith(textAlign: TextAlign.right)),
                ),
              ],
            ),
          ],
        ),
       ),
      ),
    );
  }
}

class _VideoFilmstrip extends StatefulWidget {
  final String videoPath;
  final int durationMs;

  const _VideoFilmstrip({Key? key, required this.videoPath, required this.durationMs}) : super(key: key);

  @override
  _VideoFilmstripState createState() => _VideoFilmstripState();
}

class _VideoFilmstripState extends State<_VideoFilmstrip> {
  List<Uint8List?> _thumbnails = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generateThumbnails();
  }

  @override
  void didUpdateWidget(_VideoFilmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath) {
      _generateThumbnails();
    }
  }

  Future<void> _generateThumbnails() async {
    setState(() {
      _loading = true;
    });

    int count = 10; // fixed count of thumbnails to show across the track
    List<Uint8List?> th = [];
    int interval = widget.durationMs ~/ count;

    for (int i = 0; i < count; i++) {
      try {
        final uint8list = await VideoThumbnail.thumbnailData(
          video: widget.videoPath,
          imageFormat: ImageFormat.JPEG,
          timeMs: i * interval,
          quality: 25,
          maxHeight: 100, // optimization
        );
        th.add(uint8list);
      } catch (e) {
        th.add(null);
      }
    }

    if (mounted) {
      setState(() {
        _thumbnails = th;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(color: Colors.black45);
    }
    return Row(
      children: _thumbnails.map((t) {
        if (t != null) {
          return Expanded(
            child: Image.memory(t, fit: BoxFit.cover, height: double.infinity),
          );
        } else {
          return Expanded(child: Container(color: Colors.black45));
        }
      }).toList(),
    );
  }
}
