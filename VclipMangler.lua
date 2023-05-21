local app = {
    extensionMeta = {
        title = "VclipMangler"
        , version = "0.1.0"
        , author = "pakx"
        , url = "https://github.com/pakx/VclipMangler"
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
        , testedEnvironments = "VLC 3.0.16/Win10 Prof"
    }

    , context       = nil -- used when running tests outside of vlc
    , createModel   = nil
    , createView    = nil
    , createActions = nil
    , view          = nil
}

---==================== vlc-called functions

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
    -- not requested in capabilities, but vlc 3.0.16 still looks for it
end

---==================== app functions

app.createModel = function()
    --- Creates/returns a data-only representation of the app
    --- @cfg: config table used in testing, as follows
    --- - cfg.vlc = {config.userdatadir()}
    local mdl = {}

    mdl.extensionMeta = app.extensionMeta
    mdl.consts = {
        NONE = "--none--"
        , DEF_BACKUP_COUNT = 2

        , NO_CLIP           = "No current clip"
        , NO_CLIP_SELECTED  = "Pls first select a clip from the playlist"
        , NO_PLAYLIST       = "Pls first open or create a playlist"
        , NO_START_TIME     = "Pls enter usable start-time"
        , NO_STOP_TIME      = "Pls enter usable stop-time"
        , NO_MEDIA          = "Pls select a media in player"
        , BAD_UPDT_NEWCLIP  = "Cannot update as this is a 'new' clip (did you mean to Add?)"
        , BAD_SORT_CRITERIA = "*bug: unexpected sort criteria"
    }

    mdl._id = 10
    mdl.sortCriteria = {
        "byGroup"
        , "byTitle"
    }

    local vlc = app.context and app.context.vlc or vlc

    mdl.pathSeparator =  package and package.config:sub(1,1) or "/"
    mdl.pthUdd = vlc.config.userdatadir()
    mdl.pthIni = mdl.pthUdd .. mdl.pathSeparator .. mdl.extensionMeta.title .. ".ini"
    mdl.appCfg = { backupCount=mdl.consts.DEF_BACKUP_COUNT, playlists={} }
    mdl.errs = {}       -- todo: implement err-messaging
    mdl.clip = nil      -- see acts.createClip()
    mdl.filter = nil
    mdl.playlist = nil  -- see acts.setPlaylist()

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
        local fd = io.open(pth)
        if not fd then return cfg end
    
        for line in fd:lines() do
            local b, _, key, txt = string.find(line, "%s*([^#][^=]+)=(.+)")
    
            if string.find((key or ""), "^playlist%d*$") then
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
    
        local fd = io.open (pth, "w")
        fd:write(table.concat(lst, "\n"))
        fd:close()
    end
    
    local function readPlaylistM3u(pth)
        --- Reads m3u file, returns playlist
        --- see below for recognized m3u elements
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
            , title  = "{playlist title not set}"
            , tracks = {}
        }
    
        local trk = nil
        local fd = io.open(pth)
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
    
            elseif string.find(line, "///") then
                trk.uri = line
                table.insert(playlist.tracks, trk)
                trk = nil
            end
        end
        
        fd:close()
    
        return playlist
    end
    
    local function writePlaylistM3u(playlist)
        if not playlist.path then app.utils.dump("* no playlist.path") return end
    
        local lst = {}
        table.insert(lst, "#EXTM3U")
        table.insert(lst, "#PLAYLIST:" .. playlist.title)
        table.insert(lst, "")
    
        for _, v in pairs(playlist.clips) do
            local duration = 1000
            table.insert(lst, "#EXTINF:" .. tostring(duration) ..","..v.title)
            table.insert(lst, "#EXTVLCOPT:start-time=" .. v.startTime)
            table.insert(lst, "#EXTVLCOPT:stop-time=" .. v.stopTime)
            table.insert(lst, "#EXTGRP:" .. v.group)
            table.insert(lst, v.uri)
            table.insert(lst, "")
        end
    
        app.utils.createRollingBackup(playlist.path, mdl.appCfg.backupCount)

        local fd = io.open (playlist.path, "w")
        fd:write(table.concat(lst, "\n"))
        fd:close()
    end

    local function genId()
        mdl._id = mdl._id + 1
        return mdl._id
    end

    local function createClip(clipInfo, track)
        --- @clipInfo: {same fields as clip below}
        --- @track: describes a track from acts.readPlaylistM3u()
        local ci = clipInfo
        local clip = {
            id          = (ci and ci.id) or genId()
            , isNew     = (ci and ci.isNew) or false
            , hasEdits  = (ci and ci.hasEdits)  or false
            , isInList  = (ci and ci.isInList)  or nil
    
            , title     = (ci and ci.title)  
                or (track and track.title) 
                or mdl.consts.NONE
            , uri       = (ci and ci.uri) or (track and track.uri)
            , startTime = tonumber((ci and ci.startTime)
                or (track and track.options["start-time"]) 
                or 0)
            , stopTime  = tonumber((ci and ci.stopTime) 
                or (track and track.options["stop-time"]) 
                or 0)
            , group     = (ci and ci.group) 
                or (track and track.group)
                or mdl.consts.NONE
        }
    
        clip.isOk = function() 
            local strt = tonumber(clip.startTime)
            local stop = tonumber(clip.stopTime)
            local errs = {}
            if (clip.title or "") == "" then table.insert(errs, "title") end
            if (clip.uri or "") == "" then  table.insert(errs, "meaia") end
            if (not strt or strt < 0 or not stop or stop <= strt)  then  table.insert(errs, "start/stop") end
    
            return (next(errs) == nil), table.concat(errs, " . ")
        end
    
        return clip
    end

    local function findClipById(clipId)
        for k, v in pairs(mdl.playlist.clips) do
            if v.id == clipId then return k, v end
        end
    end

    local function setClipToNew()
        --- if we have a current clip, set as new, etc
        local c = mdl.clip
        if c then
            c = createClip(c)
            c.id = genId()
            c.isNew, c.hasEdits, c.isInList = true, false, false
            mdl.clip = c
        end
    end

    local function createPlaylist(playlistInfo)
        --- Creates/returns a new, blank playlist inititlized to @playlistInfo
        --- @playlistInfo: minimum {path="..."}
        ---   This may another vanilla playlist (e.g. @see acts.newPlaylist())
        ---   or one read from disk  and with a slightly different structure
        ---   (@see readPlaylistM3u())
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
            local yn = pl.hasDeletes
            if not yn then
                for _, v in pairs(pl.clips) do
                    yn = yn or (v.hasEdits or v.isNew)
                    if yn then break end
                end
            end
            return yn
        end

        if pi.tracks then
            for _, trk in pairs(pi.tracks) do
                local clip = createClip(nil,trk)
                table.insert(pl.clips, clip)
            end
        end

        return pl
    end

    local function setPlaylist(playlist)
        --- translates from external playlist (eg m3u) to playlist of clips
        --- @playlist: see acts.createPlaylist() for expected fields
        ---   This may be data returned from an externally-read playlist
        --- @see readPlaylistM3u()
        local pl = createPlaylist(playlist)
    
        mdl.playlist = pl

        setClipToNew()
    end
    
    acts.initializeApp = function()
        local pth = mdl.pthIni
        if not app.utils.fileExists(pth) then 
            writeAppIni(mdl.appCfg, pth)
            return
        end

        local cfg = readAppIni(pth)
        cfg.backupCount = tonumber(cfg.backupCount) or mdl.consts.DEF_BACKUP_COUNT

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
            v.hasEdits, v.isNew = false, false
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
        --- Updates mdl.clip + optionally saves to mdl.playlist
        --- @clipInfo describes a clip; @see acts.createClip()
        --- @asNew true/false mdl.clip is set to a new clip initialized w/ @clipInfo
        --- @saveToList true/false adds-to/updates mdl.playlist
        --- Returns ok, errMsg, clip
        local yn, msg, clip
        if asNew then
            clip = createClip(mdl.clip)
            clip.id, clip.isNew, clip.isInList = genId(), true, false
        else
            clip = mdl.clip
        end
        if not clip then return false, mdl.consts.NO_CLIP end

        local ci = clipInfo

        if not clip.hasEdits then
            clip.hasEdits = (clip.title ~= ci.title)
                or (clip.uri ~= ci.uri)
                or (clip.startTime ~= ci.startTime)
                or (clip.stopTime ~= ci.stopTime)
                or (clip.group ~= ci.group)
        end

        clip.title      = ci.title
        clip.uri        = ci.uri
        clip.startTime  = ci.startTime
        clip.stopTime   = ci.stopTime
        clip.group      = ci.group

        mdl.clip = clip

        yn, msg = clip.isOk()
        if not yn then return yn, msg end

        if saveToList then
            if clip.isNew and not clip.isInList then
                table.insert(mdl.playlist.clips, clip)
                clip.isInList = true
            else
                local k, _ = findClipById(clip.id)
                if k then
                    mdl.playlist.clips[k] = clip 
                else
                    msg = "err: acts.updateClip() clip expected in list but not found"
                    app.utils.dump(clip, msg.."\n========== clip")
                    return false, msg
                end
            end
            if clip.isNew then clip.hasEdits = false end
        end
    
        if mdl.filter then acts.setFilter(mdl.filter) end

        return yn, msg, clip
    end

    acts.deleteClipById = function(clipId)
        local k, v = findClipById(clipId)
        if k then table.remove(mdl.playlist.clips, k) end
        if not v.isNew then mdl.playlist.hasDeletes = true end
        return v
    end

    acts.setFilter = function(regex)
        if regex == "" then acts.clearFilter() return end
        if not mdl.playlist then return end
        
        local clips = {}

        for _, v in pairs(mdl.playlist.clips) do
            if string.find(v.title, regex) then
                table.insert(clips, v)
            end
        end
        mdl.filter = regex
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
    --- note: could be part of createView(); factored out here for convenience
    --- @mdl: (readonly) @see createModel()
    --- @acts: @see createActions()
    --- @vw: (readonly) reference to app.view; @see createView()
    local h = {}
    h.groups, h.groupsByName = {}, {} -- manage entries in ddGroup

    -- internal functions

    local function getTextAsNumber(textBox)
        return tonumber(app.utils.trim2(textBox:get_text()))
    end

    local function initializeDropdownSort()
        for k, v in ipairs(mdl.sortCriteria) do
            vw.ddSort:add_value(v, k) 
        end
    end

    local function showPlaylists(recreate, refetch)
        if recreate then vw.createDropdownPlaylists(recreate) end
        local pls = mdl.appCfg.playlists
        table.sort(pls)
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

    local function showPlaylist()
        --- Shows current playlist
        local function sortByTitle(a, b)
            return a.title < b.title
        end

        local function sortByGroup(a, b)
            return a.group == b.group and a.title < b.title or a.group < b.group
        end

        vw.lstClip:clear()

        local pl = mdl.playlist
        if not pl then h.showMsg(mdl.consts.NO_PLAYLIST, 1) end

        local sortBy = mdl.sortCriteria[vw.ddSort:get_value()]
        if not sortBy then h.showMsg(mdl.consts.BAD_SORT_CRITERIA, 1) return end

        local clips = pl.filteredClips or pl.clips
        local leftPadding = nil

        if sortBy == "byGroup" then
            table.sort(clips, sortByGroup)
            leftPadding = string.rep(" ", 10)
        elseif sortBy == "byTitle" then
            table.sort(clips, sortByTitle)
            leftPadding = string.rep(" ", 5)
        end
        
        local txt = "Playlist"..(pl.isNew and " +" or (pl.hasEdits() and " *") or "")
        vw.lblCaptionPlaylist:set_text(txt)

        vw.lblPlaylist:set_text(pl.path)

        local idxSep = "."
        local idx = 0
        local DEF_GRP_ID = -1
        h.groups, h.groupsByName = {mdl.consts.NONE}, {[mdl.consts.NONE]=true}

        for _, clip in pairs(clips) do
            local clipId, isNewGroup = clip.id, false
            app.utils.dump(clip.title)

            if sortBy == "byGroup" then
                if not h.groupsByName[clip.group] then 
                    table.insert(h.groups, clip.group)
                    h.groupsByName[clip.group] = true
                    idx = 1
    
                    vw.lstClip:add_value(string.rep(".", 10) .. " " .. clip.group, DEF_GRP_ID)
                else
                    idx = idx + 1
                end
            else
                idx = idx + 1
            end

            local leader = string.sub(idx .. idxSep .. leftPadding, 1, string.len(leftPadding))
            local glyphs = (clip.isNew and "+" or "")..(clip.hasEdits and "*" or "")
            local duration = (clip.stopTime or 0) - (clip.startTime or 0)
            txt = leader
                .. ((glyphs ~= "") and (glyphs.." ") or "")
                .. clip.title
                .. (" ["..(clip.group == mdl.consts.NONE and "" or (clip.group.."/"))..duration.."]")


            vw.lstClip:add_value(txt, clipId)
        end

        showGroups(true)
    end

    local function showClipStatus()
        --- show status of current clip
        local c = mdl.clip
        vw.lblCaptionClip:set_text(
            "Clip "
            ..(c.isNew and "+" or "")
            ..(c.hasEdits and "*" or "")
        )
    end

    local function showClip()
        -- show current clip
        local clip = mdl.clip
        if not clip then h.showMsg("* no current clip",1) return end

        vw.lblGroup:set_text(clip.group)
        vw.lblMediaUri:set_text(clip.uri or "")
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
                , uri = vw.lblMediaUri:get_text()
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
        if not pl then h.showMsg("No current playlist") return end
        if not pl.isNew and not pl.hasEdits() then h.showMsg("Playlist has no edits") return end

        acts.savePlaylist()
        showPlaylists(true)
        showPlaylist()
        h.showMsg("playlist saved at " .. os.date('%Y-%m-%d %H:%M:%S'))            
    end

    h.btnPlaylistOpenClick = function()
        local function openPlaylist()
            local k, v = vw.ddPlaylists:get_value()
            if not app.utils.fileExists(v) then h.showMsg("Cannot find "..v,1) return end

            acts.openPlaylist(v)
            showPlaylist()
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
            local msg = "Current playlist ("..f..") has edits. Save?"
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
            showPlaylist()
        end

        local function cbHasEdits(btn)
            if btn == "c" then return end
            if btn == "y" then h.savePlaylist() end
            vw.overlayNewPlaylist(cbNew)
        end

        if mdl.playlist and mdl.playlist.hasEdits() then
            local p, f, e = app.utils.SplitFilename(mdl.playlist.path)
            local msg = "Current playlist ("..f..") has edits. Save?"
            vw.overlayConfirm(msg, cbHasEdits)
        else
            vw.overlayNewPlaylist(cbNew)
        end
    end

    h.btnMediaSelectClick = function()
        local uri = getMediaUriFromPlayer()
        if not uri then h.showMsg(mdl.consts.NO_MEDIA,1) return end
        vw.lblMediaUri:set_text(uri)
    end

    h.btnMediaPlayClick = function()
        local uri = vw.lblMediaUri:get_text()
        if not uri or uri == "" then h.showMsg(mdl.consts.NO_MEDIA, 1) return end

        local itm = {
            path = uri
        }

        vlc.playlist.add({itm})
    end

    h.btnSetGroupClick = function()
        local grpNew, grpDrp, yn = app.utils.trim2(vw.txtGroup:get_text()), -1, false

        if grpNew == "" then
            grpDrp = vw.ddGroups:get_value()
            if grpDrp > 0 and next(h.groups) then
                grpDrp = h.groups[tonumber(grpDrp)]
                yn = true
            end
            if not yn then h.showMsg("Pls enter or select a group", 1) return end
        end
        
        vw.lblGroup:set_text((grpNew ~= "") and grpNew or grpDrp)

        if grpNew ~= "" then
            vw.txtGroup:set_text("")
            if not h.groupsByName[grpNew] then 
                table.insert(h.groups, grpNew)
                h.groupsByName[grpNew] = 1
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
        --- show details of first selected clip
        local clipId = next(vw.lstClip:get_selection())
        if not clipId then h.showMsg(mdl.consts.NO_CLIP_SELECTED, 1) return end
        if clipId < 0 then return end -- it's a group

        acts.setClipById(clipId)
        showClip()
    end

    h.btnClipUpdateClick = function()
        if not mdl.clip then h.showMsg(mdl.consts.NO_CLIP, 1) return end
        local clip, saveToList, asNew = mdl.clip, true, false
        if clip.isNew and not clip.isInList then h.showMsg(mdl.consts.BAD_UPDT_NEWCLIP, 1) return end

        local ok, msg = updateClip(saveToList, asNew)
        if not ok then h.showMsg("Pls check " .. msg, 1) return end
        showPlaylist()
        showClip()
    end

    h.btnClipAddClick = function()
        --- Adds current clip as new item
        if not mdl.playlist then h.showMsg("Pls first open or create a playlist", 1) return end
        local saveToList, asNew = true, true
        local ok, msg, _ = updateClip(saveToList, asNew)
        if not ok then h.showMsg("Pls check " .. msg, 1) return end

        showPlaylist()
        showClip()
    end

    h.btnClipDeleteClick = function()
        local lst = vw.lstClip:get_selection()
        local k = next(lst)
        if not k then h.showMsg(mdl.consts.NO_CLIP_SELECTED, 1) return end

        for k, v in pairs(lst) do
            acts.deleteClipById(k)
        end

        showPlaylist()
    end

    h.btnSortClick = function()
        showPlaylist()
    end

    h.btnFilterClick = function()
        local rgx = app.utils.trim2(vw.txtFilter:get_text())
        if rgx == "" then return end
        acts.setFilter(rgx)
        showPlaylist()
        vw.lblFilter:set_text(rgx)
        vw.lblCaptionFilter:set_text("Filter: *")
    end

    h.btnFilterClearClick = function()
        acts.clearFilter()
        showPlaylist()
        vw.lblFilter:set_text("")
        vw.txtFilter:set_text("")
        vw.lblCaptionFilter:set_text("Filter:")
    end

    h.btnHelpClick = function()
        local html = app.genHelpText(mdl)
        vw.overlayHelp(html)
    end

    h.genTimeSetHandler = function(tb)
        return function()
            local itm = vlc.input.item()
            if not itm then h.showMsg(mdl.consts.NO_MEDIA, 1) return end
    
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
            if not itm then h.showMsg(mdl.consts.NO_MEDIA, 1) return end
    
            local n = getTextAsNumber(tb)
            if not n then h.showMsg(mdl.consts.NO_STOP_TIME, 1) return end
    
            local inp = vlc.object.input()
            vlc.var.set(inp, "time", n * 1000000)
        end
    end

    h.showMsg = function(msg, isErr)
        --- show msg in status-bar
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
        +----------------------------------------------+
        | dialog title                              x  |
        +----------------------------------------------+
        | Playlist    _ _ _ _ _ _ _ _ _ _ _ >save
        |             --------------------v >open >new
        | Clip -----------------------------------------
        | >Media:     _ _ _ _ _ _ _ _ _ _ _ _ _ _ >play
        | clip title  _______________________________
        | group:      _ _ _ _ --------------v _______ >set
        | >start-time _______ >decr   >incr   >seek
        | >stop-time  _______ >decr   >incr   >seek
        | >play       >new    >select >update >add
        | ---------------------------------------------
        | Sort:       ------v >go             >delete
        | Filter:     _______ >go     _ _ _ _
        | +------------------------------------------+
        | | 1. clip-title-1 [group/duration]         |
        | | 2. clip-title-2 [group/duration]         |
        | | ...                                      |
        | +------------------------------------------+
        | {lbl-status}                          >help
        +-----------------------------------------------
    ]]
    local vw = {}
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
        local frame, ok

        local function cbOk()
            for _, v in pairs({ok, frame}) do
                if v then vw.dlg:del_widget(v) end
                isHelpVisible = false
            end
        end

        frame = dlg:add_html(html, 1, lastRow + 1, colspanMax, lastRow)
        ok = dlg:add_button("OK", cbOk, colspanMax, lastRow + 1, 1, 1)
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
    dlg:add_button("Play", h.btnClipPlayClick, 1, row, 1)
    dlg:add_button("New", h.btnClipNewClick, 2, row, 1)
    dlg:add_button("Select", h.btnClipSelectClick, 3, row, 1)
    dlg:add_button("Update", h.btnClipUpdateClick, 4, row, 1)
    dlg:add_button("Add", h.btnClipAddClick, 5, row, 1)

    row = row + 1
    dlg:add_label("<hr>", 1, row, colspanMax, 1)

    row = row + 1
    dlg:add_label("Sort:", 1, row, 1, 1)
    vw.ddSort = dlg:add_dropdown(2, row, 1, 1)
    dlg:add_button("Go", h.btnSortClick, 3, row, 1, 1)
    dlg:add_button("Delete", h.btnClipDeleteClick, 6, row, 1)

    row = row + 1
    vw.lblCaptionFilter = dlg:add_label("Filter:", 1, row, 1, 1)
    vw.txtFilter = dlg:add_text_input("", 2, row, 1, 1)
    dlg:add_button("Go", h.btnFilterClick, 3, row, 1, 1)
    dlg:add_button("Clear", h.btnFilterClearClick, 4, row, 1, 1)
    vw.lblFilter = dlg:add_label("", 5, row, 1, 1)

    row, rowspan = row + 2, 50
    vw.lstClip = dlg:add_list(1, row, colspanMax, rowspan)

    row = row + rowspan
    dlg:add_label("<hr>", 1, row, colspanMax, 1)

    row = row + 1
    vw.lblStatus = dlg:add_label("", 1, row, colspanMax-1, 1)
    dlg:add_button("Help", h.btnHelpClick, colspanMax, row, 1, 1)

    function test()
        app.utils.dump(mdl.pthIni, "mdl.pthIni")
    end
    -- row = row + 1
    --dlg:add_button("Test", test, 1, row, 1, 1)
    lastRow = row


    vw.dlg = dlg

    h.initializeView()

    return vw
end

app.utils = {
    trim2 = function(s)
        --- @see http://lua-users.org/wiki/StringTrim
        return s:match "^%s*(.-)%s*$"
    end

    , fileExists = function(pth)
        local fd = io.open(pth,"r")
        if fd ~= nil then io.close(fd) return true else return false end
    end
    
    , getCurrentDir = function()
        return os.getenv("PWD") or io.popen("cd"):read()
    end

    , copyFile = function(pthSrc, pthDst)
        --- copy [text?]-file from @pthSrc to @pthDst
        --- @pDst ix expected to terminate in a filename
        local fsrc, fdst = io.open(pthSrc, "r")
        if fsrc then
            local txt = fsrc:read("*all")
            fdst = io.open(pthDst, "w+")
            fdst:write(txt)
            fdst:close()
            fsrc:close()
        end
    
    end

    , writeStringsToFile = function(lst, pth, rsep)
        if not rsep then rsep = "\n" end
        local fd = io.open (pth, "w")
        fd:write(table.concat(lst, rsep))
        fd:close()
    end

    , SplitFilename = function(pthFile)
        -- Returns the Path, Filename, and Extension as 3 values
        -- adapted from https://fhug.org.uk/kb/code-snippet/split-a-filename-into-path-file-and-extension/
        local pathSeparator = package and package.config:sub(1,1) or "/"
        if pathSeparator ~= "/" and string.find(pthFile, "/") then pthFile = string.gsub(pthFile, "/", pathSeparator) end
        return string.match(pthFile, "(.-)([^"..pathSeparator.."]-([^"..pathSeparator.."%.]+))$")
    end

    , dump = function(var, msg, indent)
        --- adapted from https://stackoverflow.com/questions/9168058/how-to-dump-a-table-to-console
        -- `indent` sets the initial level of indentation for tables
        if not indent then indent = 0 end
        local print = (vlc and vlc.msg and vlc.msg.dbg) or print
    
        if msg then print(msg) end
    
        if not var then
            print 'var is nil'
    
        elseif type(var) == 'table' then
            for k, v in pairs(var) do
                formatting = string.rep("  ", indent) .. k .. ":"
                if type(v) == "table" then
                    print(formatting)
                    app.utils.dump(v, indent+1)
                elseif type(v) == 'boolean' then
                    print(formatting .. tostring(v))    
                elseif type(v) == 'function' then
                    print(formatting .. type(v))    
                elseif type(v) == 'userdata' then
                    print(formatting .. type(v))   
                else
                    print(formatting .. v)
                end
            end
        else
            print(var)
        end
    end

    , scandir = function(directory, fileSpec)
        --- Finds in @directory files whose names match @fileSpec
        --- @directory path to folder to search
        --- @fileSpec: optional regex of file name
        --- adapted from https://forums.cockos.com/showpost.php?s=4a5518d1e64f5a2786484ca4c5f4dda9&p=1542391&postcount=3
        if not fileSpec then fileSpec = "." end
        local lst = {}
        local cmd = package.config:sub(1,1) == "\\" 
            and 'dir "'..directory..'" /b'
            or 'ls -a "'..directory..'"' -- possibly 'find "' .. directory "" -maxdepth 1 -type f -ls"

        local fd = io.popen(cmd)
        for fileName in fd:lines() do
            if string.find(fileName, fileSpec) then
                table.insert(lst, fileName)
            end
        end
        fd:close()

        return lst
    end

    , createRollingBackup = function(pth, backupCount)
        --- Creates a rolling backup of file indicated by @pth
        --- Backup is named {filename}_bakyyyymmddhhnnss.{ext}
        --- @backupCount: the number of backupCount to keep; default 2
        if not backupCount or not tonumber(backupCount) or tonumber(backupCount) <=0 then backupCount = 2 end
        if backupCount == 0 then return false, "backupCount is 0" end
        if not app.utils.fileExists(pth) then return false, "file-not-found" end

        local p, f, e = app.utils.SplitFilename(pth)

        -- make the backup
        local newName = string.sub(f, 1, string.len(f) - string.len(e) - 1)
            .. "_bak" .. os.date('%Y%m%d%H%M%S')
            .. "." .. e
        app.utils.copyFile(pth, p .. newName)

        -- delete per backupCount    
        local fileSpec = string.sub(f, 1, string.len(f) - string.len(e) - 1) .. "_bak%d+%." .. e
        local lst = app.utils.scandir(p, fileSpec) or {}
        table.sort(lst)

        for idx = backupCount+1, #lst do
            os.remove(p..lst[idx])
        end

        return true
    end
}

app.genHelpText = function(mdl)
    --- Generates text shown in Help
    --- Extracted from createViewHandlers() for convenience
    --- @mdl (readonly) @see createModel()

    local data = {
        mdl = mdl
        , formattedIniPth =  ({app.utils.SplitFilename(mdl.pthIni)})[1]
            .. "<b>" .. ({app.utils.SplitFilename(mdl.pthIni)})[2] .. "</b>"
        , shortdescLcase = mdl.extensionMeta.shortdesc:lower()
        , title = mdl.extensionMeta.title

        , images = app.getImages()
    }


    local function lookup(pth)
        local v = data
        for k in pth:gmatch('[^.]+') do v = v[k] end
        return v
    end        

    local html = [[
        <style>
            * {color:#444;font-family:Verdana;font-size:11pt;}
            kw {font-weight:bold;}
            .title {color:black;font-weight:bold;}
            .panel{border:1px solid grey;padding:20px;}
            .secn {color:black;display:block;font-weight:bold;}
            .sep {margin-bottom:25px;}
        </style>
        <div class="panel">
            <br/>
            <p><span class="title">{=title}</span> (v{=mdl.extensionMeta.version}): {=shortdescLcase}</p>
            <p>{=mdl.extensionMeta.description}</p>

            <p>Usage should be discoverable, if not immediately intuitive due limitations
            of the default UI widgets in Lua extensions (at least best I can tell).
            For example, to edit an element in a list we'd usually just double-click it
            to indicate selection + edit; here lacking a readily usable click event we
            click the element in the list, then click a Select button to act on it.</p>
            
            <p> Please file bugs, suggestions, etc at <a href="{=mdl.extensionMeta.url}/issues">
            {=mdl.extensionMeta.url}/issues</a>
            
            <p>A short usage guide follows.</p>

            <p><span class="secn">Extension settings</span>
                <p>Extension settings are saved in an ini-file in VLC's "userdatadir"
                ({=formattedIniPth}). If you haven't already created an ini-file, one will be
                created the first time a playlist is saved. Available settings are:</p>

                <ul>
                    <li><kw>backupCount</kw>=number of backups to keep when saving a playlist;
                    defaults to {=mdl.consts.DEF_BACKUP_COUNT}</li>
                    <li><kw>playlistFolder</kw>=path to folder to which to save new playlists by default;
                    e.g. playlistFolder=C:\projects\playlists</li>
                    <li><kw>playlist</kw>=path to m3u file; can have multiple "playlist" entries,
                    each pointing to a different m3u file; e.g.
                    <br/>playList=C:\projects\playlists\fancy-kookery-techniques.m3u</li>
                    <br/>playList=C:\projects\playlists\fancier-kookery-techniques.m3u</li>
                </ul>

                <p>NB: pls don't add settings other than the above; they will be overwritten on save.</p>
            </p>

            <p><span class="secn">Creating your first playlist</span>
                <ol>
                    <li>open a media file in vlc; you can pause it, or leave it playing</li>
                    <li class="sep">start {=mdl.extensionMeta.title}
                    (in VLC click menu/{=mdl.extensionMeta.shortdesc})</li>
                
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
                    <li>to test the clip, click Play at bottom left of the Clip section.
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
                        file, and updates the ini-file so the next time you open {=title} the
                        playlist will appear in the playlists dropdown</li>
                </ol>
            </p>

            <p><span class="secn">Miscellaneous notes</span>
                <ul>
                    <li>currently start/stop times have a resolution of 1 second</li>
                    <li>similar to the Start-time/Stop-time buttons, the Media button gets the
                    current media uri from VLC</li>
                    <li>the Play button across from the Media button plays the media in its entirety,
                    without regard to start/stop times. You can still use the Clip section's +/-/Seek
                    buttons to scrub around. Use this when you're playing a clip, then realize you
                    want to play farther out that its stop-time</li>
                    <li>if you haven't set <kw>playlistFolder</kw> in the ini-file, it will default to
                    the folder of the first saved playlist</li>
                    <li>after a playlist is saved, any info in the Clip section is considered "new";
                    this avoids thence updating an incorrect clip (due how we manage clip ids).</li>
                    <li>currently there are no facilities to delete playlists, or to open playlists
                    not previously created by {=title}; to do so pls edit the ini-file directly</li>
                </ul>
            </p>

            <p><span class="secn">About</span>
                <br/>{=title}
                <br/>Version: {=mdl.extensionMeta.version}
                <br/>Url: {=mdl.extensionMeta.url}
                <br/>Copyright: {=mdl.extensionMeta.copyright}
                <br/>Tested environments: {=mdl.extensionMeta.testedEnvironments}
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
    return {
        ["pnlNewPlaylist"] = "data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9Im5vIj8+PCFET0NUWVBFIHN2ZyBQVUJMSUMgIi0vL1czQy8vRFREIFNWRyAxLjEvL0VOIiAiaHR0cDovL3d3dy53My5vcmcvR3JhcGhpY3MvU1ZHLzEuMS9EVEQvc3ZnMTEuZHRkIj4NCjxzdmcgd2lkdGg9IjEwMCUiIGhlaWdodD0iMTAwJSIgdmlld0JveD0iMCAwIDQ4NCA5MCIgdmVyc2lvbj0iMS4xIg0KICAgIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyINCiAgICB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayIgeG1sOnNwYWNlPSJwcmVzZXJ2ZSINCiAgICB4bWxuczpzZXJpZj0iaHR0cDovL3d3dy5zZXJpZi5jb20vIiBzdHlsZT0iZmlsbC1ydWxlOmV2ZW5vZGQ7Y2xpcC1ydWxlOmV2ZW5vZGQ7c3Ryb2tlLWxpbmVjYXA6cm91bmQ7c3Ryb2tlLWxpbmVqb2luOnJvdW5kO3N0cm9rZS1taXRlcmxpbWl0OjEuNTsiPg0KICAgIDxzdHlsZSB0eXBlPSJ0ZXh0L2NzcyI+PCFbQ0RBVEFbDQogICAgLkJHe2ZpbGw6I0YwRjBGMDtzdHJva2U6bm9uZTt9DQogICAgLkNUTHtmaWxsOiNFMUUxRTE7c3Ryb2tlOiNBREFEQUQ7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLkZ7Zm9udC1mYW1pbHk6J0FyaWFsTVQnLCAnQXJpYWwnLCBzYW5zLXNlcmlmO2ZvbnQtc2l6ZToxMHB4O30NCiAgICAuTHtmaWxsOm5vbmU7c3Ryb2tlOiMwMDA7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLk9Ge2ZpbGw6I2YzODAwMDtzdHJva2U6I2YzODAwMDtzdHJva2Utd2lkdGg6MC43NXB4O30NCiAgICAuVEJ7ZmlsbDojRkZGO3N0cm9rZTojN0E3QTdBO3N0cm9rZS13aWR0aDowLjc1cHg7fQ0KXV0+PC9zdHlsZT4NCg0KICAgIDxyZWN0IGNsYXNzPSJCRyIgeD0iMCIgeT0iMjciIHdpZHRoPSI0ODMiIGhlaWdodD0iNjIiLz4NCiAgICA8cmVjdCBpZD0iYm9yZGVyIiB4PSIwLjM3NSIgeT0iMC4zNzUiIHdpZHRoPSI0ODIuOTg0IiBoZWlnaHQ9Ijg5LjI1IiBjbGFzcz0iTCIvPg0KICAgIDxnIGlkPSJ0aXRsZWJhciI+DQogICAgICAgIDxwYXRoIGlkPSJzeXMiIGNsYXNzPSJMIiBkPSJNNDI3LjQxMSwxMC43MjhsMCw2Ljg3NWw2LjUsLTBsMC4yNSwtNi44NzVsLTYuNzUsLTBabS0zMywzLjQzN2w2LDBtNjEuNSwtMy40MzdsNy4yNSw2Ljg3NW0wLC02Ljg3NWwtNi4yNSw2Ljg3NSIvPg0KICAgICAgICA8ZyBpZD0ibG9nbyI+DQogICAgICAgICAgICA8cGF0aCBkPSJNOS42MTEsMTUuNjYybC0xLjA4NiwwbC0xLjAyOSw0LjM0M2wxMC44LDAuMDczbC0wLjk1MiwtNC40MTZsLTEuMjM5LDBjMCwwIC0xLjEwNCwxLjc0MSAtMi45NTUsMS43NzNjLTIuNDIsMC4wNDMgLTMuNTM5LC0xLjc3MyAtMy41MzksLTEuNzczWiIgY2xhc3M9Ik9GIi8+DQogICAgICAgICAgICA8cGF0aCBkPSJNOS43MzksMTYuMTFsLTAuMzkzLDEuNTE3Yy0wLDAgMS4wMzksMS4wNjUgMy42MDgsMS4wMTVjMi41MDksLTAuMDUgMy43MSwtMS4zMjYgMy43MSwtMS4zMjZsLTAuNTA2LC0xLjI5NiIgc3R5bGU9ImZpbGw6bm9uZTtzdHJva2U6I2FjNDAwMDtzdHJva2Utd2lkdGg6MC40NnB4OyIvPg0KICAgICAgICAgICAgPHBhdGggZD0iTTExLjIyNSwxMi4wNDhsMy4zMzQsLTAuMDI4bDAuNjUyLDIuMTQ1bC00LjUxNSwtMGwwLjUyOSwtMi4xMTdaIiBjbGFzcz0iT0YiLz4NCiAgICAgICAgICAgIDxwYXRoIGQ9Ik05Ljg4OSwxNS42NjJsMS44NTUsLTYuMjg1bTQuMjUsNi4yODVsLTIuMDQsLTYuMjg1IiBzdHlsZT0iZmlsbDpub25lO3N0cm9rZTojYjBiNGI3O3N0cm9rZS13aWR0aDowLjQ2cHg7Ii8+DQogICAgICAgICAgICA8cGF0aCBkPSJNMTIuMjk2LDcuMzA3bDEuMTQzLDBsMC41MTUsMi4wN2wtMi4yMSwtMC4wMDFsMC41NTIsLTIuMDY5WiIgY2xhc3M9Ik9GIi8+DQogICAgICAgIDwvZz4NCiAgICAgICAgPHRleHQgeD0iMjEuNTkycHgiIHk9IjE4LjQwN3B4IiBjbGFzcz0iRiI+VmNsaXBNYW5nbGVyPC90ZXh0Pg0KICAgIDwvZz4NCiAgICA8ZyAgPg0KICAgICAgICA8cmVjdCB4PSI4Ljk2OSIgeT0iMzEuOTczIiB3aWR0aD0iNDY0LjA0OSIgaGVpZ2h0PSI1My4wNTUiIGNsYXNzPSJUQiIvPg0KICAgICAgICA8cmVjdCB4PSI4Ljk2OSIgeT0iNjYuMDk4IiB3aWR0aD0iMjk5LjQyNCIgaGVpZ2h0PSIxNS4zNjgiIGNsYXNzPSJUQiIvPg0KICAgICAgICA8cmVjdCB4PSIzMTUuMTU2IiB5PSI2Ni4wOTgiIHdpZHRoPSI5OC4wNDkiIGhlaWdodD0iMTUuMzY4IiBjbGFzcz0iQ1RMIi8+DQogICAgICAgIDxyZWN0IHg9IjQxOC4wOTQiIHk9IjY2LjA5OCIgd2lkdGg9IjU0LjkyNCIgaGVpZ2h0PSIxNS4zNjgiIGNsYXNzPSJDVEwiLz4NCg0KICAgICAgICA8dGV4dCB4PSIxMS44NDJweCIgeT0iNDQuNjU3cHgiIGNsYXNzPSJGIj5FbnRlciBmdWxsIHBhdGggdG8gbTN1IHBsYXlsaXN0IHRvIGNyZWF0ZTo8L3RleHQ+DQogICAgICAgIDx0ZXh0IHg9IjExLjg0MnB4IiB5PSI3OS4zNjJweCIgY2xhc3M9IkYiPkM6XFByb2plY3RzXHBsYXlsaXN0c1xteS3vrIFyc3QtcGxheWxpc3QubTN1PC90ZXh0Pg0KICAgICAgICA8dGV4dCB4PSIzNTYuNzI0cHgiIHk9Ijc3LjM2NHB4IiBjbGFzcz0iRiI+T0s8L3RleHQ+DQogICAgICAgIDx0ZXh0IHg9IjQzMC40MTJweCIgeT0iNzcuMzY0cHgiIGNsYXNzPSJGIj5DYW5jZWw8L3RleHQ+DQogICAgPC9nPg0KPC9zdmc+DQoNCg=="
        , ["secnClip"] = "data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9Im5vIj8+PCFET0NUWVBFIHN2ZyBQVUJMSUMgIi0vL1czQy8vRFREIFNWRyAxLjEvL0VOIiAiaHR0cDovL3d3dy53My5vcmcvR3JhcGhpY3MvU1ZHLzEuMS9EVEQvc3ZnMTEuZHRkIj4NCjxzdmcgd2lkdGg9IjEwMCUiIGhlaWdodD0iMTAwJSIgdmlld0JveD0iMCAwIDQ4NCAxNTEiIHZlcnNpb249IjEuMSINCiAgICB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciDQogICAgeG1sbnM6eGxpbms9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGxpbmsiIHhtbDpzcGFjZT0icHJlc2VydmUiDQogICAgeG1sbnM6c2VyaWY9Imh0dHA6Ly93d3cuc2VyaWYuY29tLyIgc3R5bGU9ImZpbGwtcnVsZTpldmVub2RkO2NsaXAtcnVsZTpldmVub2RkO3N0cm9rZS1saW5lY2FwOnJvdW5kO3N0cm9rZS1saW5lam9pbjpyb3VuZDtzdHJva2UtbWl0ZXJsaW1pdDoxLjU7Ij4NCiAgICA8c3R5bGUgdHlwZT0idGV4dC9jc3MiPjwhW0NEQVRBWw0KICAgIC5Ge2ZvbnQtZmFtaWx5OidBcmlhbE1UJywgJ0FyaWFsJywgc2Fucy1zZXJpZjtmb250LXNpemU6MTBweDt9DQogICAgLkx7ZmlsbDpub25lO3N0cm9rZTojMDAwO3N0cm9rZS13aWR0aDowLjc1cHg7fQ0KICAgIC5CR3tmaWxsOiNGMEYwRjA7c3Ryb2tlOm5vbmU7fQ0KICAgIC5UQntmaWxsOiNGRkY7c3Ryb2tlOiM3QTdBN0E7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLkNUTHtmaWxsOiNFMUUxRTE7c3Ryb2tlOiNBREFEQUQ7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQpdXT48L3N0eWxlPg0KICAgIDxyZWN0IHg9IjAiIHk9IjAiIHdpZHRoPSI0ODMiIGhlaWdodD0iMTUyIiBjbGFzcz0iQkciLz4NCg0KICAgIDxyZWN0IHg9IjE5Mi44NzUiIHk9IjU2LjcyMSIgd2lkdGg9IjExNSIgaGVpZ2h0PSIxNi41IiBjbGFzcz0iQ1RMIi8+DQogICAgPHBhdGggZD0iTTMwMC4wMzQsNjguNzgybDMuMzA4LC01LjY3M2wtNi42MTUsLTBsMy4zMDcsNS42NzNaIiBzdHlsZT0ic3Ryb2tlOiMwMDA7c3Ryb2tlLXdpZHRoOjAuNzVweDsiLz4NCg0KDQoNCiAgICA8cmVjdCB4PSIzMTQuNjI1IiB5PSI1Ny41OTYiIHdpZHRoPSI5Ny41IiBoZWlnaHQ9IjE2LjUiIGNsYXNzPSJUQiIvPg0KICAgIDxyZWN0IHg9IjMxNC42MjUiIHk9Ijc5LjkwNyIgd2lkdGg9Ijk3LjUiIGhlaWdodD0iMTYuNSIgY2xhc3M9IkNUTCIvPg0KICAgIDxyZWN0IHg9IjMxNC42MjUiIHk9IjEwMC40MDciIHdpZHRoPSI5Ny41IiBoZWlnaHQ9IjE2LjUiIGNsYXNzPSJDVEwiLz4NCiAgICA8cmVjdCB4PSIzMTQuNjI1IiB5PSIxMjIuNDA3IiB3aWR0aD0iOTcuNSIgaGVpZ2h0PSIxNi41IiBjbGFzcz0iQ1RMIi8+DQogICAgPHJlY3QgeD0iMTkzLjU5MiIgeT0iNzkuOTA3IiB3aWR0aD0iNTQiIGhlaWdodD0iMTYuNSIgY2xhc3M9IkNUTCIvPg0KICAgIDxyZWN0IHg9IjI1NC4wOTIiIHk9Ijc5LjkwNyIgd2lkdGg9IjU0IiBoZWlnaHQ9IjE2LjUiIGNsYXNzPSJDVEwiLz4NCg0KICAgIDxyZWN0IHg9IjI1NC4wOTIiIHk9IjEwMC40MDciIHdpZHRoPSI1NCIgaGVpZ2h0PSIxNi41IiBjbGFzcz0iQ1RMIi8+DQogICAgPHJlY3QgeD0iMjU0LjA5MiIgeT0iMTIyLjQwNyIgd2lkdGg9IjU0IiBoZWlnaHQ9IjE2LjUiIGNsYXNzPSJDVEwiLz4NCiAgICA8cmVjdCB4PSIxOTMuNTkyIiB5PSIxMDAuNDA3IiB3aWR0aD0iNTQiIGhlaWdodD0iMTYuNSIgY2xhc3M9IkNUTCIvPg0KICAgIDxyZWN0IHg9IjE5My41OTIiIHk9IjEyMi40MDciIHdpZHRoPSI1NCIgaGVpZ2h0PSIxNi41IiBjbGFzcz0iQ1RMIi8+DQogICAgPHJlY3QgeD0iNDE4LjEyNSIgeT0iMTUuNDcxIiB3aWR0aD0iNTQuNzUiIGhlaWdodD0iMTQuMjUiIGNsYXNzPSJDVEwiLz4NCiAgICA8cmVjdCB4PSI0MTkuNjI1IiB5PSI1OC45NzEiIHdpZHRoPSI1NC43NSIgaGVpZ2h0PSIxNC4yNSIgY2xhc3M9IkNUTCIvPg0KICAgIDxyZWN0IHg9IjcwLjA5MiIgeT0iNzkuOTA3IiB3aWR0aD0iMTE3IiBoZWlnaHQ9IjE2LjUiIGNsYXNzPSJUQiIvPg0KICAgIDxyZWN0IHg9IjcwLjA5MiIgeT0iMTAwLjQwNyIgd2lkdGg9IjExNyIgaGVpZ2h0PSIxNi41IiBjbGFzcz0iVEIiLz4NCiAgICA8cmVjdCB4PSI3MC4wOTIiIHk9IjEyMi40MDciIHdpZHRoPSIxMTciIGhlaWdodD0iMTYuNSIgY2xhc3M9IkNUTCIvPg0KICAgIDxyZWN0IHg9IjEwLjEyNSIgeT0iMTUuNDcxIiB3aWR0aD0iNTMuMjUiIGhlaWdodD0iMTUuNzUiIGNsYXNzPSJDVEwiLz4NCiAgICA8cmVjdCB4PSIxMC4xMjUiIHk9IjgxLjQ3MSIgd2lkdGg9IjUzLjI1IiBoZWlnaHQ9IjE1Ljc1IiBjbGFzcz0iQ1RMIi8+DQogICAgPHJlY3QgeD0iMTAuMTI1IiB5PSIxMDMuMjIxIiB3aWR0aD0iNTMuMjUiIGhlaWdodD0iMTUuNzUiIGNsYXNzPSJDVEwiLz4NCiAgICA8cmVjdCB4PSIxMC4xMjUiIHk9IjEyMi43ODIiIHdpZHRoPSI1My4yNSIgaGVpZ2h0PSIxNS43NSIgY2xhc3M9IkNUTCIvPg0KICAgIDxyZWN0IHg9IjY5LjM3NSIgeT0iMzcuOTcxIiB3aWR0aD0iNDAzLjUiIGhlaWdodD0iMTMuNSIgY2xhc3M9IlRCIi8+DQoNCiAgICA8cGF0aCBkPSJNMTAuMTI1LDE0OC40MDdsNDYzLjQ2NywtMCIgY2xhc3M9IkwiLz4NCiAgICA8cGF0aCBkPSJNNjkuMTI1LDUuMDc3bDQwNC40NjcsMCIgY2xhc3M9IkwiLz4gICAgDQogICAgPHBhdGggZD0iTTAsMGwwLDE1MC43NSIgY2xhc3M9IkwiLz4NCiAgICA8cGF0aCBkPSJNNDgzLjc1LDBsMCwxNTAuNzUiIGNsYXNzPSJMIi8+DQoNCiAgICA8dGV4dCB4PSIyNzguNDYxcHgiIHk9IjExMS44NjhweCIgY2xhc3M9IkYiPi08L3RleHQ+DQogICAgPHRleHQgeD0iMjE4Ljg5OXB4IiB5PSIxMTEuODY4cHgiIGNsYXNzPSJGIj4tPC90ZXh0Pg0KICAgIDx0ZXh0IHg9IjI3OC40NjFweCIgeT0iOTEuODAzcHgiIGNsYXNzPSJGIj4rPC90ZXh0Pg0KICAgIDx0ZXh0IHg9IjIxOC44OTlweCIgeT0iOTEuODAzcHgiIGNsYXNzPSJGIj4rPC90ZXh0Pg0KICAgIDx0ZXh0IHg9IjkuMzU0cHgiIHk9IjkuNjQ5cHgiIGNsYXNzPSJGIj5DbGlwPC90ZXh0Pg0KICAgIDx0ZXh0IHg9IjQzNy40MzhweCIgeT0iNjkuOTI1cHgiIGNsYXNzPSJGIj5TZXQ8L3RleHQ+DQogICAgPHRleHQgeD0iNDM3LjQzOHB4IiB5PSIyNy41ODZweCIgY2xhc3M9IkYiPlBsYXk8L3RleHQ+DQogICAgPHRleHQgeD0iMzUxLjY4OHB4IiB5PSI5MS45MjVweCIgY2xhc3M9IkYiPlNlZWs8L3RleHQ+DQogICAgPHRleHQgeD0iMzUxLjY4OHB4IiB5PSIxMTEuOTI1cHgiIGNsYXNzPSJGIj5TZWVrPC90ZXh0Pg0KICAgIDx0ZXh0IHg9IjM1NS40MzhweCIgeT0iMTM0LjE4NHB4IiBjbGFzcz0iRiI+QWRkPC90ZXh0Pg0KICAgIDx0ZXh0IHg9IjIwNi43MTFweCIgeT0iMTM0LjE4NHB4IiBjbGFzcz0iRiI+U2VsZWN0PC90ZXh0Pg0KICAgIDx0ZXh0IHg9IjExNy40NjFweCIgeT0iMTM0LjE4NHB4IiBjbGFzcz0iRiI+TmV3PC90ZXh0Pg0KICAgIDx0ZXh0IHg9IjI2LjcxMXB4IiB5PSIxMzQuMTg0cHgiIGNsYXNzPSJGIj5QbGF5PC90ZXh0Pg0KICAgIDx0ZXh0IHg9IjE0LjcxMXB4IiB5PSIxMTQuMTg0cHgiIGNsYXNzPSJGIj5TdG9wLXRpbWU8L3RleHQ+DQogICAgPHRleHQgeD0iMTQuNzExcHgiIHk9IjkyLjY4NHB4IiBjbGFzcz0iRiI+U3RhcnQtdGltZTwvdGV4dD4NCiAgICA8dGV4dCB4PSIyMS40NjFweCIgeT0iMjYuNzE0cHgiIGNsYXNzPSJGIj5NZWRpYTwvdGV4dD4NCiAgICA8dGV4dCB4PSIyNjQuMjExcHgiIHk9IjEzNC4xODRweCIgY2xhc3M9IkYiPlVwZGF0ZTwvdGV4dD4NCiAgICA8dGV4dCB4PSI5LjU5M3B4IiB5PSI0OC4xMTZweCIgY2xhc3M9IkYiPkNsaXAgdGl0bGU6PC90ZXh0Pg0KICAgIDx0ZXh0IHg9IjkuNTkzcHgiIHk9IjY5LjYxNnB4IiBjbGFzcz0iRiI+R3JvdXA6PC90ZXh0Pg0KPC9zdmc+"
        , ["secnPlaylist"] = "data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0iVVRGLTgiIHN0YW5kYWxvbmU9Im5vIj8+PCFET0NUWVBFIHN2ZyBQVUJMSUMgIi0vL1czQy8vRFREIFNWRyAxLjEvL0VOIiAiaHR0cDovL3d3dy53My5vcmcvR3JhcGhpY3MvU1ZHLzEuMS9EVEQvc3ZnMTEuZHRkIj4NCjxzdmcgd2lkdGg9IjEwMCUiIGhlaWdodD0iMTAwJSIgdmlld0JveD0iMCAwIDQ4NCA4NiIgdmVyc2lvbj0iMS4xIg0KICAgIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyINCiAgICB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayIgeG1sOnNwYWNlPSJwcmVzZXJ2ZSINCiAgICB4bWxuczpzZXJpZj0iaHR0cDovL3d3dy5zZXJpZi5jb20vIiBzdHlsZT0iZmlsbC1ydWxlOmV2ZW5vZGQ7Y2xpcC1ydWxlOmV2ZW5vZGQ7c3Ryb2tlLWxpbmVjYXA6cm91bmQ7c3Ryb2tlLWxpbmVqb2luOnJvdW5kO3N0cm9rZS1taXRlcmxpbWl0OjEuNTsiPg0KICAgIDxzdHlsZSB0eXBlPSJ0ZXh0L2NzcyI+PCFbQ0RBVEFbDQogICAgLkJHe2ZpbGw6I0YwRjBGMDtzdHJva2U6bm9uZTt9DQogICAgLkNUTHtmaWxsOiNFMUUxRTE7c3Ryb2tlOiNBREFEQUQ7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLkREQXtmaWxsOiMwMDA7c3Ryb2tlOiMwMDA7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLkZ7Zm9udC1mYW1pbHk6J0FyaWFsTVQnLCAnQXJpYWwnLCBzYW5zLXNlcmlmO2ZvbnQtc2l6ZToxMHB4O30NCiAgICAuTHtmaWxsOm5vbmU7c3Ryb2tlOiMwMDA7c3Ryb2tlLXdpZHRoOjAuNzVweDt9DQogICAgLk9Ge2ZpbGw6I2YzODAwMDtzdHJva2U6I2YzODAwMDtzdHJva2Utd2lkdGg6MC43NXB4O30NCl1dPjwvc3R5bGU+DQogICAgPHJlY3QgY2xhc3M9IkJHIiB4PSIwIiB5PSIyNyIgd2lkdGg9IjQ4MyIgaGVpZ2h0PSI1NyIvPg0KICAgIDxwYXRoIGlkPSJib3JkZXIiIGNsYXNzPSJMIiBkPSJNMC4zNzUsODEuNTc3bDAsLTgxLjU3N2w0ODIuOTg0LDBsLTAsODEuNTc3Ii8+DQogICAgPGcgaWQ9InRpdGxlYmFyIj4NCiAgICAgICAgPHBhdGggaWQ9InN5cyIgY2xhc3M9IkwiIGQ9Ik00MjcuNDExLDEwLjcyOGwwLDYuODc1bDYuNSwtMGwwLjI1LC02Ljg3NWwtNi43NSwtMFptLTMzLDMuNDM3bDYsMG02MS41LC0zLjQzN2w3LjI1LDYuODc1bTAsLTYuODc1bC02LjI1LDYuODc1Ii8+DQogICAgICAgIDxnIGlkPSJsb2dvIj4NCiAgICAgICAgICAgIDxwYXRoIGQ9Ik05LjYxMSwxNS42NjJsLTEuMDg2LDBsLTEuMDI5LDQuMzQzbDEwLjgsMC4wNzNsLTAuOTUyLC00LjQxNmwtMS4yMzksMGMwLDAgLTEuMTA0LDEuNzQxIC0yLjk1NSwxLjc3M2MtMi40MiwwLjA0MyAtMy41MzksLTEuNzczIC0zLjUzOSwtMS43NzNaIiBjbGFzcz0iT0YiLz4NCiAgICAgICAgICAgIDxwYXRoIGQ9Ik05LjczOSwxNi4xMWwtMC4zOTMsMS41MTdjLTAsMCAxLjAzOSwxLjA2NSAzLjYwOCwxLjAxNWMyLjUwOSwtMC4wNSAzLjcxLC0xLjMyNiAzLjcxLC0xLjMyNmwtMC41MDYsLTEuMjk2IiBzdHlsZT0iZmlsbDpub25lO3N0cm9rZTojYWM0MDAwO3N0cm9rZS13aWR0aDowLjQ2cHg7Ii8+DQogICAgICAgICAgICA8cGF0aCBkPSJNMTEuMjI1LDEyLjA0OGwzLjMzNCwtMC4wMjhsMC42NTIsMi4xNDVsLTQuNTE1LC0wbDAuNTI5LC0yLjExN1oiIGNsYXNzPSJPRiIvPg0KICAgICAgICAgICAgPHBhdGggZD0iTTkuODg5LDE1LjY2MmwxLjg1NSwtNi4yODVtNC4yNSw2LjI4NWwtMi4wNCwtNi4yODUiIHN0eWxlPSJmaWxsOm5vbmU7c3Ryb2tlOiNiMGI0Yjc7c3Ryb2tlLXdpZHRoOjAuNDZweDsiLz4NCiAgICAgICAgICAgIDxwYXRoIGQ9Ik0xMi4yOTYsNy4zMDdsMS4xNDMsMGwwLjUxNSwyLjA3bC0yLjIxLC0wLjAwMWwwLjU1MiwtMi4wNjlaIiBjbGFzcz0iT0YiLz4NCiAgICAgICAgPC9nPg0KICAgICAgICA8dGV4dCB4PSIyMS41OTJweCIgeT0iMTguNDA3cHgiIGNsYXNzPSJGIj5WY2xpcE1hbmdsZXI8L3RleHQ+DQogICAgPC9nPg0KDQogICAgPHJlY3QgeD0iNjkuMzc1IiB5PSI1Ny4wOTYiIHdpZHRoPSIyMzguNSIgaGVpZ2h0PSIxNi41IiBpZD0iZGQiIGNsYXNzPSJDVEwiLz4NCiAgICA8cGF0aCBkPSJNMzAwLjAzNCw2OS4yOTZsMy4zMDgsLTUuNjczbC02LjYxNSwtMGwzLjMwNyw1LjY3M1oiIGNsYXNzPSJEREEiLz4NCiAgICA8cmVjdCB4PSIzMTQuNjI1IiB5PSIzNC45NzEiIHdpZHRoPSI5Ny41IiBoZWlnaHQ9IjE2LjUiIGNsYXNzPSJDVEwiLz4NCiAgICA8cmVjdCB4PSIzMTQuNjI1IiB5PSI1Ny4wOTYiIHdpZHRoPSI5Ny41IiBoZWlnaHQ9IjE2LjUiIGNsYXNzPSJDVEwiLz4NCiAgICA8cmVjdCB4PSI0MTguMTI1IiB5PSI1OC4yMjEiIHdpZHRoPSI1NC43NSIgaGVpZ2h0PSIxNC4yNSIgY2xhc3M9IkNUTCIvPg0KDQogICAgPHRleHQgeD0iMTAuMDgxcHgiIHk9IjQ1Ljk2NHB4IiBjbGFzcz0iRiI+UGxheWxpc3Q8L3RleHQ+DQogICAgPHRleHQgeD0iMzUxLjY4OHB4IiB5PSI0NS45NjRweCIgY2xhc3M9IkYiPlNhdmU8L3RleHQ+DQogICAgPHRleHQgeD0iMzUxLjY4OHB4IiB5PSI2OC45MjVweCIgY2xhc3M9IkYiPk9wZW48L3RleHQ+DQogICAgPHRleHQgeD0iNDM3LjQzOHB4IiB5PSI2OC45MnB4IiBjbGFzcz0iRiI+TmV3PC90ZXh0Pg0KDQogICAgPHBhdGggZD0iTTE1LjU3Nyw4MC43NjhjLTEuOTgsLTIuMzQgLTQuNTYsLTEuMjYyIC01LjI4LDAuODA5IiBjbGFzcz0iTCIvPg0KICAgIA0KICAgIDxwYXRoIGQ9Ik0xNy41NTcsNzguODY5bC0wLjA2LDIuNzA4IiBjbGFzcz0iTCIvPg0KICAgIDxwYXRoIGQ9Ik0xOS43NzcsNzguODY5bC0wLDAuNTc3IiBjbGFzcz0iTCIvPg0KICAgIDxwYXRoIGQ9Ik0xOS43NzcsODAuNTExbC0wLDEuMDY2IiBjbGFzcz0iTCIvPg0KICAgIDxwYXRoIGQ9Ik0yMS42MzYsODEuMDQ0bDMuNjAxLDAiIGNsYXNzPSJMIi8+DQoNCiAgICA8cGF0aCBkPSJNNjkuMTI1LDgxLjU3N2w0MDQuNDY3LDAiIGNsYXNzPSJDVEwiLz4NCjwvc3ZnPg=="
    }
end

return app
