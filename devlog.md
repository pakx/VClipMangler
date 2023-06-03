# devlog

## 20230603

- fixed [Sometimes on clicking "Add" both newly-added and added-just-previously clips are set to same title, etc](https://github.com/pakx/VClipMangler/issues/7), as follows:
  - the underlying reason for this was due the current clip, i.e. mdl.clip, being added directly to the clips-list
  - thus after a first Add, mdl.clip pointed to the newly-added clip in the clips-list
  - further edits to the current clip affected mdl.clip (aka the clip in clips-list)
  - the next Add, depending on forgoing edits, resulted in the second-added clip and the first-added clip above both showing similar edits
  - the "sometimes" in the issue depended on whether view-edits invoked acts.updateClip() before the Add button were clicked: if it did, such as when using the time-adjust buttons, it resulted in mdl.clip being modified (and reflected in the clip in the clips-list); if acts.updateClip() were not called before the Add button (e.g. times were typed into the textbox) the issue didn't show
  - addressed as follows: acts.updateClip(): on saveToList, after successful save set mdl.clip to a copy of what was saved; note that on Select we were already setting mdl-clip to a copy of the selected clip rather than to the clip itself
- updated TestsB04_newClip(); prior version, which shouldn't have passed, didn't have `asNew=true` in the call following "update clip w/ all fields; should succeed"
- showPlaylist(): edited sorting to be case-insensitive (sort everything lowercase)
- app.utils.dump(): simplified
- clips-list: moved per-clip glyphs to beginning of line so they're seen more easily
- updated to v0.4.2

## 202306021405

- fixed Sort/Filter -> Go being skipped sometimes; this was because btnSortFilterClick() called showPlaylist() only on rgx ~= ""; corrected
- updated to v0.4.1

## 20230602

- fixed [Group dropdown inconsistently populated](https://github.com/pakx/VClipMangler/issues/4); this was due h.groups being reset every time in showPlaylist(), but being rebuilt only if sorting were "byGroup"; addressed as follows: identified that h.groups need be rebuilt only when  opening a playlist or creating a new one; added param isNew in showPlaylist(isNew), w/ h.groups reset/rebuilt only if isNew == true; still in showPlaylist(), used a new var, `grouping` to track group-type clips-list displays
- implemented [Add sort-by-media](https://github.com/pakx/VClipMangler/issues/5); addressed as follows: added new clips-sort option "byMedia"; edited showPlaylist() to handle sorting byMedia; when sorted byMedia, filtering also searches in clip.uri; this sorting affecting filtering is addressed below
- fixed ["Check for updates" button remains visible even after Help is closed](https://github.com/pakx/VClipMangler/issues/6); addressed in app.createView()/overlayHelp()
- writePlaylistM3u(): edited to set duration to (clip.stopTime - clip.startTime); adjusted tests
- edited formatMediaUri() to return first part .. ellipses .. last part
- showPlaylist(): refactored so sorting is table-driven, defaulting to sort byTitle
- when sorted byGroup clips no longer show group in-line (each clip now shows title + duration only)
- when sorted byMedia, Filter examines clip.title and clip.uri; rearranged sort/filter widgets to indicate they're now interrelated
- acts.setFilter(): edited to match case-insensitive; as Lua 5.1 doesn't have a case-insensitive match directive, approx-d by comparing everything lowercased
- widened clip-select button so it's an easier hit-target
- app.createView(): corrected ascii diagram to reflect v0.3.0; edited again to reflect sort/filter changes
- back-filled design notes in this document for v0.0.1
- updated to v0.4.0

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

## 20230520

- the motivation for this extension comes from wanting to have a collection of segments of instructional videos: pick segment to watch, have it play from a designated start time to a stop time
- desired list of features
  - create a "clip", identified by media-uri, title, start- and stop-time
  - display a list of such clips, sorted in various ways
  - select/edit/delete a clip
  - save a list of clips durably (probably as a file in the filesystem)
- of usual suspects in current video players VLC recognizes m3u and xml playlist formats, supports extensibility via scripted and compiled modules, and offers a rudimentary tooklit for building graphical interfaces
- VLC's scripting language, as of VLC version 3.0.18, is Lua 5.1; not a language I know, but seems easy to pick up, w/ handy resources
- our "app" seems suited for [Basic Elm-Like App Structure (BELAS)](https://github.com/pakx/the-mithril-diaries/wiki/Basic-App-Structure); to wit:
  - a `model` module, that is all data no functions; if we're able to peer inside at model data, we should be able to reconstruct the app in that state
  - an `actions` module, controller by another name, that is the only module that modifies model; if we have model + actions we should be able to write, say, a command line interface client for it (and is what we do for testing)
  - a `view` module that uses model (readonly) to render a user interface; user actions such as title-edits are passed on to `actions`, which updates `model`
  The implied unidirectional flow of data/actions should be useful even without an auto-rendering mechanism

  ```text
                     +-----+        +----------+
                     |     | <----- |   model  |
           O         |  v  |        +----------+
          -|-        |  i  |              ^
           /\        |  e  |              |  
                     |  w  |        +----------+
                     |     | -----> |  actions |
                     +-----+        +----------+
  ```

  - this immediately structures our app as follows:

    ```lua
    local app = {
        model       = createModel()
        , actions   = createActions(model)
        , view      = createView(model, actions)

        -- with the benefit of hindsight (at the time this part of the devlog is written; see #202306..)
        -- we have the following properties as well

        , utils     = {...} -- utilities such as copyFile(), fileExists()
        , context   = {...} -- VLC extensions are invoked in the context of VLC and expect to find global references
                            -- such as `vlc`; the `app.context` property is a way to provide stubs for those
                            -- expected references when this extension is run outside of VLC (such as in tests)
    }
    ```

- code conventions
  - place function-describing comments within the function, using a 3-character version of comment characters
  - use comma-first; similarly, if breaking up an expression involving operators, start the continuation line with an operator

- Resources:

  - [Lua 5.1 Reference Manual](http://www.lua.org/manual/5.1/)
  - [Programming in Lua (first edition)](https://www.lua.org/pil/contents.html#P1)
  - [Lua Tutorial](https://www.tutorialspoint.com/lua/index.htm)
  - [Lua-users wiki](http://lua-users.org/) has useful material, though not easily discovered; among these
    - [Tutorial Directory](http://lua-users.org/wiki/TutorialDirectory)
    - [Table Serialization](http://lua-users.org/wiki/TableSerialization)
  - [Lua Cookbook](https://stevedonovan.github.io/lua-cookbook/index.html)

  - [LuaUnit](https://github.com/bluebird75/luaunit) testing library; has link to separate documentation site

  - [Mefteg/basic.lua : a basic Lua extension](https://gist.github.com/Mefteg/18463a9cd362ff1f1ba6ff57cb7d4547)
  - [Scripting VLC in lua](https://forum.videolan.org/viewforum.php?f=29) user discussion forum that I haven't been able to join due its overzealous bot-filtering/IP-banning
  - [Instructions to code your own VLC Lua scripts and extensions](https://github.com/videolan/vlc/tree/master/share/lua) ; this may not be for the correct VLC version
  - [VLC Lua Docs](https://vlc.verg.ca/); see the section on Extensions; source seems to be [verghost/vlc-lua-docs](https://github.com/verghost/vlc-lua-docs/blob/master/index.md)

  - [M3U file format](https://en.wikipedia.org/wiki/M3U)
  - [XSPF(“spiff”) spec](https://www.xspf.org/spec#411214-tracklist)

  - how to deploy an extension to videolan isn't immediately obvious; eventually found these:
    - <https://forum.videolan.org/viewtopic.php?t=98644#p522451>
    - [How do I submit a VLC extension to addons.videolan.org?](https://forum.opendesktop.org/t/how-do-i-submit-a-vlc-extension-to-addons-videolan-org/20678)
  