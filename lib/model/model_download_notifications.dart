 import 'package:background_downloader/background_downloader.dart';

class ModelDownloadNotifications {
  ModelDownloadNotifications._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    final downloader = FileDownloader();
    await downloader.trackTasks();
    downloader.configureNotification(
      running: const TaskNotification(
        'Downloading Offline AI Model',
        '{filename} • {progress} ({networkSpeed})',
      ),
      complete: const TaskNotification(
        'AI Model Ready',
        '{filename} is cached for 100% offline use.',
      ),
      error: const TaskNotification(
        'Model Download Failed',
        'Could not download {filename}.',
      ),
      paused: const TaskNotification(
        'Download Paused',
        'Tap to resume downloading {filename}',
      ),
      progressBar: true,
    );
    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    final permissions = FileDownloader().permissions;
    var status = await permissions.status(PermissionType.notifications);
    if (status != PermissionStatus.granted) {
      status = await permissions.request(PermissionType.notifications);
    }
    return status == PermissionStatus.granted;
  }
}
