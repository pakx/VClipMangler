# devlog

## 20230527

- fixed [current clip not showing new-indicator after saving playlist](https://github.com/pakx/VClipMangler/issues/2); addressed by adding btnPlaylistSaveClick/showClip()
- fixed [Extract messaging to mdl.consts for possible translation](https://github.com/pakx/VClipMangler/issues/3); mdl.consts now has pseudo groups DEF\_ (default), ERR\_ (errors), MSG\_ (messages), etc
- moved FileWatcher settings (see 202305210920 below) from User to Workspace
- switched to VSCode Lua extension [lua-language-server](https://marketplace.visualstudio.com/items?itemName=sumneko.lua); better outline view, linting, selectable lua version
- various linting edits due lua-language-server extension
- removed app.{function properties} such as createModel(); they were to serve as a record of recognized properties, but only got in the way; better would be to use metamethods to "protect" `app` from haphazard property assignments
- added app.setContext(ctx) (rather than assigning directly to app.context); edited tests
- clip-secn: rearranged New and Play buttons, edited affected artifacts
- clips-secn: rearranged Select/Delete buttons, w/ Select at left (to be near list items) and Delete at far right (out of the way); uglifes ui, but bodes better navigation
- changed casing of references to VLC, the application, to "VLC"; helps identify code references, which are `vlc`
- readAppIni() was looking for "^playlist%d*$"; changed to "^playlist$"
- sample vlc dirs on windows:
  > lua debug: datadir C:\ProgramFiles\vlc-3.0.18  
  > lua debug: userdatadir C:\Users\pakx\AppData\Roaming\vlc  
  > lua debug: homedir C:\Users\pakx\Documents  
  > lua debug: configdir C:\Users\pakx\AppData\Roaming\vlc  
  > lua debug: cachedir C:\Users\pakx\AppData\Roaming\vlc  
- changed ini-file location from `userdatadir` to `homedir`, as ini less likely to be deleted from there; added logic to check both places; @see acts.initializeApp(); edited help
- rearranged app.utils functions into alphabetical order
- edited tests/_utils.lua to contain only those functions not already in VclipMangler.lua/app.utils (or not accessible at time-of-call)
- added to test/_utils.lua functions that are Windows-specific; generalize or use a library if later warranted
- fixed app.utils.createRollingBackup() to handle filenames containing Lua regex magic chars
- added test for createRollingBackup() wrt mdl.appCfg.backupCount
- now also accept http/s media uri
- account for long media uri, such as from youtube, by displaying a truncated version; see formatMediaUri()
- edited showPlaylists() to sort case-insensitive
- added optional ini-file setting `backupFolder`; defaults to `playlistFolder`; this is the folder into which playlist backups will be placed (just so playlistFolder looks less cluttered); added tests; while it would be better to default backupFolder to playlistFolder/bak, Lua has no native facilities for folder-management to create that "bak" folder, and vlc's own vlc.io.mkdir seems ureliable; e.g.
  > lua warning: Error while running script C:\ProgramFiles\vlc-3.0.18\lua\extensions\VclipMangler.lua, function (null)(): ...gramFiles\vlc-3.0.18\lua\extensions\VclipMangler.lua:1135: VLC lua error in file /builds/videolan/vlc/extras/package/win32/../../../modules/lua/libs/io.c line 247 (function vlclua_mkdir)
- added boolean `clip.hasEditsInVw` to track if curtrent clip in view has edits; this flag is cleared when clip is saved to list (even if not yet to file) via the "Update" button; this helps show the clip-secn as saved, while clips in the clips-secn show edits; `clip.hasEdits` keeps its old behavior -- it persists until the playlist is saved
- added app.utils.checkForUpdates(); uses github api to fetch `/releases` and parses content; (fyi tags: <https://api.github.com/repos/pakx/VClipMangler/tags>, releases: <https://api.github.com/repos/pakx/VclipMangler/releases>); simply checking the version of the VclipMangler.lua source file, or even checking tags, would be easier; unfortunately, checking releases is the "right" thing to do, as both the forgoing may have non-release versions
- edited incorrect casing in project-name references from "VclipMangler" to "VClipMangler"; that works for browsing to the repo, but using the releases api, etc needs the correction
- added changelog.md
- clerical edits to comments, help
- updated to version 0.3.0

## 202305210920

- added devlog.md
- updated to VLC 3.0.18
- installed <https://marketplace.visualstudio.com/items?itemName=appulate.filewatcher>, to copy VclipMangler.lua from repo to extensions folder on save
- edited test/app.lua to use VclipManager.ini from repo folder
- fixed [Move Select button to from the Clip section to the clips-list section](https://github.com/pakx/VClipMangler/issues/1); moved Select button, updated svg used in Help
- minor edits to readme, help
- items in assets/screenshot-app.png from <https://www.ign.com/lists/100-best-movie-moments/>
- updated to version 0.2.0
