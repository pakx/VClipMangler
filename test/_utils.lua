--- convenience utils for testing

local utils = {

    createFolder = function(pth)
        return os.execute("mkdir \"" .. pth .. "\"")
    end
    
    , deleteFolder = function(pth)
        --- Note: Windows
        return os.execute("rmdir \"" .. pth .. "\"")
    end

    , escapeBackslash = function(txt)
        return string.gsub(txt, "\\", "\\\\")
    end

    , getCurrentDir = function()
        return os.getenv("PWD") or io.popen("cd"):read()
    end

    , readFile = function(pth)
        local fd = assert(io.open(pth, "r"))
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
}

utils.dump = function(var, msg, indent)
    --- adapted from https://stackoverflow.com/questions/9168058/how-to-dump-a-table-to-console
    -- `indent` sets the initial level of indentation for tables
    if not indent then indent = 0 end
    local print = (vlc and vlc.msg and vlc.msg.dbg) or print

    if msg then print(msg) end

    if not var then
        print 'var is nil'

    elseif type(var) == 'table' then
        for k, v in pairs(var) do
            local formatting = string.rep("  ", indent) .. k .. ":"
            if type(v) == "table" then
                print(formatting)
                utils.dump(v, indent+1)
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

return utils