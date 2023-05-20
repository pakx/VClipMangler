--- Test extension (use cases)
--[[
    ## Running tests
    
    - uses LuaUnit; ensure it's installed and can be require-d 
      At the time of this writing an easy way to install LuaUnit is
      to place luaunit.lua in the lua/libs folder
      @see: https://github.com/bluebird75/luaunit
      @see: https://luaunit.readthedocs.io/en/latest/

    - move VClipMangler.lua to VLC's extensions folder
    - set pthVlcExtensions (below) so we can require("VClipMangler")
    - open a command prompt in this folder ("test")
    - run `lua5.1.exe app.lua` (adjust for platform, etc)

    ## Notes

    - all tests are currently in this one file
    - tests run outside vlc. However since the extension expects to find vlc,
      we supply a stub via a "context", hence the require("_context") below
    - tests exercise model (testsA*) and actions (testsB*);
      there are minimal tests for view (testsC*)
    - 
    - luaunit seems to run tests alphabetically; maybe there's a setting I've missed;
      hence the alphabetical/numbered naming
    - test functions below are exercise use cases of multiple actions; each use case
      "should" be in a test suite, but luaunit's suite-support seems weak (or perhaps
      I've misread again)
]] 


local pthVlcExtensions = "C:/ProgramFiles/VLCPortable/App/vlc/lua/extensions"

local lu = require("luaunit")
local ctx = require("_context")
local utils = require("_utils")

package.path = package.path .. ";" .. pthVlcExtensions .."/?.lua"
local app = require("VclipMangler")
app.context = ctx

-- (no more immediately-run code below this line)

function testsA01_createModel()
    local mdl = app.createModel()
    local env = {mdl = mdl}

    -- check model consistency

    lst = {
        "'" .. table.concat(mdl.sortCriteria, '.') .."' == 'byGroup.byTitle'"
        , "mdl.pathSeparator == '"..utils.escapeBackslash(ctx.pathSeparator).."'"
        , "mdl.pthUdd == '" 
            .. utils.escapeBackslash(app.context.vlc.config.userdatadir()) .."'"
        , "mdl.pthIni == '" 
            .. utils.escapeBackslash(mdl.pthUdd .. ctx.pathSeparator .. mdl.extensionMeta.title)
            .. ".ini'"
        , "mdl.appCfg.backupCount == 2"
        , "#mdl.appCfg.playlists == 0"
        , "mdl.playlist == nil"
        , "mdl.clip == nil"
        , "mdl.filter == nil"
    }

    utils.runStrings(lst, env, lu)
end

function testsB01_initializeApp_withoutIni()
    local mdl = app.createModel()
    local acts = app.createActions(mdl)

    os.remove(mdl.pthIni)

    acts.initializeApp()
    local msg = "expected ini file to be created: " .. mdl.pthIni
    lu.failIf(not utils.fileExists(mdl.pthIni), msg)
end

function testsB02_initializeApp_withIni()
    local mdl = app.createModel()
    local acts = app.createActions(mdl)
    local env = {mdl = mdl}

    local lst = {
        "backupCount=1"
        , "playlistFolder=my_playlist_folder"
        , "playlist=playlist-1"
        , "playlist=playlist-2"
    }
    utils.lstToFile(lst, mdl.pthIni)

    acts.initializeApp()

    lst = {
        "mdl.appCfg.backupCount == 1"
        , "mdl.appCfg.playlistFolder == 'my_playlist_folder'"
        , "#mdl.appCfg.playlists == 2"
        , "'" .. table.concat(mdl.appCfg.playlists,'.') .. "' == 'playlist-1.playlist-2'"
    }

    utils.runStrings(lst, env, lu)
end

function testsB03_newPlaylist()
    --- add a new, empty playlist
    --- save playlist, check file + contents
    --- check ini-file has been updated
    local mdl = app.createModel()
    local acts = app.createActions(mdl)

    local playlistFolder, _, _ = utils.SplitFilename(mdl.pthIni)
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
    txt = utils.trim2(utils.readFile(mdl.pthIni))
    msg = "unexpected ini-file " .. mdl.pthIni
    lu.assertEquals(txt, txtExpected, msg)

    -- check playlist file exists
    msg = "expected playlist exists " .. pthPlaylist
    lu.assertTrue(utils.fileExists(pthPlaylist), msg)

    -- check playlist file contents
    lst = {
        "#EXTM3U"
        , "#PLAYLIST:" .. mdl.consts.NONE
    }
    txtExpected = table.concat(lst, "\n")
    txt = utils.trim2(utils.readFile(pthPlaylist))
    msg = "unexpected playlist contents"
    lu.assertEquals(txt, txtExpected, msg)

    assert(os.remove(pthPlaylist))
end

function testsB04_newClip()
    --- add a new, empty playlist
    --- add a new clip
    --- save playlist, check file + contents
    local mdl = app.createModel()
    local acts = app.createActions(mdl)
    
    local playlistFolder, _, _ = utils.SplitFilename(mdl.pthIni)
    local pthPlaylist = playlistFolder.."newPlaylist.m3u"
    local uriClip = playlistFolder.."test1.mp4"
    local lst, txtExpected, txt
    local env = {mdl = mdl}

    os.remove(mdl.pthIni) 
    os.remove(pthPlaylist)

    acts.newPlaylist(pthPlaylist)
    acts.newClip(uriClip)

    -- update clip w/o all fields; should fail
    local yn, msg, clip = acts.updateClip({
        title = "clip-1-title"
        --, uri = uriClip
        , startTime = 0
        , stopTime = 1
        , group = "group1"
    }, true)
    lu.assertTrue(not yn, "update should have failed due insufficient clipInfo")

    -- update again, w/ all fields; should succeed
    yn, msg, clip = acts.updateClip({
        title = "clip-1-title"
        , uri = uriClip
        , startTime = 0
        , stopTime = 1
        , group = "group1"
    }, true)
    lu.assertTrue(yn, "update failed, see: "..msg)

    -- check in-memory clip; should match that from updateClip() above
    lst = {
        "mdl.clip.id == " .. clip.id
        , "mdl.clip.isNew"
        , "mdl.clip.uri == '"..utils.escapeBackslash(uriClip) .."'"
    }
    utils.runStrings(lst, env, lu)
    
    acts.savePlaylist()

    -- check in-memory clip; should be new, etc
    lst = {
        "mdl.clip.id ~= " .. clip.id
        , "mdl.clip.isNew"
        , "not mdl.clip.isInList"
        , "mdl.clip.uri == '"..utils.escapeBackslash(uriClip) .."'"
    }
    utils.runStrings(lst, env, lu)

    -- check playlist saved to file
    lu.assertTrue(utils.fileExists(pthPlaylist))

    -- check playlist file contents
    lst = {
        "#EXTM3U"
        , "#PLAYLIST:"..mdl.consts.NONE

        , "#EXTINF:1000,clip-1-title"
        , "#EXTVLCOPT:start-time=0"
        , "#EXTVLCOPT:stop-time=1"
        , "#EXTGRP:group1"
        , uriClip
    }
    txtExpected = table.concat(lst, "\n")
    txt = string.gsub(utils.trim2(utils.readFile(pthPlaylist)), "\n+", "\n")
    msg = "unexpected playlist contents"
    lu.assertEquals(txt, txtExpected, msg)

    os.remove(pthPlaylist)
    os.remove(mdl.pthIni)

end

function testC01_genHelpText()
    local mdl = app.createModel()
    -- no test per se; only that it generate w/o err
    app.genHelpText(mdl)
end

os.exit( lu.LuaUnit.run() )