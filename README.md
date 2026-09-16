# 🤖 Android Reusable CI/CD Workflows (Jetpack Compose)

A production-ready reusable **GitHub Actions CI/CD pipeline for Android applications**, supporting automated testing, JaCoCo coverage enforcement, APK/AAB builds, secure signing, Google Play deployment, Esper deployment, and GitHub release management.

---

## ✨ Features

### CI — complete quality gate, built entirely from free tooling

| Concern | Tool | Gate |
|---|---|---|
| **Security (SAST)** | Android Lint security checks, Semgrep OSS (`p/kotlin`, `p/java`, `p/secrets` + Android rules) | fails on ERROR |
| **Secret scanning** | gitleaks (binary — no org licence needed) | fails on any leak |
| **Dependency CVEs** | CycloneDX SBOM → Trivy | report-only by default |
| **Dead code** | Detekt `Unused*` rules, Android Lint `UnusedResources`, `buildHealth`, Qodana JVM Community | report-only by default |
| **Static typing** | `kotlinc` with `-Xjsr305=strict`, optional warnings-as-errors | fails on type error |
| **Lint** | Detekt with a shared config — always runs, never skip-if-absent | fails on any issue |
| **Formatting** | Spotless + ktlint, with optional ratchet for legacy repos | fails on diff |
| **Tests** | JUnit unit tests | fails on any failure |
| **Coverage** | JaCoCo, **line and branch** thresholds, per-file PR comment | fails below threshold |

Every tool is injected through a **Gradle init script** from this repo, so a caller
repository adopts the whole pipeline **without changing a single build file**.

### Platform

- Gradle build caching, per-job cache scoping
- Non-destructive Gradle wrapper bootstrap (the caller's declared version always wins)
- Parallel CI jobs with an aggregated GitHub job summary
- APK & AAB build
- Secure keystore signing
- Google Play Store deployment
- Esper device deployment
- GitHub Release creation
- Automatic semantic version conflict resolution
- Optional **“What’s New”** release notes from file

---

# 📦 Repository Structure

```
.github/
├── workflows/
│   ├── push.yml                  # Reusable Android CI workflow
│   └── release.yml               # Reusable Android CD workflow
├── actions/setup-android/        # Shared setup: pipeline checkout, JDK, cache, wrapper
└── tool/
    ├── detekt.yml                # Shared Detekt config (lint + unused-code rules)
    ├── .editorconfig             # Shared ktlint formatting contract
    ├── gitleaks.toml             # Secret-scanning rules + Android allowlists
    ├── qodana.yaml               # Cross-module dead-code inspection profile
    ├── semgrep/android-rules.yml # Android/Kotlin SAST rules
    ├── sonar-project.properties  # Optional SonarQube Community template
    └── scripts/                  # Report summarisers wired into the job summary

gradle/
├── jacoco.init.gradle            # Coverage injection
├── detekt.init.gradle            # Lint injection
├── spotless.init.gradle          # Formatting injection
├── android-lint.init.gradle      # Lint severity/report policy
├── dependency-analysis.init.gradle  # Unused-dependency injection
├── cyclonedx.init.gradle         # SBOM injection
└── kotlin-strict.init.gradle     # Compiler strictness
```

`.github/infra/` (Dockerfile + Terraform) is **not wired into either workflow**. It's example
scaffolding only — a reference build image and a reference secrets-provisioning template —
kept for teams that want a starting point, not something the CI/CD pipeline itself runs.



---

# 🧠 Architecture Overview

Caller App Repository triggers reusable workflows.

### Reusable CI Workflow (`push.yml`)

Five independent jobs run in parallel, then build and summary:

```
                    ┌─ Lint & Format ──── Spotless/ktlint + Detekt
                    │
                    ├─ Android Lint ───── security checks + unused resources
  Checkout          │
  + setup-android ──┼─ Security ───────── gitleaks + Semgrep + SBOM/Trivy
  (every job)       │
                    ├─ Dead Code ──────── buildHealth (+ optional Qodana)
                    │
                    └─ Tests & Coverage ─ JUnit + JaCoCo line/branch gates
                                                    ↓
                                          Build APK + AAB
                                                    ↓
                                          CI Summary (job summary + artifacts)
```

Only **Build** depends on **Tests** — everything else fans out, so a formatting
failure and a coverage failure surface in the same run rather than one at a time.

### Reusable CD Workflow (`release.yml`)

```
Create GitHub Release
        ↓
Download unsigned build artifacts (from the caller's own CI job -- see below)
        ↓
Sign APK/AAB
        ↓
Deploy to Play Store (optional)
        ↓
Deploy to Esper (optional)
        ↓
Upload signed artifacts to GitHub Release
```

This workflow does **not** run its own CI pass. It consumes the artifact the
caller's own CI job already built earlier in the same workflow run — see
"Consolidated CI+CD build" below for why, and what the caller needs to do.

---

## Consolidated CI+CD build

Earlier versions of this pipeline had `release.yml` re-run the entire CI
workflow itself (tests + build) before creating the release, on top of
whatever CI pass the caller's own `push.yml` already ran to gate the push.
For a release-tag push that meant the same source tree got compiled and
tested twice back-to-back — once against the Debug variant (the caller's own
CI job), once against Release (this workflow's nested one) — for no benefit,
since the quality gates (lint, formatting, security, dead-code) don't depend
on build variant and were already skipped on the second pass.

`release.yml` no longer runs a nested CI job. Instead, the **caller** picks
the build variant dynamically, once, based on the trigger:

```yaml
# caller's push.yml
ci:
  uses: your-org/android-reusable/.github/workflows/push.yml@main
  with:
    build_variant: ${{ (contains(github.ref_name, 'release') && 'Release') || 'Debug' }}
    coverage_threshold: ${{ (contains(github.ref_name, 'release') && '40.00') || '30.00' }}
    # ...

cd:
  uses: your-org/android-reusable/.github/workflows/release.yml@main
  if: contains(github.ref_name, 'release')   # same condition as above
  needs: [ci]
  with:
    build_variant: "Release"   # always matches what `ci` just built for this trigger
    # ...
```

A plain push/PR still gets a fast Debug build + full quality suite. A
release-tag push builds **Release** directly — once — and `cd` just signs
and ships the artifact that same `ci` job already produced (reusable-workflow
calls share one workflow run, so the artifact `ci` uploads is already visible
to `cd`'s jobs via plain `actions/download-artifact`). No second compile,
no second test run.

---

# 🧪 Reusable CI Workflow (`push.yml`)

## Inputs

### Required

| Input | Description |
|------|-------------|
| `java_version` | Java version for Gradle |
| `build_variant` | Android build variant (Debug / Release / StagingDebug) |
| `coverage_threshold` | Minimum LINE coverage percentage required |

### Stage toggles

| Input | Default | Description |
|------|---------|-------------|
| `runner` | `ubuntu-latest` | Runner label |
| `run_tests` | `true` | Unit tests |
| `run_coverage` | `true` | JaCoCo report + threshold gate |
| `run_static_analysis` | `true` | Detekt |
| `run_formatting` | `true` | Spotless + ktlint |
| `run_android_lint` | `true` | Android Lint (security + unused resources) |
| `run_security` | `true` | gitleaks + Semgrep |
| `run_dependency_audit` | `true` | SBOM + Trivy + dependency submission |
| `run_dead_code` | `true` | Unused-dependency analysis |
| `run_deep_dead_code` | `false` | Qodana cross-module unused declarations (slow) |

### Tuning

| Input | Default | Description |
|------|---------|-------------|
| `app_module` | `"app"` | Gradle module that produces the APK/AAB and JaCoCo report |
| `coverage_branch_threshold` | `"0"` | Minimum BRANCH coverage %. `0` disables the branch gate |
| `formatting_ratchet_from` | `""` | Git ref — only check files changed since it |
| `lint_check_all_warnings` | `false` | Enable lint checks that are off by default |
| `kotlin_jsr305_strict` | `true` | Enforce Java `@Nullable`/`@NonNull` at compile time |
| `kotlin_warnings_as_errors` | `false` | Promote Kotlin warnings to errors |

### Gates

Each gate turns its stage from *blocking* into *report-only*. Defaults are chosen
so a repo adopting the pipeline is not blocked on day one by pre-existing debt.

| Input | Default | Blocks the build? |
|------|---------|-------------------|
| `fail_on_lint` | `true` | Detekt findings |
| `fail_on_formatting` | `true` | Formatting differences |
| `fail_on_android_lint` | `true` | Lint errors + fatal security checks |
| `fail_on_security` | `true` | Semgrep ERRORs and leaked secrets |
| `fail_on_vulnerabilities` | `false` | HIGH/CRITICAL dependency CVEs |
| `fail_on_dead_code` | `false` | Unused code and unused dependencies |

### Secrets

| Secret | Required | Description |
|------|----------|-------------|
| `PIPELINE_TOKEN` | No | Only when **this** pipeline repo is private and the caller lives in a different repo. The default `GITHUB_TOKEN` is scoped to the caller and will 403 when checking out the init scripts. |

---

## Outputs

| Output | Description |
|------|-------------|
| `coverage_percent` | Computed JaCoCo LINE coverage percent |
| `branch_coverage_percent` | Computed JaCoCo BRANCH coverage percent |

---

## Adoption path

The pipeline is deliberately loud but not immediately blocking on the noisy
checks. A sensible rollout:

1. **Run it as-is.** Lint, formatting, tests and coverage gate from day one;
   CVEs and dead code report only.
2. **Triage the dead-code report.** Add suppressions for DI graphs, serializers
   and Compose previews, then set `fail_on_dead_code: true`.
3. **Triage the CVE report.** Upgrade or accept each HIGH/CRITICAL, then set
   `fail_on_vulnerabilities: true`.
4. **Clear the Kotlin warning backlog**, then set
   `kotlin_warnings_as_errors: true`.
5. **Add a branch-coverage floor** with `coverage_branch_threshold`.

For a legacy codebase, `formatting_ratchet_from: origin/main` limits the
formatting gate to changed files so the first PR is not a whole-repo reformat.

To fix formatting locally:

```bash
./gradlew -I .pipeline/gradle/spotless.init.gradle spotlessApply
```

---

## Dead code on Android modules

Every other check in this pipeline is truly zero-touch: nothing in the caller
repo needs to change. Dependency-analysis (DAGP, the "unused dependency" half
of `run_dead_code`) is the one exception, and only for repos where **any**
module applies `com.android.application`, `com.android.library`, or
`com.android.dynamic-feature`.

**Why:** DAGP is injected via a Gradle init script so callers don't have to
touch their build files. For Android modules, DAGP needs to read AGP's own
`AndroidComponentsExtension` API at runtime -- and an init script's plugin
classpath is isolated from the classloader that resolves AGP for the
caller's own `plugins {}` block. There's no reliable injection-only fix for
that (it's a hard Gradle classloading boundary, not a config issue) -- see
the comments in
[`gradle/dependency-analysis.init.gradle`](gradle/dependency-analysis.init.gradle)
for the full mechanics. The init script detects Android modules automatically
and skips them with a log line rather than crashing.

**This is whole-build, not per-module.** DAGP coordinates root and every
analyzed subproject through one root-registered build service; every copy
involved must come from the same classloader. That means a repo **cannot**
mix "root + some subprojects injected via this init script" with "one
Android module declares DAGP directly" -- doing so throws a
`ClassCastException` the first time the two copies try to coordinate, and
DAGP separately refuses outright to apply to any subproject if the root
project doesn't have a matching application of its own. So once *any* module
in a repo needs to declare DAGP directly, the **root project and every
module you want covered** (Android or not) must all declare it directly, and
the init script backs off from that repo's `dependencyAnalysis` entirely
(also with a log line, not a crash).

**The fix, for a repo with at least one Android module:** declare DAGP for
real on the root project, and on every module you want covered -- pinned to
the same version this pipeline injects (`DAGP_VERSION` in `push.yml`,
currently `1.33.0`):

```kotlin
// root build.gradle.kts -- applied for real, NOT `apply false`. DAGP
// requires a matching root application before any subproject can apply it.
plugins {
    id("com.autonomousapps.dependency-analysis") version "1.33.0"
}
```

```kotlin
// Every module you want covered, Android or not (app/build.gradle.kts,
// hl7Core/build.gradle.kts, ...) -- no version needed, inherits root's.
plugins {
    id("com.autonomousapps.dependency-analysis")
}
```

A module left out of this (root declares it, but the module itself doesn't)
simply won't appear in the dead-code report -- no crash, just missing
coverage; the init script's log line calls this out per module.

No further wiring needed beyond that -- thresholds, severity
(`DAGP_SEVERITY`) and the `fail_on_dead_code` gate are still driven entirely
by this pipeline's `push.yml` inputs, same as every other check. When
bumping `DAGP_VERSION` in the pipeline, bump the caller's pinned version to
match.

---

# 📊 Coverage Gate

The CI pipeline automatically:

1. Generates a **JaCoCo XML report** (injected — the caller needs no JaCoCo setup)
2. Extracts **LINE** and **BRANCH** coverage from the report-level counters
3. Compares both against their configured thresholds
4. On pull requests, comments per-file coverage on the changed lines

Example:

```
Line coverage:   78.43% (threshold 75%)
Branch coverage: 64.10% (threshold 60%)

Result: PASSED
```

If either figure is below its threshold, the pipeline **fails automatically**.
The branch gate is off until `coverage_branch_threshold` is set above `0`.

---

# 🚀 Reusable CD Workflow (`release.yml`)

Handles (consumes the caller's own CI job's artifact -- see "Consolidated
CI+CD build" above; does not build anything itself):

- GitHub Release creation
- APK/AAB signing
- Google Play Store deployment
- Esper deployment
- Artifact upload to GitHub Release
- Optional release notes support

---

## Inputs

| Input | Description |
|------|-------------|
| `version` | Base semantic version |
| `java_version` | Java version |
| `build_variant` | Android build variant |
| `coverage_threshold` | Coverage requirement |
| `deploy_to_playstore` | Enable Play Store deployment |
| `playstore_track` | Play Store track (internal/beta/production) |
| `playstore_status` | Release status |
| `package_name` | Android package name |
| `deploy_to_esper` | Enable Esper deployment |
| `esper_org_id` | Esper organization ID |
| `esper_app_id` | Esper application ID |
| `enable_whats_new` | Enable release notes |
| `whats_new_file` | File containing release notes |
| `android_build_tools_version` | Build-tools version used when signing (default `"34.0.0"`) |

---

# 📝 “What’s New” (Release Notes from File)

Create a file inside your app repository:

```
release_notes.txt
```

Example content:

```
- Added onboarding screen
- Improved login performance
- Fixed crash on Android 14
```

Enable it in the caller workflow:

```yaml
enable_whats_new: true
whats_new_file: release_notes.txt
```

The same release notes are used for:

- **Google Play Store release notes**
- **GitHub Release notes**

---

# 📲 Android Support

- Gradle builds
- Detekt static analysis
- Unit tests
- JaCoCo coverage reporting
- APK build
- AAB build
- Keystore signing
- Google Play Store deployment
- Esper device management deployment
- Artifact uploads
- GitHub Release integration

---

# 🔐 Required Secrets

## Android Signing

- `ANDROID_KEYSTORE`
- `KEYSTORE_PASSWORD`
- `KEY_PASSWORD`
- `KEY_ALIAS`

---

## Google Play Store

- `PLAYSTORE_SERVICE_ACCOUNT`

---

## Esper Deployment

- `ESPER_API_KEY`

---

## Pipeline checkout (optional)

- `PIPELINE_TOKEN` — forwarded to the nested CI run; same as the CI workflow's own
  `PIPELINE_TOKEN` (only needed when this pipeline repo is private and the caller
  lives elsewhere).

---

# 🧩 Example Caller Workflow Usage

`call-android-release` needs `call-android-ci` to have already built the same
`build_variant` it downloads (`Release` here) -- see "Consolidated CI+CD
build" above for the full dynamic-variant pattern; this snippet fixes it to
Release for brevity.

```yaml
call-android-ci:
  uses: your-org/android-reusable/.github/workflows/push.yml@main
  with:
    java_version: 17
    build_variant: Release
    coverage_threshold: "75.00"
    # ...

call-android-release:
  uses: your-org/android-reusable/.github/workflows/release.yml@main
  needs: call-android-ci

  with:
    version: 1.2.0
    java_version: 17
    build_variant: Release
    coverage_threshold: "75.00"

    deploy_to_playstore: true
    playstore_track: internal
    playstore_status: completed
    package_name: com.example.app

    deploy_to_esper: false

    enable_whats_new: true
    whats_new_file: release_notes.txt

  secrets:
    ANDROID_KEYSTORE: ${{ secrets.ANDROID_KEYSTORE }}
    KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
    KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
    KEY_ALIAS: ${{ secrets.KEY_ALIAS }}

    PLAYSTORE_SERVICE_ACCOUNT: ${{ secrets.PLAYSTORE_SERVICE_ACCOUNT }}

    ESPER_API_KEY: ${{ secrets.ESPER_API_KEY }}
```

---

# 📁 Example App Repository Layout

```
your-android-app
├── app
├── gradle
├── gradlew
├── release_notes.txt
└── .github/workflows
    └── main.yml
```

---

# 🏗️ Design Principles

- Fully reusable workflows
- Secure secret handling
- Modular CI/CD architecture
- CI and CD separation
- Store-ready deployments
- Coverage-enforced testing
- Optional deployments
- No secrets stored in repository

---

# 🧭 Roadmap

Planned improvements:

- Firebase App Distribution
- Slack notifications
- PR preview builds
- Play Store staged rollout
- Multi-language release notes
- Android Lint reporting
- Code coverage badges

---

# 🤝 Contributing

Pull requests are welcome for:

- Bug fixes
- CI performance improvements
- New integrations
- Documentation improvements

---

# 📜 License

MIT License

---

# ⭐ Why use this?

Because it is:

- Fully automated
- Secure
- Reusable across Android projects
- Coverage-aware
- Play Store ready
- Enterprise-ready
- GitHub Release integrated

---

# 👨‍💻 Author

**Rite Technologies - DevOps Competency**

---

# 🎯 One-command releases

Trigger the release workflow and automatically:

- Run tests
- Validate coverage
- Build APK/AAB
- Sign artifacts
- Deploy to Play Store
- Deploy to Esper
- Create GitHub Release

Ship Android apps faster 🚀
