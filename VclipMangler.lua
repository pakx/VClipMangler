local app = {
    extensionMeta = {
        title = "VClipMangler"
        , version = "0.4.2"
        , author = "pakx"
        , url = "https://github.com/pakx/VClipMangler"
        , shortdesc = "Manage Virtual Clips"
        , description = [[
            Create/manage m3u playlists of tracks ("clips"), with each clip
            assigned a title, start/stop times, group, etc.

            Clips are "virtual" in that they are just metadata about a section
            of interest in longer media, and different clips can refer to
            different sections of the same media.

            Use virtual clips to identify, organize, and play/repeat sections of
            instructional videos, scenes from movies, snatches of songs, etc.

            (NB: playlists created can be used with any player that works with
            m3u files, not just VLC.)
        ]]
        , capabilities = {
            --"menu",
            --"input-listener",
            --"meta-listener",
            --"playing-listener",
        }
        , copyright = "(c) 2023 pakx"
        , testedEnvironments = "VLC 3.0.16/Win10 Prof, VLC 3.0.18/Win10 Prof"
    }

    , context       = nil -- used when running tests outside of VLC; see setContext()
    , view          = nil
}

---==================== VLC-called functions

function descriptor()
    return app.extensionMeta
end

function activate()
    local mdl = app.createModel()
    local acts = app.createActions(mdl)
    app.view = app.createView(mdl, acts)
end

function close()
    vlc.deactivate()
end

function deactivate()
    app.view.dlg:delete()
end

function meta_changed()
    -- not requested in capabilities, but VLC 3.0.16 still looks for it
end

---==================== app functions

app.setContext = function(ctx)
    app.context = ctx
    if ctx.vlc then vlc = ctx.vlc end
end

app.createModel = function()
    --- Creates/returns a data-only representation of the app
    local mdl = {}

    mdl.extensionMeta = app.extensionMeta
    mdl.consts = {
        NONE = "--none--"

        , DEF_BACKUP_COUNT      = 2
        , DEF_PLAYLIST_TITLE    = "{playlist title not set}"

        , ERR_CLIP_BAD_STOP     = "Pls enter usable stop-time"
        , ERR_CLIP_NONE         = "No current clip"
        , ERR_CLIP_NONE_SELECTED  = "Pls first select a clip from the playlist"
        , ERR_CLIP_NOT_FOUND    = "Clip expected in list but not found"
        , ERR_CLIP_UPDT_NEW     = "Cannot update as this is a 'new' clip (did you mean to Add?)"
        , ERR_GROUP_NONE        = "Pls enter or select a group"
        , ERR_MEDIA_NONE        = "Pls select a media in player"
        , ERR_PLAYLIST_NO_EDITS = "Playlist has no edits"
        , ERR_PLAYLIST_NONE     = "No current playlist; pls open or create one"
        , ERR_PLAYLIST_NO_PATH  = "* no playlist.path"
        , ERR_SORT_CRITERIA     = "Unexpected sort criteria"

        , MSG_CANNOT_FIND       = "Cannot find "
        , MSG_CONFIRM_SAVE_PLAYLIST = "Current playlist ({=playlist}) has edits. Save?"
        , MSG_PLAYLIST_SAVED_TIME = "Playlist saved at "
        , MSG_PLS_CHECK_ERRS    = "Pls check "
        , MSG_RELEASE_HAS_NEW = "A newer release is available: {=version}"
        , MSG_RELEASE_IS_LATEST = "You have the latest release"
        , MSG_RELEASE_BAD_CHECK = "There was a problem while checking; pls try again later"
    }

    mdl._id = 10
    mdl.sortCriteria = {
        "byGroup"
        , "byMedia"
        , "byTitle"
    }

    mdl.pathSeparator   =  package and package.config:sub(1,1) or "/"
    mdl.pthIniOld       = vlc.config.userdatadir() .. mdl.pathSeparator .. mdl.extensionMeta.title .. ".ini"
    mdl.pthIni          = vlc.config.homedir() .. mdl.pathSeparator .. mdl.extensionMeta.title .. ".ini"
    mdl.appCfg          = {
        backupCount = mdl.consts.DEF_BACKUP_COUNT
        , playlists = {}
        -- see genHelpText() for other settings
    }
    mdl.errs            = {}  -- todo: implement err-messaging
    mdl.clip            = nil -- see acts.createClip()
    mdl.filter          = nil
    mdl.filterProps     = {}
    mdl.playlist        = nil -- see acts.setPlaylist()

    return mdl
end

app.createActions = function(mdl)
    --- Creates/returns functions that mutate @mdl
    --- @mdl: @see createModel()
    local acts = {}

    local function readAppIni(pth)
        --- Reads ini-file at @pth
        --- Returns {key = value, playlists = {}}

        local cfg = {playlists = {}}
        local fd = assert(io.open(pth))
        if not fd then return cfg end

        for line in fd:lines() do
            local b, _, key, txt = string.find(line, "%s*([^#][^=]+)=(.+)")

            if string.find((key or ""), "^playlist$") then
                table.insert(cfg.playlists, app.utils.trim2(txt))
            elseif b then
                cfg[key] = txt
            end
        end

        fd:close()

        return cfg
    end

    local function writeAppIni(cfg, pth)
        --- Writes ini-file to @pth
        --- @cfg see readAppIni()

        local lst = {}
        for k, v in pairs(cfg) do
            if type(v) ~= "table" then
                table.insert(lst, k .. "=" .. v)
            end
        end

        for _, v in pairs(cfg.playlists) do
            table.insert(lst, "playlist=" .. v)
        end

        app.utils.lstToFile(lst, pth)
    end

    local function readPlaylistM3u(pth)
        --- Reads m3u file, returns playlist
        --- See below for recognized m3u elements
        --- @see-also m3u elements: https://en.wikipedia.org/wiki/M3U
        local function newTrack(title, duration)
            return {
                title = title
                , duration = duration
                , group = nil
                , options = {}
                , uri = nil
            }
        end

        local playlist = {
            path     = pth
            , title  = mdl.consts.DEF_PLAYLIST_TITLE
            , tracks = {}
        }

        local trk = nil
        local fd = assert(io.open(pth))
        local lines = fd:lines()

        for line in lines do

            local _, _, key, txt = string.find(line, "#([^:]+):(.+)")

            if key == "PLAYLIST" then
                playlist.title = txt

            elseif key == "EXTINF" then
                local _, _, d, t = string.find(txt, "(%d+),(.+)")
                trk = newTrack(t, d)

            elseif key == "EXTGRP" then
                trk.group = txt

            elseif key == "EXTVLCOPT" then
                local _, _, k, v = string.find(txt, "([^=]+)=(.+)")
                trk.options[k] = v

            elseif string.find(line, "file:///") or string.find(line, "https?://") then
                trk.uri = line
                table.insert(playlist.tracks, trk)
                trk = nil
            end
        end

        fd:close()

        return playlist
    end

    local function writePlaylistM3u(playlist)
        --- Writes @playlist to file
        --- @playlist: see createPlaylist()
        --- @see-also readPlaylistM3u()
        if not playlist.path then app.utils.dump(mdl.consts.ERR_PLAYLIST_NO_PATH) return end

        local lst = {}
        table.insert(lst, "#EXTM3U")
        table.insert(lst, "#PLAYLIST:" .. playlist.title)
        table.insert(lst, "")

        for _, v in pairs(playlist.clips) do
            local duration = v.stopTime - v.startTime
            table.insert(lst, "#EXTINF:" .. tostring(duration) ..","..v.title)
            table.insert(lst, "#EXTVLCOPT:start-time=" .. v.startTime)
            table.insert(lst, "#EXTVLCOPT:stop-time=" .. v.stopTime)
            table.insert(lst, "#EXTGRP:" .. v.group)
            table.insert(lst, v.uri)
            table.insert(lst, "")
        end

        local ok, err = app.utils.createRollingBackup(
            playlist.path, mdl.appCfg.backupCount, mdl.appCfg.backupFolder)
        -- todo: add debug-level and messaging

        app.utils.lstToFile(lst, playlist.path)
    end

    local function genId()
        --- Generate unique IDs (for this session)
        --- (Thus far there's no requirement this be numeric)
        mdl._id = mdl._id + 1
        return mdl._id
    end

    local function createClip(clipInfo, trackInfo)
        --- Creates/returns a clip, w/ passed-in or new id
        --- Called in different contexts:
        ---   - to create a clip from an m3u track
        ---   - to create a new clip; see acts.newClip()
        ---   - to create a copy of a clip; see acts.updateClip()
        --- @clipInfo:  {same props as clip below}
        --- @trackInfo: {same props as track from acts.readPlaylistM3u()}
        local ci, ti = clipInfo, trackInfo
        local clip = {
            id          = (ci and ci.id) or genId()
            , isNew     = (ci and ci.isNew) or false
            , isInList  = (ci and ci.isInList)  or nil
            , hasEdits  = (ci and ci.hasEdits)  or false
            , hasEditsInVw = (ci and ci.hasEditsInVw)  or false

            , title     = (ci and ci.title)
                or (ti and ti.title)
                or mdl.consts.NONE
            , uri       = (ci and ci.uri) or (ti and ti.uri)
            , startTime = tonumber((ci and ci.startTime)
                or (ti and ti.options["start-time"])
                or 0)
            , stopTime  = tonumber((ci and ci.stopTime)
                or (ti and ti.options["stop-time"])
                or 0)
            , group     = (ci and ci.group)
                or (ti and ti.group)
                or mdl.consts.NONE
        }

        clip.isOk = function()
            --- Tells if clip data is valid
            --- Returns true/false, errMsg
            local strt = tonumber(clip.startTime)
            local stop = tonumber(clip.stopTime)
            local errs = {}
            if (clip.title or "") == "" then table.insert(errs, "title") end
            if (clip.uri or "") == "" then  table.insert(errs, "media") end
            if (not strt or strt < 0 or not stop or stop <= strt)  then  table.insert(errs, "start/stop") end

            return (next(errs) == nil), table.concat(errs, " . ")
        end

        return clip
    end

    local function findClipById(clipId)
        --- Finds/returns clip by id; nil if not found
        --- Note: we can use a lookup table if the linear search below shows issues
        for k, v in pairs(mdl.playlist.clips) do
            if v.id == clipId then return k, v end
        end
    end

    local function setClipToNew()
        --- Marks current clip new, etc
        local c = mdl.clip
        if c then
            c = createClip(c)
            c.id = genId()
            c.isNew, c.isInList, c.hasEdits, c.hasEditsInVw = true, false, false, false
            mdl.clip = c
        end
    end

    local function createPlaylist(playlistInfo)
        --- Creates/returns a new, blank playlist inititlized to @playlistInfo
        --- @playlistInfo: minimum {path="..."}
        ---   This may a playlist we created (e.g. @see acts.newPlaylist())
        ---   or one read from an m3u file (@see readPlaylistM3u())
        local pi = playlistInfo
        local pl = {
            isNew = pi.isNew or false
            , hasDeletes = false

            , title = pi.title or mdl.consts.NONE
            , path = pi.path
            , clips = {}
            , filteredClips = nil
        }

        pl.hasEdits = function()
            --- Tells if playlist has edits
            local yn = pl.hasDeletes
            if not yn then
                for _, v in pairs(pl.clips) do
                    yn = yn or (v.hasEdits or v.isNew)
                    if yn then break end
                end
            end
            return yn
        end

        -- convert tracks to clips
        if pi.tracks then
            for _, trk in pairs(pi.tracks) do
                local clip = createClip(nil,trk)
                table.insert(pl.clips, clip)
            end
        end

        return pl
    end

    local function setPlaylist(playlist)
        --- Translates from external playlist (eg m3u) to playlist of clips
        --- @playlist: see acts.createPlaylist() for expected props
        ---   This may be data returned from an externally-read playlist
        --- @see readPlaylistM3u()
        local pl = createPlaylist(playlist)

        mdl.playlist = pl

        setClipToNew()
    end

    acts.initializeApp = function()
        local pth = mdl.pthIni
        if not app.utils.fileExists(pth) then
            -- ini-file location through v0.2.0 = userdatadir
            -- location thence = homedir
            if app.utils.fileExists(mdl.pthIniOld) then
                app.utils.copyFile(mdl.pthIniOld, pth)
            else
                writeAppIni(mdl.appCfg, pth)
                return
            end
        end

        local cfg = readAppIni(pth)
        cfg.backupCount = tonumber(cfg.backupCount) or mdl.consts.DEF_BACKUP_COUNT
        -- nothing else that can be usefully defaulted here
        -- e.g. playlistFolder set in acts.newPlaylist()

        mdl.appCfg = cfg
    end

    acts.openPlaylist = function(pth)
        local pl = readPlaylistM3u(pth)
        if not pl then --[[ todo: set errs --]] return end
        setPlaylist(pl)
    end

    acts.newPlaylist = function(pth)
        setPlaylist({isNew=true, path=pth})
        -- if don't have ini-file/playlistFolder, set from pth
        if not mdl.appCfg.playlistFolder then
            local p, _, _ = app.utils.SplitFilename(pth)
            mdl.appCfg.playlistFolder = p
        end
    end

    acts.savePlaylist = function()
        local pl = mdl.playlist
        writePlaylistM3u(pl)

        if pl.isNew then
            table.insert(mdl.appCfg.playlists, pl.path)
            writeAppIni(mdl.appCfg, mdl.pthIni)
        end

        for _, v in pairs(pl.clips) do
            v.isNew, v.hasEdits, v.hasEditsInVw = false, false, false
        end
        pl.isNew, pl.hasDeletes = false, false

        setClipToNew()
    end

    acts.newClip = function(uri)
        mdl.clip = createClip({uri=uri, isNew=true})
        return mdl.clip
    end

    acts.setClipById = function(clipId)
        local _, clip = findClipById(clipId)
        mdl.clip = clip and createClip(clip) or nil
        return mdl.clip
    end

    acts.updateClip = function(clipInfo, saveToList, asNew)
        --- Updates mdl.clip + optionally saves to mdl.playlist.clips
        --- @clipInfo describes a clip; @see acts.createClip()
        --- @saveToList true/false saves to mdl.playlist.clips
        --- @asNew true/false tells whether to save mdl.clip to mdl.playlist.clips
        ---   as a new clip w/ a new id
        --- Returns ok, errMsg, clip
        local yn, msg, clip = false, nil, mdl.clip
        if not clip then return false, mdl.consts.ERR_CLIP_NONE end

        -- apply edits to mdl.clip
        local ci = clipInfo
        for _, k in pairs({"title", "uri", "startTime", "stopTime", "group"}) do
            if clip[k] ~= ci[k] then clip[k] = ci[k]; yn = true end
        end

        if yn then
            clip.hasEdits     = true
            clip.hasEditsInVw = true
        end

        yn, msg = clip.isOk()
        if not yn then return yn, msg end

        if saveToList then
            if asNew then
                clip.id = genId()
                clip.isNew = true
                clip.isInList = true

                table.insert(mdl.playlist.clips, clip)
            else
                local k, _ = findClipById(clip.id)
                if k then
                    mdl.playlist.clips[k] = clip
                else
                    msg = mdl.consts.ERR_CLIP_NOT_FOUND
                    app.utils.dump(clip, msg)
                    return false, msg
                end
            end

            clip.hasEditsInVw = false
            if clip.isNew then clip.hasEdits = false end

            -- set mdl.clip to a copy of what was saved
            mdl.clip = createClip(clip)
        end

        if mdl.filter then acts.setFilter(mdl.filter, mdl.filterProps) end

        return yn, msg, clip
    end

    acts.deleteClipById = function(clipId)
        local k, v = findClipById(clipId)
        if k then table.remove(mdl.playlist.clips, k) end
        if not v.isNew then mdl.playlist.hasDeletes = true end
        return v
    end

    acts.setFilter = function(regex, clipProps)
        --- Filters playlist.clips by @regex applied to @clipProps
        --- @regex matching is "case insensitive" (approx-d by lowercasing everything)
        --- Resulting clips are saved in `filteredClips`
        --- @regex Lua-style regex, magic chars already escaped if needing to be used as literals, etc
        --- @clipProps optional table of clip props to search; results are or-ed; defaults to {"title"};
        ---   eg {"title", "uri"}
        if regex == "" then acts.clearFilter() return end
        if not mdl.playlist then return end

        if not clipProps then clipProps = {"title"} end
        regex = string.lower(regex)
        local clips = {}

        for _, clip in pairs(mdl.playlist.clips) do
            for _, prop in pairs(clipProps) do
                if string.find(string.lower(clip[prop]), regex) then
                    table.insert(clips, clip)
                    break
                end
            end
        end

        mdl.filter = regex
        mdl.filterProps = clipProps
        mdl.playlist.filteredClips = clips
    end

    acts.clearFilter = function()
        mdl.filter = nil
        mdl.playlist.filteredClips = nil
    end

    return acts
end

local function createViewHandlers(mdl, acts, vw)
    --- view-related functions: click-handlers, etc
    --- Logically part of createView(); extracted for convenience
    --- Note: all args are readonly or not directly modified
    --- @mdl:  model; @see createModel()
    --- @acts: actions; @see createActions()
    --- @vw:   app.view; @see createView()
    local h = {}
    h.groups = {}       -- groups shown in ddGroup
    h.groupsByName = {} -- reverse-lookup for h.groups

    -- internal functions

    local function compareCaseInsensitive(a, b)
        return string.lower(a) < string.lower(b)
    end

    local function getTextAsNumber(textBox)
        return tonumber(app.utils.trim2(textBox:get_text()))
    end

    local function initializeDropdownSort()
        for k, v in ipairs(mdl.sortCriteria) do
            vw.ddSort:add_value(v, k)
        end
    end

    local function formatMediaUri(uri)
        --- Returns @uri formatted to fit/show in view
        local maxlen = 100
        if string.len(uri) <= maxlen then
            return uri
        else
            return string.sub(uri, 1, 25) .. "..." .. string.sub(uri, -72)
        end
    end

    local function showPlaylists(recreate, refetch)
        if recreate then vw.createDropdownPlaylists(recreate) end
        local pls = mdl.appCfg.playlists
        table.sort(pls, compareCaseInsensitive)
        for k, v in ipairs(pls) do
            vw.ddPlaylists:add_value(v, k)
        end
    end

    local function showGroups(recreate)
        if recreate then vw.createDropdownGroups(true) end
        table.sort(h.groups)
        for k,v in ipairs(h.groups) do
            vw.ddGroups:add_value(v, k)
        end
    end

    local function showPlaylist(isNew)
        --- Shows current playlist, w/ clips sorted per vw selection
        --- @isNew true/false tells if we're showing a different playlist from the one
        ---   being shown just before, in which case we rebuild known groups, etc
        local sortMeta = {
            byGroup = {
                fn = function(a, b)
                    return string.lower(a.group) == string.lower(b.group)
                        and string.lower(a.title) < string.lower(b.title)
                        or string.lower(a.group) < string.lower(b.group)
                end
                , lpad = string.rep(" ", 10)
            }
            , byMedia = {
                fn = function(a, b)
                    return a.uri == b.uri
                        and (a.startTime == b.startTime
                            and string.lower(a.title) < string.lower(b.title)
                            or a.startTime < b.startTime
                        )
                        or a.uri < b.uri
                end
                , lpad = string.rep(" ", 10)
            }
            , byTitle = {
                fn = function(a, b)
                    return string.lower(a.title) < string.lower(b.title)
                end
                , lpad = string.rep(" ", 5)
            }
        }

        vw.lstClip:clear()

        local pl = mdl.playlist
        if not pl then h.showMsg(mdl.consts.ERR_PLAYLIST_NONE, 1) end

        local txt = "Playlist"..(pl.isNew and " +" or (pl.hasEdits() and " *") or "")
        vw.lblCaptionPlaylist:set_text(txt)
        vw.lblPlaylist:set_text(pl.path)

        local clips = pl.filteredClips or pl.clips
        local idx, sepIdx, DEF_GRP_ID = 0, ".", -1
        local grouping = {}

        local sortBy = mdl.sortCriteria[vw.ddSort:get_value()]
        local sm = sortMeta[sortBy]
        if not sm then
            h.showMsg(mdl.consts.ERR_SORT_CRITERIA, 1)
            sm = sortMeta["byTitle"]
        end
        table.sort(clips, sm.fn)

        if isNew then
            h.groups       = {mdl.consts.NONE}
            h.groupsByName = {[mdl.consts.NONE]=true}
        end

        for _, clip in pairs(clips) do
            local clipId = clip.id

            if isNew and not h.groupsByName[clip.group] then
                table.insert(h.groups, clip.group)
                h.groupsByName[clip.group] = true
            end

            if sortBy == "byGroup" then
                if not grouping[clip.group] then
                    grouping[clip.group] = true
                    idx = 1
                    vw.lstClip:add_value(string.rep(".", 10) .. " " .. clip.group, DEF_GRP_ID)
                else
                    idx = idx + 1
                end
                txt = (
                    " ["
                    .. ((clip.stopTime or 0) - (clip.startTime or 0))
                    .. "]"
                )
            elseif sortBy == "byMedia" then
                if not grouping[clip.uri] then
                    grouping[clip.uri] = true
                    idx = 1
                    vw.lstClip:add_value(string.rep(".", 10) .. " " .. formatMediaUri(clip.uri), DEF_GRP_ID)
                else
                    idx = idx + 1
                end
                txt = (
                    " ["
                    ..(clip.group == mdl.consts.NONE and "" or (clip.group.."/"))
                    .. tostring(clip.startTime or 0) .. "-" .. tostring(clip.stopTime or 0)
                    .. "]"
                )
            else -- byTitle
                idx = idx + 1

                txt = (
                    " ["
                    ..(clip.group == mdl.consts.NONE and "" or (clip.group.."/"))
                    .. ((clip.stopTime or 0) - (clip.startTime or 0))
                    .. "]"
                )
            end

            local leader = string.sub(idx .. sepIdx .. sm.lpad, 1, string.len(sm.lpad))
            local glyphs = (clip.isNew and "+" or "")..((clip.hasEdits) and "*" or "")
            txt = leader
                .. ((glyphs ~= "") and (glyphs.." ") or "")
                .. clip.title
                .. txt

            vw.lstClip:add_value(txt, clipId)
        end

        if isNew then showGroups(true) end
    end

    local function showClipStatus()
        --- Shows status of current clip
        local c = mdl.clip
        vw.lblCaptionClip:set_text(
            "Clip "
            ..(c.isNew and "+" or "")
            ..(c.hasEditsInVw and "*" or "")
        )
    end

    local function showClip()
        -- show current clip
        local clip = mdl.clip
        if not clip then h.showMsg(mdl.consts.ERR_CLIP_NONE,1) return end

        vw.lblGroup:set_text(clip.group)
        vw.mediaUri = clip.uri
        vw.lblMediaUri:set_text(formatMediaUri(clip.uri or ""))
        vw.txtClipTitle:set_text(clip.title or "")
        vw.txtClipStart:set_text(clip.startTime or "")
        vw.txtClipStop:set_text(clip.stopTime or "")
        showClipStatus()

        vw.lblStatus:set_text("")
    end

    local function getMediaUriFromPlayer()
        local itm = vlc.input.item()
        return itm and itm:uri() or nil
    end

    local function updateClip(saveToList, asNew)
        return acts.updateClip(
            { title = app.utils.trim2(vw.txtClipTitle:get_text())
                , uri = vw.mediaUri
                , startTime = tonumber(vw.txtClipStart:get_text())
                , stopTime = tonumber(vw.txtClipStop:get_text())
                , group = vw.lblGroup:get_text()
            }
            , saveToList
            , asNew
        )
    end

    -- public/widget handlers

    h.initializeView = function()
        initializeDropdownSort()
        acts.initializeApp()
        showPlaylists()
    end

    h.btnPlaylistSaveClick = function()
        local pl = mdl.playlist
        if not pl then h.showMsg(mdl.consts.ERR_PLAYLIST_NONE) return end
        if not pl.isNew and not pl.hasEdits() then h.showMsg(mdl.consts.ERR_PLAYLIST_NO_EDITS) return end

        acts.savePlaylist()
        showPlaylists(true)
        showPlaylist()
        showClip()
        h.showMsg(mdl.consts.MSG_PLAYLIST_SAVED_TIME .. os.date("%Y-%m-%d %H:%M:%S"))
    end

    h.btnPlaylistOpenClick = function()
        local function openPlaylist()
            local k, v = vw.ddPlaylists:get_value()
            if not app.utils.fileExists(v) then h.showMsg(mdl.consts.MSG_CANNOT_FIND ..v,1) return end

            acts.openPlaylist(v)
            showPlaylist(true)
            showClip()
            h.showMsg("")
        end

        local function cbHasEdits(btn)
            if btn == "c" then return end
            if btn == "y" then h.savePlaylist() end
            openPlaylist()
        end

        if mdl.playlist and mdl.playlist.hasEdits() then
            local _, f, _ = app.utils.SplitFilename(mdl.playlist.path)
            local msg = string.gsub(mdl.consts.MSG_CONFIRM_SAVE_PLAYLIST, "{=playlist}", f)
            vw.overlayConfirm(msg, cbHasEdits)
        else
            openPlaylist()
        end
    end

    h.btnPlaylistNewClick = function()
        local function cbNew(btn, pth)
            if btn ~= "ok" then return end

            if not string.find(string.lower(pth), "%.m3u$") then pth = pth .. ".m3u" end
            pth = string.gsub(pth, "%....$", ".m3u")

            acts.newPlaylist(pth)
            showPlaylist(true)
        end

        local function cbHasEdits(btn)
            if btn == "c" then return end
            if btn == "y" then h.savePlaylist() end
            vw.overlayNewPlaylist(cbNew)
        end

        if mdl.playlist and mdl.playlist.hasEdits() then
            local p, f, e = app.utils.SplitFilename(mdl.playlist.path)
            local msg = string.gsub(mdl.consts.MSG_CONFIRM_SAVE_PLAYLIST, "{=playlist}", f)
            vw.overlayConfirm(msg, cbHasEdits)
        else
            vw.overlayNewPlaylist(cbNew)
        end
    end

    h.btnMediaSelectClick = function()
        local uri = getMediaUriFromPlayer()
        if not uri then h.showMsg(mdl.consts.ERR_MEDIA_NONE,1) return end
        vw.mediaUri = uri
        vw.lblMediaUri:set_text(formatMediaUri(uri))
    end

    h.btnMediaPlayClick = function()
        local uri = vw.lblMediaUri:get_text()
        if not uri or uri == "" then h.showMsg(mdl.consts.ERR_MEDIA_NONE, 1) return end

        local itm = {
            path = uri
        }

        vlc.playlist.add({itm})
    end

    h.btnSetGroupClick = function()
        --- Sets a clip's group per vw
        --- Updates list of known groups as needed
        local txtNew, txtDrp = app.utils.trim2(vw.txtGroup:get_text()), nil

        if txtNew == "" then
            local k, v = vw.ddGroups:get_value()
            if k < 1 then h.showMsg(mdl.consts.ERR_GROUP_NONE, 1) return end
            txtDrp = v
        end

        vw.lblGroup:set_text((txtNew ~= "") and txtNew or txtDrp)

        if txtNew ~= "" then
            vw.txtGroup:set_text("")
            if not h.groupsByName[txtNew] then
                table.insert(h.groups, txtNew)
                h.groupsByName[txtNew] = true
                showGroups(true)
            end
        end

        updateClip()
        showClip()
    end

    h.btnClipPlayClick = function()
        local yn, msg, clip = updateClip()
        if not yn then h.showMsg(msg, 1) return end

        local itm = {
            path = clip.uri
            , options = {
                "start-time="..clip.startTime
                , "stop-time="..clip.stopTime
            }
        }

        vlc.playlist.add({itm})
    end

    h.btnClipNewClick = function()
        acts.newClip(getMediaUriFromPlayer())
        showClip()
    end

    h.btnClipSelectClick = function()
        --- Shows details of first selected clip
        local clipId = next(vw.lstClip:get_selection())
        if not clipId then h.showMsg(mdl.consts.ERR_CLIP_NONE_SELECTED, 1) return end
        if clipId < 0 then return end -- it's a group

        acts.setClipById(clipId)
        showClip()
    end

    h.btnClipUpdateClick = function()
        if not mdl.clip then h.showMsg(mdl.consts.ERR_CLIP_NONE, 1) return end
        local clip, saveToList, asNew = mdl.clip, true, false
        if clip.isNew and not clip.isInList then h.showMsg(mdl.consts.ERR_CLIP_UPDT_NEW, 1) return end

        local ok, msg = updateClip(saveToList, asNew)
        if not ok then h.showMsg("Pls check " .. msg, 1) return end
        showPlaylist()
        showClip()
    end

    h.btnClipAddClick = function()
        --- Adds current clip as new item
        if not mdl.playlist then h.showMsg(mdl.consts.ERR_PLAYLIST_NONE, 1) return end
        local saveToList, asNew = true, true
        local ok, msg, _ = updateClip(saveToList, asNew)
        if not ok then h.showMsg(mdl.consts.MSG_PLS_CHECK_ERRS .. msg, 1) return end

        showPlaylist()
        showClip()
    end

    h.btnClipDeleteClick = function()
        local lst = vw.lstClip:get_selection()
        local k = next(lst)
        if not k then h.showMsg(mdl.consts.ERR_CLIP_NONE_SELECTED, 1) return end

        for k, v in pairs(lst) do
            acts.deleteClipById(k)
        end

        showPlaylist()
    end

    h.btnSortFilterClick = function()
        --- Sets filter; sort is picked up by showPlaylist()
        --- We could make a case for showPlaylist() picking up or being passed in
        --- both filter and sort. Perhaps a tbd; no hurry.
        local rgx = app.utils.trim2(vw.txtFilter:get_text())
        if rgx == "" and mdl.filter and mdl.filter ~= "" then
            h.btnSortFilterClearClick()
            return
        end

        if rgx ~= "" then
            local sortBy = mdl.sortCriteria[vw.ddSort:get_value()]
            local props = (sortBy == "byMedia") and {"title", "uri"} or {"title"}
            acts.setFilter(rgx, props)
            vw.lblFilter:set_text(rgx)
            vw.lblCaptionFilter:set_text("Sort/Filter: *")
        end
        showPlaylist()
    end

    h.btnSortFilterClearClick = function()
        acts.clearFilter()
        vw.lblFilter:set_text("")
        vw.txtFilter:set_text("")
        vw.lblCaptionFilter:set_text("Sort/Filter:")
        showPlaylist()
    end

    h.btnHelpClick = function()
        local html = app.genHelpText(mdl)
        vw.overlayHelp(html)
    end

    h.genTimeSetHandler = function(tb)
        return function()
            local itm = vlc.input.item()
            if not itm then h.showMsg(mdl.consts.ERR_MEDIA_NONE, 1) return end

            local inp = vlc.object.input()
            local n = math.floor(vlc.var.get(inp, "time")/1000000)

            tb:set_text(n)
            updateClip()
            showClipStatus()
        end
    end

    h.genTimeAdjustHandler = function(tb, amt, lbound)
        return function()
            local n = getTextAsNumber(tb)
            if not n or (n + amt) <= lbound then return end
            tb:set_text(n+amt)
            updateClip()
            showClipStatus()
        end
    end

    h.genTimeSeekHandler = function(tb)
        return function()
            local itm = vlc.input.item()
            if not itm then h.showMsg(mdl.consts.ERR_MEDIA_NONE, 1) return end

            local n = getTextAsNumber(tb)
            if not n then h.showMsg(mdl.consts.ERR_CLIP_BAD_STOP, 1) return end

            local inp = vlc.object.input()
            vlc.var.set(inp, "time", n * 1000000)
        end
    end

    h.showMsg = function(msg, isErr)
        --- Shows @msg in status-bar
        if isErr then msg = '<font color="red">'..msg..'</font>' end
        vw.lblStatus:set_text(msg)
    end

    return h
end

app.createView = function(mdl, acts)
    --- Creates/returns view (the visible GUI)
    --- @mdl: (readonly) @see createModel()
    --- @acts: @see createActions()
    --[[
        +-------------------------------------------------+
        | dialog title                                  x |
        +-------------------------------------------------+
        | Playlist    _ _ _ _ _ _ _ _ _ _ _   >save
        |             --------------------v   >open   >new
        | Clip -----------------------------------------
        | >Media:     _ _ _ _ _ _ _ _ _ _ _ _ _ _ _   >play
        | clip title  ___________________________________
        | group:      _ _ _ _ --------------v ______  >set
        | >start-time _______ >decr   >incr   >seek
        | >stop-time  _______ >decr   >incr   >seek
        | >play       >new    >select >update >add
        | -------------------------------------------------
        | Filter/Sort:------v _______ >go     >clear _ _ _
        | >select                             >delete
        | +-----------------------------------------------+
        | | 1. clip-title-1 [group/duration]              |
        | | 2. clip-title-2 [group/duration]              |
        | | ...                                           |
        | +-----------------------------------------------+
        | {lbl-status}                                >help
        +-----------------------------------------------
    ]]
    local vw = {}
    vw.mediaUri = nil -- vw.lblMediaUri shows a truncated version

    local h = createViewHandlers(mdl, acts, vw)
    local dlg = vlc.dialog(mdl.extensionMeta.title)
    local row, rowspan, colspanMax = 1, 1, 6
    local lastRow = 0
    local isHelpVisible = false

    vw.createDropdownPlaylists = function(recreate)
        local row = 2
        if recreate then dlg:del_widget(vw.ddPlaylists) end
        vw.ddPlaylists = dlg:add_dropdown(2, row, 3, 1)
    end

    vw.createDropdownGroups = function(recreate)
        local row = 6
        if recreate then dlg:del_widget(vw.ddGroups) end
        vw.ddGroups = dlg:add_dropdown(3, row, 2, 1)
    end

    vw.overlayConfirm = function(msg, handler, buttons)
        --- Creates an overlay showing @msg + @buttons
        --- @handler `function(button) ... end`, called after user selection;
        ---   `button` is set to 1 char from @buttons
        --- @buttons "[y][n][c]" for yes-no-cancel; defaults to "ync"
        local cfg, knownBtns = {{"y", "Yes"}, {"n", "No"}, {"c", "Cancel"}}, ""
        for _, v in pairs(cfg) do knownBtns = knownBtns .. v[1] end

        local function genOnClick(btn)
            return function()
                for _, v in pairs(cfg) do
                    if v[3] then dlg:del_widget(v[3]) end
                end
                handler(btn)
            end
        end

        buttons = string.lower(buttons or knownBtns):gsub("[^"..knownBtns.."]", "")

        local html = ([[
            <style>
                panel: {border:1px solid grey;}
            </style>
            <div class='panel'>
            {=msg}
            </div>
            ]]):gsub("{=msg}", msg)

        local frame = dlg:add_html(html, 1, 1, 6, 2)
        local col = colspanMax - string.len(buttons) - 1

        for _, v in ipairs(cfg) do
            if string.find(buttons, v[1]) then
                col = col + 1
                local ctl = dlg:add_button(v[2], genOnClick(v[1]), col, 2, 1, 1)
                table.insert(v, ctl) -- e.g. now meta/v => {"y", "Yes", ctl}
            end
        end

        table.insert(cfg, {nil, nil, frame})
    end

    vw.overlayNewPlaylist = function(handler)
        local frame, t, y, c
        local function genOnClick(btn)
            return function()
                local txt = app.utils.trim2(t:get_text())
                for _, v in pairs({t, y, c, frame}) do
                    if v then dlg:del_widget(v) end
                end
                handler(btn, txt)
            end
        end

        -- pth -> cfg["playlistFolder"], or folder of first playlist, or ""
        local pth = mdl.appCfg.playlistFolder
        if not pth then
            local _, v = next(mdl.appCfg.playlists)
            pth = v and app.utils.SplitFilename(v) or ""
        elseif not string.find(pth, mdl.pathSeparator.."$") then
            pth = pth .. mdl.pathSeparator
        end

        local html = "<div style='border:1px solid grey;padding:10px;'>"
            .. "Enter full-path to m3u playlist to create:"
            .. "</div>"
        frame = dlg:add_html(html, 1, 1, 6, 2)

        t = dlg:add_text_input(pth, 1, 2, 4, 1)
        y = dlg:add_button("OK", genOnClick("ok"), 5, 2, 1, 1)
        c = dlg:add_button("Cancel", genOnClick("c"), 6, 2, 1, 1)
    end

    vw.overlayHelp = function(html)
        if isHelpVisible then return end
        local row, frame, btnOk, btnCheck

        local function cbOk()
            for _, v in pairs({btnCheck, btnOk, frame}) do
                if v then vw.dlg:del_widget(v) end
                isHelpVisible = false
            end
        end

        local function cbCheck()
            local version = app.utils.checkForUpdates(mdl)
            local msg = version == mdl.extensionMeta.version
                and mdl.consts.MSG_RELEASE_IS_LATEST
                or (version == mdl.consts.NONE and mdl.consts.MSG_RELEASE_BAD_CHECK)
                or string.gsub(mdl.consts.MSG_RELEASE_HAS_NEW, "{=version}", version)
            h.showMsg(msg)
        end

        row = lastRow + 1
        frame = dlg:add_html(html, 1, row, colspanMax, lastRow)
        btnOk = dlg:add_button("OK", cbOk, colspanMax, row, 1, 1)
        btnCheck = dlg:add_button("Check for updates ...", cbCheck, 1, row, 1, 1)
        isHelpVisible = true
    end

    vw.lblCaptionPlaylist = dlg:add_label("Playlist", 1, row, 1, 1)
    vw.lblPlaylist = dlg:add_label("", 2, row, 3, 1)
    dlg:add_button("Save", h.btnPlaylistSaveClick, colspanMax-1, row, 1, 1)

    row = row + 1
    vw.createDropdownPlaylists()
    dlg:add_button("Open", h.btnPlaylistOpenClick, colspanMax-1, row, 1, 1)
    dlg:add_button("New", h.btnPlaylistNewClick, colspanMax, row, 1, 1)

    row = row + 1
    vw.lblCaptionClip = dlg:add_label("Clip", 1, row, 1, 1)
    dlg:add_label("<hr>", 2, row, colspanMax-1, 1)

    row = row + 1
    dlg:add_button("Media", h.btnMediaSelectClick, 1, row, 1, 1)
    vw.lblMediaUri = dlg:add_label("", 2, row, colspanMax-2, 1)
    dlg:add_button("Play", h.btnMediaPlayClick, colspanMax, row, 1, 1)
    row = row + 1
    dlg:add_label("Clip title:", 1, row, 1, 1)
    vw.txtClipTitle = dlg:add_text_input("", 2, row, colspanMax-1, 1)
    row = row + 1
    dlg:add_label("Group:", 1, row, 1, 1)
    vw.lblGroup = dlg:add_label("", 2, row, 2, 1)
    vw.createDropdownGroups()
    vw.txtGroup = dlg:add_text_input("", 5, row, 1, 1)
    dlg:add_button("Set", h.btnSetGroupClick, 6, row, 1, 1)

    row = row + rowspan
    vw.txtClipStart = dlg:add_text_input("", 2, row, 1, 1) -- create before handler-refs below
    dlg:add_button("Start-time", h.genTimeSetHandler(vw.txtClipStart), 1, row, 1, 1)
    dlg:add_button("-", h.genTimeAdjustHandler(vw.txtClipStart, -1, 0), 3, row, 1, 1)
    dlg:add_button("+", h.genTimeAdjustHandler(vw.txtClipStart,  1, 0), 4, row, 1, 1)
    dlg:add_button("Seek", h.genTimeSeekHandler(vw.txtClipStart), 5, row, 1, 1)

    row = row + 1
    vw.txtClipStop = dlg:add_text_input("", 2, row, 1, 1) -- create before handler-refs below
    dlg:add_button("Stop-time", h.genTimeSetHandler(vw.txtClipStop), 1, row, 1, 1)
    dlg:add_button("-", h.genTimeAdjustHandler(vw.txtClipStop, -1, 0), 3, row, 1, 1)
    dlg:add_button("+", h.genTimeAdjustHandler(vw.txtClipStop,  1, 0), 4, row, 1, 1)
    dlg:add_button("Seek", h.genTimeSeekHandler(vw.txtClipStop), 5, row, 1, 1)

    row = row + 1
    dlg:add_button("New", h.btnClipNewClick, 1, row, 1, 1)
    dlg:add_button("Play", h.btnClipPlayClick, 2, row, 1, 1)
    dlg:add_button("Update", h.btnClipUpdateClick, 3, row, 1, 1)
    dlg:add_button("Add", h.btnClipAddClick, 4, row, 1, 1)

    row = row + 1
    dlg:add_label("<hr>", 1, row, colspanMax, 1)

    row = row + 1
    vw.lblCaptionFilter = dlg:add_label("Sort/Filter:", 1, row, 1, 1)
    vw.ddSort = dlg:add_dropdown(2, row, 1, 1)
    vw.txtFilter = dlg:add_text_input("", 3, row, 1, 1)
    dlg:add_button("Go", h.btnSortFilterClick, 4, row, 1, 1)
    dlg:add_button("Clear", h.btnSortFilterClearClick, 5, row, 1, 1)
    vw.lblFilter = dlg:add_label("", 6, row, 1, 1)

    row = row + 1
    dlg:add_button("Select", h.btnClipSelectClick, 1, row, 2, 1)
    dlg:add_button("Delete", h.btnClipDeleteClick, 6, row, 1, 1)

    row, rowspan = row + 2, 50
    vw.lstClip = dlg:add_list(1, row, colspanMax, rowspan)

    row = row + rowspan
    dlg:add_label("<hr>", 1, row, colspanMax, 1)

    row = row + 1
    vw.lblStatus = dlg:add_label("", 1, row, colspanMax-1, 1)
    dlg:add_button("Help", h.btnHelpClick, colspanMax, row, 1, 1)

    local function test()
    end
    --row = row + 1; dlg:add_button("Test", test, 1, row, 1, 1)

    lastRow = row -- @see vw.overlayHelp()

    vw.dlg = dlg

    h.initializeView()

    return vw
end

app.utils = {
    checkForUpdates = function(mdl)
        --- Finds/returns latest release version
        --- We fetch info from repo api, and report version of first-appearing
        --- (i.e. latest) release. Ideally we'd parse the JSON returned by the
        --- api, but here get it from property `html_url .../releases/vx.x.x`
        local xm = mdl.extensionMeta
        local url = string.format("https://api.github.com/repos/%s/%s/releases"
            , xm.author, xm.title)
        local resp = vlc.stream(url)
        local txt = resp:read( 500 )
        local pat = "html_url.+https://github.com/" .. xm.author
            .. "/" .. xm.title .. "/releases/tag/v([%d%.]+)"
        local _, _, v = string.find(txt, pat)

        return v or mdl.consts.NONE
    end

    , copyFile = function(pthSrc, pthDst)
        --- Copies [text?]-file from @pthSrc to @pthDst
        --- @pthDst is expected to terminate in a filename
        local fsrc = assert(io.open(pthSrc, "r"))
        if fsrc then
            local fdst = assert(io.open(pthDst, "w+"))
            local txt = fsrc:read("*all")
            fdst:write(txt)
            fdst:close()
            fsrc:close()
        end
        return true
    end

    , createRollingBackup = function(filePath, backupCount, destFolder)
        --- Creates a rolling backup of file indicated by @filePath, into @destFolder
        --- Backup is named {filename}_bakyyyymmddhhnnss.{ext}
        --- @filePath: path to file to back up
        --- @backupCount: optional; the number of backups to keep; default 2
        --- @destFolder: optional; path to folder into which to back up;
        ---     defaults to folder of @filePath
        --- Returns true/false, errMsg
        if not backupCount or not tonumber(backupCount) or tonumber(backupCount) <=0 then backupCount = 2 end
        local msg = "createRollingBackup() file not found: " .. filePath
        if not app.utils.fileExists(filePath) then return false, msg end

        local pathSeparator = package and package.config:sub(1,1) or "/"
        local p, f, e = app.utils.SplitFilename(filePath)
        if not destFolder then
            destFolder = p
        elseif string.sub(destFolder, string.len(destFolder), string.len(destFolder)) ~= pathSeparator then
            destFolder = destFolder .. pathSeparator
        end

        -- make the backup
        local newName = string.sub(f, 1, string.len(f) - string.len(e) - 1)
            .. "_bak" .. os.date('%Y%m%d%H%M%S') .. "." .. e
        app.utils.copyFile(filePath, destFolder .. newName)

        -- delete per backupCount
        local fileSpec = app.utils.escapeMagic(string.sub(f, 1, string.len(f) - string.len(e) - 1))
            .. "_bak%d+%." .. e
        local lst = app.utils.scandir(destFolder, fileSpec) or {}
        table.sort(lst)

        for idx = backupCount+1, #lst do
            os.remove(destFolder .. lst[idx])
        end

        return true
    end

    , dump = function(var, msg, indent)
        --- Adapted from https://stackoverflow.com/questions/9168058/how-to-dump-a-table-to-console
        -- `indent` sets the initial level of indentation for tables
        if not indent then indent = 0 end
        local print = (vlc and vlc.msg and vlc.msg.dbg) or print

        if msg then print(msg) end

        if not var then
            print 'dump(): @var is nil'

        elseif type(var) == 'table' then
            for k, v in pairs(var) do
                local leader = string.rep("  ", indent) .. k .. ": "
                local typ = type(v)
                if typ == "table" then
                    print(leader)
                    app.utils.dump(v, indent+1)
                elseif typ == 'function' or typ == 'userdata' then
                    print(leader .. typ)
                else
                    print(leader .. tostring(v))
                end
            end
        else
            print(tostring(var))
        end
    end

    , escapeMagic = function(s)
        --- @see https://stackoverflow.com/a/72666170
        return (s:gsub('[%-%.%+%[%]%(%)%$%^%%%?%*]','%%%1'))
    end

    , fileExists = function(pth)
        local fd = io.open(pth,"r")
        if fd ~= nil then io.close(fd) return true else return false end
    end

    , getCurrentDir = function()
        return os.getenv("PWD") or io.popen("cd"):read()
    end

    , lstToFile = function(lst, pth, rsep)
        if not rsep then rsep = "\n" end
        local fd = assert(io.open (pth, "w"))
        fd:write(table.concat(lst, rsep))
        fd:close()
    end

    , scandir = function(directory, filenameRegex)
        --- Adapted from https://forums.cockos.com/showpost.php?s=4a5518d1e64f5a2786484ca4c5f4dda9&p=1542391&postcount=3
        --- Finds in @directory files whose names match @filenameRegex
        --- @directory path to folder to search
        --- @filenameRegex: optional regex of file name
        if not filenameRegex then filenameRegex = "." end
        local lst = {}
        local cmd = package.config:sub(1,1) == "\\"
            and 'dir "'..directory..'" /b'
            or 'ls -a "'..directory..'"' -- possibly 'find "' .. directory "" -maxdepth 1 -type f -ls"

        local fd = assert(io.popen(cmd))
        for fileName in fd:lines() do
            if string.find(fileName, filenameRegex) then
                table.insert(lst, fileName)
            end
        end
        fd:close()

        return lst
    end

    , SplitFilename = function(pthFile)
        --- Adapted from https://fhug.org.uk/kb/code-snippet/split-a-filename-into-path-file-and-extension/
        --- Returns the Path, Filename, and Extension as 3 values
        local pathSeparator = package and package.config:sub(1,1) or "/"
        if pathSeparator ~= "/" and string.find(pthFile, "/") then pthFile = string.gsub(pthFile, "/", pathSeparator) end
        return string.match(pthFile, "(.-)([^"..pathSeparator.."]-([^"..pathSeparator.."%.]+))$")
    end

    , trim2 = function(s)
        --- @see http://lua-users.org/wiki/StringTrim
        return s:match "^%s*(.-)%s*$"
    end
}

app.genHelpText = function(mdl)
    --- Generates text shown in Help
    --- @mdl (readonly) @see createModel()
    --- Logically part of createView(); extracted for convenience.
    --- There was also a thought of placing this function in a separate file
    --- to be concatenated to the main file during a build process, ergo this
    --- being toward the end if the main file.

    local data = {
        mdl = mdl
        , xm = mdl.extensionMeta
        , icoWarn = "&#9888;"
        , pthIniFormatted =  ({app.utils.SplitFilename(mdl.pthIni)})[1]
            .. "<b>" .. ({app.utils.SplitFilename(mdl.pthIni)})[2] .. "</b>"
        , shortdescLcase = mdl.extensionMeta.shortdesc:lower()

        , images = app.getImages()
    }


    local function lookup(pth)
        local v = data
        for k in pth:gmatch('[^.]+') do v = v[k] end
        return v
    end

    local html = [[
        <style>
            *{color:#444;font-family:Verdana;font-size:11pt;}
            ico{font-size:15pt;font-weight:bold;}
            kw{font-weight:bold;}
            .title{color:black;font-weight:bold;}
            .panel{border:1px solid grey;padding:20px;}
            .secn{color:black;display:block;font-weight:bold;}
            .sep{margin-bottom:25px;}
        </style>
        <div class="panel">
            <br/>
            <p><span class="title">{=xm.title}</span> (v{=xm.version}): {=shortdescLcase}</p>
            <p>{=xm.description}</p>

            <p>Note: extension usage should be discoverable, if not immediately intuitive
            due limitations of the default UI widgets in Lua extensions (at least best I
            can tell). 
            For example, to edit an element in a list we'd usually just double-click it
            to indicate selection + edit, whereas here lacking a readily usable click event
            we click the element in the list, then click a Select button to act on it.</p>

            <p> Please file bugs, suggestions, etc at <a href="{=xm.url}/issues">
            {=xm.url}/issues</a>

            <p>A short usage guide follows.</p>

            <p><span class="secn">Extension settings</span>
                <p>Extension settings are saved in an ini-file in the user's "homedir"
                ({=pthIniFormatted}). If you haven't already created an ini-file, one will be
                created when the extension is started. Available settings are:</p>

                <ul>
                    <li><kw>backupCount</kw>=number of backups to keep when saving a playlist;
                    defaults to {=mdl.consts.DEF_BACKUP_COUNT}</li>

                    <li><kw>backupFolder</kw>=path to folder into which to save playlist backups;
                    note: this folder should exist -- it will not be created; defaults to
                    <kw>playlistFolder</kw> (see below); e.g. backupFolder=C:\projects\playlists\bak</li>

                    <li><kw>playlistFolder</kw>=path to folder to which to save new playlists by default;
                    note: this folder should exist -- it will not be created; if not set in the ini-file,
                    it will default to the folder of the first saved playlist e.g.
                    <br/>playlistFolder=C:\projects\playlists</li>

                    <li><kw>playlist</kw>=path to m3u file; can have multiple "playlist" entries,
                    each pointing to a different m3u file; e.g.
                    <br/>playList=C:\projects\playlists\fancy-kookery-techniques.m3u</li>
                    <br/>playList=C:\projects\playlists\fancier-kookery-techniques.m3u</li>
                </ul>

                <p><ico>{=icoWarn}</ico> Settings other than the above will be discarded on save</p>
            </p>

            <p><span class="secn">Creating your first playlist</span>
                <ol>
                    <li>open a media file in VLC; you can pause it, or leave it playing</li>
                    <li class="sep">start {=xm.title}
                    (in VLC click menu/{=xm.shortdesc})</li>

                    <li>in the "Playlist" section, click New
                    <p><img src="{=images.secnPlaylist}"></p></li>
                    <li>in the panel that appears enter the path to an m3u file to create
                    <p><img src="{=images.pnlNewPlaylist}"></p></li>
                    <li class="sep">click OK; this initializes a playlist (but it's not
                    yet saved to file)</li>

                    <li>in the Clip section, click New; this initializes a new clip, using the
                    current media in VLC; a "+" next to Clip indicates it's new
                    <p><img src="{=images.secnClip}"></p></li>
                    <li>enter a title; enter start/stop times as a whole number of seconds or
                    click the corresponding buttons to get the playhead time from VLC</li>
                    <li>you can set an optional group for the clip by selecting an entry from
                    the group dropdown or by entering a group name in the group textbox, then
                    clicking Set</li>
                    <li>to test the clip, click Play at bottom of the Clip section.
                    (FYI each time you click Play a new track is added to VLC's own tracklist.)</li>

                    <li>when you're satisfied with the clip, click Add; this saves the clip to the
                        playlist and displays it in the clips-list (but it's still not written to
                        file)</li>
                    <li>New/Add more clips as you want</li>
                    <li class="sep">to edit a clip already in the clips-list, highlight the clip
                        and click Select; this will show its details in the Clip section; edit,
                        and click Update; a "*" next to Playlist, Clip and the clip in the clips-list
                        indicates edits</li>

                    <li>back in the Playlist section, click Save; this actually saves the playlist to
                        file, and updates the ini-file so the next time you open ({=xm.title} the
                        playlist will appear in the playlists dropdown</li>
                </ol>
            </p>

            <p><span class="secn">Miscellaneous notes</span>
                <ul>
                    <li>currently start/stop times have a resolution of 1 second</li>
                    <li>similar to the Start-time/Stop-time buttons, the Media button gets the
                    current media uri from VLC</li>
                    <li>the Play button across from the Media button plays the media without regard
                    to start/stop times. Use this if you're playing a clip, then realize you
                    want to play farther out that its stop-time. You can still use the time inputs
                    and the -/+/Seek buttons to scrub around.</li>
                    <li>Filter interprets search text as a Lua-style regular expression; this could
                    lead to surprises if it contains "magic characters"; pls see
                    <a href="https://www.lua.org/pil/20.2.html">20.2 – Patterns</a></li>
                    <li>when sorted byGroup or byTitle, Filter searches only in clip title; when sorted
                    byMedia, Filter searches in clip title and uri (the path to the media file)</li>
                    <li>after a playlist is saved, any info in the Clip section is considered "new";
                    this avoids thence updating an incorrect clip (due how we manage clip ids).</li>
                    <li>currently there are no facilities to delete playlists, or to open ones not
                    previously created by {=xm.title}; to do either pls edit the ini-file directly</li>
                </ul>
            </p>

            <p><span class="secn">About</span>
                <br/>{=xm.title}
                <br/>Version: {=xm.version}
                <br/>Url: {=xm.url}
                <br/>Copyright: {=xm.copyright}
                <br/>Tested environments: {=xm.testedEnvironments}
                <br/>
            </p>
        </div>
    ]]

    --html = html:gsub("%s+//[^\n]+", "") -- remove //-comments

    for tok in html:gmatch("{=[^}]+}") do
        local _, _, pth = string.find(tok, "{=([^}]+)}")
        local v = lookup(pth)
        html = html:gsub(tok, v)
    end

    return html
end

app.getImages = function()
    --- Returns a table of base64 image data, keyed by name
    --- Logically part of createView(); extracted for convenience.
    --- There was also a thought of placing this function in a separate file
    --- to be concatenated to the main file during a build process, ergo this
    --- being toward the end if the main file.
    return {
        ["pnlNewPlaylist"] = "data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9Im5vIj8+PCFET0NUWVBFIHN2ZyBQVUJMSUMgIi0vL1czQy8vRFREIFNWRyAxLjEvL0VOIiAiaHR0cDovL3d3dy53My5vcmcvR3JhcGhpY3MvU1ZHLzEuMS9EVEQvc3ZnMTEuZHRkIj4NCjxzdmcgd2lkdGg9IjEwMCUiIGhlaWdodD0iMTAwJSIgdmlld0JveD0iMCAwIDQ4NCA5MCIgdmVyc2lvbj0iMS4xIg0KICAgIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyINCiAgICB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayIgeG1sOnNwYWNlPSJwcmVzZXJ2ZSINCiAgICB4bWxuczpzZXJpZj0iaHR0cDovL3d3dy5zZXJpZi5jb20vIiBzdHlsZT0iZmlsbC1ydWxlOmV2ZW5vZGQ7Y2xpcC1ydWxlOmV2ZW5vZGQ7c3Ryb2tlLWxpbmVjYXA6cm91bmQ7c3Ryb2tlLWxpbmVqb2luOnJvdW5kO3N0cm9rZS1taXRlcmxpbWl0OjEuNTsiPg0KICAgIDxzdHlsZSB0eXBlPSJ0ZXh0L2NzcyI+PCFbQ0RBVEFbDQogICAgLkJHe2ZpbGw6I0YwRjBGMDtzdHJva2U6bm9uZTt9DQogICAgLkNUTHtmaWxsOiNFMUUxRTE7c3Ryb2tlOiNBREFEQUQ7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLkZ7Zm9udC1mYW1pbHk6J0FyaWFsTVQnLCAnQXJpYWwnLCBzYW5zLXNlcmlmO2ZvbnQtc2l6ZToxMHB4O30NCiAgICAuTHtmaWxsOm5vbmU7c3Ryb2tlOiMwMDA7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLk9Ge2ZpbGw6I2YzODAwMDtzdHJva2U6I2YzODAwMDtzdHJva2Utd2lkdGg6MC43NXB4O30NCiAgICAuVEJ7ZmlsbDojRkZGO3N0cm9rZTojN0E3QTdBO3N0cm9rZS13aWR0aDowLjc1cHg7fQ0KXV0+PC9zdHlsZT4NCg0KICAgIDxyZWN0IGNsYXNzPSJCRyIgeD0iMCIgeT0iMjciIHdpZHRoPSI0ODMiIGhlaWdodD0iNjIiLz4NCiAgICA8cmVjdCBpZD0iYm9yZGVyIiB4PSIwLjM3NSIgeT0iMC4zNzUiIHdpZHRoPSI0ODIuOTg0IiBoZWlnaHQ9Ijg5LjI1IiBjbGFzcz0iTCIvPg0KICAgIDxnIGlkPSJ0aXRsZWJhciI+DQogICAgICAgIDxwYXRoIGlkPSJzeXMiIGNsYXNzPSJMIiBkPSJNNDI3LjQxMSwxMC43MjhsMCw2Ljg3NWw2LjUsLTBsMC4yNSwtNi44NzVsLTYuNzUsLTBabS0zMywzLjQzN2w2LDBtNjEuNSwtMy40MzdsNy4yNSw2Ljg3NW0wLC02Ljg3NWwtNi4yNSw2Ljg3NSIvPg0KICAgICAgICA8ZyBpZD0ibG9nbyI+DQogICAgICAgICAgICA8cGF0aCBkPSJNOS42MTEsMTUuNjYybC0xLjA4NiwwbC0xLjAyOSw0LjM0M2wxMC44LDAuMDczbC0wLjk1MiwtNC40MTZsLTEuMjM5LDBjMCwwIC0xLjEwNCwxLjc0MSAtMi45NTUsMS43NzNjLTIuNDIsMC4wNDMgLTMuNTM5LC0xLjc3MyAtMy41MzksLTEuNzczWiIgY2xhc3M9Ik9GIi8+DQogICAgICAgICAgICA8cGF0aCBkPSJNOS43MzksMTYuMTFsLTAuMzkzLDEuNTE3Yy0wLDAgMS4wMzksMS4wNjUgMy42MDgsMS4wMTVjMi41MDksLTAuMDUgMy43MSwtMS4zMjYgMy43MSwtMS4zMjZsLTAuNTA2LC0xLjI5NiIgc3R5bGU9ImZpbGw6bm9uZTtzdHJva2U6I2FjNDAwMDtzdHJva2Utd2lkdGg6MC40NnB4OyIvPg0KICAgICAgICAgICAgPHBhdGggZD0iTTExLjIyNSwxMi4wNDhsMy4zMzQsLTAuMDI4bDAuNjUyLDIuMTQ1bC00LjUxNSwtMGwwLjUyOSwtMi4xMTdaIiBjbGFzcz0iT0YiLz4NCiAgICAgICAgICAgIDxwYXRoIGQ9Ik05Ljg4OSwxNS42NjJsMS44NTUsLTYuMjg1bTQuMjUsNi4yODVsLTIuMDQsLTYuMjg1IiBzdHlsZT0iZmlsbDpub25lO3N0cm9rZTojYjBiNGI3O3N0cm9rZS13aWR0aDowLjQ2cHg7Ii8+DQogICAgICAgICAgICA8cGF0aCBkPSJNMTIuMjk2LDcuMzA3bDEuMTQzLDBsMC41MTUsMi4wN2wtMi4yMSwtMC4wMDFsMC41NTIsLTIuMDY5WiIgY2xhc3M9Ik9GIi8+DQogICAgICAgIDwvZz4NCiAgICAgICAgPHRleHQgeD0iMjEuNTkycHgiIHk9IjE4LjQwN3B4IiBjbGFzcz0iRiI+VmNsaXBNYW5nbGVyPC90ZXh0Pg0KICAgIDwvZz4NCiAgICA8ZyAgPg0KICAgICAgICA8cmVjdCB4PSI4Ljk2OSIgeT0iMzEuOTczIiB3aWR0aD0iNDY0LjA0OSIgaGVpZ2h0PSI1My4wNTUiIGNsYXNzPSJUQiIvPg0KICAgICAgICA8cmVjdCB4PSI4Ljk2OSIgeT0iNjYuMDk4IiB3aWR0aD0iMjk5LjQyNCIgaGVpZ2h0PSIxNS4zNjgiIGNsYXNzPSJUQiIvPg0KICAgICAgICA8cmVjdCB4PSIzMTUuMTU2IiB5PSI2Ni4wOTgiIHdpZHRoPSI5OC4wNDkiIGhlaWdodD0iMTUuMzY4IiBjbGFzcz0iQ1RMIi8+DQogICAgICAgIDxyZWN0IHg9IjQxOC4wOTQiIHk9IjY2LjA5OCIgd2lkdGg9IjU0LjkyNCIgaGVpZ2h0PSIxNS4zNjgiIGNsYXNzPSJDVEwiLz4NCg0KICAgICAgICA8dGV4dCB4PSIxMS44NDJweCIgeT0iNDQuNjU3cHgiIGNsYXNzPSJGIj5FbnRlciBmdWxsIHBhdGggdG8gbTN1IHBsYXlsaXN0IHRvIGNyZWF0ZTo8L3RleHQ+DQogICAgICAgIDx0ZXh0IHg9IjExLjg0MnB4IiB5PSI3OS4zNjJweCIgY2xhc3M9IkYiPkM6XFByb2plY3RzXHBsYXlsaXN0c1xteS3vrIFyc3QtcGxheWxpc3QubTN1PC90ZXh0Pg0KICAgICAgICA8dGV4dCB4PSIzNTYuNzI0cHgiIHk9Ijc3LjM2NHB4IiBjbGFzcz0iRiI+T0s8L3RleHQ+DQogICAgICAgIDx0ZXh0IHg9IjQzMC40MTJweCIgeT0iNzcuMzY0cHgiIGNsYXNzPSJGIj5DYW5jZWw8L3RleHQ+DQogICAgPC9nPg0KPC9zdmc+DQoNCg=="
        , ["secnClip"] = "data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9Im5vIj8+PCFET0NUWVBFIHN2ZyBQVUJMSUMgIi0vL1czQy8vRFREIFNWRyAxLjEvL0VOIiAiaHR0cDovL3d3dy53My5vcmcvR3JhcGhpY3MvU1ZHLzEuMS9EVEQvc3ZnMTEuZHRkIj4NCjxzdmcgd2lkdGg9IjEwMCUiIGhlaWdodD0iMTAwJSIgdmlld0JveD0iMCAwIDQ4NCAxNTEiIHZlcnNpb249IjEuMSINCiAgICB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciDQogICAgeG1sbnM6eGxpbms9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGxpbmsiIHhtbDpzcGFjZT0icHJlc2VydmUiDQogICAgeG1sbnM6c2VyaWY9Imh0dHA6Ly93d3cuc2VyaWYuY29tLyIgc3R5bGU9ImZpbGwtcnVsZTpldmVub2RkO2NsaXAtcnVsZTpldmVub2RkO3N0cm9rZS1saW5lY2FwOnJvdW5kO3N0cm9rZS1saW5lam9pbjpyb3VuZDtzdHJva2UtbWl0ZXJsaW1pdDoxLjU7Ij4NCiAgICA8c3R5bGUgdHlwZT0idGV4dC9jc3MiPjwhW0NEQVRBWw0KICAgIC5Ge2ZvbnQtZmFtaWx5OidBcmlhbE1UJywgJ0FyaWFsJywgc2Fucy1zZXJpZjtmb250LXNpemU6MTBweDt9DQogICAgLkx7ZmlsbDpub25lO3N0cm9rZTojMDAwO3N0cm9rZS13aWR0aDowLjc1cHg7fQ0KICAgIC5CR3tmaWxsOiNGMEYwRjA7c3Ryb2tlOm5vbmU7fQ0KICAgIC5UQntmaWxsOiNGRkY7c3Ryb2tlOiM3QTdBN0E7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLkNUTHtmaWxsOiNFMUUxRTE7c3Ryb2tlOiNBREFEQUQ7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQpdXT48L3N0eWxlPg0KICAgIDxyZWN0IHg9IjAiIHk9IjAiIHdpZHRoPSI0ODMiIGhlaWdodD0iMTUyIiBjbGFzcz0iQkciLz4NCg0KICAgIDx0ZXh0IGNsYXNzPSJGIiB4PSI5LjM1NHB4IiB5PSI5LjY0OXB4Ij5DbGlwPC90ZXh0Pg0KDQogICAgPHJlY3QgaWQ9ImJ0bk1lZGlhU2VsZWN0IiBjbGFzcz0iQ1RMIiB4PSIxMC4xMjUiIHk9IjE1LjQ3MSIgd2lkdGg9IjUzLjI1IiBoZWlnaHQ9IjE1Ljc1Ii8+DQogICAgPHRleHQgY2xhc3M9IkYiIHg9IjIxLjQ2MXB4IiB5PSIyNi43MTRweCI+TWVkaWE8L3RleHQ+DQogICAgPHJlY3QgaWQ9ImJ0bk1lZGlhUGxheSIgY2xhc3M9IkNUTCIgeD0iNDE4LjEyNSIgeT0iMTUuNDcxIiB3aWR0aD0iNTQuNzUiIGhlaWdodD0iMTQuMjUiLz4NCiAgICA8dGV4dCBjbGFzcz0iRiIgeD0iNDM3LjQzOHB4IiB5PSIyNi43MTRweCI+UGxheTwvdGV4dD4NCg0KICAgIDx0ZXh0IGNsYXNzPSJGIiB4PSI5LjU5M3B4IiB5PSI0OC4xMTZweCI+Q2xpcCB0aXRsZTo8L3RleHQ+DQogICAgPHJlY3QgaWQ9InR4dENsaXBUaXRsZSIgY2xhc3M9IlRCIiB4PSI2OS4zNzUiIHk9IjM3Ljk3MSIgd2lkdGg9IjQwMy41IiBoZWlnaHQ9IjEzLjUiLz4NCg0KICAgIDx0ZXh0IGNsYXNzPSJGIiB4PSI5LjU5M3B4IiB5PSI2OS42MTZweCI+R3JvdXA6PC90ZXh0Pg0KICAgIDxnIGlkPSJkZEdyb3VwcyI+DQogICAgICAgIDxyZWN0IGlkPSIiIHg9IjE5Mi44NzUiIHk9IjU2LjcyMSIgd2lkdGg9IjExNSIgaGVpZ2h0PSIxNi41IiBjbGFzcz0iQ1RMIi8+DQogICAgICAgIDxwYXRoIGQ9Ik0zMDAuMDM0LDY4Ljc4MmwzLjMwOCwtNS42NzNsLTYuNjE1LC0wbDMuMzA3LDUuNjczWiIgc3R5bGU9InN0cm9rZTojMDAwO3N0cm9rZS13aWR0aDowLjc1cHg7Ii8+DQogICAgPC9nPg0KICAgIDxyZWN0IGlkPSJ0eHRHcm91cCIgY2xhc3M9IlRCIiB4PSIzMTQuNjI1IiB5PSI1Ny41OTYiIHdpZHRoPSI5Ny41IiBoZWlnaHQ9IjE2LjUiLz4NCiAgICA8cmVjdCBpZD0iYnRuR3JvdXBTZXQiIGNsYXNzPSJDVEwiIHg9IjQxOS42MjUiIHk9IjU4Ljk3MSIgd2lkdGg9IjU0Ljc1IiBoZWlnaHQ9IjE0LjI1Ii8+DQogICAgPHRleHQgY2xhc3M9IkYiIHg9IjQzNy40MzhweCIgeT0iNjkuOTI1cHgiPlNldDwvdGV4dD4NCg0KICAgIDxyZWN0IGlkPSJidG5DbGlwU3RhcnQiIGNsYXNzPSJDVEwiIHg9IjEwLjEyNSIgeT0iODEuNDcxIiB3aWR0aD0iNTMuMjUiIGhlaWdodD0iMTUuNzUiLz4NCiAgICA8dGV4dCBjbGFzcz0iRiIgeD0iMTQuNzExcHgiIHk9IjkyLjY4NHB4Ij5TdGFydC10aW1lPC90ZXh0Pg0KICAgIDxyZWN0IGlkPSJ0eHRDbGlwU3RhcnQiIGNsYXNzPSJUQiIgeD0iNzAuMDkyIiB5PSI3OS45MDciIHdpZHRoPSIxMTciIGhlaWdodD0iMTYuNSIvPg0KICAgIDxyZWN0IGlkPSJidG5DbGlwU3RhcnREZWNyIiBjbGFzcz0iQ1RMIiB4PSIxOTMuNTkyIiB5PSI3OS45MDciIHdpZHRoPSI1NCIgaGVpZ2h0PSIxNi41Ii8+DQogICAgPHRleHQgY2xhc3M9IkYiIHg9IjIxOC44OTlweCIgeT0iOTEuODAzcHgiPi08L3RleHQ+DQogICAgPHJlY3QgaWQ9ImJ0bkNsaXBTdGFydEluY3IiIGNsYXNzPSJDVEwiIHg9IjI1NC4wOTIiIHk9Ijc5LjkwNyIgd2lkdGg9IjU0IiBoZWlnaHQ9IjE2LjUiLz4NCiAgICA8dGV4dCBjbGFzcz0iRiIgeD0iMjc4LjQ2MXB4IiB5PSI5MS44MDNweCI+KzwvdGV4dD4NCiAgICA8cmVjdCBpZD0iYnRuQ2xpcFN0YXJ0U2VlayIgY2xhc3M9IkNUTCIgeD0iMzE0LjYyNSIgeT0iNzkuOTA3IiB3aWR0aD0iOTcuNSIgaGVpZ2h0PSIxNi41Ii8+DQogICAgPHRleHQgY2xhc3M9IkYiIHg9IjM1MS42ODhweCIgeT0iOTEuOTI1cHgiPlNlZWs8L3RleHQ+DQoNCiAgICA8cmVjdCBpZD0iYnRuQ2xpcFN0b3AiIGNsYXNzPSJDVEwiIHg9IjEwLjEyNSIgeT0iMTAzLjIyMSIgd2lkdGg9IjUzLjI1IiBoZWlnaHQ9IjE1Ljc1Ii8+DQogICAgPHRleHQgY2xhc3M9IkYiIHg9IjE0LjcxMXB4IiB5PSIxMTQuMTg0cHgiPlN0b3AtdGltZTwvdGV4dD4NCiAgICA8cmVjdCBpZD0idHh0Q2xpcFN0b3AiIGNsYXNzPSJUQiIgeD0iNzAuMDkyIiB5PSIxMDAuNDA3IiB3aWR0aD0iMTE3IiBoZWlnaHQ9IjE2LjUiLz4NCiAgICA8cmVjdCBpZD0iYnRuQ2xpcFN0b3BEZWNyIiBjbGFzcz0iQ1RMIiB4PSIxOTMuNTkyIiB5PSIxMDAuNDA3IiB3aWR0aD0iNTQiIGhlaWdodD0iMTYuNSIvPg0KICAgIDx0ZXh0IGNsYXNzPSJGIiB4PSIyMTguODk5cHgiIHk9IjExMS44NjhweCI+LTwvdGV4dD4NCiAgICA8cmVjdCBpZD0iYnRuQ2xpcFN0b3BJbmNyIiBjbGFzcz0iQ1RMIiB4PSIyNTQuMDkyIiB5PSIxMDAuNDA3IiB3aWR0aD0iNTQiIGhlaWdodD0iMTYuNSIvPg0KICAgIDx0ZXh0IGNsYXNzPSJGIiB4PSIyNzguNDYxcHgiIHk9IjExMS44NjhweCI+KzwvdGV4dD4NCiAgICA8cmVjdCBpZD0iYnRuQ2xpcFN0b3BTZWVrIiBjbGFzcz0iQ1RMIiB4PSIzMTQuNjI1IiB5PSIxMDAuNDA3IiB3aWR0aD0iOTcuNSIgaGVpZ2h0PSIxNi41Ii8+DQogICAgPHRleHQgY2xhc3M9IkYiIHg9IjM1MS42ODhweCIgeT0iMTExLjkyNXB4Ij5TZWVrPC90ZXh0Pg0KDQogICAgPHJlY3QgaWQ9ImJ0bkNsaXBQbGF5IiBjbGFzcz0iQ1RMIiB4PSIxMC4xMjUiIHk9IjEyMi43ODIiIHdpZHRoPSI1My4yNSIgaGVpZ2h0PSIxNS43NSIvPg0KICAgIDx0ZXh0IGNsYXNzPSJGIiB4PSIyNi43MTFweCIgeT0iMTM0LjE4NHB4Ij5OZXc8L3RleHQ+DQogICAgPHJlY3QgaWQ9ImJ0bkNsaXBOZXciIGNsYXNzPSJDVEwiIHg9IjcwLjA5MiIgeT0iMTIyLjQwNyIgd2lkdGg9IjExNyIgaGVpZ2h0PSIxNi41Ii8+DQogICAgPHRleHQgY2xhc3M9IkYiIHg9IjExNy40NjFweCIgeT0iMTM0LjE4NHB4Ij5QbGF5PC90ZXh0Pg0KICAgIDxyZWN0IGlkPSJidG5DbGlwQWRkIiBjbGFzcz0iQ1RMIiB4PSIxOTMuNTkyIiB5PSIxMjIuNDA3IiB3aWR0aD0iNTQiIGhlaWdodD0iMTYuNSIvPg0KICAgIDx0ZXh0IGNsYXNzPSJGIiB4PSIyMDUuNDM4cHgiIHk9IjEzNC4xODRweCI+VXBkYXRlPC90ZXh0Pg0KICAgIDxyZWN0IGlkPSJidG5DbGlwVXBkYXRlIiBjbGFzcz0iQ1RMIiB4PSIyNTQuMDkyIiB5PSIxMjIuNDA3IiB3aWR0aD0iNTQiIGhlaWdodD0iMTYuNSIvPg0KICAgIDx0ZXh0IGNsYXNzPSJGIiB4PSIyNzIuMjExcHgiIHk9IjEzNC4xODRweCI+QWRkPC90ZXh0Pg0KDQogICAgPHBhdGggZD0iTTEwLjEyNSwxNDguNDA3bDQ2My40NjcsLTAiIGNsYXNzPSJMIi8+DQogICAgPHBhdGggZD0iTTY5LjEyNSw1LjA3N2w0MDQuNDY3LDAiIGNsYXNzPSJMIi8+ICAgIA0KICAgIDxwYXRoIGQ9Ik0wLDBsMCwxNTAuNzUiIGNsYXNzPSJMIi8+DQogICAgPHBhdGggZD0iTTQ4My43NSwwbDAsMTUwLjc1IiBjbGFzcz0iTCIvPg0KDQo8L3N2Zz4="
        , ["secnPlaylist"] = "data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9Im5vIj8+PCFET0NUWVBFIHN2ZyBQVUJMSUMgIi0vL1czQy8vRFREIFNWRyAxLjEvL0VOIiAiaHR0cDovL3d3dy53My5vcmcvR3JhcGhpY3MvU1ZHLzEuMS9EVEQvc3ZnMTEuZHRkIj4NCjxzdmcgd2lkdGg9IjEwMCUiIGhlaWdodD0iMTAwJSIgdmlld0JveD0iMCAwIDQ4NCA4NiIgdmVyc2lvbj0iMS4xIg0KICAgIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyINCiAgICB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayIgeG1sOnNwYWNlPSJwcmVzZXJ2ZSINCiAgICB4bWxuczpzZXJpZj0iaHR0cDovL3d3dy5zZXJpZi5jb20vIiBzdHlsZT0iZmlsbC1ydWxlOmV2ZW5vZGQ7Y2xpcC1ydWxlOmV2ZW5vZGQ7c3Ryb2tlLWxpbmVjYXA6cm91bmQ7c3Ryb2tlLWxpbmVqb2luOnJvdW5kO3N0cm9rZS1taXRlcmxpbWl0OjEuNTsiPg0KICAgIDxzdHlsZSB0eXBlPSJ0ZXh0L2NzcyI+PCFbQ0RBVEFbDQogICAgLkJHe2ZpbGw6I0YwRjBGMDtzdHJva2U6bm9uZTt9DQogICAgLkNUTHtmaWxsOiNFMUUxRTE7c3Ryb2tlOiNBREFEQUQ7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLkREQXtmaWxsOiMwMDA7c3Ryb2tlOiMwMDA7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLkZ7Zm9udC1mYW1pbHk6J0FyaWFsTVQnLCAnQXJpYWwnLCBzYW5zLXNlcmlmO2ZvbnQtc2l6ZToxMHB4O30NCiAgICAuTHtmaWxsOm5vbmU7c3Ryb2tlOiMwMDA7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLk9Ge2ZpbGw6I2YzODAwMDtzdHJva2U6I2YzODAwMDtzdHJva2Utd2lkdGg6MC43NXB4O30NCl1dPjwvc3R5bGU+DQogICAgPHJlY3QgY2xhc3M9IkJHIiB4PSIwIiB5PSIyNyIgd2lkdGg9IjQ4MyIgaGVpZ2h0PSI1NyIvPg0KICAgIDxwYXRoIGlkPSJib3JkZXIiIGNsYXNzPSJMIiBkPSJNMC4zNzUsODEuNTc3bDAsLTgxLjU3N2w0ODIuOTg0LDBsLTAsODEuNTc3Ii8+DQogICAgPGcgaWQ9InRpdGxlYmFyIj4NCiAgICAgICAgPHBhdGggaWQ9InN5cyIgY2xhc3M9IkwiIGQ9Ik00MjcuNDExLDEwLjcyOGwwLDYuODc1bDYuNSwtMGwwLjI1LC02Ljg3NWwtNi43NSwtMFptLTMzLDMuNDM3bDYsMG02MS41LC0zLjQzN2w3LjI1LDYuODc1bTAsLTYuODc1bC02LjI1LDYuODc1Ii8+DQogICAgICAgIDxnIGlkPSJsb2dvIj4NCiAgICAgICAgICAgIDxwYXRoIGQ9Ik05LjYxMSwxNS42NjJsLTEuMDg2LDBsLTEuMDI5LDQuMzQzbDEwLjgsMC4wNzNsLTAuOTUyLC00LjQxNmwtMS4yMzksMGMwLDAgLTEuMTA0LDEuNzQxIC0yLjk1NSwxLjc3M2MtMi40MiwwLjA0MyAtMy41MzksLTEuNzczIC0zLjUzOSwtMS43NzNaIiBjbGFzcz0iT0YiLz4NCiAgICAgICAgICAgIDxwYXRoIGQ9Ik05LjczOSwxNi4xMWwtMC4zOTMsMS41MTdjLTAsMCAxLjAzOSwxLjA2NSAzLjYwOCwxLjAxNWMyLjUwOSwtMC4wNSAzLjcxLC0xLjMyNiAzLjcxLC0xLjMyNmwtMC41MDYsLTEuMjk2IiBzdHlsZT0iZmlsbDpub25lO3N0cm9rZTojYWM0MDAwO3N0cm9rZS13aWR0aDowLjQ2cHg7Ii8+DQogICAgICAgICAgICA8cGF0aCBkPSJNMTEuMjI1LDEyLjA0OGwzLjMzNCwtMC4wMjhsMC42NTIsMi4xNDVsLTQuNTE1LC0wbDAuNTI5LC0yLjExN1oiIGNsYXNzPSJPRiIvPg0KICAgICAgICAgICAgPHBhdGggZD0iTTkuODg5LDE1LjY2MmwxLjg1NSwtNi4yODVtNC4yNSw2LjI4NWwtMi4wNCwtNi4yODUiIHN0eWxlPSJmaWxsOm5vbmU7c3Ryb2tlOiNiMGI0Yjc7c3Ryb2tlLXdpZHRoOjAuNDZweDsiLz4NCiAgICAgICAgICAgIDxwYXRoIGQ9Ik0xMi4yOTYsNy4zMDdsMS4xNDMsMGwwLjUxNSwyLjA3bC0yLjIxLC0wLjAwMWwwLjU1MiwtMi4wNjlaIiBjbGFzcz0iT0YiLz4NCiAgICAgICAgPC9nPg0KICAgICAgICA8dGV4dCB4PSIyMS41OTJweCIgeT0iMTguNDA3cHgiIGNsYXNzPSJGIj5WY2xpcE1hbmdsZXI8L3RleHQ+DQogICAgPC9nPg0KDQogICAgPHJlY3QgeD0iNjkuMzc1IiB5PSI1Ny4wOTYiIHdpZHRoPSIyMzguNSIgaGVpZ2h0PSIxNi41IiBpZD0iZGQiIGNsYXNzPSJDVEwiLz4NCiAgICA8cGF0aCBkPSJNMzAwLjAzNCw2OS4yOTZsMy4zMDgsLTUuNjczbC02LjYxNSwtMGwzLjMwNyw1LjY3M1oiIGNsYXNzPSJEREEiLz4NCiAgICA8cmVjdCB4PSIzMTQuNjI1IiB5PSIzNC45NzEiIHdpZHRoPSI5Ny41IiBoZWlnaHQ9IjE2LjUiIGNsYXNzPSJDVEwiLz4NCiAgICA8cmVjdCB4PSIzMTQuNjI1IiB5PSI1Ny4wOTYiIHdpZHRoPSI5Ny41IiBoZWlnaHQ9IjE2LjUiIGNsYXNzPSJDVEwiLz4NCiAgICA8cmVjdCB4PSI0MTguMTI1IiB5PSI1OC4yMjEiIHdpZHRoPSI1NC43NSIgaGVpZ2h0PSIxNC4yNSIgY2xhc3M9IkNUTCIvPg0KDQogICAgPHRleHQgeD0iMTAuMDgxcHgiIHk9IjQ1Ljk2NHB4IiBjbGFzcz0iRiI+UGxheWxpc3Q8L3RleHQ+DQogICAgPHRleHQgeD0iMzUxLjY4OHB4IiB5PSI0NS45NjRweCIgY2xhc3M9IkYiPlNhdmU8L3RleHQ+DQogICAgPHRleHQgeD0iMzUxLjY4OHB4IiB5PSI2OC45MjVweCIgY2xhc3M9IkYiPk9wZW48L3RleHQ+DQogICAgPHRleHQgeD0iNDM3LjQzOHB4IiB5PSI2OC45MnB4IiBjbGFzcz0iRiI+TmV3PC90ZXh0Pg0KDQogICAgPHBhdGggZD0iTTE1LjU3Nyw4MC43NjhjLTEuOTgsLTIuMzQgLTQuNTYsLTEuMjYyIC01LjI4LDAuODA5IiBjbGFzcz0iTCIvPg0KICAgIA0KICAgIDxwYXRoIGQ9Ik0xNy41NTcsNzguODY5bC0wLjA2LDIuNzA4IiBjbGFzcz0iTCIvPg0KICAgIDxwYXRoIGQ9Ik0xOS43NzcsNzguODY5bC0wLDAuNTc3IiBjbGFzcz0iTCIvPg0KICAgIDxwYXRoIGQ9Ik0xOS43NzcsODAuNTExbC0wLDEuMDY2IiBjbGFzcz0iTCIvPg0KICAgIDxwYXRoIGQ9Ik0yMS42MzYsODEuMDQ0bDMuNjAxLDAiIGNsYXNzPSJMIi8+DQoNCiAgICA8cGF0aCBkPSJNNjkuMTI1LDgxLjU3N2w0MDQuNDY3LDAiIGNsYXNzPSJDVEwiLz4NCjwvc3ZnPg=="
        , ["warningIcon"] = "data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9Im5vIj8+PCFET0NUWVBFIHN2ZyBQVUJMSUMgIi0vL1czQy8vRFREIFNWRyAxLjEvL0VOIiAiaHR0cDovL3d3dy53My5vcmcvR3JhcGhpY3MvU1ZHLzEuMS9EVEQvc3ZnMTEuZHRkIj48c3ZnIHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIHZpZXdCb3g9IjAgMCAzNSAzOSIgdmVyc2lvbj0iMS4xIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIiB4bWw6c3BhY2U9InByZXNlcnZlIiB4bWxuczpzZXJpZj0iaHR0cDovL3d3dy5zZXJpZi5jb20vIiBzdHlsZT0iZmlsbC1ydWxlOmV2ZW5vZGQ7Y2xpcC1ydWxlOmV2ZW5vZGQ7c3Ryb2tlLWxpbmVqb2luOnJvdW5kO3N0cm9rZS1taXRlcmxpbWl0OjI7Ij48Zz48cGF0aCBkPSJNMC42MiwzMC4zNDFsMTEuMzYxLC0xOS42NDJsMC4wNDUsLTAuMDcxYzAuNDcyLC0wLjc2OSAxLjEwOSwtMS40MjQgMS44NjUsLTEuOTE2YzAuNzE3LC0wLjQ2IDEuNTQ5LC0wLjcwNyAyLjQwMSwtMC43MTJjMC44NTUsLTAuMDAxIDEuNjkzLDAuMjQ2IDIuNDExLDAuNzEyYzAuNzUzLDAuNDk0IDEuMzg2LDEuMTUgMS44NTIsMS45MjFjMC4wMzQsMC4wNTcgMC4wNjUsMC4xMTIgMC4wOTUsMC4xNjdsMTEuMTc2LDE5LjQwOWwwLjA2NCwwLjExNmMwLjQxOCwwLjgzNyAwLjYzMywxLjc2MSAwLjYyNywyLjY5N2MtMC4wMDYsMC43NzMgLTAuMjAzLDEuNTMyIC0wLjU3NCwyLjIxYy0wLjQxOCwwLjc1NiAtMS4wNTksMS4zNjYgLTEuODM0LDEuNzQ2Yy0wLjA1MSwwLjAyNyAtMC4xMDQsMC4wNDggLTAuMTU0LDAuMDY5Yy0wLjc1OSwwLjMzMSAtMS41ODMsMC40ODkgLTIuNDExLDAuNDYzbC0yMy4wNTgsMGMtMC41NjEsLTAuMDA0IC0xLjExNiwtMC4xMDcgLTEuNjQxLC0wLjMwNGMtMC44MzQsLTAuMzE2IC0xLjU1MSwtMC44ODIgLTIuMDUzLC0xLjYyYy0wLjUwNiwtMC43NDggLTAuNzgyLC0xLjYyOSAtMC43OTQsLTIuNTMyYy0wLjAxMywtMC43OTEgMC4xMjgsLTEuNTc3IDAuNDE1LC0yLjMxM2MwLjA1MywtMC4xNDEgMC4xMjEsLTAuMjc1IDAuMjA0LC0wLjRsMC4wMDMsMFoiIHN0eWxlPSJmaWxsOiMwMTAxMDE7ZmlsbC1ydWxlOm5vbnplcm87Ii8+PHBhdGggZD0iTTIuMzc5LDMxLjQ4N2wxMS40MTIsLTE5Ljc0YzEuMzg3LC0yLjE4MyAzLjU4MywtMi4yMzkgNC45OTQsMGwxMS4yMjgsMTkuNTAyYzAuODk4LDEuODAyIDAuNDUzLDQuMjM0IC0yLjQ2OSw0LjE3M2wtMjIuODg2LDBjLTEuOTIxLDAuMDQ4IC0zLjE2LC0xLjYzOCAtMi4yNzksLTMuOTM1WiIgc3R5bGU9ImZpbGw6I2ZmZjsiLz48cGF0aCBkPSJNMTUuMjMzLDMwLjE3MmMwLjI0NCwtMC4yNDIgMC41NjYsLTAuMzkgMC45MDgsLTAuNDE4YzAuMjE2LC0wLjAxNSAwLjQzMywwLjAxNyAwLjYzNSwwLjA5NWMwLjE5OSwwLjA3NiAwLjM3OSwwLjE5MyAwLjUyOSwwLjM0NGMwLjM0OCwwLjM0NSAwLjUwMSwwLjg0MiAwLjQwOCwxLjMyM2MtMC4wMjQsMC4xMjMgLTAuMDYxLDAuMjQzIC0wLjExMSwwLjM1N2MtMC4yNDUsMC41MzggLTAuNzkxLDAuODc5IC0xLjM4MiwwLjg2M2MtMC4yMDcsLTAuMDA1IC0wLjQxMiwtMC4wNTMgLTAuNiwtMC4xNGMtMC4zMzIsLTAuMTU4IC0wLjU5MywtMC40MzYgLTAuNzI4LC0wLjc3OGMtMC4wNDYsLTAuMTA4IC0wLjA3OCwtMC4yMjEgLTAuMDk2LC0wLjMzNmMtMC4wMTgsLTAuMTE1IC0wLjAyMywtMC4yMzEgLTAuMDE1LC0wLjM0N2MwLjAyMSwtMC4xODMgMC4wNzIsLTAuMzYyIDAuMTUsLTAuNTI5YzAuMDcxLC0wLjE1NyAwLjE3NCwtMC4yOTggMC4zMDIsLTAuNDEzbDAsLTAuMDIxWm0yLjE1NywtMi43MWMtMC4wNSwxLjI2NyAtMi4xOTksMS4yNyAtMi4yNDcsLTBjLTAuMjE3LC0yLjE3MyAtMC43NzMsLTcuNzY1IC0wLjc1NywtOS44MDVjMC4wMTksLTAuNjMgMC41MywtMS4wMDMgMS4yMDcsLTEuMTQ2YzAuNDM3LC0wLjA4NyAwLjg4NiwtMC4wODcgMS4zMjMsLTBjMC42OTEsMC4xNDggMS4yMzEsMC41MjkgMS4yMzEsMS4xNzVsLTAsMC4wNjNsLTAuNzU3LDkuNzEzWiIgc3R5bGU9ImZpbGw6IzAxMDEwMTtmaWxsLXJ1bGU6bm9uemVybzsiLz48L2c+PC9zdmc+"
    }
end

return app
