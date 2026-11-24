-- Game functions the browser preview lacks, for Undead Route (tools/preview/server.js loads this before the addon).
-- A made-up place to stand, so the guide and the arrow can say how far away a step is: you stand at (60, 25) of
-- the zone picked in the panel, and every zone is 3000 yards across, all on one continent.
local YARDS = 3000
CreateVector2D = CreateVector2D or function(x, y)
    return { x = x, y = y, GetXY = function(v) return v.x, v.y end }
end
C_Map.GetPlayerMapPosition = function()
    return CreateVector2D(0.60, 0.25)
end
C_Map.GetWorldPosFromMapPos = function(_, v)
    return 1, CreateVector2D(v.x * YARDS, v.y * YARDS)
end
