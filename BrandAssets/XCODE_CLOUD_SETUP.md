# Building EEAccess on Xcode Cloud

Why: your only Mac is on **macOS 27 beta**, and Apple rejects App Store builds
produced on a beta OS (ITMS-90111) even when the SDK is correct. Xcode Cloud
builds on Apple's own **release** macOS + Xcode, so the build isn't flagged and
is delivered straight to App Store Connect.

The repo is already prepared:
- `git` initialised, first commit made.
- `.gitignore` excludes build artifacts / venvs / the generated `.xcodeproj`.
- `ci_scripts/ci_post_clone.sh` installs XcodeGen and regenerates
  `EEAccess.xcodeproj` from `project.yml` on every Xcode Cloud build (all Swift
  packages are vendored locally, so no registry access is needed).

## 1. Push the repo to GitHub (or GitLab / Bitbucket)

Create an **empty** private repo on github.com (no README/.gitignore), then:

```bash
cd /Users/brunopais/Documents/EEAccess
git branch -M main
git remote add origin https://github.com/<your-username>/EEAccess.git
git push -u origin main
```

## 2. Create the Xcode Cloud workflow

In the **release Xcode 26.5** window (the one you launched directly):

1. Menu **Integrate → Create Workflow** (or **Product → Xcode Cloud → Create Workflow**).
2. Pick the **EEAccess** app, then connect your **source repository** when prompted
   (authorize Xcode Cloud to access your GitHub account / the repo).
3. Configure the workflow:
   - **Environment → Xcode:** choose **Xcode 26** (latest *release* — NOT a beta).
     This is the whole point: it builds on Apple's supported toolchain/OS.
   - **Start Conditions:** "Branch Changes" on `main` (or "Manual" if you'd rather
     trigger by hand).
   - **Actions:** add an **Archive** action → scheme **EEAccess** → **iOS** →
     configuration **Release**.
   - **Post-Actions:** add **TestFlight Internal Testing** (and/or **App Store**)
     so the build is delivered to App Store Connect automatically.
4. Save. Xcode Cloud may prompt to grant access and to set up **managed signing** —
   accept; it creates and manages the distribution certificate/profiles for you
   (no certs to upload, no local keychain involved).

## 3. Run it

Trigger the workflow (push to `main`, or "Start Build" in the Cloud sidebar /
App Store Connect → your app → Xcode Cloud). It will:
- clone the repo → run `ci_post_clone.sh` (xcodegen generate) → resolve the
  vendored packages → archive with release Xcode 26 → upload to App Store Connect.

When it finishes, the build appears under **TestFlight** (and is submittable to
the App Store). Because it was built on Apple's release environment, **ITMS-90111
won't happen.**

## Notes / gotchas
- **Free tier:** 25 compute hours/month — far more than you'll use.
- **Bundle IDs / capabilities** are already registered (you've archived before),
  so managed signing has everything it needs.
- **Versioning still lives in `project.yml`** (currently `2.0`, build `5`). Bump
  `CURRENT_PROJECT_VERSION` there, commit, push — the next Cloud build picks it
  up. (Xcode Cloud can also auto-increment build numbers if you enable it, but
  the project.yml value is the source of truth here.)
- If the first build fails in `ci_post_clone` (e.g. Homebrew/xcodegen), tell me
  the log — the fallback is to commit the generated `.xcodeproj` instead and
  drop the script.
- Keep committing through git from now on; regenerate the project locally with
  `xcodegen generate` after editing `project.yml` (the Cloud does the same).
