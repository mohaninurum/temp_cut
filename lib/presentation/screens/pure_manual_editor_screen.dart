import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';

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
  VideoPlayerController? _videoController;
  Timer? _timer;

  // Dragging state for smooth timeline updates
  Duration? _dragInitialStartTime;
  Duration? _dragInitialEndTime;
  double _dragAccumulator = 0.0;

  Size _canvasSize = Size.zero;
  
  final ScrollController _timelineScrollController = ScrollController();
  bool _isScrollingTimeline = false;
  static const double _pixelsPerSecond = 50.0;
  bool _isReady = false;

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
        ref.read(manualEditorProvider.notifier).setCurrentTime(Duration(milliseconds: clampedTimeMs.toInt()));
        if (_videoController != null && !_videoController!.value.isPlaying) {
          _videoController!.seekTo(Duration(milliseconds: clampedTimeMs.toInt()) + state.baseVideoTrimStart);
        }
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _timer?.cancel();
    _timelineScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickBackgroundMedia() async {
    final picker = ImagePicker();
    final media = await picker.pickMedia();

    if (media != null) {
      final isVideo =
          media.path.toLowerCase().endsWith('.mp4') ||
          media.path.toLowerCase().endsWith('.mov');

      if (isVideo) {
        _videoController?.dispose();
        _videoController = VideoPlayerController.file(File(media.path));
        await _videoController!.initialize();
        ref
            .read(manualEditorProvider.notifier)
            .setBackgroundAsset(
              media.path,
              duration: _videoController!.value.duration,
            );
        _togglePlayback(ref.read(manualEditorProvider));
      } else {
        _videoController?.dispose();
        _videoController = null;
        ref
            .read(manualEditorProvider.notifier)
            .setBackgroundAsset(
              media.path,
              duration: const Duration(seconds: 15),
            );
      }
    }
  }

  void _togglePlayback(ManualEditorState state) {
    if (state.isPlaying) {
      _timer?.cancel();
      _videoController?.pause();
      ref.read(manualEditorProvider.notifier).setPlaying(false);
    } else {
      _videoController?.play();
      ref.read(manualEditorProvider.notifier).setPlaying(true);

      _timer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final currentState = ref.read(manualEditorProvider);
        final maxDuration = currentState.backgroundDuration;

        Duration newTime;
        if (_videoController != null && _videoController!.value.isInitialized) {
          newTime = _videoController!.value.position - currentState.baseVideoTrimStart;
        } else {
          newTime = currentState.currentTime + const Duration(milliseconds: 33);
        }

        if (newTime >= maxDuration || newTime.isNegative) {
          newTime = Duration.zero;
          _videoController?.seekTo(currentState.baseVideoTrimStart);
          if (_videoController == null) {
            timer.cancel();
            ref.read(manualEditorProvider.notifier).setPlaying(false);
          }
        }
        ref.read(manualEditorProvider.notifier).setCurrentTime(newTime);
        
        if (!_isScrollingTimeline && _timelineScrollController.hasClients) {
          final targetOffset = (newTime.inMilliseconds / 1000.0) * _pixelsPerSecond;
          _timelineScrollController.jumpTo(targetOffset);
        }
      });
    }
  }

  void _addTextOverlay() {
    String input = 'New Text';
    final state = ref.read(manualEditorProvider);
    
    final textOverlays = state.overlays.where((o) => o.type == OverlayType.text);
    Duration startTime = Duration.zero;
    if (textOverlays.isNotEmpty) {
      startTime = textOverlays.map((o) => o.endTime).reduce((a, b) => a > b ? a : b);
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
      
      final imageOverlays = state.overlays.where((o) => o.type == OverlayType.image);
      Duration startTime = Duration.zero;
      if (imageOverlays.isNotEmpty) {
        startTime = imageOverlays.map((o) => o.endTime).reduce((a, b) => a > b ? a : b);
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

  Widget _buildTextCustomizer(OverlayItem item) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF181818),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Style',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => ref
                    .read(manualEditorProvider.notifier)
                    .setSelectedOverlay(null),
              ),
            ],
          ),
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
                        ref
                            .read(manualEditorProvider.notifier)
                            .updateOverlay(item.copyWith(textStyleMode: mode));
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
              const Text('Align:', style: TextStyle(color: Colors.white)),
              IconButton(
                icon: Icon(
                  Icons.format_align_left,
                  color: item.textAlign == TextAlign.left
                      ? Colors.blueAccent
                      : Colors.white,
                ),
                onPressed: () => ref
                    .read(manualEditorProvider.notifier)
                    .updateOverlay(item.copyWith(textAlign: TextAlign.left)),
              ),
              IconButton(
                icon: Icon(
                  Icons.format_align_center,
                  color: item.textAlign == TextAlign.center
                      ? Colors.blueAccent
                      : Colors.white,
                ),
                onPressed: () => ref
                    .read(manualEditorProvider.notifier)
                    .updateOverlay(item.copyWith(textAlign: TextAlign.center)),
              ),
              IconButton(
                icon: Icon(
                  Icons.format_align_right,
                  color: item.textAlign == TextAlign.right
                      ? Colors.blueAccent
                      : Colors.white,
                ),
                onPressed: () => ref
                    .read(manualEditorProvider.notifier)
                    .updateOverlay(item.copyWith(textAlign: TextAlign.right)),
              ),
            ],
          ),
        ],
      ),
    );
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
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 2,
              ),
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
    return SizedBox(
      width: width,
      child: trackContent,
    );
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

  Widget _buildMainMediaTrack(
    String path,
    double maxMs,
    bool isSelected,
    VoidCallback onTap,
    ManualEditorState state,
    double trackWidth,
  ) {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final totalDurationMs = _videoController!.value.duration.inMilliseconds.toDouble();
    final startMs = state.baseVideoTrimStart.inMilliseconds.toDouble();
    final endMs = state.baseVideoTrimEnd.inMilliseconds.toDouble();

    final startPx = (startMs / totalDurationMs) * trackWidth;
    final endPx = (endMs / totalDurationMs) * trackWidth;
    final widthPx = endPx - startPx;

    final durationSeconds = (endMs - startMs) / 1000.0;
    final durationText = '${durationSeconds.toStringAsFixed(2)}s';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        height: 40,
        width: trackWidth,
        color: Colors.grey[900],
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: startPx.clamp(0, trackWidth),
              width: widthPx.clamp(0, trackWidth - startPx),
              top: 0,
              bottom: 0,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (details) {
                        _dragInitialStartTime = state.baseVideoTrimStart;
                        _dragInitialEndTime = state.baseVideoTrimEnd;
                        _dragAccumulator = 0.0;
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_dragInitialStartTime == null || _dragInitialEndTime == null) return;
                        _dragAccumulator += details.delta.dx;
                        final deltaMs = (_dragAccumulator / trackWidth) * totalDurationMs;
                        final duration = _dragInitialEndTime!.inMilliseconds - _dragInitialStartTime!.inMilliseconds;

                        int newStartMs = _dragInitialStartTime!.inMilliseconds + deltaMs.toInt();
                        int newEndMs = _dragInitialEndTime!.inMilliseconds + deltaMs.toInt();

                        if (newStartMs < 0) {
                          newStartMs = 0;
                          newEndMs = duration;
                        } else if (newEndMs > totalDurationMs) {
                          newEndMs = totalDurationMs.toInt();
                          newStartMs = newEndMs - duration;
                        }

                        ref.read(manualEditorProvider.notifier).updateBaseVideoTrim(
                              Duration(milliseconds: newStartMs),
                              Duration(milliseconds: newEndMs),
                            );
                      },
                      onHorizontalDragEnd: (_) {
                        _dragInitialStartTime = null;
                        _dragInitialEndTime = null;
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF004D40) : Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                          border: isSelected ? Border.all(color: Colors.yellowAccent, width: 1.5) : Border.all(color: Colors.white, width: 1),
                        ),
                        child: Center(
                          child: Text(
                            isSelected ? 'Main Video - $durationText' : 'Main Video',
                            style: TextStyle(
                              color: isSelected ? Colors.yellowAccent : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                        _dragInitialStartTime = state.baseVideoTrimStart;
                        _dragAccumulator = 0.0;
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_dragInitialStartTime == null) return;
                        _dragAccumulator += details.delta.dx;
                        final deltaMs = (_dragAccumulator / trackWidth) * totalDurationMs;
                        final clampedStart = (_dragInitialStartTime!.inMilliseconds + deltaMs.toInt())
                            .clamp(0, state.baseVideoTrimEnd.inMilliseconds - 500);
                        ref.read(manualEditorProvider.notifier).updateBaseVideoTrim(
                              Duration(milliseconds: clampedStart),
                              state.baseVideoTrimEnd,
                            );
                      },
                      onHorizontalDragEnd: (_) => _dragInitialStartTime = null,
                      child: Container(
                        width: 16,
                        decoration: isSelected
                            ? const BoxDecoration(
                                color: Colors.yellowAccent,
                                borderRadius: BorderRadius.horizontal(left: Radius.circular(3)),
                              )
                            : const BoxDecoration(color: Colors.transparent),
                        child: Center(
                          child: Icon(
                            isSelected ? Icons.keyboard_arrow_left : Icons.drag_indicator,
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
                        _dragInitialEndTime = state.baseVideoTrimEnd;
                        _dragAccumulator = 0.0;
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_dragInitialEndTime == null) return;
                        _dragAccumulator += details.delta.dx;
                        final deltaMs = (_dragAccumulator / trackWidth) * totalDurationMs;
                        final clampedEnd = (_dragInitialEndTime!.inMilliseconds + deltaMs.toInt())
                            .clamp(state.baseVideoTrimStart.inMilliseconds + 500, totalDurationMs.toInt());
                        ref.read(manualEditorProvider.notifier).updateBaseVideoTrim(
                              state.baseVideoTrimStart,
                              Duration(milliseconds: clampedEnd),
                            );
                      },
                      onHorizontalDragEnd: (_) => _dragInitialEndTime = null,
                      child: Container(
                        width: 16,
                        decoration: isSelected
                            ? const BoxDecoration(
                                color: Colors.yellowAccent,
                                borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
                              )
                            : const BoxDecoration(color: Colors.transparent),
                        child: Center(
                          child: Icon(
                            isSelected ? Icons.keyboard_arrow_right : Icons.drag_indicator,
                            size: isSelected ? 16 : 12,
                            color: isSelected ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayTrack(
    List<OverlayItem> items,
    double maxMs,
    ManualEditorState state,
    String emptyText,
  ) {
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
            ],
          );
        },
      ),
    );
  }

  Widget _buildTrackItem(
    OverlayItem item,
    double maxMs,
    double trackWidth,
    ManualEditorState state,
  ) {
    final startPx = (item.startTime.inMilliseconds / maxMs) * trackWidth;
    final endPx = (item.endTime.inMilliseconds / maxMs) * trackWidth;
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

                ref
                    .read(manualEditorProvider.notifier)
                    .updateOverlay(
                      item.copyWith(
                        startTime: Duration(milliseconds: newStartMs),
                        endTime: Duration(milliseconds: newEndMs),
                      ),
                    );
              },
              onHorizontalDragEnd: (_) {
                _dragInitialStartTime = null;
                _dragInitialEndTime = null;
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF004D40) // Dark teal
                      : Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                  border: isSelected
                      ? Border.all(color: Colors.cyanAccent, width: 1.5)
                      : Border.all(color: Colors.white, width: 1),
                ),
                child: Center(
                  child: isSelected
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.type == OverlayType.emoji
                                  ? item.value
                                  : 'Text',
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              durationText,
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          item.type == OverlayType.emoji ? item.value : 'Text',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
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
                _dragAccumulator = 0.0;
              },
              onHorizontalDragUpdate: (details) {
                if (_dragInitialStartTime == null) return;
                _dragAccumulator += details.delta.dx;
                final deltaMs = (_dragAccumulator / trackWidth) * maxMs;
                final clampedStart =
                    (_dragInitialStartTime!.inMilliseconds + deltaMs.toInt())
                        .clamp(0, item.endTime.inMilliseconds - 500);
                ref
                    .read(manualEditorProvider.notifier)
                    .updateOverlay(
                      item.copyWith(
                        startTime: Duration(milliseconds: clampedStart),
                      ),
                    );
              },
              onHorizontalDragEnd: (_) => _dragInitialStartTime = null,
              child: Container(
                width: 16,
                decoration: isSelected
                    ? const BoxDecoration(
                        color: Colors.cyanAccent,
                        borderRadius: BorderRadius.horizontal(
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
                ref
                    .read(manualEditorProvider.notifier)
                    .updateOverlay(
                      item.copyWith(
                        endTime: Duration(milliseconds: clampedEnd),
                      ),
                    );
              },
              onHorizontalDragEnd: (_) => _dragInitialEndTime = null,
              child: Container(
                width: 16,
                decoration: isSelected
                    ? const BoxDecoration(
                        color: Colors.cyanAccent,
                        borderRadius: BorderRadius.horizontal(
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
    if (maxMs == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final halfWidth = screenWidth / 2;
        final timelineWidth = (maxMs / 1000.0) * _pixelsPerSecond;

        // The tracks column
        final tracksColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            _buildTrackContentRow(
              _buildEmptyTrackPlaceholder('Tap to add music'),
              timelineWidth,
            ),
            _buildTrackContentRow(
              _buildOverlayTrack(
                state.overlays.where((o) => o.type == OverlayType.text).toList(),
                maxMs,
                state,
                'Tap to add subtitle',
              ),
              timelineWidth,
            ),
            _buildTrackContentRow(
              _buildOverlayTrack(
                state.overlays
                    .where((o) => o.type == OverlayType.emoji || o.type == OverlayType.image)
                    .toList(),
                maxMs,
                state,
                'Tap to add sticker / PiP',
              ),
              timelineWidth,
            ),
            _buildTrackContentRow(
              state.backgroundAssetPath != null
                  ? _buildMainMediaTrack(
                      state.backgroundAssetPath!,
                      maxMs,
                      state.selectedOverlayId == 'main_video',
                      () => ref.read(manualEditorProvider.notifier).setSelectedOverlay('main_video'),
                      state,
                      timelineWidth,
                    )
                  : _buildEmptyTrackPlaceholder('Tap to add video'),
              timelineWidth,
            ),
            _buildTrackContentRow(_buildEmptyTrackPlaceholder(''), timelineWidth),
          ],
        );

        final iconsColumn = Column(
          children: [
            const SizedBox(height: 10),
            _buildTrackIconRow(icon: Icons.music_note, label: '+', onTap: () {}),
            _buildTrackIconRow(icon: Icons.title, label: '+', onTap: _addTextOverlay),
            _buildTrackIconRow(icon: Icons.image, label: '+', onTap: _addImageOverlay),
            _buildTrackIconRow(
              icon: Icons.video_library,
              label: '+',
              hasCoverButton: true,
              onTap: _pickBackgroundMedia,
            ),
            _buildTrackIconRow(icon: Icons.volume_up, label: '', onTap: () {}),
          ],
        );

        return SingleChildScrollView(
          child: Stack(
            children: [
              // Scrollable Timeline
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => ref.read(manualEditorProvider.notifier).clearSelection(),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is UserScrollNotification) {
                      final isScrolling = notification.direction != ScrollDirection.idle;
                      if (isScrolling && !_isScrollingTimeline) {
                        _isScrollingTimeline = true;
                        if (state.isPlaying) {
                          _togglePlayback(state); // Pause playback on manual drag
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
                      color: const Color(0xFF1E1E1E), // Solid background hides track underneath
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
                child: Container(
                  width: 2,
                  color: Colors.white,
                ),
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
            _buildToolbarActionMini(
              Icons.sync,
              'Replace',
              () => _addImageOverlay(),
            ),
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
              // We could show the customizer here using a modal bottom sheet!
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => Container(
                  height: MediaQuery.of(context).size.height * 0.4,
                  child: _buildTextCustomizer(item),
                ),
              );
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
                if (selectedTabIndex == 0 || selectedTabIndex == 2) {
                  ref
                      .read(manualEditorProvider.notifier)
                      .setCurrentTime(currentItem.startTime);
                  _videoController?.seekTo(currentItem.startTime);
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
                  _videoController?.seekTo(seekTime);
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

  Widget _buildMainVideoToolbar() {
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
              () => _pickBackgroundMedia(),
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

  Widget _buildToolbarIcon(IconData icon, String label) {
    return Padding(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(
        backgroundColor: Color(0xFF181818),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final state = ref.watch(manualEditorProvider);
    final guidelines = ref.watch(guidelineProvider);

    OverlayItem? selectedOverlay;
    if (state.selectedOverlayId != null) {
      final matches = state.overlays.where(
        (o) => o.id == state.selectedOverlayId,
      );
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
                              if (state.backgroundAssetPath != null)
                                Positioned.fill(
                                  child: GestureDetector(
                                    onTap: () => ref
                                        .read(manualEditorProvider.notifier)
                                        .setSelectedOverlay('main_video'),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        SizedBox.expand(
                                          child: state.backgroundAssetPath!
                                                      .toLowerCase()
                                                      .endsWith('.mp4') ||
                                                  state.backgroundAssetPath!
                                                      .toLowerCase()
                                                      .endsWith('.mov')
                                              ? (_videoController != null &&
                                                      _videoController!
                                                          .value.isInitialized
                                                  ? FittedBox(
                                                      fit: BoxFit.cover,
                                                      child: SizedBox(
                                                        width: _videoController!
                                                            .value.size.width,
                                                        height:
                                                            _videoController!
                                                                .value.size.height,
                                                        child: VideoPlayer(
                                                          _videoController!,
                                                        ),
                                                      ),
                                                    )
                                                  : const Center(
                                                      child:
                                                          CircularProgressIndicator(),
                                                    ))
                                              : Image.file(
                                                  File(
                                                    state.backgroundAssetPath!,
                                                  ),
                                                  fit: BoxFit.cover,
                                                ),
                                        ),
                                        if (state.selectedOverlayId ==
                                            'main_video')
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
                                )
                              else
                                const Center(
                                  child: Text(
                                    'Tap Background Tool to Add',
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 14,
                                    ),
                                  ),
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

          if (state.selectedOverlayId == 'main_video')
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: _buildMainVideoToolbar(),
            )
          else if (state.selectedOverlayId != null && selectedOverlay != null)
            if (selectedOverlay.type == OverlayType.image)
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
                  _buildToolbarIcon(Icons.content_cut, 'Trim'),
                  _buildToolbarIcon(Icons.auto_awesome, 'FX'),
                  _buildToolbarIcon(Icons.call_split, 'Split'),
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
