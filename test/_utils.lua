--- convenience utils for testing

local utils = {

    copyFile = function(pthSrc, pthDst)
        --- copy [text?]-file from @pthSrc to @pthDst
        --- @pDst ix expected to terminate in a filename
        local fsrc = io.open(pthSrc, "r")
        local fdst = io.open(pthDst, "w+")
        fdst:write(fsrc:read("*all"))
        fdst:close()
        fsrc:close()
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
                    dump(v, indent+1)
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

    , escapeBackslash = function(txt)
        return string.gsub(txt, "\\", "\\\\")
    end

    , fileExists = function(pth)
        local fd = io.open(pth,"r")
        if fd ~= nil then io.close(fd) return true else return false end
    end
    
    , getCurrentDir = function()
        return os.getenv("PWD") or io.popen("cd"):read()
    end

    , lstToFile = function(lst, pth, rsep)
        --- Writes @lst of strings, soncatenated w/ @rsep, to @pth
        if not rsep then rsep = "\n" end
        local fd = io.open (pth, "w")
        fd:write(table.concat(lst, rsep))
        fd:close()
    end

    , readFile = function(pth)
        local fd = io.open(pth, "r")
        local txt = fd:read("*all")
        fd:close()
        return txt
    end

    , runStrings = function(lst, env, testRunner)
        --- @lst table of strings to run
        --- @env environment to use
        for _, v in ipairs(lst) do
            local txt = "return " .. v
            local fn = assert(loadstring(txt))
            setfenv(fn, env)
    
            testRunner.failIf(not fn(), "expected: " .. v)
        end
    end

    , trim2 = function(s)
        --- @see http://lua-users.org/wiki/StringTrim
        return s:match "^%s*(.-)%s*$"
    end
    
    , SplitFilename = function(strFilename)
        -- adapted from https://fhug.org.uk/kb/code-snippet/split-a-filename-into-path-file-and-extension/
        -- Returns the Path, Filename, and Extension as 3 values
        local pathSeparator = package and package.config:sub(1,1) or "/"
        return string.match(strFilename, "(.-)([^"..pathSeparator.."]-([^"..pathSeparator.."%.]+))$")
    end

}

return utils