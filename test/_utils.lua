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

return utils