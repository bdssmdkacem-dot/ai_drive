# ML Kit
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }

# Isar
-keep class dev.isar.** { *; }

# CameraX / camera plugin
-keep class androidx.camera.** { *; }

# Flutter TTS / speech_to_text platform channels
-keep class com.tundralabs.fluttertts.** { *; }
-keep class com.csdcorp.speech_to_text.** { *; }

# Keep annotations used by generated Isar schemas
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
