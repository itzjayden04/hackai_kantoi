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

# The JNI method signatures above also name Kotlin runtime classes
# (e.g. setBool(..., Lkotlin/coroutines/Continuation;)). If R8 renames those,
# the signature no longer matches and the lookup fails, so keep their names.
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.CoroutineContext { *; }
-keep class kotlin.coroutines.intrinsics.** { *; }
-keep class kotlin.enums.EnumEntries { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
