import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ScreenshotGalleryDialog extends StatefulWidget {
  final int initialIndex;
  final List<String> imageUrls;

  const ScreenshotGalleryDialog({
    super.key,
    required this.initialIndex,
    required this.imageUrls,
  });

  @override
  State<ScreenshotGalleryDialog> createState() => _ScreenshotGalleryDialogState();
}

class _ScreenshotGalleryDialogState extends State<ScreenshotGalleryDialog> {
  late PageController _pageController;
  late int _currentIndex;
  final List<TransformationController> _transformationControllers = [];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    for (int i = 0; i < widget.imageUrls.length; i++) {
      _transformationControllers.add(TransformationController());
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _transformationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleDoubleTap(int index) {
    final controller = _transformationControllers[index];
    if (controller.value != Matrix4.identity()) {
      controller.value = Matrix4.identity();
    } else {
      // Zoom in to 2x at the center
      controller.value = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Background tap to close
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.black),
            ),
            
            // Main PageView with Desktop support
            ScrollConfiguration(
              behavior: const _DesktopScrollBehavior(),
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.imageUrls.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                  // Reset zoom on previous page if needed
                  for (int i = 0; i < _transformationControllers.length; i++) {
                    if (i != index && _transformationControllers[i].value != Matrix4.identity()) {
                      _transformationControllers[i].value = Matrix4.identity();
                    }
                  }
                },
                itemBuilder: (context, index) {
                  return Center(
                    child: GestureDetector(
                      onDoubleTap: () => _handleDoubleTap(index),
                      child: InteractiveViewer(
                        transformationController: _transformationControllers[index],
                        minScale: 1.0,
                        maxScale: 4.0,
                        child: CachedNetworkImage(
                          imageUrl: widget.imageUrls[index],
                          fit: BoxFit.contain,
                          placeholder: (context, url) => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          errorWidget: (context, url, error) => const Icon(
                            Icons.image_not_supported,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            // Indicator (1/N)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.imageUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
            
            // Close button
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: CircleAvatar(
                backgroundColor: Colors.black45,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close gallery',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}
