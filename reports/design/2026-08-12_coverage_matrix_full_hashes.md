# Control visual-diff coverage matrix — DesignPack v2 engine

Parity contract (master plan §6.3): control baseline on iPhone + iPad, light + dark.

- **Build A** = `76e1033` (pre-refactor main)
- **Build B** = `0603038aeb3f9ce855eb97c28943f07cb26e0145` (engine branch final code head)
- Devices: iPhone 17 Pro `A1C9D39C-3B4C-4B17-832D-E885A9A464BA`, iPad Pro 13-inch (M5) `460EDAE8-65D2-4285-8C26-082CD49CF4F0` (both iOS 26.4)
- App is `UIDeviceFamily = [1]` (iPhone-only) → iPad captures show iPad **compatibility mode** (scaled iPhone canvas on the iPad screen).

## Method

Untracked throwaway `Tests/UITests/Support/VisualDiffCaptureTests.swift`, the identical file compiled against both commits (untracked files survive `git checkout --detach`, so only the app under test changes). One launch per run with `LOCAL_DEMO_MODE` + `UI_TEST_PRO` and `EXPERIMENT_FORCE_DESIGN_ARM=control` (demo mode runs ExperimentStore with `defaults: nil`, so its unit id is a fresh UUID per launch and the 50/50 assignment would otherwise re-hash every run). Tabs are tapped, each waits for `selected == true` + sync-badge settle + 3 s; login is reached by demo sign-out. Capture is `XCUIScreen.main.screenshot()` written straight to the host.

Per run: `simctl ui <udid> appearance <light|dark>` and `simctl status_bar <udid> override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3`.

**Running-image verification (landmine #9)** — after every run the installed `Garage.app/Garage` hash was compared to the built product:

| build | SHA-256 of app binary |
|---|---|
| A (76e1033) | `eb9762a440f47cd30706b226713e21bb7f60efdf77bf1788c0467df137b79343` |
| B (0603038) | `20404fadbfd96cd07b2ecc09c12ac9ca045938aab23c39a1e4b29f5feb8a28f1` |

## iPhone 17 Pro — light

Canvas 1206×2622 · `shots-iphone-light-A` vs `shots-iphone-light-B`

| screen | bytes equal | AE (px) | max channel delta | bbox |
|---|---|---|---|---|
| 01-dashboard | yes | 0 | 0 | None |
| 02-log | yes | 0 | 0 | None |
| 03-garage | yes | 0 | 0 | None |
| 04-stats | yes | 0 | 0 | None |
| 05-settings | no | 189,476 | 255 | (48, 1837, 1158, 2246) |
| 06-login | yes | 0 | 0 | None |
| **total** | — | **189,476** | — | — |

## iPhone 17 Pro — dark

Canvas 1206×2622 · `shots-iphone-dark-A` vs `shots-iphone-dark-B`

| screen | bytes equal | AE (px) | max channel delta | bbox |
|---|---|---|---|---|
| 01-dashboard | yes | 0 | 0 | None |
| 02-log | yes | 0 | 0 | None |
| 03-garage | yes | 0 | 0 | None |
| 04-stats | yes | 0 | 0 | None |
| 05-settings | no | 189,454 | 255 | (48, 1837, 1158, 2246) |
| 06-login | yes | 0 | 0 | None |
| **total** | — | **189,454** | — | — |

## iPad Pro 13-inch (M5) — light

Canvas 2064×2752 · `shots-ipad-light-A` vs `shots-ipad-light-B`

| screen | bytes equal | AE (px) | max channel delta | bbox |
|---|---|---|---|---|
| 01-dashboard | no | 12 | 1 | (1300, 2442, 1310, 2468) |
| 02-log | no | 620 | 1 | (466, 761, 1600, 1565) |
| 03-garage | no | 1 | 1 | (1170, 136, 1187, 182) |
| 04-stats | yes | 0 | 0 | None |
| 05-settings | no | 222,834 | 255 | (450, 1910, 1616, 2357) |
| 06-login | yes | 0 | 0 | None |
| **total** | — | **223,467** | — | — |

## iPad Pro 13-inch (M5) — dark

Canvas 2064×2752 · `shots-ipad-dark-A` vs `shots-ipad-dark-B`

| screen | bytes equal | AE (px) | max channel delta | bbox |
|---|---|---|---|---|
| 01-dashboard | yes | 0 | 0 | None |
| 02-log | yes | 0 | 0 | None |
| 03-garage | yes | 0 | 0 | None |
| 04-stats | yes | 0 | 0 | None |
| 05-settings | no | 222,722 | 255 | (450, 1910, 1616, 2357) |
| 06-login | yes | 0 | 0 | None |
| **total** | — | **222,722** | — | — |

## Same-build noise floor (per device)

### iPhone 17 Pro — build A, dark, run 1 vs run 2

| screen | bytes equal | AE (px) | max channel delta | bbox |
|---|---|---|---|---|
| 01-dashboard | yes | 0 | 0 | None |
| 02-log | yes | 0 | 0 | None |
| 03-garage | yes | 0 | 0 | None |
| 04-stats | yes | 0 | 0 | None |
| 05-settings | yes | 0 | 0 | None |
| 06-login | yes | 0 | 0 | None |
| **total** | — | **0** | — | — |

### iPad Pro 13-inch — build A, light, run 1 vs run 2

| screen | bytes equal | AE (px) | max channel delta | bbox |
|---|---|---|---|---|
| 01-dashboard | no | 12 | 1 | (1300, 2442, 1310, 2468) |
| 02-log | yes | 0 | 0 | None |
| 03-garage | yes | 0 | 0 | None |
| 04-stats | yes | 0 | 0 | None |
| 05-settings | yes | 0 | 0 | None |
| 06-login | yes | 0 | 0 | None |
| **total** | — | **12** | — | — |

### iPad Pro 13-inch — build B, light, run 1 vs run 2

| screen | bytes equal | AE (px) | max channel delta | bbox |
|---|---|---|---|---|
| 01-dashboard | yes | 0 | 0 | None |
| 02-log | no | 620 | 1 | (466, 761, 1600, 1565) |
| 03-garage | no | 1 | 1 | (1170, 136, 1187, 182) |
| 04-stats | no | 396 | 1 | (505, 852, 956, 864) |
| 05-settings | yes | 0 | 0 | None |
| 06-login | yes | 0 | 0 | None |
| **total** | — | **1,017** | — | — |

## Verdict

| configuration | A-vs-B differing px | of which above noise | verdict |
|---|---|---|---|
| iPhone 17 Pro — light | 189,476 | 189,476 (05-settings only) | DIFFERS — 05-settings |
| iPhone 17 Pro — dark | 189,454 | 189,454 (05-settings only) | DIFFERS — 05-settings |
| iPad Pro 13-inch (M5) — light | 223,467 | 222,834 (05-settings only) | DIFFERS — 05-settings |
| iPad Pro 13-inch (M5) — dark | 222,722 | 222,722 (05-settings only) | DIFFERS — 05-settings |

**Differing region (all four configurations): `05-settings`, the final form section.**
iPhone bbox `(48, 1837)–(1158, 2246)`; iPad bbox `(450, 1910)–(1616, 2357)`. Build A renders a **“Design Feedback”** row above Sign Out; build B does not, and the rows below shift up by one row height.

Cause is NOT the theme engine. `ExperimentRegistry.bundled` flips the design-megatest epoch-1 definition from `isKilled: false` to `isKilled: true` (commit `a86808e`, "bundle records the epoch-1 kill"). `ExperimentStore.isSurveyAvailable` returns false for a killed definition, so `SettingsView`'s survey row disappears. This is the intended, operator-recorded kill of epoch 1, not a control-render regression — and it is the ONLY difference anywhere in the matrix.

Corroboration: the same iPhone-light comparison against the earlier engine head `da0b861` (which still carried `isKilled: false`) was byte-identical on all screens, which localises this delta to the registry commit rather than to any DesignPack change.

Every non-`05-settings` difference in the matrix is at or below the same-build noise floor: max channel delta 1 (±1 LSB), and each one reproduces with an identical bounding box in a same-build rerun (iPad `02-log` 620 px at `(466,761)–(1600,1565)`, `03-garage` 1 px at `(1170,136)–(1187,182)`, `01-dashboard` 12 px at `(1300,2442)–(1310,2468)`, `04-stats` 396 px at `(505,852)–(956,864)`). It is compositing jitter from iPad compatibility-mode scaling; the iPhone noise floor is exactly 0.

## SHA-256 per screenshot

### iPhone 17 Pro — light

| screen | A (`76e1033`) | B (`0603038`) |
|---|---|---|
| 01-dashboard | `1bf9cec07d5e9e92267087219b82674ea01c90f1f5ab3d2d83809b8d7f0cb1ca` | `1bf9cec07d5e9e92267087219b82674ea01c90f1f5ab3d2d83809b8d7f0cb1ca` |
| 02-log | `b1b1bec6260eaf3f0d7e031608ab9f0324bf9468cd94d0cceb38a02216a07299` | `b1b1bec6260eaf3f0d7e031608ab9f0324bf9468cd94d0cceb38a02216a07299` |
| 03-garage | `92742e33784d69bf747046fb7b4367a48fae08ae1ac1e2c49b2667dc6723b973` | `92742e33784d69bf747046fb7b4367a48fae08ae1ac1e2c49b2667dc6723b973` |
| 04-stats | `dad3a9243db3565786fa984069c2f96ef32023e2da58842e85f666346e17c7a7` | `dad3a9243db3565786fa984069c2f96ef32023e2da58842e85f666346e17c7a7` |
| 05-settings | `d3232669d0ecf587a352dd25764bbd2e43f4358cd8d4acc436d4b9610cc15701` | `b9dbbc145237a133e67595da68e765f4896fb160fe37e4b6f37fd217539fe238` |
| 06-login | `0229179743c45c26d4611af983272a05a731e9700293af8e48fdc1c31022c738` | `0229179743c45c26d4611af983272a05a731e9700293af8e48fdc1c31022c738` |

### iPhone 17 Pro — dark

| screen | A (`76e1033`) | B (`0603038`) |
|---|---|---|
| 01-dashboard | `cf60f741201311f9d50d38aab1373ec9125cfd88f08845c150ffcc3d17a6ddc6` | `cf60f741201311f9d50d38aab1373ec9125cfd88f08845c150ffcc3d17a6ddc6` |
| 02-log | `025a2f5935d1c6b9f0bb18c48abe95eccc4158c46a1c16c476578511c524d5c2` | `025a2f5935d1c6b9f0bb18c48abe95eccc4158c46a1c16c476578511c524d5c2` |
| 03-garage | `f33e3f6695aa41efbda3d1ad68358e6b2ec6027ff703fc156c60f945d158984d` | `f33e3f6695aa41efbda3d1ad68358e6b2ec6027ff703fc156c60f945d158984d` |
| 04-stats | `06627465e4f36e04f1041dc07179789d2cdcc5fae4da5a01f2c78fffed7da795` | `06627465e4f36e04f1041dc07179789d2cdcc5fae4da5a01f2c78fffed7da795` |
| 05-settings | `7612bbe0cfc57b40a0fb4013a7b8804d301a40eb59e5397faa2b162f948aa307` | `876d092d897eeae4adc022cb7be31f017e891d7b48aaa718aeea3a0b73da39f0` |
| 06-login | `48d23bd591844c466216b7778da761d042d5aaada9ee25b9db7307ca96f203d6` | `48d23bd591844c466216b7778da761d042d5aaada9ee25b9db7307ca96f203d6` |

### iPad Pro 13-inch (M5) — light

| screen | A (`76e1033`) | B (`0603038`) |
|---|---|---|
| 01-dashboard | `8e229564dfb50438cf466243ddf4e176a8a045ebbecb44a00717082c0af10ae3` | `aaa83c9d4eef78ba4e4562246ba237935f212b1d73502717eba1ceea0f3c91d1` |
| 02-log | `3494aa05dca35bae07e717fa06b9d9fdf29f9b43f27455680339c3de609599c3` | `34c879b6f806a96a9e6153bf333250cbd93cfc83c74a5988ecf2df9492a572e6` |
| 03-garage | `9b720885e5993800b96db3f98f4cef417ce19d21e3ba5058598cb85db12a2685` | `922f0dfdd0574485b597b1e2a4b4a93382607aa4986503d815b4d2eb23ab61c1` |
| 04-stats | `5a6ef4b31d22bb881d59cf45239aa7063b4f1384cb3ae91f6ada34dcb8d5f217` | `5a6ef4b31d22bb881d59cf45239aa7063b4f1384cb3ae91f6ada34dcb8d5f217` |
| 05-settings | `69dc623081df2ebc011aed5ad3c96a2866ce8bad63725828dd7a7e574bde88b8` | `b77e0d60846194fb9809e7d7ff1568100c42495f3e793d5545662dfc246fd3df` |
| 06-login | `89a993f0e5316ff337eb95548ecc5a54b5a63d9488ed07ff7115aa0797165c18` | `89a993f0e5316ff337eb95548ecc5a54b5a63d9488ed07ff7115aa0797165c18` |

### iPad Pro 13-inch (M5) — dark

| screen | A (`76e1033`) | B (`0603038`) |
|---|---|---|
| 01-dashboard | `7accedad8b176390c0d3c5a1242a0299a34fb4f3f154999d3cd651ee2055dad0` | `7accedad8b176390c0d3c5a1242a0299a34fb4f3f154999d3cd651ee2055dad0` |
| 02-log | `b468670dc04d51eeb079bd35aa3d825aea469201a7cd85d2c7d280083cd9e4ed` | `b468670dc04d51eeb079bd35aa3d825aea469201a7cd85d2c7d280083cd9e4ed` |
| 03-garage | `f409b462b5a3c75a4916f16007800825c249b6366cf069aab0da2e6e56bb59d3` | `f409b462b5a3c75a4916f16007800825c249b6366cf069aab0da2e6e56bb59d3` |
| 04-stats | `4b9ff9c13351bbdcd1b7d0750c72ffbe8eb59ea0707465232f36a9713c121da3` | `4b9ff9c13351bbdcd1b7d0750c72ffbe8eb59ea0707465232f36a9713c121da3` |
| 05-settings | `f991648799c77dc764a7b343edeae460a2ee16b6021448dfb5bf8f42e2c53526` | `311b3ae0a004f4abe49d62caa57771444316548ab75a1c8f0599015dff658a35` |
| 06-login | `78a06f4caf66a15e174553b07a1416df6a3042ebdbe801e7f4fcfee6d7fdc903` | `78a06f4caf66a15e174553b07a1416df6a3042ebdbe801e7f4fcfee6d7fdc903` |
