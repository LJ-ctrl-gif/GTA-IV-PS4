# GTA IV Setup Manager

A separate PS4 homebrew utility for preparing Liberty Recompiled data directories.

On launch it creates, if missing:
- /data/LibertyRecomp/source/
- /data/LibertyRecomp/game/
- /data/LibertyRecomp/Diagnostics/
- /data/LibertyRecomp/env.txt (only if it does not already exist)

It checks for non-empty default.xex and default.xexp files in the prepared game directory, writes setup-status.txt, and appends scan details to Diagnostics/setup-manager.log.

It never fabricates game binaries, overwrites existing settings, deletes user files, or modifies the Liberty Recompiled application. The update/ folder is reported as an additional check; the current PS4 runtime readiness check is the default.xex + default.xexp pair.

Transfer the complete prepared game folder contents into /data/LibertyRecomp/game/ using your existing FTP workflow. Avoid a nested path such as /data/LibertyRecomp/game/game/.

Controls: Cross = scan again; Circle = exit.

## Build identity
- Home-screen title: GTA IV Setup Manager
- Title ID: GIVS00001
- Content ID: IV0000-GIVS00001_00-GTAIVSETUPMGR000
