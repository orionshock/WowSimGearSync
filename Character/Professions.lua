local _, WSGS = ...
local Professions = {}
WSGS.Professions = Professions

function Professions:ScanProfessions()
    local first, second = GetProfessions()
    local professions = {}
    for _, professionIndex in pairs({first, second}) do
        local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(professionIndex)
        if skillLine then
            professions[skillLine] = {
                name = name,
                index = professionIndex,
                rank = rank,
                maxRank = maxRank,
                skillLine = skillLine,
            }
        end
    end
    return professions
end

function Professions:GetProfession(skillLineID)
    return self:ScanProfessions()[skillLineID]
end

function Professions:CharacterContext()
    local professions = self:ScanProfessions()
    local details = {}
    for skillLine, profession in pairs(professions) do
        details[#details + 1] = string.format("%s(%d)=%s/%s", profession.name or "unknown", skillLine,
            tostring(profession.rank), tostring(profession.maxRank))
    end
    table.sort(details)
    local signature = table.concat(details, ",")
    if self.professionSignature ~= signature then
        self.professionSignature = signature
        WSGS:Debug("[ACTION][PLAN] professions=" .. (signature ~= "" and signature or "none"))
    end
    return {
        professions = professions
    }
end

