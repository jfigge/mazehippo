import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureAudioSession()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// Tell iOS what kind of noise this app makes, before anything makes any.
  ///
  /// This has to be here rather than in Dart: flutter_soloud does not set the
  /// category, and says so in its own miniaudio backend — "AVAudioSession must
  /// already be active (the app is responsible for calling setActive:YES)
  /// before calling this". Left unset, the default category stops whatever the
  /// player already had playing and ignores the ring/silent switch, which for a
  /// puzzle game with an optional ambient bed is the wrong answer twice.
  ///
  /// `.ambient` is the answer to both. It is silenced by the hardware switch —
  /// a player who has muted their phone has muted this — and it mixes rather
  /// than interrupts, so a podcast someone was listening to keeps going and
  /// this plays underneath if they want it.
  ///
  /// Failures are ignored on purpose. Audio is not a reason a game does not
  /// start; SoLoud's own init will fail politely afterwards and `Ambience` will
  /// go quiet by itself.
  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    try? session.setActive(true)
  }
}
