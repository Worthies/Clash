import 'dart:collection';
import 'package:flutter/material.dart';

/// Real-time bandwidth chart showing upload/download trends over 30 seconds
class BandwidthChart extends StatefulWidget {
  final int uploadBytes;
  final int downloadBytes;

  const BandwidthChart({
    super.key,
    required this.uploadBytes,
    required this.downloadBytes,
  });

  @override
  State<BandwidthChart> createState() => _BandwidthChartState();
}

class _BandwidthChartState extends State<BandwidthChart> {
  // Store bandwidth samples (bytes/sec) for last 30 seconds
  final Queue<double> _uploadSamples = Queue();
  final Queue<double> _downloadSamples = Queue();

  int _lastUploadBytes = 0;
  int _lastDownloadBytes = 0;
  DateTime _lastUpdate = DateTime.now();

  static const int maxSamples = 60; // 30 seconds at 2 samples/sec

  @override
  void initState() {
    super.initState();
    _lastUploadBytes = widget.uploadBytes;
    _lastDownloadBytes = widget.downloadBytes;
    // Seed samples with zeros to avoid an initial spike in the UI
    for (int i = 0; i < 4; i++) {
      _uploadSamples.add(0.0);
      _downloadSamples.add(0.0);
    }
    _lastUpdate = DateTime.now();
  }

  @override
  void didUpdateWidget(BandwidthChart oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Always update bandwidth sampling when widget updates (even if values didn't change)
    _updateBandwidth();
    // Ensure repaint after updating internal samples
    if (mounted) setState(() {});
  }

  void _updateBandwidth() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastUpdate).inMilliseconds / 1000.0;

    // Avoid updates if time delta is too small (which can create huge spikes)
    if (elapsed <= 0 || elapsed < 0.05) {
      _lastUpdate = now;
      return;
    }

    // Calculate bandwidth in bytes/sec and clamp negatives to zero
    final rawUpload = (widget.uploadBytes - _lastUploadBytes) / elapsed;
    final rawDownload = (widget.downloadBytes - _lastDownloadBytes) / elapsed;
    final uploadBandwidth = rawUpload.isFinite && rawUpload > 0
        ? rawUpload
        : 0.0;
    final downloadBandwidth = rawDownload.isFinite && rawDownload > 0
        ? rawDownload
        : 0.0;

    // If no difference in bytes, push zero to keep chart moving and show 0 B/s
    final uploadToPush = (widget.uploadBytes - _lastUploadBytes) == 0
        ? 0.0
        : uploadBandwidth;
    final downloadToPush = (widget.downloadBytes - _lastDownloadBytes) == 0
        ? 0.0
        : downloadBandwidth;

    _uploadSamples.add(uploadToPush);
    _downloadSamples.add(downloadToPush);

    // Keep only last maxSamples
    while (_uploadSamples.length > maxSamples) {
      _uploadSamples.removeFirst();
    }
    while (_downloadSamples.length > maxSamples) {
      _downloadSamples.removeFirst();
    }

    _lastUploadBytes = widget.uploadBytes;
    _lastDownloadBytes = widget.downloadBytes;
    _lastUpdate = now;
    // Ensure widget repaints to reflect new sample
    if (mounted) setState(() {});
  }

  String _formatBandwidth(double bytesPerSec) {
    final v = (bytesPerSec.isFinite ? bytesPerSec.abs() : 0.0);
    if (v < 1024) {
      return '${v.toStringAsFixed(0)} B/s';
    } else if (v < 1024 * 1024) {
      return '${(v / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(v / 1024 / 1024).toStringAsFixed(2)} MB/s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploadCurrent = _uploadSamples.isNotEmpty ? _uploadSamples.last : 0.0;
    final downloadCurrent = _downloadSamples.isNotEmpty
        ? _downloadSamples.last
        : 0.0;

    // Center legend and chart horizontally and vertically
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Legend with current bandwidth
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 2, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(
                      '↑ ${_formatBandwidth(uploadCurrent)}',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 2, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text(
                      '↓ ${_formatBandwidth(downloadCurrent)}',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Chart with fixed height so it centers nicely inside parent
          SizedBox(
            height: 54,
            width: double.infinity,
            child: CustomPaint(
              painter: _BandwidthChartPainter(
                uploadSamples: _uploadSamples.toList(),
                downloadSamples: _downloadSamples.toList(),
                isDark: Theme.of(context).brightness == Brightness.dark,
              ),
              child: Container(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandwidthChartPainter extends CustomPainter {
  final List<double> uploadSamples;
  final List<double> downloadSamples;
  final bool isDark;

  _BandwidthChartPainter({
    required this.uploadSamples,
    required this.downloadSamples,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (uploadSamples.isEmpty && downloadSamples.isEmpty) {
      return;
    }

    final paint = Paint()
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Find max bandwidth for scaling
    double maxBandwidth = 1024.0; // Min 1 KB/s
    for (final sample in uploadSamples) {
      if (sample > maxBandwidth) maxBandwidth = sample;
    }
    for (final sample in downloadSamples) {
      if (sample > maxBandwidth) maxBandwidth = sample;
    }

    // Add 10% padding to max
    maxBandwidth *= 1.1;

    const maxSamples = 60;
    final xStep = size.width / (maxSamples - 1);
    final yScale = size.height / maxBandwidth;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)
      ..strokeWidth = 0.5;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw upload line (green)
    if (uploadSamples.isNotEmpty) {
      paint.color = Colors.green;
      final path = Path();

      for (int i = 0; i < uploadSamples.length; i++) {
        final x = (maxSamples - uploadSamples.length + i) * xStep;
        final y = size.height - (uploadSamples[i] * yScale);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(path, paint);
    }

    // Draw download line (blue)
    if (downloadSamples.isNotEmpty) {
      paint.color = Colors.blue;
      final path = Path();

      for (int i = 0; i < downloadSamples.length; i++) {
        final x = (maxSamples - downloadSamples.length + i) * xStep;
        final y = size.height - (downloadSamples[i] * yScale);

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_BandwidthChartPainter oldDelegate) {
    return uploadSamples != oldDelegate.uploadSamples ||
        downloadSamples != oldDelegate.downloadSamples;
  }
}
