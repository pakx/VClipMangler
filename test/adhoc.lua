local utils = require("_utils")
local ctx = require("_context")

package.path = package.path .. ";" .. utils.getCurrentDir().."/.." .."/?.lua"
local app = require("VClipMangler")
app.setContext(ctx)
local apputils = app.utils
