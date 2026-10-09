# Release shrinking/obfuscation is ON. Firebase, RevenueCat, Credential Manager, Play Core and kotlinx.serialization
# ship consumer rules, and the app maps Firestore data by hand (no reflection), so no blanket -keep is needed.
# Keep readable stack traces for Crashlytics.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
