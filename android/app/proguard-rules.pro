# Keep WebRTC classes from being removed/obfuscated
-keep class org.webrtc.** { *; }
-dontwarn org.chromium.**