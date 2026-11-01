# ML Kit text recognition: Kantoi ships only the Latin and Chinese models.
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# shared_preferences_android 2.5 and path_provider_android 2.3 call their
# Kotlin code from Dart through JNI. R8 can't see those calls, so without these
# rules it strips the methods and every call fails in release builds
# (NoSuchMethodError "no non-static method Lio/flutter/plugins/sharedpreferences/...").
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
