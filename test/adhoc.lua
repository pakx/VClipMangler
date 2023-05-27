local utils = require("_utils")

package.path = package.path .. ";" .. utils.getCurrentDir().."/.." .."/?.lua"
local app = require("VclipMangler")
local apputils = app.utils
