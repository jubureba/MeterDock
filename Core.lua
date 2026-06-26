local addonName, ns = ...

--------------------------------------------------------------------
-- MeterDock v1.1.0
-- Dock, snap & enhance the Blizzard damage meter (12.0+)
--
-- Rules:
--   • Window #1 (Edit Mode) = ANCHOR. Never moved/resized by addon.
--   • Secondary windows dock to anchor or to another docked window.
--   • Dock on any side: LEFT, RIGHT, TOP, BOTTOM.
--   • No two windows can dock on the same side of the same target.
--   • Docked windows inherit FULL size (W+H) from the anchor.
--   • Docked windows are LOCKED (cannot move until undocked).
--   • Each docked window gets a small undock button.
--   • Peek expand: drag up on top edge to temporarily see more bars.
--------------------------------------------------------------------

local DMP = CreateFrame("Frame", "MeterDockFrame", UIParent)
ns.DMP = DMP
DMP.version = "1.2.0"

local DEFAULTS = {
    enabled = true,
    snapDistance = 18,
    -- sizeMode: "inherit" | "keep" | "auto" | "manual"
    sizeMode = "inherit",
    docked = {},  -- [windowIdx] = { side, anchorTo }

    -- Visual Customization
    theme = "blizzard",  -- "blizzard" | "dark" | "minimal" | "neon" | "custom"

    -- Custom theme colors (used when theme == "custom")
    colors = {
        accent     = { 0.78, 0.65, 0.36 },  -- glow/highlight color
        accentBright = { 0.9, 0.75, 0.3 },   -- brighter variant
        accentDim  = { 0.6, 0.5, 0.2 },      -- dimmer variant
        text       = { 0.85, 0.72, 0.4 },    -- peek text / arrows
        undockIcon = { 0.78, 0.65, 0.36 },    -- undock button icon
        undockHover = { 0.9, 0.25, 0.2 },     -- undock hover bg
        flashDock  = { 0.9, 0.75, 0.3 },      -- dock animation color
        flashUndock = { 1.0, 0.3, 0.15 },     -- undock animation color
    },

    -- Bar texture override (empty = use Blizzard default)
    barTexture = "",

    -- Background alpha override (0 = don't override, 0.01-1.0 = custom)
    backgroundAlpha = 0,

    -- Show/hide peek expand indicators
    showPeekHint = true,

    -- Dock gap (pixels between docked windows, 0 = flush)
    dockGap = 0,

    -- Hide Blizzard header on docked windows (cleaner look)
    hideDockedHeaders = false,
}

-- Theme presets
local THEMES = {
    blizzard = {
        accent       = { 0.78, 0.65, 0.36 },
        accentBright = { 0.9, 0.75, 0.3 },
        accentDim    = { 0.6, 0.5, 0.2 },
        text         = { 0.85, 0.72, 0.4 },
        undockIcon   = { 0.78, 0.65, 0.36 },
        undockHover  = { 0.9, 0.25, 0.2 },
        flashDock    = { 0.9, 0.75, 0.3 },
        flashUndock  = { 1.0, 0.3, 0.15 },
    },
    dark = {
        accent       = { 0.45, 0.45, 0.5 },
        accentBright = { 0.6, 0.6, 0.65 },
        accentDim    = { 0.3, 0.3, 0.35 },
        text         = { 0.55, 0.55, 0.6 },
        undockIcon   = { 0.5, 0.5, 0.55 },
        undockHover  = { 0.7, 0.2, 0.2 },
        flashDock    = { 0.5, 0.5, 0.55 },
        flashUndock  = { 0.8, 0.25, 0.15 },
    },
    minimal = {
        accent       = { 0.9, 0.9, 0.9 },
        accentBright = { 1.0, 1.0, 1.0 },
        accentDim    = { 0.6, 0.6, 0.6 },
        text         = { 0.8, 0.8, 0.8 },
        undockIcon   = { 0.7, 0.7, 0.7 },
        undockHover  = { 0.8, 0.2, 0.2 },
        flashDock    = { 0.9, 0.9, 0.9 },
        flashUndock  = { 0.7, 0.2, 0.1 },
    },
    neon = {
        accent       = { 0.0, 0.9, 0.7 },
        accentBright = { 0.2, 1.0, 0.8 },
        accentDim    = { 0.0, 0.5, 0.4 },
        text         = { 0.1, 0.95, 0.75 },
        undockIcon   = { 0.0, 0.8, 0.6 },
        undockHover  = { 1.0, 0.1, 0.3 },
        flashDock    = { 0.0, 1.0, 0.8 },
        flashUndock  = { 1.0, 0.2, 0.4 },
    },
}

-- Runtime
local anchorWindow = nil
local secondaryWindows = {}
local allWindows = {}
local snapIndicator = nil

--------------------------------------------------------------------
-- Theme Color Resolver
--------------------------------------------------------------------

function DMP:GetColors()
    local theme = self.db and self.db.theme or "blizzard"
    if theme == "custom" then
        return self.db.colors or THEMES.blizzard
    end
    return THEMES[theme] or THEMES.blizzard
end

function DMP:C(key)
    local colors = self:GetColors()
    return colors[key] or THEMES.blizzard[key]
end

--------------------------------------------------------------------
-- Bar Texture Helper
--------------------------------------------------------------------

function DMP:GetBarTexture()
    local tex = self.db and self.db.barTexture or ""
    if tex == "" then return nil end  -- nil = don't override Blizzard default
    return tex
end

--------------------------------------------------------------------
-- Apply visual overrides to Blizzard meter windows
--------------------------------------------------------------------

function DMP:ApplyVisualOverrides()
    local c = self:GetColors()

    -- Update all peek handles with new theme colors
    for _, win in ipairs(allWindows) do
        local ph = win._dmpPeekHandle
        if ph then
            -- Arrows
            if ph._arrowLeft then
                ph._arrowLeft:SetVertexColor(c.text[1], c.text[2], c.text[3])
            end
            if ph._arrowRight then
                ph._arrowRight:SetVertexColor(c.text[1], c.text[2], c.text[3])
            end
            -- Label
            if ph._arrowLabel then
                ph._arrowLabel:SetTextColor(c.text[1], c.text[2], c.text[3])
            end
        end

        -- Undock button
        local btn = win._dmpUndockBtn
        if btn and btn._icon then
            btn._icon:SetVertexColor(c.undockIcon[1], c.undockIcon[2], c.undockIcon[3])
        end
    end

    -- Update snap indicator colors (will take effect next time it shows)
    if snapIndicator and snapIndicator._tex then
        snapIndicator._tex:SetColorTexture(c.accentBright[1], c.accentBright[2], c.accentBright[3], 0.5)
    end
    if snapIndicator and snapIndicator._outer then
        snapIndicator._outer:SetColorTexture(c.accentDim[1], c.accentDim[2], c.accentDim[3], 0.15)
    end

    -- Background alpha
    local bgAlpha = self.db.backgroundAlpha or 0
    if bgAlpha > 0 then
        for _, win in ipairs(allWindows) do
            if win.SetBackdropColor then
                win:SetBackdropColor(0, 0, 0, bgAlpha)
            end
        end
    end

    -- Bar texture
    local barTex = self:GetBarTexture()
    if barTex then
        self:ApplyBarTexture(barTex)
    end

    -- Hide/show headers on docked windows
    for idx, _ in pairs(self.db.docked) do
        local win = allWindows[idx]
        if win and win.Header then
            win.Header:SetAlpha(self.db.hideDockedHeaders and 0 or 1)
        end
    end
end

function DMP:ApplyBarTexture(texturePath)
    -- Hook the Blizzard bar style function to apply our texture
    if not self._barTextureHooked and DamageMeterEntryMixin then
        hooksecurefunc(DamageMeterEntryMixin, "UpdateStyle", function(entry)
            if self.db.barTexture ~= "" then
                local bar = entry.StatusBar or entry.Bar
                if bar and bar.SetStatusBarTexture then
                    bar:SetStatusBarTexture(self.db.barTexture)
                end
            end
        end)
        self._barTextureHooked = true
    end
end

--------------------------------------------------------------------
-- Init
--------------------------------------------------------------------

DMP:RegisterEvent("ADDON_LOADED")
DMP:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        self:UnregisterEvent("ADDON_LOADED")
        self:Init()
    end
end)

function DMP:Init()
    DamageMeterPlusDB = DamageMeterPlusDB or {}
    -- Migration: move old DB to new name if needed
    if not MeterDockDB and DamageMeterPlusDB then
        MeterDockDB = DamageMeterPlusDB
    end
    MeterDockDB = MeterDockDB or {}
    self.db = setmetatable(MeterDockDB, { __index = DEFAULTS })
    if not self.db.docked then self.db.docked = {} end

    C_Timer.After(1, function()
        self:FindWindows()
        if anchorWindow then
            self:HookAnchorResize()
            self:HookSecondaryDrag()
            self:HookPeekExpand()
            self:HookBlizzardMenu()
            self:RestoreLayout()
            self:ApplyVisualOverrides()
        end
    end)

    self:RegisterSlashCommands()
    self:Print("|cffcc9900MeterDock|r v" .. self.version .. " loaded. /md")
end

--------------------------------------------------------------------
-- Find Blizzard windows
--------------------------------------------------------------------

function DMP:FindWindows()
    allWindows = {}
    secondaryWindows = {}
    anchorWindow = nil

    if DamageMeter and DamageMeter.sessionWindows then
        for i, win in ipairs(DamageMeter.sessionWindows) do
            allWindows[i] = win
            win._dmpIndex = i
        end
    else
        for i = 1, 3 do
            local frame = _G["DamageMeterSessionWindow" .. i]
            if frame then
                allWindows[#allWindows + 1] = frame
                frame._dmpIndex = #allWindows
            end
        end
    end

    if #allWindows == 0 then
        self:Print("|cffff4444Meter windows not found.|r Enable in Edit Mode.")
        return
    end

    anchorWindow = allWindows[1]
    anchorWindow._dmpIsAnchor = true
    for i = 2, #allWindows do
        secondaryWindows[#secondaryWindows + 1] = allWindows[i]
    end

    self:Print("Anchor: #1. Secondary: " .. #secondaryWindows .. " window(s).")
end

--------------------------------------------------------------------
-- Anchor resize watcher → propagate size
--------------------------------------------------------------------

function DMP:HookAnchorResize()
    if not anchorWindow then return end
    local lastW, lastH = anchorWindow:GetWidth(), anchorWindow:GetHeight()

    local watcher = CreateFrame("Frame", nil, anchorWindow)
    watcher:SetScript("OnUpdate", function()
        if not self.db.enabled then return end
        local w, h = anchorWindow:GetWidth(), anchorWindow:GetHeight()
        if w ~= lastW or h ~= lastH then
            lastW, lastH = w, h
            self:PropagateSize()
            self:RepositionAll()
        end
    end)
end

function DMP:PropagateSize()
    local mode = self.db.sizeMode or "inherit"
    -- Only propagate if mode is "inherit" or "auto"
    if mode == "keep" or mode == "manual" then return end

    local w = anchorWindow:GetWidth()
    local h = anchorWindow:GetHeight()
    for idx, info in pairs(self.db.docked) do
        local win = allWindows[idx]
        if win and win:IsShown() then
            win._dmpSyncing = true
            if mode == "inherit" then
                win:SetSize(w, h)
            elseif mode == "auto" then
                -- Auto: match dimension that aligns with dock side
                if info.side == "LEFT" or info.side == "RIGHT" then
                    win:SetHeight(h)
                elseif info.side == "TOP" or info.side == "BOTTOM" then
                    win:SetWidth(w)
                end
            end
            win._dmpSyncing = false
        end
    end
end

--------------------------------------------------------------------
-- Apply size on dock based on sizeMode
--------------------------------------------------------------------

function DMP:ApplySizeMode(win, side)
    local mode = self.db.sizeMode or "inherit"
    win._dmpSyncing = true

    if mode == "inherit" then
        -- Match anchor's full size
        win:SetSize(anchorWindow:GetWidth(), anchorWindow:GetHeight())
    elseif mode == "keep" then
        -- Keep current size, don't change anything
    elseif mode == "auto" then
        -- Match the relevant dimension only
        if side == "LEFT" or side == "RIGHT" then
            win:SetHeight(anchorWindow:GetHeight())
        elseif side == "TOP" or side == "BOTTOM" then
            win:SetWidth(anchorWindow:GetWidth())
        end
    elseif mode == "manual" then
        -- Don't touch size at all
    end

    win._dmpSyncing = false
end

--------------------------------------------------------------------
-- Position docked windows
--------------------------------------------------------------------

function DMP:RepositionAll()
    -- Reposition in dependency order to avoid circular anchors
    -- First: windows anchored to #1
    for idx, info in pairs(self.db.docked) do
        if info.anchorTo == 1 then
            local win = allWindows[idx]
            if win and anchorWindow then
                self:PositionWindow(win, anchorWindow, info.side)
            end
        end
    end
    -- Then: windows anchored to other secondaries
    for idx, info in pairs(self.db.docked) do
        if info.anchorTo ~= 1 then
            local win = allWindows[idx]
            local target = allWindows[info.anchorTo]
            if win and target then
                self:PositionWindow(win, target, info.side)
            end
        end
    end
end

function DMP:PositionWindow(win, anchor, side)
    -- Break ALL existing anchor dependencies on both frames to prevent
    -- Blizzard's internal parent-child chain from causing circular refs.

    -- 1. Pin the anchor to UIParent (absolute position) if it's not the main anchor.
    if anchor ~= anchorWindow then
        self:PinToUIParent(anchor)
    end

    -- 2. Clear the window we're about to position
    win:ClearAllPoints()

    -- 3. Set the new anchor point with optional gap
    local gap = self.db.dockGap or 0
    if side == "RIGHT" then
        win:SetPoint("TOPLEFT", anchor, "TOPRIGHT", gap, 0)
    elseif side == "LEFT" then
        win:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -gap, 0)
    elseif side == "TOP" then
        win:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, gap)
    elseif side == "BOTTOM" then
        win:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
    end
end

-- Pin a frame to UIParent at its current screen position (breaks all dependencies)
function DMP:PinToUIParent(frame)
    local left = frame:GetLeft()
    local top = frame:GetTop()
    if not left or not top then return end

    local scale = frame:GetEffectiveScale()
    local uiScale = UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                   left * scale / uiScale,
                   top * scale / uiScale)
end

--------------------------------------------------------------------
-- Hook secondary window drag (only when NOT docked)
--------------------------------------------------------------------

function DMP:HookSecondaryDrag(win)
    for _, w in ipairs(secondaryWindows) do
        self:HookWindowDrag(w)
    end
end

function DMP:HookWindowDrag(win)
    -- When docked: let Blizzard call StartMoving (to avoid taint),
    -- but immediately StopMovingOrSizing and reposition back.
    hooksecurefunc(win, "StartMoving", function(frame)
        if not self.db.enabled then return end
        if frame._dmpLocked then
            -- Immediately stop and reposition
            frame:StopMovingOrSizing()
            local info = self.db.docked[frame._dmpIndex]
            if info then
                local anchor = allWindows[info.anchorTo or 1]
                if anchor then
                    self:PositionWindow(frame, anchor, info.side)
                end
            end
            return
        end
        frame._dmpDragging = true
    end)

    hooksecurefunc(win, "StopMovingOrSizing", function(frame)
        if not self.db.enabled then return end
        if frame._dmpDragging then
            frame._dmpDragging = false
            self:HideSnapPreview()
            local target, side = self:FindSnapTarget(frame)
            if target then
                self:DockWindow(frame, target, side)
            end
        end
    end)

    -- Snap preview during drag
    local updater = CreateFrame("Frame", nil, win)
    updater:SetScript("OnUpdate", function()
        if win._dmpDragging and self.db.enabled then
            local target, side = self:FindSnapTarget(win)
            if target then
                self:ShowSnapPreview(target, side)
            else
                self:HideSnapPreview()
            end
        end
    end)
end

--------------------------------------------------------------------
-- Snap detection (4 sides, NO duplicates on same slot)
--------------------------------------------------------------------

-- Check if a specific side of a target is already occupied
function DMP:IsSideOccupied(targetIdx, side)
    for _, info in pairs(self.db.docked) do
        if info.anchorTo == targetIdx and info.side == side then
            return true
        end
    end
    return false
end

function DMP:FindSnapTarget(draggedWin)
    local threshold = self.db.snapDistance or 18

    local dL = draggedWin:GetLeft()
    local dR = draggedWin:GetRight()
    local dT = draggedWin:GetTop()
    local dB = draggedWin:GetBottom()
    if not dL then return nil, nil end

    -- Candidates: anchor + all currently docked windows
    local candidates = { anchorWindow }
    for idx, _ in pairs(self.db.docked) do
        if allWindows[idx] and allWindows[idx] ~= draggedWin then
            candidates[#candidates + 1] = allWindows[idx]
        end
    end

    for _, target in ipairs(candidates) do
        if target ~= draggedWin and target:IsShown() then
            local tL = target:GetLeft()
            local tR = target:GetRight()
            local tT = target:GetTop()
            local tB = target:GetBottom()
            if not tL then break end

            local targetIdx = target._dmpIndex
            local vertOverlap = (dT > tB - threshold) and (dB < tT + threshold)
            local horizOverlap = (dR > tL - threshold) and (dL < tR + threshold)

            if vertOverlap then
                if math.abs(dL - tR) < threshold and
                   not self:IsSideOccupied(targetIdx, "RIGHT") then
                    return target, "RIGHT"
                end
                if math.abs(dR - tL) < threshold and
                   not self:IsSideOccupied(targetIdx, "LEFT") then
                    return target, "LEFT"
                end
            end

            if horizOverlap then
                if math.abs(dT - tB) < threshold and
                   not self:IsSideOccupied(targetIdx, "BOTTOM") then
                    return target, "BOTTOM"
                end
                if math.abs(dB - tT) < threshold and
                   not self:IsSideOccupied(targetIdx, "TOP") then
                    return target, "TOP"
                end
            end
        end
    end

    return nil, nil
end

--------------------------------------------------------------------
-- Dock / Undock
--------------------------------------------------------------------

function DMP:DockWindow(win, anchor, side)
    local idx = win._dmpIndex
    local anchorIdx = anchor._dmpIndex
    if not idx or not anchorIdx then return end

    -- Store dock info
    self.db.docked[idx] = { side = side, anchorTo = anchorIdx }

    -- Apply size based on sizeMode
    self:ApplySizeMode(win, side)

    -- Position
    self:PositionWindow(win, anchor, side)

    -- Lock movement (disable drag on this window)
    self:LockWindow(win)

    -- Show undock button
    self:ShowUndockButton(win)

    -- Animate
    self:AnimateDock(win)
end

function DMP:UndockWindow(win)
    local idx = win._dmpIndex
    if not idx then return end
    if not self.db.docked[idx] then return end

    -- Re-anchor to UIParent
    local left = win:GetLeft()
    local top = win:GetTop()
    if left and top then
        local scale = win:GetEffectiveScale()
        local uiScale = UIParent:GetEffectiveScale()
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                     left * scale / uiScale,
                     top * scale / uiScale)
    end

    self.db.docked[idx] = nil

    -- Unlock movement
    self:UnlockWindow(win)

    -- Hide undock button
    self:HideUndockButton(win)

    -- Animate undock
    self:AnimateUndock(win)
end

function DMP:UndockAll()
    for idx, _ in pairs(self.db.docked) do
        local win = allWindows[idx]
        if win then
            self:UndockWindow(win)
        end
    end
    self.db.docked = {}
    self:Print("All windows undocked.")
end

--------------------------------------------------------------------
-- Lock / Unlock movement on docked windows
-- Instead of SetMovable(false) which conflicts with Blizzard code,
-- we let the move start but immediately stop it and reposition.
--------------------------------------------------------------------

function DMP:LockWindow(win)
    win._dmpLocked = true
end

function DMP:UnlockWindow(win)
    win._dmpLocked = false
end

--------------------------------------------------------------------
-- Undock Button (modern, minimal, docked windows only)
--------------------------------------------------------------------

function DMP:ShowUndockButton(win)
    if not win._dmpUndockBtn then
        local btn = CreateFrame("Button", nil, win)
        btn:SetSize(16, 16)
        btn:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 5, 5)
        btn:SetFrameLevel(win:GetFrameLevel() + 10)

        -- Background circle
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(16, 16)
        bg:SetPoint("CENTER")
        bg:SetTexture("Interface\\COMMON\\Indicator-Gray")
        bg:SetVertexColor(0.15, 0.15, 0.2, 0.8)
        btn._bg = bg

        -- Unlink icon
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(10, 10)
        icon:SetPoint("CENTER")
        icon:SetTexture("Interface\\BUTTONS\\UI-GroupLoot-Pass-Up")
        local ic = self:C("undockIcon")
        icon:SetVertexColor(ic[1], ic[2], ic[3])
        icon:SetAlpha(0.7)
        btn._icon = icon

        btn:SetScript("OnEnter", function()
            local hc = self:C("undockHover")
            bg:SetVertexColor(hc[1], hc[2], hc[3], 0.9)
            icon:SetVertexColor(1, 1, 1)
            icon:SetAlpha(1.0)
            GameTooltip:SetOwner(btn, "ANCHOR_TOPRIGHT")
            GameTooltip:AddLine("Undock", 1, 1, 1)
            GameTooltip:AddLine("Detach this window", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            bg:SetVertexColor(0.15, 0.15, 0.2, 0.8)
            local lc = self:C("undockIcon")
            icon:SetVertexColor(lc[1], lc[2], lc[3])
            icon:SetAlpha(0.7)
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function()
            self:UndockWindow(win)
        end)

        -- Subtle appear/disappear on parent hover
        btn:SetAlpha(0)
        win._dmpUndockBtn = btn

        win:HookScript("OnEnter", function()
            if win._dmpUndockBtn and win._dmpUndockBtn:IsShown() then
                self:FadeIn(win._dmpUndockBtn, 0.15, 1.0)
            end
        end)
        win:HookScript("OnLeave", function()
            if win._dmpUndockBtn and win._dmpUndockBtn:IsShown() then
                self:FadeOut(win._dmpUndockBtn, 0.3, 0)
            end
        end)
    end

    win._dmpUndockBtn:Show()
    win._dmpUndockBtn:SetAlpha(0)
end

function DMP:HideUndockButton(win)
    if win._dmpUndockBtn then
        win._dmpUndockBtn:Hide()
    end
end

--------------------------------------------------------------------
-- Smooth Fade Helpers
--------------------------------------------------------------------

function DMP:FadeIn(frame, duration, targetAlpha)
    if frame._dmpFadeTicker then frame._dmpFadeTicker:Cancel() end
    local startAlpha = frame:GetAlpha()
    local t = 0
    frame._dmpFadeTicker = C_Timer.NewTicker(0.016, function(ticker)
        t = t + 0.016
        local progress = math.min(t / duration, 1)
        frame:SetAlpha(startAlpha + (targetAlpha - startAlpha) * progress)
        if progress >= 1 then ticker:Cancel(); frame._dmpFadeTicker = nil end
    end)
end

function DMP:FadeOut(frame, duration, targetAlpha)
    if frame._dmpFadeTicker then frame._dmpFadeTicker:Cancel() end
    local startAlpha = frame:GetAlpha()
    local t = 0
    frame._dmpFadeTicker = C_Timer.NewTicker(0.016, function(ticker)
        t = t + 0.016
        local progress = math.min(t / duration, 1)
        frame:SetAlpha(startAlpha + (targetAlpha - startAlpha) * progress)
        if progress >= 1 then ticker:Cancel(); frame._dmpFadeTicker = nil end
    end)
end

--------------------------------------------------------------------
-- Modern Animations
--------------------------------------------------------------------

-- Dock animation: border glow sweep (left-to-right wipe effect)
function DMP:AnimateDock(win)
    local c = self:GetColors()

    if not win._dmpDockLine then
        win._dmpDockLine = win:CreateTexture(nil, "OVERLAY")
        win._dmpDockLine:SetHeight(2)
    end

    local line = win._dmpDockLine
    local fc = c.flashDock
    line:SetColorTexture(fc[1], fc[2], fc[3], 0)
    line:Show()
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    line:SetWidth(1)

    local totalWidth = win:GetWidth()
    local duration = 0.35
    local t = 0

    C_Timer.NewTicker(0.016, function(ticker)
        t = t + 0.016
        local progress = math.min(t / duration, 1.0)
        local ease = 1 - (1 - progress) * (1 - progress)
        line:SetWidth(math.max(1, totalWidth * ease))

        local alpha
        if progress < 0.3 then
            alpha = (progress / 0.3) * 0.7
        else
            alpha = 0.7 * (1 - (progress - 0.3) / 0.7)
        end
        line:SetColorTexture(fc[1], fc[2], fc[3], math.max(0, alpha))

        if progress >= 1.0 then
            line:Hide()
            ticker:Cancel()
        end
    end)

    -- Subtle full-frame flash
    if not win._dmpGlow then
        win._dmpGlow = win:CreateTexture(nil, "OVERLAY")
        win._dmpGlow:SetAllPoints()
    end
    local ac = c.accent
    win._dmpGlow:SetColorTexture(ac[1], ac[2], ac[3], 0)
    win._dmpGlow:Show()
    local gt = 0
    C_Timer.NewTicker(0.016, function(ticker)
        gt = gt + 0.016
        local alpha = 0.15 * math.max(0, 1 - gt / 0.25)
        win._dmpGlow:SetColorTexture(ac[1], ac[2], ac[3], alpha)
        if gt >= 0.25 then
            win._dmpGlow:Hide()
            ticker:Cancel()
        end
    end)
end

-- Undock animation: themed flash → dissolve
function DMP:AnimateUndock(win)
    local c = self:GetColors()

    if not win._dmpDockLine then
        win._dmpDockLine = win:CreateTexture(nil, "OVERLAY")
        win._dmpDockLine:SetHeight(2)
    end

    local line = win._dmpDockLine
    local fc = c.flashUndock
    line:SetColorTexture(fc[1], fc[2], fc[3], 0)
    line:Show()
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    line:SetHeight(2)

    local t = 0
    C_Timer.NewTicker(0.016, function(ticker)
        t = t + 0.016
        local progress = math.min(t / 0.3, 1.0)
        local alpha = 0.6 * (1 - progress * progress)
        line:SetColorTexture(fc[1], fc[2], fc[3], math.max(0, alpha))
        line:SetHeight(2 + 4 * progress)

        if progress >= 1.0 then
            line:Hide()
            ticker:Cancel()
        end
    end)
end

-- Snap preview: pulsing glow line with gradient effect
function DMP:ShowSnapPreview(target, side)
    if not snapIndicator then
        snapIndicator = CreateFrame("Frame", nil, UIParent)
        snapIndicator:SetFrameStrata("TOOLTIP")

        -- Main glow
        local tex = snapIndicator:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        snapIndicator._tex = tex

        -- Outer soft glow (wider, dimmer)
        local outer = snapIndicator:CreateTexture(nil, "BACKGROUND")
        outer:SetPoint("TOPLEFT", -3, 3)
        outer:SetPoint("BOTTOMRIGHT", 3, -3)
        snapIndicator._outer = outer

        -- Smooth pulse using theme colors
        local pulse_t = 0
        snapIndicator:SetScript("OnUpdate", function(si, elapsed)
            pulse_t = pulse_t + elapsed
            local c = DMP:GetColors()
            local alpha = 0.5 + 0.25 * math.sin(pulse_t * 5)
            si._tex:SetColorTexture(c.accentBright[1], c.accentBright[2], c.accentBright[3], alpha)
            si._outer:SetColorTexture(c.accentDim[1], c.accentDim[2], c.accentDim[3], alpha * 0.3)
        end)
    end

    snapIndicator:ClearAllPoints()

    if side == "RIGHT" then
        snapIndicator:SetSize(3, target:GetHeight())
        snapIndicator:SetPoint("TOPLEFT", target, "TOPRIGHT", -1, 0)
    elseif side == "LEFT" then
        snapIndicator:SetSize(3, target:GetHeight())
        snapIndicator:SetPoint("TOPRIGHT", target, "TOPLEFT", 1, 0)
    elseif side == "TOP" then
        snapIndicator:SetSize(target:GetWidth(), 3)
        snapIndicator:SetPoint("BOTTOMLEFT", target, "TOPLEFT", 0, -1)
    elseif side == "BOTTOM" then
        snapIndicator:SetSize(target:GetWidth(), 3)
        snapIndicator:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, 1)
    end

    snapIndicator:Show()
end

function DMP:HideSnapPreview()
    if snapIndicator then
        snapIndicator:Hide()
    end
end

--------------------------------------------------------------------
-- Restore layout on login
--------------------------------------------------------------------

function DMP:RestoreLayout()
    -- First: pin ALL secondary windows to UIParent to break any Blizzard
    -- internal dependency chains BEFORE we start repositioning them.
    for _, win in ipairs(secondaryWindows) do
        self:PinToUIParent(win)
    end

    -- Pass 1: windows docked directly to the main anchor (#1)
    for idx, info in pairs(self.db.docked) do
        if info.anchorTo == 1 then
            local win = allWindows[idx]
            if win and anchorWindow then
                self:ApplySizeMode(win, info.side)
                self:PositionWindow(win, anchorWindow, info.side)
                self:LockWindow(win)
                self:ShowUndockButton(win)
            end
        end
    end

    -- Pass 2: windows docked to other secondary windows
    for idx, info in pairs(self.db.docked) do
        if info.anchorTo ~= 1 then
            local win = allWindows[idx]
            local anchor = allWindows[info.anchorTo]
            if win and anchor then
                self:ApplySizeMode(win, info.side)
                self:PositionWindow(win, anchor, info.side)
                self:LockWindow(win)
                self:ShowUndockButton(win)
            end
        end
    end
end

--------------------------------------------------------------------
-- Options Panel
--------------------------------------------------------------------

function DMP:OpenOptions()
    if self.optionsFrame and self.optionsFrame:IsShown() then
        self.optionsFrame:Hide()
        return
    end
    if not self.optionsFrame then
        self:CreateOptionsFrame()
    end
    self:RefreshOptions()
    self.optionsFrame:Show()
end

function DMP:CreateOptionsFrame()
    local f = CreateFrame("Frame", "DMP_Options", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(340, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    f.TitleText:SetText("MeterDock")

    -- Enable toggle
    local enableCB = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", 16, -40)
    enableCB.text = enableCB.text or enableCB:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enableCB.text:SetPoint("LEFT", enableCB, "RIGHT", 4, 0)
    enableCB.text:SetText("Enable snap/dock")
    enableCB:SetScript("OnClick", function(cb)
        self.db.enabled = cb:GetChecked()
    end)
    f.enableCB = enableCB

    -- Sync resize toggle
    local syncCB = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    syncCB:SetPoint("TOPLEFT", enableCB, "BOTTOMLEFT", 0, -8)
    syncCB.text = syncCB.text or syncCB:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    syncCB.text:SetPoint("LEFT", syncCB, "RIGHT", 4, 0)
    syncCB.text:SetText("Sync resize (follow anchor size)")
    syncCB:SetScript("OnClick", function(cb)
        self.db.syncResize = cb:GetChecked()
    end)
    f.syncCB = syncCB

    -- Size Mode label
    local sizeModeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeModeLabel:SetPoint("TOPLEFT", syncCB, "BOTTOMLEFT", 0, -12)
    sizeModeLabel:SetText("Dock size mode:")

    -- Size Mode buttons (radio-style)
    local SIZE_MODES = {
        { key = "inherit", label = "Inherit (match anchor)" },
        { key = "keep",    label = "Keep (preserve original)" },
        { key = "auto",    label = "Auto (match side dimension)" },
        { key = "manual",  label = "Manual (don't change)" },
    }

    f.sizeModeButtons = {}
    for i, mode in ipairs(SIZE_MODES) do
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(200, 20)
        btn:SetPoint("TOPLEFT", sizeModeLabel, "BOTTOMLEFT", 0, -4 - (i - 1) * 22)
        btn:SetText(mode.label)
        btn:SetScript("OnClick", function()
            self.db.sizeMode = mode.key
            self:RefreshOptions()
            -- Re-apply to all docked windows
            for idx, info in pairs(self.db.docked) do
                local win = allWindows[idx]
                if win then
                    self:ApplySizeMode(win, info.side)
                end
            end
            self:RepositionAll()
        end)
        f.sizeModeButtons[i] = { btn = btn, key = mode.key }
    end

    -- Docked windows header
    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", sizeModeLabel, "BOTTOMLEFT", 0, -(#SIZE_MODES * 22 + 20))
    header:SetText("Docked Windows")

    -- Undock buttons per secondary
    f.undockBtns = {}
    for i, win in ipairs(secondaryWindows) do
        local idx = win._dmpIndex
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetSize(160, 24)
        btn:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8 - (i - 1) * 30)
        btn:SetScript("OnClick", function()
            self:UndockWindow(win)
            self:RefreshOptions()
        end)
        f.undockBtns[i] = { btn = btn, idx = idx }
    end

    -- Undock All
    local undockAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    undockAll:SetSize(140, 26)
    undockAll:SetPoint("BOTTOMLEFT", 16, 16)
    undockAll:SetText("Undock All")
    undockAll:SetScript("OnClick", function()
        self:UndockAll()
        self:RefreshOptions()
    end)

    self.optionsFrame = f
end

function DMP:RefreshOptions()
    local f = self.optionsFrame
    if not f then return end
    f.enableCB:SetChecked(self.db.enabled)
    f.syncCB:SetChecked(self.db.syncResize ~= false)

    -- Highlight active size mode
    local currentMode = self.db.sizeMode or "inherit"
    for _, entry in ipairs(f.sizeModeButtons) do
        if entry.key == currentMode then
            entry.btn:SetText("|cffcc9900> " .. entry.btn:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r")
            entry.btn:Disable()
        else
            -- Reset text (remove color codes)
            local cleanLabel
            for _, m in ipairs({ "Inherit (match anchor)", "Keep (preserve original)", "Auto (match side dimension)", "Manual (don't change)" }) do
                if entry.key == "inherit" and m:find("Inherit") then cleanLabel = m; break
                elseif entry.key == "keep" and m:find("Keep") then cleanLabel = m; break
                elseif entry.key == "auto" and m:find("Auto") then cleanLabel = m; break
                elseif entry.key == "manual" and m:find("Manual") then cleanLabel = m; break end
            end
            if cleanLabel then entry.btn:SetText(cleanLabel) end
            entry.btn:Enable()
        end
    end

    for i, entry in ipairs(f.undockBtns) do
        local info = self.db.docked[entry.idx]
        if info then
            entry.btn:SetText("Undock #" .. entry.idx .. " (" .. info.side .. ")")
            entry.btn:Enable()
        else
            entry.btn:SetText("#" .. entry.idx .. " (free)")
            entry.btn:Disable()
        end
    end
end

--------------------------------------------------------------------
-- Hook into Blizzard's damage meter right-click / settings menu
-- Injects DMP options directly into the native context menu.
--------------------------------------------------------------------

function DMP:HookBlizzardMenu()
    -- The Blizzard meter uses MenuUtil.CreateContextMenu on right-click
    -- or has a settings button that triggers a dropdown.
    -- We hook the menu generator on each session window.
    for _, win in ipairs(allWindows) do
        self:InjectMenuHook(win)
    end
end

function DMP:InjectMenuHook(win)
    -- Method 1: Hook right-click on the window to show our extended menu
    if not win._dmpMenuHooked then
        win:HookScript("OnMouseUp", function(frame, button)
            if button == "RightButton" and self.db.enabled then
                self:ShowContextMenu(frame)
            end
        end)
        win._dmpMenuHooked = true
    end
end

function DMP:ShowContextMenu(win)
    if not MenuUtil or not MenuUtil.CreateContextMenu then return end

    local idx = win._dmpIndex
    local dockInfo = self.db.docked[idx]

    MenuUtil.CreateContextMenu(win, function(_, rootDescription)
        rootDescription:CreateTitle("|cffcc9900MeterDock|r")
        rootDescription:CreateDivider()

        -- Toggle snap/dock
        rootDescription:CreateCheckbox(
            "|TInterface\\BUTTONS\\UI-GuildButton-OfficerNote-Up:14:14:0:0|t Snap/Dock",
            function() return self.db.enabled end,
            function()
                self.db.enabled = not self.db.enabled
            end
        )

        -- Toggle sync resize
        rootDescription:CreateCheckbox(
            "|TInterface\\BUTTONS\\UI-GuildButton-PublicNote-Up:14:14:0:0|t Sync Resize",
            function() return self.db.syncResize ~= false end,
            function()
                self.db.syncResize = not self.db.syncResize
            end
        )

        -- Size mode options
        rootDescription:CreateDivider()
        rootDescription:CreateTitle("Size Mode: |cffcc9900" .. (self.db.sizeMode or "inherit") .. "|r")

        local modes = {
            { key = "inherit", label = "Inherit (match anchor)" },
            { key = "keep",    label = "Keep (preserve original)" },
            { key = "auto",    label = "Auto (side dimension only)" },
            { key = "manual",  label = "Manual (don't change)" },
        }
        for _, m in ipairs(modes) do
            local current = (self.db.sizeMode or "inherit") == m.key
            local prefix = current and "|cff66cc33● |r" or "    "
            rootDescription:CreateButton(prefix .. m.label, function()
                self.db.sizeMode = m.key
                if m.key == "inherit" or m.key == "auto" then
                    self:PropagateSize()
                    self:RepositionAll()
                end
            end)
        end

        rootDescription:CreateDivider()

        -- Undock this window (only if docked)
        if dockInfo and not win._dmpIsAnchor then
            rootDescription:CreateButton(
                "|TInterface\\BUTTONS\\UI-GroupLoot-Pass-Up:14:14:0:0|t Undock This (" .. dockInfo.side .. ")",
                function() self:UndockWindow(win) end
            )
        end

        -- Undock all
        local hasAnyDocked = false
        for _ in pairs(self.db.docked) do hasAnyDocked = true; break end
        if hasAnyDocked then
            rootDescription:CreateButton(
                "|TInterface\\BUTTONS\\CancelButton-Up:14:14:0:0|t Undock All",
                function() self:UndockAll() end
            )
        end

        rootDescription:CreateDivider()

        -- Dock info (non-interactive, just visual)
        if win._dmpIsAnchor then
            rootDescription:CreateTitle("|cff888888This is the anchor window|r")
        end

        -- Theme selector
        rootDescription:CreateDivider()
        rootDescription:CreateTitle("Theme: |cffcc9900" .. (self.db.theme or "blizzard") .. "|r")
        for _, t in ipairs({"blizzard", "dark", "minimal", "neon", "custom"}) do
            local isCurrent = (self.db.theme or "blizzard") == t
            local prefix = isCurrent and "|cffffff00● |r" or "    "
            rootDescription:CreateButton(prefix .. t, function()
                self.db.theme = t
                self:ApplyVisualOverrides()
                self:Print("Theme: |cffcc9900" .. t .. "|r")
            end)
        end

        rootDescription:CreateDivider()

        -- Customization submenu
        rootDescription:CreateCheckbox(
            "Show peek hint",
            function() return self.db.showPeekHint ~= false end,
            function() self.db.showPeekHint = not self.db.showPeekHint end
        )
        rootDescription:CreateCheckbox(
            "Hide docked headers",
            function() return self.db.hideDockedHeaders end,
            function()
                self.db.hideDockedHeaders = not self.db.hideDockedHeaders
                self:ApplyVisualOverrides()
            end
        )

        rootDescription:CreateDivider()

        -- Open full options
        rootDescription:CreateButton(
            "|TInterface\\BUTTONS\\UI-OptionsButton:14:14:0:0|t Options Panel",
            function() self:OpenOptions() end
        )
    end)
end

--------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------

function DMP:RegisterSlashCommands()
    SLASH_DMP1 = "/md"
    SLASH_DMP2 = "/meterdock"

    SlashCmdList["DMP"] = function(input)
        input = (input or ""):match("^%s*(.-)%s*$")
        if input == "" or input == "options" or input == "config" then
            self:OpenOptions()
        elseif input == "snap" or input == "toggle" then
            self.db.enabled = not self.db.enabled
            self:Print("Snap/dock: " ..
                (self.db.enabled and "|cff66cc33ON|r" or "|cffff4444OFF|r"))
        elseif input == "sync" then
            self.db.syncResize = not self.db.syncResize
            self:Print("Synced resize: " ..
                (self.db.syncResize and "|cff66cc33ON|r" or "|cffff4444OFF|r"))
        elseif input == "undock" or input == "reset" then
            self:UndockAll()
        elseif input == "find" then
            self:FindWindows()
            if anchorWindow then
                self:HookAnchorResize()
                self:HookSecondaryDrag()
            end
        elseif input == "status" then
            self:PrintStatus()
        elseif input:match("^theme") then
            local themeName = input:match("^theme%s+(.+)")
            if themeName and THEMES[themeName] then
                self.db.theme = themeName
                self:ApplyVisualOverrides()
                self:Print("Theme set to: |cffcc9900" .. themeName .. "|r")
            elseif themeName == "custom" then
                self.db.theme = "custom"
                self:Print("Theme: custom (edit colors via SavedVariables)")
            else
                self:Print("Themes: blizzard, dark, minimal, neon, custom")
                self:Print("Current: |cffcc9900" .. (self.db.theme or "blizzard") .. "|r")
            end
        elseif input:match("^bar") then
            local barArg = input:match("^bar%s+(.+)")
            if barArg == "default" or barArg == "reset" then
                self.db.barTexture = ""
                self:Print("Bar texture: Blizzard default")
            elseif barArg == "flat" then
                self.db.barTexture = "Interface\\Buttons\\WHITE8X8"
                self:ApplyVisualOverrides()
                self:Print("Bar texture: Flat")
            elseif barArg == "smooth" then
                self.db.barTexture = "Interface\\TargetingFrame\\UI-StatusBar"
                self:ApplyVisualOverrides()
                self:Print("Bar texture: Smooth")
            elseif barArg == "blizzard" then
                self.db.barTexture = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
                self:ApplyVisualOverrides()
                self:Print("Bar texture: Blizzard Raid")
            elseif barArg then
                self.db.barTexture = barArg
                self:ApplyVisualOverrides()
                self:Print("Bar texture: " .. barArg)
            else
                self:Print("Bar textures: default, flat, smooth, blizzard")
                self:Print("  Or: /md bar Interface\\Path\\To\\Texture")
                self:Print("Current: " .. (self.db.barTexture ~= "" and self.db.barTexture or "default"))
            end
        elseif input:match("^alpha") then
            local val = tonumber(input:match("^alpha%s+(.+)"))
            if val then
                val = math.max(0, math.min(1, val))
                self.db.backgroundAlpha = val
                self:ApplyVisualOverrides()
                self:Print("Background alpha: " .. string.format("%.2f", val) ..
                    (val == 0 and " (disabled)" or ""))
            else
                self:Print("Usage: /md alpha 0.0-1.0 (0 = use Blizzard default)")
            end
        elseif input == "gap" or input:match("^gap") then
            local val = tonumber(input:match("^gap%s+(.+)"))
            if val then
                self.db.dockGap = math.max(0, math.floor(val))
                self:RepositionAll()
                self:Print("Dock gap: " .. self.db.dockGap .. "px")
            else
                self:Print("Usage: /md gap 0-20 (pixels between docked windows)")
                self:Print("Current: " .. (self.db.dockGap or 0) .. "px")
            end
        else
            self:Print("|cffcc9900MeterDock|r v" .. self.version)
            self:Print("  /md            - Options panel")
            self:Print("  /md snap       - Toggle dock")
            self:Print("  /md sync       - Toggle sync resize")
            self:Print("  /md undock     - Undock all")
            self:Print("  /md theme [x]  - Change theme")
            self:Print("  /md bar [x]    - Change bar texture")
            self:Print("  /md alpha [x]  - Background opacity")
            self:Print("  /md gap [x]    - Gap between docked")
            self:Print("  /md find       - Re-scan windows")
            self:Print("  /md status     - Status")
        end
    end
end

function DMP:PrintStatus()
    self:Print("|cffcc9900— Status —|r")
    self:Print("  Enabled: " .. (self.db.enabled and "|cff66cc33YES|r" or "|cffff4444NO|r"))
    self:Print("  Sync: " .. (self.db.syncResize ~= false and "|cff66cc33ON|r" or "|cffff4444OFF|r"))
    self:Print("  Theme: |cffcc9900" .. (self.db.theme or "blizzard") .. "|r")
    self:Print("  Bar: " .. (self.db.barTexture ~= "" and self.db.barTexture or "default"))
    self:Print("  BG alpha: " .. (self.db.backgroundAlpha or 0))
    self:Print("  Gap: " .. (self.db.dockGap or 0) .. "px")
    self:Print("  Anchor: " .. (anchorWindow and "#1" or "none"))
    self:Print("  Secondary: " .. #secondaryWindows)
    local n = 0
    for idx, info in pairs(self.db.docked) do
        n = n + 1
        self:Print("    #" .. idx .. " → " .. info.side .. " of #" .. info.anchorTo)
    end
    if n == 0 then self:Print("    No docked windows.") end
end

--------------------------------------------------------------------
-- Peek Expand: drag up on title bar to temporarily expand height
-- Release to snap back to original size.
--------------------------------------------------------------------

function DMP:HookPeekExpand()
    for _, win in ipairs(allWindows) do
        self:SetupPeekExpand(win)
    end
end

function DMP:SetupPeekExpand(win)
    -- Always use the TOP edge for peek expand (all windows).
    -- For the anchor window, we use a higher strata to get above Blizzard's header.
    local peekHandle = CreateFrame("Frame", nil, UIParent)
    peekHandle:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    peekHandle:SetPoint("TOPRIGHT", win, "TOPRIGHT", 0, 0)
    peekHandle:SetHeight(10)
    peekHandle:SetFrameStrata("FULLSCREEN_DIALOG")
    peekHandle:SetFrameLevel(500)
    peekHandle:EnableMouse(true)
    peekHandle:Show()

    -- No background bar - just show text + icons cleanly

    -- Animated arrow indicator
    local arrowTexture = "Interface\\BUTTONS\\Arrow-Up-Up"

    -- Left arrow icon
    local arrowLeft = peekHandle:CreateTexture(nil, "OVERLAY")
    arrowLeft:SetSize(12, 12)
    arrowLeft:SetPoint("RIGHT", peekHandle, "CENTER", -42, 0)
    arrowLeft:SetTexture(arrowTexture)
    arrowLeft:SetAlpha(0)
    peekHandle._arrowLeft = arrowLeft

    -- Right arrow icon
    local arrowRight = peekHandle:CreateTexture(nil, "OVERLAY")
    arrowRight:SetSize(12, 12)
    arrowRight:SetPoint("LEFT", peekHandle, "CENTER", 42, 0)
    arrowRight:SetTexture(arrowTexture)
    arrowRight:SetAlpha(0)
    peekHandle._arrowRight = arrowRight

    -- Text label
    local arrowLabel = peekHandle:CreateFontString(nil, "OVERLAY")
    arrowLabel:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    arrowLabel:SetPoint("CENTER", peekHandle, "CENTER", 0, 0)
    arrowLabel:SetText("drag to expand")
    arrowLabel:SetShadowOffset(1, -1)
    arrowLabel:SetShadowColor(0, 0, 0, 0.8)
    arrowLabel:SetAlpha(0)
    peekHandle._arrowLabel = arrowLabel

    -- Arrow bounce animation state
    local arrowBounce = 0
    local arrowShowing = false

    peekHandle:SetScript("OnEnter", function()
        if self.db.showPeekHint == false then return end
        local c = self:GetColors()
        arrowLeft:SetVertexColor(c.text[1], c.text[2], c.text[3])
        arrowRight:SetVertexColor(c.text[1], c.text[2], c.text[3])
        arrowLabel:SetTextColor(c.text[1], c.text[2], c.text[3])
        arrowShowing = true
        arrowBounce = 0
        arrowLabel:SetAlpha(0.85)
        arrowLeft:SetAlpha(0.85)
        arrowRight:SetAlpha(0.85)
    end)
    peekHandle:SetScript("OnLeave", function()
        if not win._dmpPeeking then
            arrowShowing = false
            arrowLabel:SetAlpha(0)
            arrowLeft:SetAlpha(0)
            arrowRight:SetAlpha(0)
        end
    end)

    -- Animate the arrows bouncing up and text
    peekHandle:SetScript("OnUpdate", function(_, elapsed)
        if arrowShowing and not win._dmpPeeking then
            arrowBounce = arrowBounce + elapsed
            local offset = 2.5 * math.sin(arrowBounce * 4)
            arrowLabel:SetPoint("CENTER", peekHandle, "CENTER", 0, offset)
            arrowLeft:SetPoint("RIGHT", peekHandle, "CENTER", -40, offset)
            arrowRight:SetPoint("LEFT", peekHandle, "CENTER", 40, offset)
        end

        if win._dmpPeeking then
            arrowLabel:SetAlpha(0)
            arrowLeft:SetAlpha(0)
            arrowRight:SetAlpha(0)
            local currentY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
            local delta = currentY - win._dmpPeekStartY

            -- Dragging UP (delta positive) expands height
            local expandDelta = delta

            if expandDelta > 0 then
                local newHeight = win._dmpPeekOrigHeight + expandDelta
                local maxH = UIParent:GetHeight() * 0.7
                newHeight = math.min(newHeight, maxH)

                -- Must clear conflicting anchor points that lock the size
                if not win._dmpPeekAnchorsCleared then
                    win._dmpPeekAnchorsCleared = true
                    -- Save current position then re-anchor with single point
                    local left = win:GetLeft()
                    local top = win:GetTop()
                    if left and top then
                        local scale = win:GetEffectiveScale()
                        local uiScale = UIParent:GetEffectiveScale()
                        local width = win:GetWidth()
                        win:ClearAllPoints()
                        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
                                     left * scale / uiScale,
                                     top * scale / uiScale)
                        win:SetWidth(width)
                    end
                end

                win._dmpSyncing = true
                win:SetHeight(newHeight)
                win._dmpSyncing = false
            end
        end
    end)

    -- Drag to expand upward
    peekHandle:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            win._dmpPeeking = true
            win._dmpPeekOrigHeight = win:GetHeight()
            win._dmpPeekOrigWidth = win:GetWidth()
            win._dmpPeekAnchorsCleared = false
            win._dmpPeekOrigPoints = {}
            for i = 1, win:GetNumPoints() do
                win._dmpPeekOrigPoints[i] = { win:GetPoint(i) }
            end
            win._dmpPeekStartY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        end
    end)

    peekHandle:SetScript("OnMouseUp", function()
        if win._dmpPeeking then
            win._dmpPeeking = false
            arrowShowing = false
            arrowLabel:SetAlpha(0)
            arrowLeft:SetAlpha(0)
            arrowRight:SetAlpha(0)
            self:AnimatePeekRestore(win, win._dmpPeekOrigHeight)
        end
    end)

    win._dmpPeekHandle = peekHandle
end

-- Smooth animate back to original height, then restore original anchors
function DMP:AnimatePeekRestore(win, targetHeight)
    local startHeight = win:GetHeight()
    if math.abs(startHeight - targetHeight) < 1 then
        self:RestorePeekAnchors(win)
        return
    end

    local duration = 0.2
    local t = 0

    C_Timer.NewTicker(0.016, function(ticker)
        t = t + 0.016
        local progress = math.min(t / duration, 1.0)
        local ease = 1 - (1 - progress) * (1 - progress) * (1 - progress)
        local h = startHeight + (targetHeight - startHeight) * ease

        win._dmpSyncing = true
        win:SetHeight(h)
        win._dmpSyncing = false

        if progress >= 1.0 then
            ticker:Cancel()
            self:RestorePeekAnchors(win)
        end
    end)
end

-- Restore the original Blizzard anchor points after peek expand ends
function DMP:RestorePeekAnchors(win)
    if win._dmpPeekAnchorsCleared and win._dmpPeekOrigPoints then
        win:ClearAllPoints()
        for _, pt in ipairs(win._dmpPeekOrigPoints) do
            win:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
        end
        win._dmpPeekAnchorsCleared = false
        win._dmpPeekOrigPoints = nil
    end
end

--------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------

function DMP:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc9900[MeterDock]|r " .. msg)
end
