import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
  ConsumerState<PureManualEditorScreen> createState() => _PureManualEditorScreenState();
}

class _PureManualEditorScreenState extends ConsumerState<PureManualEditorScreen> {
  VideoPlayerController? _videoController;
  
  // Playback state
  bool _isPlaying = false;
  Duration _currentTime = Duration.zero;
  Timer? _timer;

  // Selected Item for Customizer
  String? _selectedOverlayId;

  Size _canvasSize = Size.zero;

  @override
  void dispose() {
    _videoController?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _pickBackgroundMedia() async {
    final picker = ImagePicker();
    final media = await picker.pickMedia();
    
    if (media != null) {
      final isVideo = media.path.toLowerCase().endsWith('.mp4') || media.path.toLowerCase().endsWith('.mov');
      
      if (isVideo) {
        _videoController?.dispose();
        _videoController = VideoPlayerController.file(File(media.path));
        await _videoController!.initialize();
        ref.read(manualEditorProvider.notifier).setBackgroundAsset(
          media.path, 
          duration: _videoController!.value.duration,
        );
        _togglePlayback();
      } else {
        ref.read(manualEditorProvider.notifier).setBackgroundAsset(
          media.path,
          duration: const Duration(seconds: 15),
        );
      }
      setState(() {});
    }
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _timer?.cancel();
      _videoController?.pause();
      setState(() => _isPlaying = false);
    } else {
      _videoController?.play();
      setState(() => _isPlaying = true);
      
      _timer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
        if (!mounted) return;
        final maxDuration = ref.read(manualEditorProvider).backgroundDuration;
        
        setState(() {
          if (_videoController != null && _videoController!.value.isInitialized) {
            _currentTime = _videoController!.value.position;
          } else {
            _currentTime += const Duration(milliseconds: 33);
          }

          if (_currentTime >= maxDuration) {
            _currentTime = Duration.zero;
            _videoController?.seekTo(Duration.zero);
            if (_videoController == null) {
              _togglePlayback(); // Pause if image
            }
          }
        });
      });
    }
  }

  void _addTextOverlay() {
    String input = 'New Text';
    ref.read(manualEditorProvider.notifier).addOverlay(
      OverlayItem(
        id: const Uuid().v4(),
        type: OverlayType.text,
        value: input,
        position: const Offset(100, 200),
        startTime: Duration.zero,
        endTime: ref.read(manualEditorProvider).backgroundDuration,
      ),
    );
  }

  void _addEmojiOverlay() {
    ref.read(manualEditorProvider.notifier).addOverlay(
      OverlayItem(
        id: const Uuid().v4(),
        type: OverlayType.emoji,
        value: '🔥',
        position: const Offset(150, 300),
        scale: 2.0,
        startTime: Duration.zero,
        endTime: ref.read(manualEditorProvider).backgroundDuration,
      ),
    );
  }

  // 2. Instagram-Style Trending Text Customizer UI
  Widget _buildTextCustomizer(OverlayItem item) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Style', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectedOverlayId = null)),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: TextStyleMode.values.map((mode) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(mode.name, style: const TextStyle(color: Colors.white)),
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
              const Text('Align:', style: TextStyle(color: Colors.white)),
              IconButton(
                icon: Icon(Icons.format_align_left, color: item.textAlign == TextAlign.left ? Colors.blueAccent : Colors.white),
                onPressed: () => ref.read(manualEditorProvider.notifier).updateOverlay(item.copyWith(textAlign: TextAlign.left)),
              ),
              IconButton(
                icon: Icon(Icons.format_align_center, color: item.textAlign == TextAlign.center ? Colors.blueAccent : Colors.white),
                onPressed: () => ref.read(manualEditorProvider.notifier).updateOverlay(item.copyWith(textAlign: TextAlign.center)),
              ),
              IconButton(
                icon: Icon(Icons.format_align_right, color: item.textAlign == TextAlign.right ? Colors.blueAccent : Colors.white),
                onPressed: () => ref.read(manualEditorProvider.notifier).updateOverlay(item.copyWith(textAlign: TextAlign.right)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Curve:', style: TextStyle(color: Colors.white)),
              Expanded(
                child: Slider(
                  value: item.curveFactor,
                  min: 0.0,
                  max: 1.0,
                  activeColor: Colors.pinkAccent,
                  onChanged: (val) {
                    ref.read(manualEditorProvider.notifier).updateOverlay(item.copyWith(curveFactor: val));
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 1. Multi-Track Duration Timeline
  Widget _buildTimelineTrack(ManualEditorState state) {
    final maxMs = state.backgroundDuration.inMilliseconds.toDouble();
    if (maxMs == 0) return const SizedBox.shrink();

    return Container(
      height: 160,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          // Playhead Progress
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('${(_currentTime.inMilliseconds / 1000).toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white, fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _currentTime.inMilliseconds.toDouble().clamp(0, maxMs),
                    min: 0,
                    max: maxMs,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                    onChanged: (val) {
                      final newTime = Duration(milliseconds: val.toInt());
                      setState(() => _currentTime = newTime);
                      _videoController?.seekTo(newTime);
                    },
                  ),
                ),
              ],
            ),
          ),
          // Tracks
          Expanded(
            child: ListView.builder(
              itemCount: state.overlays.length,
              itemBuilder: (context, index) {
                final item = state.overlays[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final trackWidth = constraints.maxWidth;
                      final startPx = (item.startTime.inMilliseconds / maxMs) * trackWidth;
                      final endPx = (item.endTime.inMilliseconds / maxMs) * trackWidth;
                      final width = endPx - startPx;

                      return Stack(
                        children: [
                          Container(height: 30, color: Colors.grey[900], width: double.infinity),
                          Positioned(
                            left: startPx.clamp(0, trackWidth),
                            width: width.clamp(0, trackWidth - startPx),
                            height: 30,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _selectedOverlayId == item.id ? Colors.blueAccent : Colors.white24,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white, width: 1),
                              ),
                              child: Center(
                                child: Text(item.type == OverlayType.emoji ? item.value : 'Text', 
                                    style: const TextStyle(color: Colors.white, fontSize: 10), overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ),
                          // Start Handle
                          Positioned(
                            left: startPx.clamp(0, trackWidth) - 10,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (details) {
                                final newStartPx = startPx + details.delta.dx;
                                final newStartMs = (newStartPx / trackWidth) * maxMs;
                                final clampedStart = newStartMs.toInt().clamp(0, item.endTime.inMilliseconds - 500);
                                final newStart = Duration(milliseconds: clampedStart);
                                ref.read(manualEditorProvider.notifier).updateOverlay(item.copyWith(startTime: newStart));
                              },
                              child: Container(width: 20, height: 30, color: Colors.transparent, child: const Center(child: Icon(Icons.drag_indicator, size: 12, color: Colors.white))),
                            ),
                          ),
                          // End Handle
                          Positioned(
                            left: endPx.clamp(0, trackWidth) - 10,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (details) {
                                final newEndPx = endPx + details.delta.dx;
                                final newEndMs = (newEndPx / trackWidth) * maxMs;
                                final clampedEnd = newEndMs.toInt().clamp(item.startTime.inMilliseconds + 500, state.backgroundDuration.inMilliseconds);
                                final newEnd = Duration(milliseconds: clampedEnd);
                                ref.read(manualEditorProvider.notifier).updateOverlay(item.copyWith(endTime: newEnd));
                              },
                              child: Container(width: 20, height: 30, color: Colors.transparent, child: const Center(child: Icon(Icons.drag_indicator, size: 12, color: Colors.white))),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualEditorProvider);
    final guidelines = ref.watch(guidelineProvider);

    final selectedOverlay = _selectedOverlayId != null 
        ? state.overlays.firstWhere((o) => o.id == _selectedOverlayId, orElse: () => state.overlays.first)
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Advanced Manual Editor', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
            onPressed: _togglePlayback,
          ),
          IconButton(
            icon: const Icon(Icons.check, color: Colors.blueAccent),
            onPressed: () {},
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // 1. Strict 9:16 canvas
                Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (_canvasSize != Size(constraints.maxWidth, constraints.maxHeight)) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                          });
                        }
                        return Container(
                          color: Colors.grey[900],
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              // Background
                              if (state.backgroundAssetPath != null)
                                Positioned.fill(
                                  child: state.backgroundAssetPath!.toLowerCase().endsWith('.mp4') || state.backgroundAssetPath!.toLowerCase().endsWith('.mov')
                                      ? (_videoController != null && _videoController!.value.isInitialized
                                          ? SizedBox.expand(
                                              child: FittedBox(
                                                fit: BoxFit.cover,
                                                child: SizedBox(
                                                  width: _videoController!.value.size.width,
                                                  height: _videoController!.value.size.height,
                                                  child: VideoPlayer(_videoController!),
                                                ),
                                              ),
                                            )
                                          : const Center(child: CircularProgressIndicator()))
                                      : Image.file(File(state.backgroundAssetPath!), fit: BoxFit.cover),
                                )
                              else
                                const Center(child: Text('No Background Media', style: TextStyle(color: Colors.white54, fontSize: 18))),
                                
                              // 4. Snap-to-Center Guidelines
                              if (guidelines['v'] == true)
                                Positioned(
                                  left: constraints.maxWidth / 2,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(width: 1, decoration: const BoxDecoration(color: Colors.pinkAccent, boxShadow: [BoxShadow(color: Colors.pink, blurRadius: 4)])),
                                ),
                              if (guidelines['h'] == true)
                                Positioned(
                                  top: constraints.maxHeight / 2,
                                  left: 0,
                                  right: 0,
                                  child: Container(height: 1, decoration: const BoxDecoration(color: Colors.pinkAccent, boxShadow: [BoxShadow(color: Colors.pink, blurRadius: 4)])),
                                ),

                              // Overlays
                              for (final overlay in state.overlays)
                                EditableOverlayItemWidget(
                                  key: ValueKey(overlay.id),
                                  item: overlay,
                                  canvasSize: _canvasSize,
                                  currentPlaybackTime: _currentTime,
                                  onEditTap: () => setState(() => _selectedOverlayId = overlay.id),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                // Toolbar floating on bottom of canvas
                if (_selectedOverlayId == null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildToolButton(icon: Icons.image, label: 'Background', onTap: _pickBackgroundMedia),
                            const SizedBox(width: 24),
                            _buildToolButton(icon: Icons.title, label: 'Add Text', onTap: _addTextOverlay),
                            const SizedBox(width: 24),
                            _buildToolButton(icon: Icons.emoji_emotions, label: 'Add Emoji', onTap: _addEmojiOverlay),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Customizer or Timeline Area
          if (_selectedOverlayId != null && selectedOverlay != null)
            _buildTextCustomizer(selectedOverlay)
          else
            _buildTimelineTrack(state),
        ],
      ),
    );
  }

  Widget _buildToolButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
