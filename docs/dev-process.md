# Local Dev Process

This file is the source of truth for reinstalling and resetting a local `open-wispr` development setup.

Use this when you want to stay on your local branch only and avoid Homebrew-installed releases.

## Clean uninstall

Run the uninstall script from the repo root:

```bash
bash scripts/uninstall.sh
```

That removes the local app bundle, config, cached models, logs, and any Homebrew-managed install if one exists.

## Reinstall from local source

From the repo root:

```bash
bash scripts/dev.sh
```

That script:

1. Reads your current config from `~/.config/open-wispr/config.json`.
2. Prompts you for the desired model, language, punctuation, recordings, toggle mode, and hotkey.
3. Saves the config back to disk.
4. Stops any running local `open-wispr` process.
5. Removes any Homebrew `open-wispr` install so the local build wins.
6. Installs `whisper-cpp` if needed.
7. Builds the app in release mode.
8. Bundles the binary into `OpenWispr.app`.
9. Copies the app to `~/Applications/OpenWispr.app`.
10. Launches the local app.

## Manual reinstall sequence

If you want the steps separately instead of the one-shot helper:

```bash
bash scripts/uninstall.sh
brew install whisper-cpp
swift build -c release
bash scripts/bundle-app.sh .build/release/open-wispr OpenWispr.app dev
rm -rf ~/Applications/OpenWispr.app
cp -R OpenWispr.app ~/Applications/OpenWispr.app
open ~/Applications/OpenWispr.app
```

## Notes

- Use the local app bundle in `~/Applications/OpenWispr.app` for permission prompts and testing.
- Do not reinstall from the Homebrew tap unless you explicitly want the packaged release.
- If the menu bar app does not refresh after reinstall, quit it fully and relaunch `~/Applications/OpenWispr.app`.
