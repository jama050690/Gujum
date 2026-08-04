-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.socket.** { *; }
-keep class com.google.android.gms.auth.api.signin.** { *; }
-dontwarn com.google.android.gms.**
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-dontwarn javax.annotation.**

# R8 is on for release, so anything reached only by reflection needs keeping.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
