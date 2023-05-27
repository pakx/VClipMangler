# changelog

## [0.3.0] - 2023-05-29

For details pls see [devlog#20230529](devlog.md#20230527)

### Added

- Add optional ini-file setting `backupFolder`; defaults to `playlistFolder`
- Add "Check for updates ..." button in Help section

### Changed

- Rearrange clip buttons Play, New, Select, Delete
- Format/truncate displayed media uri to account for long, http-style uris
- Sort playlists-dropdown to show ascending, case-insensitive
- Separately track whether clip has edits in clip-secn (i.e. it should be updated) vs whether it has edits in clips-list (i.e. playlist should be saved)
- Change ini-file location from `userdatadir` to `homedir`

### Fixed

- [current clip not showing new-indicator after saving playlist](https://github.com/pakx/VClipMangler/issues/2)
- [Extract messaging to mdl.consts for possible translation](https://github.com/pakx/VClipMangler/issues/3)

## [0.2.0] - 2023-05-21

For details pls see [devlog#202305210920](devlog.md#202305210920)

### Changed

- Updated to VLC 3.0.18

### Fixed

- [Move Select button to from the Clip section to the clips-list section](https://github.com/pakx/VClipMangler/issues/1)

## [0.1.0] - 2023-05-20

Initial commit
