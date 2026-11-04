local _, WSGS = ...
local Modules = WSGS.Private
function WSGS:Print(message)
    local separator = message:sub(1, 1) == "[" and "" or " "
    DEFAULT_CHAT_FRAME:AddMessage("[WSGS]" .. separator .. message)
end

function WSGS:Debug(message)
    if self.db and self.db.profile.debug then
        self:Print(message)
    end
end

-- Translate diagnostic reasons only where they are shown to the player.
-- Keep the original reasons on operations and in structured debug output.
