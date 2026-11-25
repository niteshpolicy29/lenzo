# ML Kit looks up some of its internal classes at runtime. R8 strips or
# renames them in release builds, which crashes InputImage.fromFilePath
# with a NullPointerException. Keep them intact.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face_bundled.** { *; }
-dontwarn com.google.mlkit.**

# TensorFlow Lite (used by tflite_flutter) also uses JNI/reflection.
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**
