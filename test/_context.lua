local utils = require("_utils")

local ctx = {
    pathSeparator = package and package.config:sub(1,1) or "/"
    , vlc = {
        config = { 
            userdatadir = function() 
                return utils.getCurrentDir()
            end
        }
        , msg = {
            err = print
        }
    }
}

return ctx