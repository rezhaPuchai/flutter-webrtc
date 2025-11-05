import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
          _ application: UIApplication,
          didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
      ) -> Bool {
          // Ensure the window is properly initialized
//          if self.window == nil {
//              self.window = UIWindow(frame: UIScreen.main.bounds)
//          }
//          
//          let controller = FlutterViewController(
//              project: nil,
//              nibName: nil,
//              bundle: nil
//          )
//          
//          self.window?.rootViewController = controller
//          self.window?.makeKeyAndVisible()
//          
          GeneratedPluginRegistrant.register(with: self)
          return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
