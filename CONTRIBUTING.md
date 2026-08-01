# Contributing to Dictus

Thank you for your interest in contributing to Dictus! Whether you are fixing a bug, adding a feature, or improving documentation, your help is welcome. First-time contributors are encouraged.

## How to Contribute

1. **Fork** the repository.
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** following the conventions below.
4. **Test** your changes on a real device (the keyboard extension requires a physical iPhone).
5. **Open a Pull Request** against `main`.

## Code Conventions

Dictus is built with **Swift 5.9+** and **SwiftUI**.

- **Naming**: `camelCase` for variables and functions, `PascalCase` for types and structs.
- **One file = one responsibility** -- keep files focused.
- **No force unwraps** (`!`) unless justified with a comment explaining why.
- **Code comments** in English.
- **UI strings**: French (primary language) + English.

## Project Structure

| Target | Role |
|---|---|
| **DictusApp** | Main app -- onboarding, settings, model manager |
| **DictusKeyboard** | Keyboard extension -- custom keyboard + dictation trigger |
| **DictusCore** | Shared framework -- App Group storage, models, preferences |

### Important Constraints

- **DictusKeyboard** has a ~50 MB memory limit. Only tiny, base, and small models run in the extension.
- **No `UIApplication.shared`** in the keyboard extension -- iOS does not allow it.
- All shared data goes through the **App Group** (`group.solutions.pivi.dictus`).

## Running Tests

```bash
cd DictusCore
swift test
```

## Continuous Integration

Every pull request runs through GitHub Actions. Two checks must pass before a PR can be merged:

- **SwiftLint** -- enforces style rules defined in `.swiftlint.yml`. Runs on Linux, completes in under a minute.
- **Build** -- compiles the `DictusApp` scheme (which embeds `DictusKeyboard`, `DictusWidgets`, and depends on `DictusCore`) for iOS Simulator. Runs on macOS, takes 5-10 minutes.

To check locally before pushing:

```bash
brew install swiftlint
swiftlint lint --strict
```

`--strict` is what CI runs, and it passes on a clean checkout with no exemption
file. If you need a force unwrap, keep it and write a
`// swiftlint:disable:next force_unwrapping` directive above it with a comment
saying why the value cannot be nil — that is the project convention, not a
workaround.

The CI does **not** sign builds, run tests, or upload to TestFlight. Its only job is to catch broken compilations and obvious style regressions.

## Pull Request Guidelines

- Use a **descriptive title** (e.g., "Fix waveform animation on cold start").
- **Explain what and why** in the PR description, not just what changed.
- Keep PRs **focused** -- one feature or fix per PR.
- Make sure the project builds without warnings before submitting.
- Verify CI is green before requesting review.

## No CLA Required

You do not need to sign a Contributor License Agreement. By submitting a PR, you agree that your contribution is licensed under the same MIT license as the project.

## Code of Conduct

Be respectful and constructive. We are all here to build something useful together.
