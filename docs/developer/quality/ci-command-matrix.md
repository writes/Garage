# CI and Verification Commands

Run these after full Xcode is installed.

## Local Generation

1. `xcodegen generate`
2. `xcodebuild -version`
3. `xcodebuild -list -project Garage.xcodeproj`
4. `./scripts/ci/policy-checks.sh`
5. `./scripts/ci/security-checks.sh`
6. `./scripts/ci/verify-ios.sh`

The CI script prefers repo-local tools in `.tools/bin` and auto-selects the first available iOS simulator when one exists.

## Unit and UI Tests

1. `xcodebuild test -project Garage.xcodeproj -scheme Garage -destination 'platform=iOS Simulator,name=iPhone 16'`
2. `xcodebuild test -project Garage.xcodeproj -scheme GarageUnitTests -destination 'platform=iOS Simulator,name=iPhone 16'`
3. `xcodebuild test -project Garage.xcodeproj -scheme GarageUITests -destination 'platform=iOS Simulator,name=iPhone 16'`

## Archive Checks

1. `xcodebuild archive -project Garage.xcodeproj -scheme Garage -configuration Release -destination 'generic/platform=iOS' -archivePath build/Garage.xcarchive`
2. Confirm zero warnings in the archive log
3. Confirm dSYMs and Crashlytics upload steps are present

## Security Checks

1. Confirm App Check is configured and enforced in Firebase
2. Confirm Firestore rules deploy cleanly
3. Confirm Storage rules deploy cleanly
4. Confirm no secret-bearing files are tracked by git
5. Confirm privacy disclosures match the shipping SDK set
