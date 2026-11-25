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

## Bubble motion correction after device feedback

The user reported static and non-draggable bubbles in the first build. Screenshots establish appearance only; they do not establish animation timing.

Before recording the correction, expect:

- The existing bubbles retain their artwork, size, colors, number and starting anchors. They follow bounded, smooth trajectories (at most 7 pt horizontal / 5 pt vertical), with stable variation in depth and periods of 8�11 seconds. This is floating around the existing anchors, not a full revolution around the avatar.
- The same layers keep moving while the profile stands still and while scrolling updates their base positions. The motion phase must not reset at scroll start/end or at the loop seam.
- A pan captures the bubble at touch-down, moves the whole shell/gift together, and returns with a continuous hand-over to the current floating phase. Empty space passes through to the profile. Buttons must remain usable.
- Rotation preserves layer identity and the number of displayed bubbles, adapting existing anchors to the new content width. No gift should fade out and be recreated solely because of resizing.
- Reduce Motion holds the current offset without a snap. Disabling it resumes from that phase. Leaving/re-entering the window and app suspension should also preserve phase.

Code changes replace the existing hover animation with compositor-driven transform translation and replace helper-layer hierarchy notifications with UIView window/app lifecycle handling. CALayer presentation copies now use super.init(layer:) and do not instantiate extra sticker renderers. Transparent backing contents provide the touch surface required by the documented iOS 27 behavior. Bubble hit testing precedes the buttons' container and uses the presentation geometry.

Added iOS regression target: //submodules/TelegramUI/Components/PeerInfo/PeerInfoCoverComponent:PeerInfoCoverComponentTests. It checks nonzero motion, bounded displacement, loop position/velocity continuity and depth variation. It still requires execution on the Mac; numerical tests cannot verify actual compositing or touch delivery.

Record at least 24 seconds stationary, then scroll, drag/release, rotate, toggle Reduce Motion, and background/foreground. Track the gift and rim separately on the sheets; inspect the loop boundaries and drag hand-over for jumps. Device/simulator recording and Swift compilation remain outstanding in this Windows session. Do not label the fix visually verified until frame evidence is appended.
