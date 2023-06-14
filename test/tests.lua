--- Test extension (use cases)
--[[
    ## Running tests

    - uses LuaUnit; ensure it's installed and can be require-d
      At the time of this writing an easy way to install LuaUnit is
      to place luaunit.lua in the {lua-installation}/libs folder
      @see: https://github.com/bluebird75/luaunit
      @see: https://luaunit.readthedocs.io/en/latest/

    - open a command prompt in this folder ("test")
    - run `lua5.1.exe app.lua` (adjust for platform, etc)

    ## Notes

    - all tests are currently in this one file
    - tests run outside VLC. However since the extension expects to find vlc,
      we supply a stub via a "context", hence the require("_context") below
    - tests exercise model (Test*A*) and actions (Test*B*);
      there are minimal tests for view (TestsC*)
    -
    - luaunit seems to run tests alphabetically; maybe there's a setting I've missed;
      hence the alphabetical/numbered naming
    - test functions below exercise use cases of multiple actions; each use case
      "should" be in a test suite, but luaunit's suite-support seems weak (or perhaps
      I've misread again)
]]


local lu = require("luaunit")
local ctx = require("_context")
local utils = require("_utils")
-- get VClipMangler from parent folder
package.path = package.path .. ";" .. utils.getCurrentDir().."/.." .."/?.lua"
local app = require("VClipMangler")
local apputils = app.utils

app.setContext(ctx)

-- (no more immediately-run code, except tests runner at eof)
-- ====================

local function writeSamplePlaylist(pth)
    local txt = [[
        #EXTM3U
        #PLAYLIST:{playlist title not set}
        
        #EXTINF:1,apple
        #EXTVLCOPT:start-time=0
        #EXTVLCOPT:stop-time=1
        #EXTGRP:fruit
        file:///G:/multimedia/apple.mp4
        
        #EXTINF:1,battle
        #EXTVLCOPT:start-time=0
        #EXTVLCOPT:stop-time=2
        #EXTGRP:event
        file:///G:/multimedia/battle.mp4
        
        #EXTINF:1,cattle
        #EXTVLCOPT:start-time=0
        #EXTVLCOPT:stop-time=3
        #EXTGRP:animal
        file:///G:/multimedia/cattle.mp4
    ]]
    apputils.writeTextToFile(txt, pth)
end

function TestCoverage()
    --- Tests test-coverage; currently we expect coverage for:
    --- - actions.{public functions}
    ---
    --- To do this we make a list of public functions in, say, `actions`,
    --- then check off those functions called in this file; what remains
    --- is not covered by a test.
    ---
    --- Note: we don't build an AST of this file, so for this to work we
    --- need to adhere to the following conventions:
    --- - actions: functions must be called via a var named "acts"
    local fns = {}

    -- collect all acts.{public functions}
    local acts = app.createActions(app.createModel())
    for k, v in pairs(acts) do
        if type(v) == "function" then fns["acts."..k] = true end
    end

    -- remove from above list `acts` functions called in this file
    local info = debug.getinfo(1, 'S');
    local _, thisFile, _ = apputils.SplitFilename(string.sub(info.source, 2))

    local fd = assert(io.open(thisFile))
    for line in fd:lines() do
        local s, _, fn = string.find(line, "(acts%.[^%s%(]+)%(")
        if s then
            fns[fn] = nil
        end
    end
    fd:close()

    -- if all functions called, expect empty list
    local ok = (next(fns) == nil)
    local msg = "these functions not covered: "

    if not ok then
        local lst = {}
        for k, _ in pairs(fns) do
            table.insert(lst, k)
        end
        msg = msg .. table.concat(lst, ", ")
    end

    lu.assertTrue(ok, msg)
end

function TestUsecaseA01_initial_model()
    --- Tests an initially-created model
    local mdl = app.createModel()
    local env = {mdl = mdl}

    local lst = {
        "'" .. table.concat(mdl.sortCriteria, '.') .."' == 'byGroup.byMedia.byTitle'"
        , "mdl.pathSeparator == '"..utils.escapeBackslash(ctx.pathSeparator).."'"
        , "mdl.pthIniOld == '"
            .. utils.escapeBackslash(app.context.vlc.config.userdatadir()
            .. ctx.pathSeparator .. mdl.extensionMeta.title) .. ".ini'"
        , "mdl.pthIni == '"
            .. utils.escapeBackslash(ctx.vlc.config.homedir()
            .. ctx.pathSeparator .. mdl.extensionMeta.title) .. ".ini'"
        , "mdl.appCfg.backupCount == 2"
        , "#mdl.appCfg.playlists == 0"
        , "mdl.playlist == nil"
        , "mdl.clip == nil"
        , "mdl.filter == nil"
    }

    utils.runStrings(lst, env, lu)
end

function TestUsecaseB01_initialize_app_wo_ini()
    --- Tests initializing app w/o an existing ini-file
    local mdl = app.createModel()
    local acts = app.createActions(mdl)

    os.remove(mdl.pthIni)

    acts.initializeApp()
    local msg = "expected ini file to be created: " .. mdl.pthIni
    lu.failIf(not apputils.fileExists(mdl.pthIni), msg)
end

function TestUsecaseB02_initialize_app_wi_ini()
    --- Tests initializing app w/ an existing ini-file
    local mdl = app.createModel()
    local acts = app.createActions(mdl)
    local env = {mdl = mdl}

    local lst = {
        "backupCount=1"
        , "playlistFolder=my_playlist_folder"
        , "playlist=playlist-1"
        , "playlist=playlist-2"
    }
    apputils.writeLstToFile(lst, mdl.pthIni)

    acts.initializeApp()

    lst = {
        "mdl.appCfg.backupCount == 1"
        , "mdl.appCfg.playlistFolder == 'my_playlist_folder'"
        , "#mdl.appCfg.playlists == 2"
        , "'" .. table.concat(mdl.appCfg.playlists,'.') .. "' == 'playlist-1.playlist-2'"
    }

    utils.runStrings(lst, env, lu)
end

function TestUsecaseB03_new_playlist()
    --- Tests creating/saving a new playlist
    local mdl = app.createModel()
    local acts = app.createActions(mdl)

    local playlistFolder, _, _ = apputils.SplitFilename(mdl.pthIni)
    local pthPlaylist = playlistFolder.."newPlaylist.m3u"

    local lst, txtExpected, txt, msg
    local env = {mdl = mdl}

    acts.newPlaylist(pthPlaylist)

    -- check in-memory model
    lst = {
        "mdl.appCfg.playlistFolder == '"
            .. utils.escapeBackslash(playlistFolder) .. "'"
        , "mdl.playlist ~= nil"
        , "mdl.playlist.isNew"
        , "#mdl.playlist.clips == 0"
    }
    utils.runStrings(lst, env, lu)

    os.remove(mdl.pthIni)
    os.remove(pthPlaylist)

    acts.savePlaylist()

    -- check ini-file
    lst = {
        "backupCount="..mdl.appCfg.backupCount
        , "playlistFolder="..playlistFolder
        , "playlist="..pthPlaylist
    }
    txtExpected = table.concat(lst, "\n")
    txt = apputils.trim2(utils.readFile(mdl.pthIni))
    msg = "unexpected ini-file " .. mdl.pthIni
    lu.assertEquals(txt, txtExpected, msg)

    -- check playlist file exists
    msg = "expected playlist exists " .. pthPlaylist
    lu.assertTrue(apputils.fileExists(pthPlaylist), msg)

    -- check playlist file contents
    lst = {
        "#EXTM3U"
        , "#PLAYLIST:" .. mdl.consts.NONE
    }
    txtExpected = table.concat(lst, "\n")
    txt = apputils.trim2(utils.readFile(pthPlaylist))
    msg = "unexpected playlist contents"
    lu.assertEquals(txt, txtExpected, msg)

    assert(os.remove(pthPlaylist))
end

function TestUsecaseB04_new_clip()
    --- Tests creating/saving a new clip
    local mdl = app.createModel()
    local acts = app.createActions(mdl)

    local playlistFolder, _, _ = apputils.SplitFilename(mdl.pthIni)
    local pthPlaylist = playlistFolder.."newPlaylist.m3u"
    local uriClip = playlistFolder.."test1.mp4"
    local lst, txtExpected, txt
    local env = {mdl = mdl}

    os.remove(mdl.pthIni)
    os.remove(pthPlaylist)

    -- create/save playlist (we need m3u file for subsequent tests)
    acts.newPlaylist(pthPlaylist)
    acts.savePlaylist()

    acts.newClip(uriClip)

    -- update clip w/o all fields; should fail
    local yn, msg, clip = acts.updateClip({
        title = "clip-1-title"
        --, uri = uriClip
        , startTime = 0
        , stopTime = 1
        , group = "group1"
    }, true, true)
    lu.assertTrue(not yn, "update should have failed due insufficient clipInfo")

    -- update clip w/ all fields; should succeed
    yn, msg, clip = acts.updateClip({
        title = "clip-1-title"
        , uri = uriClip
        , startTime = 0
        , stopTime = 1
        , group = "group1"
    }, true, true)
    lu.assertTrue(yn, "update failed, see: "..msg)

    assert(clip, "valid clip expected")

    -- check in-memory clip; should match that from updateClip() above
    lst = {
        "mdl.clip.id == " .. clip.id
        , "mdl.clip.isNew"
        , "mdl.clip.uri == '" .. utils.escapeBackslash(uriClip) .."'"
    }
    utils.runStrings(lst, env, lu)

    acts.savePlaylist()

    -- check in-memory clip; should now have new id, be marked new, etc
    lst = {
        (tonumber(mdl.clip.id) and "true" or "false")
            .. " and mdl.clip.id ~= " .. clip.id
        , "mdl.clip.isNew"
        , "not mdl.clip.isInList"
        , "mdl.clip.uri == '"..utils.escapeBackslash(uriClip) .."'"
    }
    utils.runStrings(lst, env, lu)

    -- check playlist is saved to file
    lu.assertTrue(apputils.fileExists(pthPlaylist))

    -- check playlist file contents
    lst = {
        "#EXTM3U"
        , "#PLAYLIST:"..mdl.consts.NONE

        , string.format("#EXTINF:%d,clip-1-title", clip.stopTime - clip.startTime)
        , "#EXTVLCOPT:start-time=" .. clip.startTime
        , "#EXTVLCOPT:stop-time=" .. clip.stopTime
        , "#EXTGRP:group1"
        , uriClip
    }
    txtExpected = table.concat(lst, "\n")
    txt = string.gsub(apputils.trim2(utils.readFile(pthPlaylist)), "\n+", "\n")
    msg = "unexpected playlist contents"
    lu.assertEquals(txt, txtExpected, msg)

    -- cleanup
    os.remove(pthPlaylist)
    os.remove(mdl.pthIni)
    -- delete backups
    lst = apputils.scandir(playlistFolder, "newPlaylist_bak")
    for i=1, #lst do
        os.remove(playlistFolder  .. lst[i])
    end
end

function TestUsecaseB05_playlist_rolling_backup()
    --- Tests playlist backups
    local mdl = app.createModel()
    local acts = app.createActions(mdl)

    local playlistFolder, _, _ = apputils.SplitFilename(mdl.pthIni)
    local backupFolder = playlistFolder .. "bak"
    local pthPlaylist = playlistFolder.."newPlaylist.m3u"

    os.remove(mdl.pthIni)
    os.remove(pthPlaylist)
    lu.assertEquals(0, utils.createFolder(backupFolder))

    -- fake the backupFolder setting
    mdl.appCfg.backupFolder = backupFolder

    acts.newPlaylist(pthPlaylist)

    -- first-time save: no backups created
    acts.savePlaylist()

    -- save again ...
    acts.savePlaylist()

    -- check we have 1 backup
    local lst = apputils.scandir(backupFolder, "newPlaylist_bak")
    local msg = string.format("expected %d playlist backups, in %s", 1, backupFolder)
    lu.assertEquals(#lst, 1, msg)

    -- create additional fake backup playlists, to test backup deletions
    local now = os.time()
    for i=1, mdl.appCfg.backupCount + 1 do
        lst = {"playlist file ".. i}
        local pth =  backupFolder ..  mdl.pathSeparator .. "newPlaylist_bak"
            .. os.date("%Y%m%d%H%M%S", (now - 5 * i))
            .. ".m3u"
        apputils.writeLstToFile(lst, pth)
    end

    -- (save again ...)
    acts.savePlaylist()

    -- check # backups
    lst = apputils.scandir(backupFolder, "newPlaylist_bak")
    msg = string.format("expected %d playlist backups, in %s", mdl.appCfg.backupCount, backupFolder)
    lu.assertEquals(#lst, mdl.appCfg.backupCount, msg)

    -- cleanup
    for i=1, #lst do
        os.remove(backupFolder  .. mdl.pathSeparator .. lst[i])
    end
    os.remove(pthPlaylist)
    os.remove(mdl.pthIni)
    utils.deleteFolder(backupFolder)
end

function TestUsecaseB06_open_playlist()
    --- Open an existing playlist
    local mdl = app.createModel()
    local acts = app.createActions(mdl)

    local playlistFolder, _, _ = apputils.SplitFilename(mdl.pthIni)
    local pthPlaylist = playlistFolder.."playlist.m3u"

    local lst, txtExpected, txt, msg
    local env = {mdl = mdl}

    -- write sample playlist to file
    writeSamplePlaylist(pthPlaylist)

    acts.openPlaylist(pthPlaylist)

    -- check in-memory model
    lst = {
        "mdl.playlist ~= nil"
        , "not mdl.playlist.isNew"
        , "#mdl.playlist.clips == 3"
        , "mdl.playlist.clips[1].title == 'apple'"
        , "mdl.playlist.clips[1].group == 'fruit'"
        , "mdl.playlist.clips[1].stopTime == 1"

        , "mdl.playlist.clips[2].title == 'battle'"
        , "mdl.playlist.clips[2].group == 'event'"
        , "mdl.playlist.clips[2].stopTime == 2"

        , "mdl.playlist.clips[3].title == 'cattle'"
        , "mdl.playlist.clips[3].group == 'animal'"
        , "mdl.playlist.clips[3].stopTime == 3"
    }
    utils.runStrings(lst, env, lu)

    os.remove(mdl.pthIni)
    os.remove(pthPlaylist)
end

function TestUsecaseB07_filters()
    --- Test setting/clearing filters
    local mdl = app.createModel()
    local acts = app.createActions(mdl)

    local playlistFolder, _, _ = apputils.SplitFilename(mdl.pthIni)
    local pthPlaylist = playlistFolder.."playlist.m3u"

    local lst, txtExpected, txt, msg
    local env = {mdl = mdl}

    -- write sample playlist to file
    writeSamplePlaylist(pthPlaylist)

    acts.openPlaylist(pthPlaylist)
    lu.assertTrue(mdl.playlist.filteredClips == nil)

    acts.setFilter("App") -- should compare lowercase
    lst = {
        "#mdl.playlist.filteredClips == 1"
        , "mdl.playlist.filteredClips[1].title == 'apple'"
    }
    utils.runStrings(lst, env, lu)

    acts.clearFilter()
    lu.assertTrue(mdl.playlist.filteredClips == nil)

    acts.setFilter("ttl")
    lst = {
        "#mdl.playlist.filteredClips == 2"
        , "mdl.playlist.filteredClips[1].title == 'battle'"
        , "mdl.playlist.filteredClips[2].title == 'cattle'"
    }
    utils.runStrings(lst, env, lu)

    os.remove(mdl.pthIni)
    os.remove(pthPlaylist)
end

function TestUsecaseB08_setByClipId()
    --- Set mdl.clip to a specific clip from playlist.clips
    local mdl = app.createModel()
    local acts = app.createActions(mdl)

    local playlistFolder, _, _ = apputils.SplitFilename(mdl.pthIni)
    local pthPlaylist = playlistFolder.."playlist.m3u"

    local lst, txtExpected, txt, msg
    local env = {mdl = mdl}

    writeSamplePlaylist(pthPlaylist)
    acts.openPlaylist(pthPlaylist)

    lu.assertTrue(mdl.clip == nil)

    local idx = 3
    local id = mdl.playlist.clips[idx].id
    acts.setClipById(id)
    lst = {
        "mdl.clip.id == " .. id
        , string.format("mdl.clip.title == '%s'", mdl.playlist.clips[idx].title)
    }
    utils.runStrings(lst, env, lu)

    os.remove(mdl.pthIni)
    os.remove(pthPlaylist)
end

function TestUsecaseB09_deleteByClipId()
    --- Delete specific clip from playlist.clips
    local mdl = app.createModel()
    local acts = app.createActions(mdl)

    local playlistFolder, _, _ = apputils.SplitFilename(mdl.pthIni)
    local pthPlaylist = playlistFolder.."playlist.m3u"

    local lst
    local env = {mdl = mdl}

    writeSamplePlaylist(pthPlaylist)
    acts.openPlaylist(pthPlaylist)

    lst = {
        "#mdl.playlist.clips == 3"
        , "mdl.playlist.clips[1].title .. mdl.playlist.clips[2].title .. mdl.playlist.clips[3].title == 'applebattlecattle'"
    }
    utils.runStrings(lst, env, lu)

    local idx = 2
    local id = mdl.playlist.clips[idx].id
    acts.deleteClipById(id)
    lst = {
        "#mdl.playlist.clips == 2"
        , "mdl.playlist.clips[1].title .. mdl.playlist.clips[2].title == 'applecattle'"
    }
    utils.runStrings(lst, env, lu)

    os.remove(mdl.pthIni)
    os.remove(pthPlaylist)
end

function TestC01_genHelpText()
    local mdl = app.createModel()
    local html = app.genHelpText(mdl)
    lu.assertTrue(html ~= nil)
end

-- run all tests: lua {thisfile.lua}
-- run specific test by [partial-]name, e.g: lua {thisfile.lua} -p TestsB
local lu2 = lu.LuaUnit.new()
os.exit( lu2:runSuite() )
