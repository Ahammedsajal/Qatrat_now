import UIKit
import Flutter
import FirebaseCore
import GoogleSignIn          // keep; needed for silent-sign-in, etc.
import flutter_downloader

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Initialize Firebase
    FirebaseApp.configure()

    // Register Flutter plugins
    GeneratedPluginRegistrant.register(with: self)

    // Register FlutterDownloader background isolate
    FlutterDownloaderPlugin.setPluginRegistrantCallback(registerPlugins)

    // Call super so Flutter can finish its own setup
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// MARK: - Plugin registration for background isolate
private func registerPlugins(registry: FlutterPluginRegistry) {
  GeneratedPluginRegistrant.register(with: registry)
}