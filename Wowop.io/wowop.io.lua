-- Create addon namespace
local addonName, addon = ...
WOWOPDB = WOWOPDB or {}

-- Initialize frame and register events
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")

-- Create our custom tooltip frame for LFG applicants
local ApplicantTooltip = CreateFrame("GameTooltip", "WowopApplicantTooltip", UIParent, "GameTooltipTemplate")
ApplicantTooltip:SetClampedToScreen(true)

-- Add these utility functions near the top of the file
local ScrollBoxUtil = {}

function ScrollBoxUtil:OnViewFramesChanged(scrollBox, callback)
    if not scrollBox then
        return
    end
    if scrollBox.buttons then -- legacy support
        callback(scrollBox.buttons, scrollBox)
        return 1
    end
    if scrollBox.RegisterCallback then
        local frames = scrollBox:GetFrames()
        if frames and frames[1] then
            callback(frames, scrollBox)
        end
        scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, function()
            frames = scrollBox:GetFrames()
            callback(frames, scrollBox)
        end)
        return true
    end
    return false
end

function ScrollBoxUtil:OnViewScrollChanged(scrollBox, callback)
    if not scrollBox then
        return
    end
    local function wrappedCallback()
        callback(scrollBox)
    end
    if scrollBox.update then -- legacy support
        hooksecurefunc(scrollBox, "update", wrappedCallback)
        return 1
    end
    if scrollBox.RegisterCallback then
        scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnScroll, wrappedCallback)
        return true
    end
    return false
end

local HookUtil = {}

function HookUtil:MapOn(object, map)
    if type(object) ~= "table" then
        return
    end
    if type(object.GetObjectType) == "function" then
        for key, callback in pairs(map) do
            if not object.wowopHooked then
                object:HookScript(key, callback)
                object.wowopHooked = true
            end
        end
        return 1
    end
    for key, callback in pairs(map) do
        for _, frame in pairs(object) do
            if not frame.wowopHooked then
                frame:HookScript(key, callback)
                frame.wowopHooked = true
            end
        end
    end
    return true
end

-- Add this helper function near the top
local function GetObjOwnerName(self)
    local owner, owner_name = self:GetOwner()
    if owner then
        owner_name = owner:GetName()
        if not owner_name then
            owner_name = owner:GetDebugName()
        end
    end
    return owner, owner_name
end

-- Function to get player score
local function GetPlayerScore(playerName, realmName)
    -- If realm is empty, use player's realm
    if not realmName or realmName == "" then
        realmName = GetRealmName()
    end
    
    -- Create the full player-realm key
    local playerKey = playerName .. "-" .. realmName
    
    -- Return the data or nil if not found
    return WOWOP_DATABASE[playerKey]
end

-- Function to get color for score (0-10)
local function GetScoreColor(score)
    if not score then return 1, 1, 1 end -- white for no score
    
    -- Convert score to 0-1 range
    local normalizedScore = score / 10
    
    -- Red to Yellow to Green gradient
    if normalizedScore < 0.5 then
        -- Red to Yellow (0-0.5)
        return 1, normalizedScore * 2, 0
    else
        -- Yellow to Green (0.5-1)
        return (1 - (normalizedScore - 0.5) * 2), 1, 0
    end
end

-- Function to add stats to tooltip
local function AddStatsToTooltip(tooltip, name, realm, forceShowAll)
    -- If no realm is specified, use the player's realm
    if not realm or realm == "" then
        realm = GetRealmName()
    end
    
    -- Get the player data
    local playerData = GetPlayerScore(name, realm)
    
    -- Add data to tooltip
    if playerData then
        tooltip:AddLine(" ")  -- Empty line for spacing
        tooltip:AddLine("WoWOP.io Stats:", 0.27, 0.74, 0.98)
        
        -- Add score with color
        if playerData.score then
            local r, g, b = GetScoreColor(playerData.score)
            tooltip:AddLine(string.format("Score: %.1f", playerData.score), r, g, b)
        end
        
        -- Show detailed stats when holding shift or when forceShowAll is true
        if IsShiftKeyDown() or forceShowAll then
            if playerData.recent_runs then
                tooltip:AddLine("Recent M+ Runs: " .. playerData.recent_runs, 1, 1, 1)
            end
            if playerData.favorite_dungeon then
                tooltip:AddLine("Favorite Dungeon: " .. playerData.favorite_dungeon, 1, 1, 1)
            end
            if playerData.deaths_per_hour then
                tooltip:AddLine("Deaths/Hour: " .. string.format("%.1f", playerData.deaths_per_hour), 1, 1, 1)
            end
            if playerData.interrupts_per_minute then
                tooltip:AddLine("Interrupts/Min: " .. string.format("%.1f", playerData.interrupts_per_minute), 1, 1, 1)
            end
            if playerData.dps then
                tooltip:AddLine("DPS: " .. playerData.dps, 1, 1, 1)
            end
            if playerData.hps then
                tooltip:AddLine("HPS: " .. playerData.hps, 1, 1, 1)
            end
        else
            -- When not holding shift and not forced, show hint
            tooltip:AddLine("Hold SHIFT to show detailed stats", 0.5, 0.5, 0.5)
        end
        
        tooltip:AddLine(" ")  -- Empty line for spacing
    else
        tooltip:AddLine(" ")  -- Empty line for spacing
        tooltip:AddLine("WoWOP.io Stats: N/A", 0.27, 0.74, 0.98)
        tooltip:AddLine(" ")  -- Empty line for spacing
    end
end

-- Function to handle mouse enter on LFG list items 
local function OnEnter(self)
    if self.applicantID then
        for i = 1, #self.Members do
            local member = self.Members[i]
            local name = member.Name:GetText()
            if name then
                local playerName, realm = name:match("([^-]+)-?(.*)")
                if playerName then
                    GameTooltip:SetOwner(member, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(name)
                    GameTooltip:Show()
                    AddStatsToTooltip(GameTooltip, playerName, realm, true)
                end
            end
        end
    end
end

-- Function to handle mouse leave
local function OnLeave(self)
    GameTooltip:Hide()
    ApplicantTooltip:Hide()
end

-- Function to handle scroll events
local function OnScroll()
    GameTooltip:Hide()
end

-- Hook into all possible tooltip types
local function HookTooltips()
    -- Unit tooltips (nameplates, character frames)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        local unit = select(2, tooltip:GetUnit())
        if not unit then return end
        
        local name, realm = UnitName(unit)
        if not name then return end
        
        AddStatsToTooltip(tooltip, name, realm)
    end)

    -- LFG tooltips
    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(tooltip, resultID, autoAcceptOption)
        local searchResultInfo = C_LFGList.GetSearchResultInfo(resultID)
        if not searchResultInfo or not searchResultInfo.leaderName then return end
        
        local name, realm = searchResultInfo.leaderName:match("([^-]+)-?(.*)")
        if name then
            AddStatsToTooltip(tooltip, name, realm, true)
        end
    end)

    -- Guild roster tooltips
    if CommunitiesFrame then
        hooksecurefunc(CommunitiesFrame.MemberList, "RefreshLayout", function()
            local scrollTarget = CommunitiesFrame.MemberList.ScrollBox.ScrollTarget
            if scrollTarget then
                for _, child in ipairs({scrollTarget:GetChildren()}) do
                    if child.NameFrame and not child.wowopHooked then
                        child:HookScript("OnEnter", function(self)
                            if self.memberInfo and self.memberInfo.name then
                                local name, realm = self.memberInfo.name:match("([^-]+)-?(.*)")
                                if name then
                                    if realm == "" then realm = GetRealmName() end
                                    AddStatsToTooltip(GameTooltip, name, realm)
                                    GameTooltip:Show()
                                end
                            end
                        end)
                        child.wowopHooked = true
                    end
                end
            end
        end)
    end

    -- Add LFG frame integration
    if LFGListFrame then
        -- Hook search panel (when looking at groups)
        if LFGListFrame.SearchPanel and LFGListFrame.SearchPanel.ScrollBox then
            local hookMap = { OnEnter = OnEnter, OnLeave = OnLeave }
            ScrollBoxUtil:OnViewFramesChanged(LFGListFrame.SearchPanel.ScrollBox, function(buttons) 
                HookUtil:MapOn(buttons, hookMap)
            end)
            ScrollBoxUtil:OnViewScrollChanged(LFGListFrame.SearchPanel.ScrollBox, OnScroll)
        end

        -- Hook applicant viewer tooltips
        hooksecurefunc(GameTooltip, "SetText", function(self, text)
            local owner, owner_name = GetObjOwnerName(self)
            if not owner or not owner_name then return end
            
            if owner_name:find("LFGListApplicationViewer") or 
               owner_name:find("LFGListFrame.ApplicationViewer") then
                local button = owner
                while button and not button.applicantID do
                    button = button:GetParent()
                end
                
                if button and button.applicantID and owner.memberIdx then
                    local name = C_LFGList.GetApplicantMemberInfo(button.applicantID, owner.memberIdx)
                    if name then
                        local playerName, realm = name:match("([^-]+)-?(.*)")
                        if playerName then
                            AddStatsToTooltip(self, playerName, realm, true)
                        end
                    end
                end
            end
        end)
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == addonName then
        print("WoWOP.io addon loaded!")
        
        -- Hook all tooltips
        HookTooltips()
    end
end)

-- Add slash commands
SLASH_WOWOP1 = "/wowop"
SlashCmdList["WOWOP"] = function(msg)
    print("WoWOP.io: Available commands:")
    print("/wowop - Show this help message")
end 