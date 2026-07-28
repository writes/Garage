# Build 4 — what to test

Two testers, so this is ordered by what would hurt most if it were still broken. Please do #1
first; the rest can be opportunistic.

---

## 1. Voice quick-add — it was crashing (Pro)

This is the fix that motivated the build. Two separate crashes were found, both in the audio
setup, and both would kill the app outright rather than show an error.

**Please try, in this order:**

1. Settings → tap the mic. Speak one entry: *"changed the oil at 42,000 miles, ninety dollars at
   Firestone"*. Tap to stop.
   - Expect: a drafted entry form with type, mileage, cost and shop prefilled, for you to confirm.
   - **The last word or two used to go missing** — check the end of your sentence survived.
2. **Tap the mic, then immediately tap it again** (start/stop/start quickly, a few times). This was
   the second crash: a second recording started before the first finished tearing down.
3. **Start dictating, then trigger an interruption** — have someone call you, or start a podcast in
   another app, or unplug headphones mid-sentence.
   - Expect: it stops cleanly and says *"The microphone isn't available…"*.
   - It previously kept showing "listening" on a microphone iOS had already taken away, and
     everything said after that point was silently lost.
4. Try a sentence with a brand in it: *"new Michelins"*, *"Mobil 1"*, *"replaced the rotors"*.
   - The recogniser is now told this app's vocabulary, so these should transcribe correctly rather
     than as "Michelle in" / "mobile one" / "routers".

**If it still crashes, the crash report is the useful thing** — Xcode → Window → Devices and
Simulators → View Device Logs, or just tell me what you did immediately before.

---

## 2. Adding an entry from the Dashboard

Add an entry using the ➕ button while on the **Dashboard** tab.

- Expect: the Dashboard updates immediately — odometer, Recent activity, wear.
- It previously did not refresh at all, so a first entry appeared to vanish.

## 3. The PDF export

Settings → Export → build the PDF.

- Expect: your year/make/model and VIN at the top, services **grouped by type** with the **mileage
  and cost of each**, and a cost-of-ownership summary.
- It previously printed only a nickname, an odometer, and one bare line per service with no
  mileage. If you tick Wear summary / Warranties / Recalls, those now actually render.

## 4. Second vehicle (free account)

On a free account with one vehicle, open the vehicle switcher and tap Add.

- Expect: **"Add Vehicle (Pro)"** taking you straight to the paywall.
- It previously let you fill in the entire form and then failed with "Try Again", which could never
  work.

## 5. New things worth a look

- **Dashboard → "Needs attention"**: oil, tyre rotation, brakes, alignment, based on your logged
  history. Says *"no record in your last 50 entries"* rather than claiming you are overdue for
  something it simply has not seen.
- **Stats → Cost of ownership**: cost per mile / per month.
- **Garage → Warranty & Recalls**: there is now a **+** button. This screen could not hold a record
  at all before.
- **Brake and Tire forms**: pad/rotor percentages and tread depths. These feed the Dashboard wear
  bars, which were empty for everyone until now.
- **Reminders**: a mileage-only reminder now says plainly that it cannot send an alert. That was
  always true; the app just never admitted it.

---

## Known and deliberate

- The app is still called **Harry's Playhouse** on the App Store record. Naming is unresolved and
  the release is set to manual, so nothing publishes by accident.
- Support/privacy links point at `harrys-playhouse-prod.web.app` until a domain is chosen.
- The AI functions were deployed to production ahead of this build, so oil-analysis and voice
  parsing improved on build 3 too.
