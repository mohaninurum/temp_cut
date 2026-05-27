import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';

import 'package:uuid/uuid.dart';

import '../../domain/models/video_template.dart';
import '../../domain/models/template_slot.dart';
import '../../domain/models/overlay_item.dart';
import '../providers/editor_state_provider.dart';
import '../../services/ffmpeg_export_service.dart';
import '../widgets/editable_overlay_item.dart';

class PureTemplateEditorScreen extends ConsumerStatefulWidget {
  const PureTemplateEditorScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PureTemplateEditorScreen> createState() => _PureTemplateEditorScreenState();
}

class _PureTemplateEditorScreenState extends ConsumerState<PureTemplateEditorScreen> with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  
  // High-End Preview Synchronization
  bool _isPlaying = false;
  Duration _currentPreviewTime = Duration.zero;
  Timer? _playbackTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Video player controllers mapped by slotId
  final Map<String, VideoPlayerController> _videoControllers = {};
  
  bool _isExporting = false;
  Size _canvasSize = Size.zero;
  
  // Random waveform heights for UI mock
  late List<double> _waveformHeights;

  @override
  void initState() {
    super.initState();
    final random = Random();
    _waveformHeights = List.generate(80, (index) => random.nextDouble() * 40 + 10);
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _audioPlayer.dispose();
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // 1. Automated Multi-Slot Batch Picker
  Future<void> _batchImportMedia(VideoTemplate template) async {
    try {
      final List<XFile> mediaList = await _picker.pickMultipleMedia();
      if (mediaList.isEmpty) return;

      final List<String> slotIds = template.mediaSlots.map((s) => s.slotId).toList();
      final List<String> paths = mediaList.map((m) => m.path).toList();

      ref.read(editorStateProvider.notifier).batchFillSlots(slotIds, paths);

      // Initialize all video streams concurrently
      for (int i = 0; i < slotIds.length && i < paths.length; i++) {
        await _initializeSlotVideo(slotIds[i], paths[i]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error importing media: $e')));
      }
    }
  }

  Future<void> _pickMediaForSlot(String slotId) async {
    try {
      final XFile? media = await _picker.pickMedia();
      if (media != null) {
        ref.read(editorStateProvider.notifier).fillTemplateSlot(slotId, media.path);
        _initializeSlotVideo(slotId, media.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking media: $e')));
      }
    }
  }

  Future<void> _initializeSlotVideo(String slotId, String path) async {
    final isVideo = path.toLowerCase().endsWith('.mp4') || path.toLowerCase().endsWith('.mov');
    if (isVideo) {
      final oldController = _videoControllers[slotId];
      if (oldController != null) {
        await oldController.dispose();
      }
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      // Mute the user video so only the template audio plays
      await controller.setVolume(0.0);
      setState(() {
        _videoControllers[slotId] = controller;
      });
    }
  }

  // 5. Seamless Preview Controller Synchronization (Smooth 60FPS loop approx 16ms)
  void _togglePlayback(VideoTemplate template, String? customAudioPath) async {
    if (_isPlaying) {
      _playbackTimer?.cancel();
      await _audioPlayer.pause();
      for (var controller in _videoControllers.values) {
        controller.pause();
      }
      setState(() {
        _isPlaying = false;
      });
    } else {
      if (customAudioPath != null) {
        await _audioPlayer.play(DeviceFileSource(customAudioPath));
      } else if (template.audioUrl.isNotEmpty && template.audioUrl.startsWith('http')) {
        await _audioPlayer.play(UrlSource(template.audioUrl));
      }
      
      setState(() {
        _isPlaying = true;
      });

      _playbackTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        setState(() {
          _currentPreviewTime += const Duration(milliseconds: 16);
          if (_currentPreviewTime >= template.totalDuration) {
            _currentPreviewTime = Duration.zero; // Seamless Loop
            _togglePlayback(template, customAudioPath);
          }
        });
      });
    }
  }

  String? _getActiveSlotId(VideoTemplate template) {
    for (var slot in template.mediaSlots) {
      if (_currentPreviewTime >= slot.startTime && _currentPreviewTime < slot.endTime) {
        return slot.slotId;
      }
    }
    return null;
  }

  void _exportVideo(VideoTemplate template, Map<String, String> filledSlots, String? customAudioPath) async {
    if (filledSlots.length < template.mediaSlots.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all slots before exporting')),
      );
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final outputPath = await FFmpegExportService.exportStoryVideo(
        template: template,
        filledSlots: filledSlots,
        customAudioPath: customAudioPath,
        uiCanvasSize: _canvasSize,
      );
      
      if (mounted && outputPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported successfully to: $outputPath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  // 4. Real-Time Dynamic Caption Engine
  Widget _buildDynamicText(TemplateTextOverlay text) {
    final timeAliveMs = (_currentPreviewTime - text.appearanceStartTime).inMilliseconds;
    final totalDurationMs = (text.appearanceEndTime - text.appearanceStartTime).inMilliseconds;
    
    // Dynamic Scale Animation (Pop-in effect over the first 300ms)
    double scale = 1.0;
    if (timeAliveMs < 300) {
      // Elastic pop math
      final t = timeAliveMs / 300.0;
      scale = 0.5 + (sin(t * pi * 1.5) * 0.5 * (1 - t)) + (t * 0.5);
    }

    final words = text.value.split(' ');
    final msPerWord = totalDurationMs / (words.isNotEmpty ? words.length : 1);
    final activeWordIndex = (timeAliveMs / msPerWord).floor();

    return Transform.scale(
      scale: scale,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: List.generate(words.length, (index) {
              final isHighlighted = index == activeWordIndex;
              return TextSpan(
                text: '${words[index]} ',
                style: TextStyle(
                  color: isHighlighted ? Colors.white : text.flutterColor.withOpacity(0.8),
                  fontSize: text.fontSize,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: const Offset(0, 0),
                      blurRadius: isHighlighted ? 15.0 : 4.0,
                      color: isHighlighted ? text.flutterColor : Colors.black87,
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  void _addTextOverlay(Duration backgroundDuration) {
    String input = 'New Text';
    final state = ref.read(editorStateProvider);
    final textOverlays = state.overlays.where((o) => o.type == OverlayType.text);
    
    Duration startTime = Duration.zero;
    if (textOverlays.isNotEmpty) {
      startTime = textOverlays.map((o) => o.endTime).reduce((a, b) => a > b ? a : b);
    }

    Duration endTime = startTime + const Duration(seconds: 3);
    if (endTime > backgroundDuration) {
      endTime = backgroundDuration;
      if (startTime >= backgroundDuration) {
        startTime = backgroundDuration - const Duration(seconds: 3);
        if (startTime.isNegative) startTime = Duration.zero;
      }
    }

    ref.read(editorStateProvider.notifier).addOverlay(
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

  Future<void> _addImageOverlay(Duration backgroundDuration) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final state = ref.read(editorStateProvider);
      final imageOverlays = state.overlays.where((o) => o.type == OverlayType.image);
      
      Duration startTime = Duration.zero;
      if (imageOverlays.isNotEmpty) {
        startTime = imageOverlays.map((o) => o.endTime).reduce((a, b) => a > b ? a : b);
      }

      Duration endTime = startTime + const Duration(seconds: 3);
      if (endTime > backgroundDuration) {
        endTime = backgroundDuration;
        if (startTime >= backgroundDuration) {
          startTime = backgroundDuration - const Duration(seconds: 3);
          if (startTime.isNegative) startTime = Duration.zero;
        }
      }

      ref.read(editorStateProvider.notifier).addOverlay(
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

  Widget _buildPreviewCanvas(VideoTemplate template, Map<String, String> filledSlots) {
    final activeSlotId = _getActiveSlotId(template);
    final activeAssetPath = activeSlotId != null ? filledSlots[activeSlotId] : null;

    final activeTexts = template.textOverlays.where((t) {
      return _currentPreviewTime >= t.appearanceStartTime && _currentPreviewTime < t.appearanceEndTime;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_canvasSize != Size(constraints.maxWidth, constraints.maxHeight)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
          });
        }

        return Container(
          color: Colors.black,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // 2. Smart Auto-Crop & Aspect Ratio Fitting Layer
              if (activeAssetPath != null)
                Positioned.fill(
                  child: activeAssetPath.toLowerCase().endsWith('.mp4') || activeAssetPath.toLowerCase().endsWith('.mov')
                      ? (_videoControllers[activeSlotId] != null && _videoControllers[activeSlotId]!.value.isInitialized
                          ? Builder(builder: (context) {
                              final ctrl = _videoControllers[activeSlotId]!;
                              if (_isPlaying && !ctrl.value.isPlaying) {
                                final slot = template.mediaSlots.firstWhere((s) => s.slotId == activeSlotId);
                                final localTime = _currentPreviewTime - slot.startTime;
                                ctrl.seekTo(localTime);
                                ctrl.play();
                              } else if (!_isPlaying && ctrl.value.isPlaying) {
                                ctrl.pause();
                              }
                              // Smart Auto-Crop for Video
                              return SizedBox.expand(
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: ctrl.value.size.width,
                                    height: ctrl.value.size.height,
                                    child: VideoPlayer(ctrl),
                                  ),
                                ),
                              );
                            })
                          : const Center(child: CircularProgressIndicator()))
                      // Smart Auto-Crop for Image is natively handled by BoxFit.cover
                      : Image.file(File(activeAssetPath), fit: BoxFit.cover),
                )
              else
                Positioned.fill(
                  child: Center(
                    child: Text(
                      'Preview\n${(_currentPreviewTime.inMilliseconds / 1000).toStringAsFixed(1)}s / ${(template.totalDuration.inMilliseconds / 1000).toStringAsFixed(1)}s',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 18),
                    ),
                  ),
                ),

              // Dynamic Captions (Predefined in Template)
              for (final text in activeTexts)
                Positioned(
                  left: constraints.maxWidth * text.xPercentage,
                  top: constraints.maxHeight * text.yPercentage,
                  child: _buildDynamicText(text),
                ),

              // User Custom Overlays (Text / Image)
              for (final overlay in ref.read(editorStateProvider).overlays)
                if (_currentPreviewTime >= overlay.startTime && _currentPreviewTime < overlay.endTime)
                  EditableOverlayItemWidget(
                    key: ValueKey(overlay.id),
                    item: overlay,
                    canvasSize: _canvasSize,
                    currentPlaybackTime: _currentPreviewTime,
                    isSelected: ref.read(editorStateProvider).selectedSlotId == overlay.id,
                    onEditTap: () => ref.read(editorStateProvider.notifier).setSelectedSlot(overlay.id),
                    onUpdate: (updatedItem) => ref.read(editorStateProvider.notifier).updateOverlay(updatedItem),
                  ),
            ],
          ),
        );
      },
    );
  }

  // 3. Beat-Synced Visual Waveform Track
  Widget _buildWaveformTrack(VideoTemplate template) {
    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalMs = template.totalDuration.inMilliseconds;
          final currentMs = _currentPreviewTime.inMilliseconds;
          final progressPercent = totalMs > 0 ? currentMs / totalMs : 0.0;
          
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Waveform bars
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(_waveformHeights.length, (index) {
                  final barPercent = index / _waveformHeights.length;
                  final isPassed = barPercent <= progressPercent;
                  return Container(
                    width: 3,
                    height: _waveformHeights[index],
                    decoration: BoxDecoration(
                      color: isPassed ? Colors.blueAccent : Colors.grey[800],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
              // Transition Beat Markers (Neon Dots)
              for (final slot in template.mediaSlots)
                if (slot.endTime.inMilliseconds < totalMs)
                  Positioned(
                    left: constraints.maxWidth * (slot.endTime.inMilliseconds / totalMs) - 4,
                    top: 26,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.pinkAccent.withOpacity(0.8), blurRadius: 8, spreadRadius: 2),
                        ],
                      ),
                    ),
                  ),
              // Playback Cursor
              Positioned(
                left: constraints.maxWidth * progressPercent - 1,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Colors.white, blurRadius: 4, spreadRadius: 1),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickCustomAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result != null && result.files.single.path != null) {
        ref.read(editorStateProvider.notifier).setCustomAudio(result.files.single.path!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom audio selected!')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking audio: $e')));
      }
    }
  }

  Widget _buildToolbarActionMini(IconData icon, String label, VoidCallback onTap, {Color color = Colors.white}) {
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

  Widget _buildSlotToolbar(String slotId, VideoTemplate template) {
    return Container(
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E64CC), // CapCut blue style
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildToolbarActionMini(Icons.sync, 'Replace', () {
              _pickMediaForSlot(slotId);
            }),
            _buildToolbarActionMini(Icons.content_cut, 'Trim', () {}),
            _buildToolbarActionMini(Icons.speed, 'Speed', () {}),
            _buildToolbarActionMini(Icons.volume_up, 'Volume', () {}),
            _buildToolbarActionMini(Icons.animation, 'Animation', () {
               final state = ref.read(editorStateProvider);
               final currentTrans = state.slotTransitions[slotId] ?? 'None';
               _showTransitionBottomSheet(slotId, currentTrans);
            }),
            _buildToolbarActionMini(Icons.delete_outline, 'Delete', () {
              ref.read(editorStateProvider.notifier).removeTemplateSlot(slotId);
              ref.read(editorStateProvider.notifier).clearSelection();
            }),
          ],
        ),
      ),
    );
  }

  void _showTransitionBottomSheet(String slotId, String currentTransition) {
    if (_isPlaying) {
      _togglePlayback(ref.read(editorStateProvider).activeTemplate!, ref.read(editorStateProvider).customAudioPath);
    }

    final transitions = [
      {'name': 'None', 'icon': Icons.not_interested},
      {'name': 'Fade', 'icon': Icons.compare_arrows},
      {'name': 'Scale', 'icon': Icons.fit_screen},
      {'name': 'Spin', 'icon': Icons.rotate_right},
      {'name': 'Slide', 'icon': Icons.arrow_downward},
      {'name': 'Reveal', 'icon': Icons.ad_units},
      {'name': 'Gradient', 'icon': Icons.gradient},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          height: 200,
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            children: [
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
              const Center(
                child: Text(
                  'Select Transition',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 85,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: transitions.length,
                  itemBuilder: (context, index) {
                    final trans = transitions[index];
                    final isSelected = currentTransition == trans['name'];
                    return GestureDetector(
                      onTap: () {
                        ref.read(editorStateProvider.notifier).setSlotTransition(slotId, trans['name'] as String);
                        Navigator.pop(context);
                      },
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
                                border: isSelected ? Border.all(color: Colors.blueAccent, width: 1.5) : null,
                              ),
                              child: Icon(
                                trans['icon'] as IconData,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              trans['name'] as String,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white54,
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTemplateSlotTracker(VideoTemplate template, Map<String, String> filledSlots, Map<String, String> slotTransitions, String? customAudioPath, String? selectedSlotId) {
    return Column(
      children: [
        _buildWaveformTrack(template),
        Container(
          height: 100,
          padding: const EdgeInsets.only(bottom: 16),
          color: Colors.black,
          child: Row(
            children: [
              // Batch Import Button
              GestureDetector(
                onTap: () => _batchImportMedia(template),
                child: Container(
                  width: 80,
                  margin: const EdgeInsets.only(left: 16, right: 12),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.2),
                    border: Border.all(color: Colors.blueAccent, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome_mosaic, color: Colors.blueAccent),
                      SizedBox(height: 4),
                      Text('Batch\nImport', textAlign: TextAlign.center, style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              // Custom Audio Button
              GestureDetector(
                onTap: _pickCustomAudio,
                child: Container(
                  width: 70,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: customAudioPath != null ? Colors.pinkAccent.withOpacity(0.2) : Colors.grey[900],
                    border: Border.all(color: customAudioPath != null ? Colors.pinkAccent : Colors.white24, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.music_note, color: customAudioPath != null ? Colors.pinkAccent : Colors.white54),
                      const SizedBox(height: 4),
                      Text(customAudioPath != null ? 'Audio\nSet' : 'Select\nAudio', textAlign: TextAlign.center, style: TextStyle(color: customAudioPath != null ? Colors.pinkAccent : Colors.white, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: template.mediaSlots.length,
                  itemBuilder: (context, index) {
                    final slot = template.mediaSlots[index];
                    final isFilled = filledSlots.containsKey(slot.slotId);
                    final durationSec = (slot.endTime - slot.startTime).inMilliseconds / 1000;
                    final assetPath = filledSlots[slot.slotId];

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (isFilled) {
                              ref.read(editorStateProvider.notifier).setSelectedSlot(slot.slotId);
                            } else {
                              _pickMediaForSlot(slot.slotId);
                            }
                          },
                      child: Container(
                        width: 70,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: isFilled ? Colors.transparent : Colors.grey[900],
                          border: Border.all(
                            color: selectedSlotId == slot.slotId ? Colors.yellowAccent : (isFilled ? Colors.white70 : Colors.white24), 
                            width: selectedSlotId == slot.slotId ? 2.5 : 2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          image: isFilled && assetPath != null && (assetPath.toLowerCase().endsWith('.jpg') || assetPath.toLowerCase().endsWith('.png'))
                              ? DecorationImage(image: FileImage(File(assetPath)), fit: BoxFit.cover)
                              : null,
                        ),
                        child: Stack(
                          children: [
                            if (isFilled && assetPath != null && (assetPath.toLowerCase().endsWith('.mp4') || assetPath.toLowerCase().endsWith('.mov')))
                              const Center(child: Icon(Icons.videocam, color: Colors.white54, size: 28)),
                            if (!isFilled)
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      slot.expectedType == SlotMediaType.image ? Icons.image : Icons.videocam,
                                      color: Colors.white54,
                                      size: 20,
                                    ),
                                    const SizedBox(height: 4),
                                    Text('${durationSec.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white, fontSize: 10)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (index < template.mediaSlots.length - 1)
                      GestureDetector(
                        onTap: () {
                          final currentTrans = slotTransitions[slot.slotId] ?? 'None';
                          _showTransitionBottomSheet(slot.slotId, currentTrans);
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.black, width: 1.5),
                          ),
                          child: Center(
                            child: Icon(
                              (slotTransitions[slot.slotId] != null && slotTransitions[slot.slotId] != 'None')
                                  ? Icons.compare
                                  : Icons.add,
                              size: 16,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(editorStateProvider);
    final activeTemplate = editorState.activeTemplate;
    final customAudioPath = editorState.customAudioPath;

    if (activeTemplate == null) {
      return const Scaffold(body: Center(child: Text("No Template Selected")));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(activeTemplate.templateName, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: () => _togglePlayback(activeTemplate, customAudioPath),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => _exportVideo(activeTemplate, editorState.filledSlotAssets, customAudioPath),
            child: const Text('Export', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Main Canvas area
              Expanded(
                child: GestureDetector(
                  onTap: () => ref.read(editorStateProvider.notifier).clearSelection(),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: _buildPreviewCanvas(activeTemplate, editorState.filledSlotAssets),
                    ),
                  ),
                ),
              ),
              
              if (editorState.selectedSlotId != null)
                _buildSlotToolbar(editorState.selectedSlotId!, activeTemplate),

              // Main Add Overlay Toolbar
              Container(
                height: 48,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                      icon: const Icon(Icons.text_fields, color: Colors.white),
                      label: const Text('Add Text', style: TextStyle(color: Colors.white)),
                      onPressed: () => _addTextOverlay(activeTemplate.totalDuration),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white10),
                      icon: const Icon(Icons.image, color: Colors.white),
                      label: const Text('Add Image', style: TextStyle(color: Colors.white)),
                      onPressed: () => _addImageOverlay(activeTemplate.totalDuration),
                    ),
                  ],
                ),
              ),

              // Timeline tracker area
              _buildTemplateSlotTracker(activeTemplate, editorState.filledSlotAssets, editorState.slotTransitions, customAudioPath, editorState.selectedSlotId),
            ],
          ),
          
          if (_isExporting)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.blueAccent),
                      SizedBox(height: 24),
                      Text('Rendering Story Video...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('This may take a few moments.', style: TextStyle(color: Colors.white54, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
