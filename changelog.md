# changelog

## [0.4.0] - 2023-06-

For details pls see [devlog#202306==](devlog.md#202306==)

### Added

- Implement [Add sort-by-media](https://github.com/pakx/VClipMangler/issues/5)

### Changed

- When sorted byGroup, clips no longer show clip-group in-line (each clip shows title + duration only)
- Rearrange widgets for sort/filter to reflect they're now interrelated (when sorted byMedia, filter examines clip-title and -uri)
- Change Filter to compare case-insensitive

### Fixed

- [Group dropdown inconsistently populated](https://github.com/pakx/VClipMangler/issues/4)
- ["Check for updates" button remains visible even after Help is closed](https://github.com/pakx/VClipMangler/issues/6)

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

<!-- markdownlint-configure-file {"MD024": false} -->
