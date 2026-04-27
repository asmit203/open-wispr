# Custom Dictionary Comparison

This note compares:

- **Current local implementation** on `dev` at `7c8e62a`
- **human37 branch implementation** at `upstream/ammon/custom-dictionary` (`fe792f3`)

The goal is to isolate **dictionary-related differences** only. There are many unrelated app differences between the branches because the local branch also contains newer work such as meeting capture, audio input selection, accessibility flow changes, and the on-screen overlay.

## Executive Summary

The short version:

- The **core custom-dictionary feature is functionally very close** to human37's branch.
- The **dictionary algorithm and UI are nearly the same**.
- The **biggest behavioral difference** is integration scope:
  - human37's branch applies dictionary logic to normal dictation and reprocess flow
  - the local branch applies it there **and also to meeting capture transcription**
- The earlier local gap was **dictionary test depth**, and that gap is now closed on `dev`.

## File-by-File Comparison

### `Sources/OpenWisprLib/Config.swift`

**Dictionary-specific result:** effectively the same feature, but local branch lives inside a newer config model.

Same:

- Both add `DictionaryEntry`.
- Both add `customDictionary: [DictionaryEntry]?`.
- Both keep it optional so existing configs still decode.
- Both default `customDictionary` to `nil`.

Different:

- The local branch also contains newer unrelated fields:
  - `audioInputDeviceID`
  - `meetingTranscriptDirectory`
- Those are not dictionary differences, just branch evolution.

Conclusion:

- **No meaningful dictionary behavior difference** here.

### `Sources/OpenWisprLib/Transcriber.swift`

**Dictionary-specific result:** same dictionary feature, local branch has extra unrelated transcription hardening.

Same:

- Both add `customDictionary: [DictionaryEntry]`.
- Both build a prompt from dictionary `to` values.
- Both append `--prompt` only when the prompt is non-empty.

Different:

- The local branch also strips Whisper non-speech markers from transcription output.
- That marker-stripping logic is unrelated to dictionary behavior.

Conclusion:

- **Dictionary implementation is the same in purpose and behavior**.
- Local branch adds extra non-dictionary cleanup on top.

### `Sources/OpenWisprLib/DictionaryPostProcessor.swift`

**Dictionary-specific result:** behavior is essentially the same.

Same:

- Same prompt format: `Vocabulary: ...`.
- Same dedupe strategy for prompt values.
- Same greedy longest-match replacement logic.
- Same exact-match phrase handling.
- Same trailing punctuation preservation.

Minor code differences:

- Local branch uses `entries.map(\.to)` instead of `entries.map { $0.to }`.
- Local branch uses `index` / `phraseLength` naming instead of `i` / `phraseLen`.
- Local branch uses `guard let candidates` for the no-match path.
- Local branch names the punctuation variable `punctuation` instead of `punct`.

Conclusion:

- **This is effectively the same implementation**, only lightly refactored for readability/style.

### `Sources/OpenWisprLib/DictionaryWindowController.swift`

**Dictionary-specific result:** same UI concept, with one small local cleanup improvement.

Same:

- Same singleton window controller approach.
- Same `NSTableView` with:
  - `Whisper hears`
  - `Should be`
- Same add/remove interaction.
- Same immediate save-on-edit behavior.
- Same menu reload integration expectation.

Different:

- human37 branch deduplicates on raw `entry.from` once rows are non-empty.
- local branch trims whitespace/newlines and lowercases before dedupe and save.
- local branch also trims `to` before save.

Why this matters:

- The local branch is slightly more defensive about dirty input.
- It avoids storing whitespace-only variants or duplicate `from` values that differ only by spacing/casing.

Conclusion:

- **Same feature**, but the local branch has a **small input-normalization improvement**.

### `Sources/OpenWisprLib/AppDelegate.swift`

**Dictionary-specific result:** local branch integrates the feature more broadly because the app now has more transcription paths.

Same:

- Both set `transcriber.customDictionary` from config during setup.
- Both set it again on config reload.
- Both route normal dictation through a shared `postProcess` flow.
- Both apply dictionary replacement after spoken-punctuation processing.

Different:

- human37 branch only had dictionary integration for:
  - hotkey dictation
  - reprocess flow
- local branch additionally applies dictionary post-processing to:
  - meeting capture chunk transcription

Why this matters:

- In the local branch, the dictionary feature is available across **more transcription surfaces**.
- This is an intentional extension, not a divergence from the base dictionary design.

Conclusion:

- **Local branch is strictly broader in integration scope**.

### `Sources/OpenWisprLib/StatusBarController.swift`

**Dictionary-specific result:** dictionary menu integration is the same, but the file overall diverges because the app menu grew.

Same:

- Both add a `Custom Dictionary...` menu item.
- Both open `DictionaryWindowController.shared`.
- Both reload the dictionary window inside `reloadConfiguration()`.

Different:

- The local branch also contains many newer non-dictionary menu features:
  - audio input selection
  - meeting transcript folder
  - start/stop meeting capture
  - overlay state callback

Conclusion:

- **Dictionary-specific behavior matches**.
- The rest of the file differs because the app has evolved beyond human37's branch point.

## Test Comparison

### `Tests/OpenWisprTests/DictionaryPostProcessorTests.swift`

This was the clearest quality gap before the latest local updates.

human37 branch coverage:

- empty prompt
- single-entry prompt
- multi-entry prompt
- deduplicated prompt
- single-word replacement
- case-insensitive single-word replacement
- punctuation preservation
- period preservation
- multi-word replacement
- multi-word punctuation
- multi-word case insensitivity
- greedy longest match
- no-match passthrough
- empty dictionary passthrough
- empty string passthrough
- duplicate `from` handling
- multiple replacements in one sentence

current local branch coverage:

- empty prompt
- deduplicated prompt
- single-word replacement
- multi-word replacement
- greedy longest match
- punctuation preservation
- duplicate `from` handling
- empty input passthrough

Conclusion:

- The local branch now covers the same meaningful dictionary edge cases as human37's branch.
- There is **no remaining meaningful dictionary-specific test deficit** on `dev`.

### `Tests/OpenWisprTests/ConfigTests.swift`

Dictionary-related coverage is essentially equivalent.

Same:

- decode with custom dictionary
- decode without custom dictionary
- decode empty custom dictionary
- default custom dictionary is `nil`

Different:

- local branch also has tests for newer config fields like `meetingTranscriptDirectory`.

Conclusion:

- **No important dictionary gap** here.

## Meaningful Differences That Affect Behavior

These are the only differences that materially affect dictionary behavior:

1. **Meeting capture integration**
   - Local branch applies dictionary corrections to meeting capture output.
   - human37 branch cannot, because that feature did not exist there yet.

2. **Input normalization in dictionary save path**
   - Local branch trims and normalizes dictionary entries more aggressively before saving.
   - human37 branch is slightly looser here.

3. **Dictionary test history**
   - human37 branch originally validated more dictionary edge cases explicitly.
   - the local branch now includes those missing assertions as well.

## Where They Do Not Meaningfully Differ

These parts are basically the same:

- config shape for `DictionaryEntry` / `customDictionary`
- `--prompt` integration in `Transcriber`
- prompt vocabulary construction
- greedy phrase replacement algorithm
- table-based dictionary editing window
- menu entry for opening the dictionary window

In those areas, the local implementation is best understood as:

- **human37's dictionary implementation forward-ported into a newer app**
- with **small code cleanup / normalization changes**
- and **broader use in newer transcription paths**

## Final Assessment

If the question is:

> "Did the local branch fundamentally reimplement the dictionary feature differently?"

The answer is:

- **No, not fundamentally.**

If the question is:

> "Are there any real differences?"

The answer is:

- **Yes, but they are mostly around integration scope and test depth, not the core dictionary algorithm.**

The current local implementation is closest to:

- **the same dictionary feature as human37's branch**
- **ported onto a newer codebase**
- **extended to meeting capture**
- **with slightly more defensive save normalization**
- **but with a less exhaustive dedicated dictionary test suite**
