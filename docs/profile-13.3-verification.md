# Custom profile refresh (13.3)

This is a local profile redesign, not a merge of the official Telegram 13.3 release.

## Intended visual behavior, before recording

- Pinned collectible gifts (excluding the status gift, up to six that fit) appear in translucent rounded bubbles. The existing navigation, title, reserved side strips and avatar are exclusion regions.
- Each bubble drifts around a small ellipse (14 by 10 points) near the avatar, completing a cycle in 7–9 seconds. This is local orbital motion, not a full revolution behind the avatar.
- Touching a bubble opens its gift. Dragging takes precedence over the ancestor scroll gesture, follows the finger and returns to its resting position over about 0.65 seconds. Expect a small spring overshoot; no teleport at pickup, clipped rim or gift moving separately from its shell.
- A collectible status supplies the full screen backdrop, including the space between gift cards. Removing the status restores the ordinary background. Ordinary profiles and Settings retain their backgrounds.
- Playing the profile's displayed track dims only the backdrop. The dim amount follows actual player amplitude (12–28% black), with a 0.12-second attack and 0.38-second release. Pausing, buffering, switching to another track/account or closing the screen clears the effect. This does not isolate bass frequencies.
- Reduce Motion disables orbital/wiggle/glow motion and replaces reactive dimming with constant dimming during playback. Drag return is a short ease-out.

## Required simulator verification — outstanding

No Xcode, Swift compiler, `xcrun`, or XcodeBuildMCP is available in the Windows workspace used for this change. No iOS build or runtime/visual verification has been performed.

Build on the Mac using the root CLAUDE.md command. Use only an authorized dedicated simulator, preserving the account data as documented there. Record with `simctl io recordVideo`, then use `tools/animation_sheet.py` and its ffprobe timestamps; do not substitute fixed-rate recordings.

Record opening/closing the profile, at least one complete orbital cycle, tap, drag/release/cancel, scrolling and avatar expansion/collapse. Repeat for light/dark mode, Reduce Motion, a narrow phone and reserved-side-strip layout, profiles with zero/one/multiple pinned gifts, with/without collectible status, and live removal of the status/pinned gift. Verify that navigation controls and profile scrolling remain usable.

For music, record play/pause/resume, buffering, track switching, silence and a percussive track. Check the normal background returns on pause and another account's playback never drives the profile. Also check gift detail presentation and return, backgrounding the app, and profile expansion transitions.

Track both shell and gift on a drag/release crop. Inspect every flagged gap/jump and all sheets for clipping, overlap, text contrast and background seams. Append frame numbers, timestamps and observed overshoot before marking visual verification complete.

## Checks completed in Windows

- `python build-system/Make/PostboxImportCheck.py`: passed.
- `git diff --check`: passed.
- Inspected the music event path from MediaPlayerAudioRenderer through SharedMediaPlayer and MediaManager; music previously returned a never-emitting signal.
- These checks do not establish Swift compilation or visual correctness.
