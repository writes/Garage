# Security Policy

## Supported platform

Garage is a native iOS app (SwiftUI, Swift 6, iOS 17+) backed by Firebase (Auth, Firestore,
Storage, Functions, App Check) and RevenueCat. This repository is a public portfolio snapshot (2026-10-07) of a project whose active development
is paused; the `main` branch is the supported surface for security reports.

## Reporting a vulnerability

Please report suspected vulnerabilities privately — do not open a public GitHub issue.

Email **jonathonhthompson@gmail.com** with a description of the issue, steps to reproduce, and
any relevant logs or proof-of-concept. We'll acknowledge your report and follow up as the issue
is investigated.

There is no bug bounty program at this time.

## Secrets

Secrets (Firebase config, API keys, signing overrides, Cloud Functions environment files) are
never committed to this repository — they are gitignored (`Configuration/Secrets.swift`,
`Garage/Resources/GoogleService-Info.plist`, `Configuration/Local.xcconfig`,
`CloudFunctions/.env*`) and are provisioned locally or via Secret Manager at deploy time. If you
believe a secret has been committed, please report it the same way as a vulnerability above.

## Public snapshot

Before this copy was published, the full history (all branches) was scanned with gitleaks and a
custom per-blob scan. No credentials were found; one internal billing identifier in `HANDOFF.md`
history was redacted (see the README's *Public snapshot notes*).
