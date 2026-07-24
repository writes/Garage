// onObjectFinalized (firebase-functions/v2/storage) resolves its default bucket name eagerly at
// CloudFunction-declaration time via FIREBASE_CONFIG (see
// node_modules/firebase-functions/lib/common/config.js firebaseConfig()), which is only
// auto-populated inside a deployed/emulated Cloud Functions environment — plain `vitest run`
// throws "Missing bucket name" the moment such a module is imported without it. Import this file
// FIRST, before importing anything from a module that declares an onObjectFinalized trigger
// (ESM imports evaluate top-to-bottom, so this must be the first import line in that test file).
// The value is a placeholder used only to unblock import-time declaration; it has no bearing on
// production, which always runs with the real per-project FIREBASE_CONFIG injected by Cloud
// Functions/Firebase Tools at deploy/runtime.
if (!process.env.FIREBASE_CONFIG) {
  process.env.FIREBASE_CONFIG = JSON.stringify({ storageBucket: "test-project.appspot.com" });
}
