Garage App — Full Product Blueprint
Prepared for Claude Code handoff | April 2026

1. Project Summary
   A mobile-first Progressive Web App (PWA) for serious car owners to log, track, and report on everything that happens to their vehicles — from routine oil changes to track day lap times to oil analysis reports. Built to be the digital equivalent of a comprehensive paper maintenance book, but smarter.

Primary user: An enthusiast owner tracking 1–3 vehicles, ranging from daily drivers to dedicated track cars. Cares deeply about maintenance history, resale documentation, and performance data.

Initial vehicles:

2008 Dodge Viper ACR (track-focused, high-performance use)
2015 Audi SQ5 (daily driver, routine maintenance focus) 2. Tech Stack
Layer Choice Reason
Frontend React (PWA) Works on iPhone via Add to Home Screen, installable, offline-capable
Styling Tailwind CSS Fast, mobile-friendly, easy to iterate
Backend / Database Supabase Free to start, Postgres under the hood, real-time, future-ready for analytics
Authentication Supabase Auth (Sign in with Apple + Google) No passwords, one tap, cross-device
File storage Supabase Storage PDFs, images, receipts, glamour shots
PDF parsing Claude API (Anthropic) For Blackstone oil analysis autofill
PDF export pdf-lib or react-pdf Generate full history reports
CSV export Native JS Simple, no library needed
Hosting Vercel Free tier, auto-deploys from GitHub
Repo GitHub Version control, Claude Code integration
Architecture note: Design the database schema with community analytics in mind (anonymized make/model/tire/wear data stored per entry) but do not build the analytics UI in v1. Just ensure the data is there for a future query.

Architecture note: The CarFax/vehicle history API integration is a future feature. Do not build it in v1, but design the vehicle record and report builder so that a "vehicle history" data block can be injected later without restructuring the schema. Reserve a external_history JSONB column on the vehicles table for this purpose.

3. Authentication & User Profile
   Login
   Sign in with Apple
   Sign in with Google
   No email/password option (keeps it simple)
   User Profile Fields
   Name
   Address
   Phone
   Insurance Company (optional)
   Policy Number (optional)
4. Vehicle Profile
   Each user can have multiple vehicles. Each vehicle is a separate record with its own full log.

Vehicle Fields
Nickname (e.g. "The Viper", "Daily SQ5")
Make
Model
Year
License Plate
Purchase Date
Purchase Price
Current Odometer
Odometer at Purchase
Engine Oil Type (e.g. Mobil 1 0W-40)
Tire Size (front + rear if staggered)
Fuel Type (Premium 93, Premium 91, Regular, E85, Diesel)
VIN (optional)
Color (optional)
Notes / description
external_history (reserved JSONB field for future CarFax/API data)
Vehicle Switcher
Top-level UI element always visible
Tap to switch between garage vehicles
Each vehicle has its own isolated log, wear items, settings, and photo gallery 5. Vehicle Photo Gallery ("Glamour Shots")
Each vehicle has a dedicated photo gallery separate from log entry attachments. This is for beauty shots, show photos, before/afters, and anything the owner wants to preserve as part of the car's story.

Features
Upload multiple photos per vehicle
Each photo has an optional caption and date
Photos are tagged as selectable for PDF export
In the report builder, user can pick a subset of gallery photos to include on the vehicle cover page or a dedicated "Gallery" section of the PDF
Support for ordering/reordering photos
Storage: Supabase Storage, linked to vehicle record
Wheel gallery sub-section
A dedicated tab or section within the gallery for wheel/tire combo shots
Fields: wheel brand, model, size, finish, tire combo at time of photo
Ties loosely to the wheels/tires section of the parts log
Photos exportable to PDF like the main gallery 6. Odometer Check-in
Every single log entry — regardless of type — requires a current odometer reading and date. This is non-negotiable and enforced at the UI level. It is the backbone of interval tracking, wear calculations, and the export report.

7. Log Entry Types
   7a. Oil Change
   Date + odometer (required, all entries)
   Oil brand & grade
   Quantity (quarts)
   Filter brand
   Cost
   DIY or shop (if shop: shop name)
   Receipt / invoice upload (optional, stored in Supabase Storage)
   Notes
   7b. Oil Consumption Log
   Date + odometer
   Quarts added (top-off, not full change)
   Running total consumption since last change (calculated automatically)
   Receipt / invoice upload (optional)
   Notes
   7c. Oil Analysis (Blackstone or similar)
   Date + odometer
   Lab name (default: Blackstone)
   Upload PDF → Claude API reads it and autofills fields
   Manual fields (autofilled from PDF if uploaded):
   Aluminum, Chromium, Iron, Copper, Lead, Tin, Molybdenum, Nickel, Manganese, Silver, Titanium (ppm)
   Silicon, Sodium, Potassium (ppm)
   Viscosity
   Insolubles
   Miles on oil at sample
   Lab recommendation / notes
   Receipt / invoice upload (optional)
   User notes
   7d. Fuel Fill-up
   Date + odometer
   Gallons
   Price per gallon
   Total cost
   Station name (optional)
   Fuel grade
   MPG auto-calculated from previous fill-up odometer
   Receipt upload (optional)
   7e. Tire Entry (comprehensive)
   Date + odometer
   Action type: New Install / Rotation / Tread Depth Reading / Removed
   Tire brand + model
   Tire size (front/rear)
   Position (FL, FR, RL, RR or all four)
   Tread depth reading per corner (32nds of an inch)
   Heat cycles (for track tires — increment each track day)
   Cost (if purchase)
   Compound / treadwear rating
   Receipt / invoice upload (optional)
   Notes
   7f. Brake Service
   Date + odometer
   Action: Pads replaced / Rotors replaced / Fluid flush / Inspection
   Position (front / rear / all)
   Pad brand + compound
   Rotor brand (if replaced)
   Pad thickness remaining at install (mm)
   Cost
   DIY or shop
   Receipt / invoice upload (optional)
   Notes
   7g. Wheel Alignment
   Date + odometer
   Shop name
   Cost
   Alignment specs (before + after, per corner):
   Camber
   Toe
   Caster (front)
   Alignment sheet upload (photo or PDF)
   Receipt / invoice upload (optional)
   Notes
   7h. Standard Maintenance Items
   Each with: date, odometer, cost, DIY/shop, receipt upload, notes, resolved/unresolved status, symptom description, resolution description.

Items:

Air filter (engine)
Cabin air filter
Fuel system service
Rotate / balance tires
Spark plugs
Transmission service
Differential service (front / rear / both)
Wiper blades
Battery replaced
Radiator / cooling system
Belts and hoses
Brake fluid flush
Coolant flush
Other (free text label)
7i. General Service / Repair
Date + odometer
Title / description
Symptom description (optional)
Resolution description (optional)
Resolved toggle (yes / no / in progress)
Cost
Shop or DIY
Receipt / invoice / record of service upload (photos or PDF)
Additional attachments (photos of damage, parts, etc.)
Notes
7j. Track Day
Date + odometer
Venue / track name
Event type (HPDE / Time Trial / Lapping / Race)
Run group
Number of laps
Best lap time (mm:ss.xxx)
Conditions (dry / wet / mixed)
Tire set used (links to a tire entry)
Fuel used (gallons, optional)
Car observations / notes (free text, rich — this is the session journal)
Driver notes
Heat cycles added (auto-increments linked tire set's heat cycle count)
Receipt / entry fee upload (optional)
7k. Upgrade / Modification Log
Date + odometer
Part / upgrade name
Category (suspension / engine / aero / interior / wheels / other)
Brand
Part number (optional)
Cost
Installed by (DIY / shop)
Description / notes
Receipt / invoice upload (optional)
Before/after photos (upload)
7l. DME / ECU Report Upload (Porsche / BMW / etc.)
Date + odometer
File upload (PDF or image)
Report type (Over-revs, Fault codes, other)
Notes
Parsed data display if structured (future — v1 just stores the file) 8. Detailing Log
A dedicated section for documenting the aesthetic condition and cosmetic care of the vehicle. Separate from mechanical maintenance.

Paint & Exterior
Last paint correction date
Paint correction type (light polish / full correction / multi-stage)
Shop or DIY
Products used
Cost
Notes
Before/after photos (upload)
Paint Protection Film (PPF)
Install date
Coverage area (full front / partial / full wrap / custom)
Brand / product (e.g. XPEL Ultimate Plus)
Shop name
Cost
Warranty expiration
Condition notes
Photos (upload)
Ceramic / Paint Coating
Coating product name
Install date
Installer (DIY / shop name)
Number of layers
Warranty expiration
Maintenance wash schedule notes
Cost
Photos (upload)
Cosmetic Improvements Log
A running log of any aesthetic changes — wraps, tint, badges, interior work, etc.

Date
Description of work
Shop or DIY
Cost
Receipt upload (optional)
Photos (upload)
Detailing export
All detailing records are included as an optional section in the PDF report builder.

9. Spare Parts Inventory
   A place to log parts the owner has on hand that are tied to a specific vehicle but not yet installed.

Fields per part
Part name
Category (engine / suspension / brakes / body / interior / wheels / other)
Brand
Part number
Quantity
Where purchased
Purchase date
Cost
Storage location (optional free text — "garage shelf B", "shipping box in trunk")
Condition (new / used / refurbished)
Notes
Photo (optional)
Receipt upload (optional)
Behavior
Parts inventory is per-vehicle
When a part is installed (via an upgrade or maintenance entry), user can mark it as "consumed" and it links to that log entry
Exportable as a section in the PDF report ("Parts on hand at time of sale") 10. Warranty & Recall Tracker
Factory Warranty
Warranty start date (typically purchase/in-service date)
Basic / bumper-to-bumper term (e.g. 3 years / 36,000 miles)
Powertrain term (e.g. 5 years / 60,000 miles)
Corrosion / rust-through term (if applicable)
Roadside assistance term (if applicable)
Expiration date (calculated automatically from start date + term, or entered manually)
Notes
Extended Warranty (if applicable)
Provider name (dealer, third-party, CPO)
Plan name / tier
Coverage start date
Coverage end date
Mileage limit
Deductible amount
Contract / policy number
Provider phone number
What is covered (free text or checklist — powertrain / electrical / tech / etc.)
What is excluded (free text)
Document upload (warranty contract PDF)
Notes
Recall Log
Each recall is a separate record tied to the vehicle.

Fields per recall:

NHTSA Campaign Number (or manufacturer recall number)
Recall title / description
Component affected (e.g. "Fuel pump", "Airbag inflator")
Date recall announced
Status: Outstanding / Completed / Not applicable to this VIN
If completed:
Date performed
Dealership / shop name
Odometer at time of service
Receipt / work order upload (optional)
Notes
Future feature (do not block architecturally):

Auto-lookup of open recalls by VIN using NHTSA public API (free, no key required)
Display outstanding recalls as a dashboard alert
Reserve a recall_source field (manual / nhtsa_api) on each recall record
Warranty display on dashboard
If any warranty is active: show a small status badge on the vehicle card ("Under warranty until MM/YYYY")
If any recall is outstanding: show a red alert badge ("1 open recall")
Warranty in export
Factory and extended warranty details included as an optional section in the PDF report builder
Recall log included as its own optional section, with completed recalls showing work order details 11. Wear Items Dashboard
A dedicated section showing the current health of consumable items at a glance.

Items tracked:
Front brake pads (% life remaining, mm thickness)
Rear brake pads (% life remaining, mm thickness)
Front rotors
Rear rotors
Clutch (% life estimate)
Front tires (tread depth, heat cycles)
Rear tires (tread depth, heat cycles)
Display:
Color-coded bar per item (green > 60%, amber 30–60%, red < 30%)
Tap to see full history for that item
Updated automatically when a relevant log entry is made 12. Service Reminders
User can set custom intervals per vehicle (e.g. oil change every 5,000 mi or 6 months)
App calculates next due date/mileage based on last logged service
Dashboard surfaces upcoming items (e.g. "Oil change due in 800 mi")
Reminder types: mileage-based, time-based, or both
Future v2: OEM interval lookup by make/model/year 13. Screens & Navigation
Bottom tab bar (5 tabs):
Dashboard — hero odometer card, wear items, upcoming reminders, open recalls alert, recent log feed
Log — full chronological history, filterable by entry type, searchable
Garage — photo gallery, wheel gallery, spare parts inventory, detailing log
Stats — MPG trend, cost breakdown by category, wear item history charts
Settings — vehicle profiles, user profile, reminder config, data export
Additional flows:
Add entry — floating + button, always visible, opens entry type selector then form
Vehicle switcher — top bar, tap to switch or add new vehicle
Report builder — accessed from Settings > Export 14. Export & Report Builder
PDF Report
User selects which sections to include (checkboxes):
Vehicle info & specs
Photo gallery (user selects which glamour shots)
Maintenance history
Oil changes & analysis
Track day log
Tire history
Brake history
Alignment records
Upgrade / modification log
Detailing history
Spare parts on hand
Wear item summary
Cost summary
Receipts & invoices (optional attachment section)
Warranty information (factory + extended)
Recall history (completed + outstanding)
CarFax / vehicle history (future — placeholder in builder)
User selects date range
Output: clean, formatted PDF with:
Vehicle cover page (user-selected photo, specs, purchase info)
Sections per selected entry type
Wear item summary
Cost summary
Upgrade history
Designed to hand to a buyer or mechanic
CSV Export
Raw data export of all entries for selected vehicle
One row per entry, columns per field
Full fidelity — every field included 15. Data Architecture (Supabase / Postgres)
Tables (top level):
users — auth + profile fields
vehicles — one per car, linked to user; includes external_history JSONB column reserved for CarFax/API data
entries — all log entries (type field determines shape)
entry_details — JSONB column for type-specific fields (flexible, future-proof)
wear_snapshots — point-in-time wear readings linked to entries
attachments — file references (PDFs, photos, receipts) stored in Supabase Storage; tagged by type (receipt / photo / report / glamour)
reminders — interval rules per vehicle per service type
tire_sets — trackable tire sets with heat cycle count, linked to entries
detailing_records — paint, PPF, coating, cosmetic log per vehicle
parts_inventory — spare parts per vehicle, with consumed/installed status
vehicle_gallery — glamour shots per vehicle, with caption, date, export-selected flag, display order
warranties — factory and extended warranty records per vehicle
recalls — recall records per vehicle; includes recall_source field (manual / nhtsa_api) for future NHTSA API integration
Community analytics readiness:
vehicles table includes make, model, year, weight class (optional)
wear_snapshots and tire_sets include anonymized aggregate fields
No PII in analytics-eligible rows
Opt-out flag on user record (default: opted in, anonymized only)
CarFax / external history readiness:
external_history JSONB column on vehicles table reserved for future API payload
Report builder includes a placeholder CarFax section that renders "not connected" in v1 — REMOVED 2026-08-05 per U4: the stub shipped on by default and printed "Vehicle History: Not connected" inside the paid dossier; the reservation below still stands, the placeholder section does not
No schema migration needed when the integration is eventually built 16. Claude API Integration (Blackstone PDF Autofill)
When user uploads a Blackstone (or similar) oil analysis PDF:

File is sent to Claude API with prompt: "Extract all oil analysis fields from this report and return structured JSON"
Claude returns parsed JSON
App pre-fills the oil analysis form fields
User reviews, corrects if needed, and saves
Original PDF is stored in Supabase Storage attached to the entry
This is the only AI feature in v1. It saves significant manual data entry for a task users will repeat every oil change interval.

17. Build Phases
    Phase 1 — Foundation (build first, get this working end-to-end)
    Supabase project setup + schema
    Auth (Sign in with Apple + Google)
    Vehicle profile creation (2 vehicles)
    Odometer check-in enforcement
    Oil change log entry
    Dashboard shell with vehicle switcher
    Phase 2 — Core logging
    All remaining entry types (fuel, tires, brakes, track day, maintenance items)
    Receipt / attachment upload on all entry types
    Wear items dashboard
    Log tab with filter + search
    Phase 3 — Smart features
    MPG auto-calculation
    Service reminders (mileage + time based)
    Oil consumption running total
    Heat cycle auto-increment on track day entry
    Phase 4 — Garage tab + Warranty
    Vehicle photo gallery (glamour shots) with PDF export selection
    Wheel gallery sub-section
    Spare parts inventory
    Detailing log (paint correction, PPF, coatings, cosmetic improvements)
    Warranty tracker (factory + extended)
    Recall log (manual entry; NHTSA auto-lookup in Phase 6)
    Phase 5 — Reports & export
    PDF report builder with section selection and photo inclusion
    CSV export
    Receipt/invoice attachment section in PDF output
    Phase 6 — AI + advanced
    Blackstone PDF autofill via Claude API
    Alignment spec entry + history chart
    DME report upload + storage
    Stats tab charts (cost breakdown, MPG trend, wear history)
    CarFax API integration (future — schema already ready)
    NHTSA recall auto-lookup by VIN (free public API — schema already ready)
18. Monetization Strategy
    Model: Freemium + Annual Subscription
    Free tier (forever):

1 vehicle
All core log entry types
Basic wear item tracking
No export
Pro tier (~$4.99/month or $39.99/year):

Unlimited vehicles
PDF and CSV export / report builder
Photo gallery + glamour shot PDF inclusion
Blackstone PDF autofill (Claude API)
Service reminders
Spare parts inventory
Detailing log
Receipt/invoice storage
Full stats and charts
Future revenue layers:

Contextual parts reorder links (affiliate — Tire Rack, Amazon, etc.)
Anonymized community analytics access (tire life benchmarks, clutch life by model, etc.) — paid tier or separate product
CarFax integration as a premium add-on
Pricing rationale
Enthusiast car owners spend hundreds to thousands on parts and maintenance without hesitation. $5/month or $40/year for an app that documents the full ownership history of a car they care about is an easy sell — especially when the PDF export alone saves hours of work when selling the vehicle.

19. Persona Prompt for Claude Code
    Paste this at the start of every Claude Code session:

You are a principal-level full-stack engineer and product thinker with 15 years of experience building consumer mobile apps. You specialize in React PWAs, Supabase backends, and data-rich iOS-targeted web applications. You think like a product manager and an engineer simultaneously — you anticipate edge cases before they're mentioned, you write clean and well-commented code, and you always consider the non-technical end user's experience. You are building a car maintenance and track day logging app for an enthusiast owner. The user is not technical, so every architectural decision should minimize future complexity and maximize reliability. Prefer simple, proven patterns over clever ones. When in doubt, ask one clarifying question rather than assuming.

20. Recommended Workflow for Claude Code Sessions
    Open Claude Code in terminal (or VS Code with Claude extension)
    Paste the persona prompt above
    Say: "We are building in phases. Today we are working on Phase [X]. Here is the full blueprint for context: [paste this document]. Focus only on Phase [X] items. Use extended thinking. Use Opus for architecture decisions and Sonnet for implementation. Turn on Autopilot."
    Walk away. Review output when done.
    Come back to Claude Chat to refine or plan the next phase.
