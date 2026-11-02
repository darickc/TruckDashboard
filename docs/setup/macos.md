# macOS development setup (Apple Silicon)

Daily development happens on macOS: the Flutter UI, the Rust services in
simulation, and the ESP32 firmware. AGL image builds do **not**; see
[linux-build-host.md](linux-build-host.md).

## One command

```bash
make setup
```

Run [`tools/dev/setup-macos.sh`](../../tools/dev/setup-macos.sh). It is safe to
re-run. It:

1. installs, with Homebrew: `rustup`, `protobuf` (protoc), `buf`, `fvm`
2. installs the Rust toolchain pinned in [`rust-toolchain.toml`](../../rust-toolchain.toml)
   (stable, rustfmt, clippy, the `aarch64-unknown-linux-gnu` target)
3. installs the Flutter SDK pinned in [`.fvmrc`](../../.fvmrc), **3.38.3**, the
   engine version in the AGL Vimba 22.0.0 Pi 5 image
4. **checks, without installing**: Xcode, CocoaPods, PlatformIO and Docker. It
   prints how to fix anything missing.

Homebrew's `rustup` is keg-only. The Makefile finds it on its own. For an
interactive shell, add it to `~/.zshrc`:

```bash
export PATH="$(brew --prefix rustup)/bin:$HOME/.cargo/bin:$PATH"
```

Then check everything:

```bash
make doctor   # print versions
make test     # every test that exists for the components present
make lint     # link check, plus Rust/proto/Flutter linters as they appear
```

## Prerequisites the script won't install

| Tool | Needed for | Install |
|---|---|---|
| Homebrew | everything | https://brew.sh |
| Xcode (full app) | Flutter macOS desktop target (Phase 2) | App Store, then `sudo xcodebuild -runFirstLaunch` |
| CocoaPods | Flutter macOS plugins | `brew install cocoapods` |
| PlatformIO | `firmware/esp32` | `brew install platformio`, or the VS Code PlatformIO extension (installs to `~/.platformio/penv/bin/pio`) |
| Docker Desktop | `make linux-test` (Linux-only code, such as SocketCAN) | https://www.docker.com/products/docker-desktop/ |

## Flutter through fvm

Use `fvm flutter …` (or `make ui` / `make ui-test`), not a global `flutter`.
The pin keeps the app compatible with the engine on the truck.

- **VS Code:** set `"dart.flutterSdkPath": ".fvm/flutter_sdk"` in workspace
  settings.
- `.fvm/` is git-ignored.

## Recommended VS Code extensions

- rust-analyzer
- Dart and Flutter
- PlatformIO IDE
- Buf (`bufbuild.vscode-buf`)
- Even Better TOML
- YAML (Red Hat)
- markdownlint
- Markdown Preview Mermaid Support (the architecture docs use Mermaid)

## Day-to-day commands

| Command | What |
|---|---|
| `make fw-test` / `make fw-build` | ESP32 host tests / firmware build |
| `make ui-web` | Dashboard in a browser at http://127.0.0.1:8250 (release build; no Xcode needed). `SCENARIO=eot_ect_freeze START=110` jumps into a scenario |
| `make ui` | Dashboard in an 800×480 macOS window (needs Xcode; CocoaPods only once plugins are added) |
| `make ui-test` / `make sim-test` | Flutter app tests / simulator tests |
| `make proto` | Regenerate gRPC code *(Phase 3)* |
| `make sim` | Gateway with the simulated Power Stroke driving the UI *(Phase 3)* |
| `make linux-test` | Rust tests in a Linux container *(Phase 3)* |
| `make deploy PI=<host>` / `make logs PI=<host>` | Deploy to the Pi / collect logs from it *(Phase 5)* |

Targets for phases that haven't landed say so. Test and lint targets print
`skip:` and exit 0. Run targets exit 1.
