local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local P = Players.LocalPlayer
local PG = P:WaitForChild("PlayerGui")

-- the gift module lives in the lobby listener; in a run it may sit in another listener
local function findGiftModule()
    local deadline = os.clock() + 6
    repeat
        local mainUI = PG:FindFirstChild("MainUI")
        if mainUI then
            for _, o in ipairs(mainUI:GetDescendants()) do
                if o:IsA("ModuleScript") and o.Name == "GotGift" then
                    return o
                end
            end
        end
        task.wait(0.25)
    until os.clock() > deadline
    return nil
end

local GotGift = nil
do
    local mod = findGiftModule()
    if mod then
        local ok, res = pcall(require, mod)
        if ok then
            GotGift = res
        end
    end
end

local env = getgenv and getgenv() or _G
if env.GiftClose then
    pcall(env.GiftClose)
end

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local CONFIG_DIR = "VisualHub"
local LAST_FILE = CONFIG_DIR .. "/_last.txt"

-- ===== sound counter =====
local getups = debug.getupvalues or getupvalues
local setup = debug.setupvalue or setupvalue
local idx = nil
if GotGift then
    for i, v in pairs(getups(GotGift)) do
        if type(v) == "number" and v <= 5 then
            idx = i
        end
    end
end

-- sets the module's internal sound counter (1-5)
local function setSound(n)
    if GotGift and idx then
        pcall(setup, GotGift, idx, n)
    end
end
setSound(1)

-- ===== gift types =====
local TYPES = {
    ["Knobs"]         = {text = "Knobs",       kind = "Knob",     qty = true},
    ["Revives"]       = {text = "Revives",     kind = "Revive",   qty = true},
    ["Stardust"]      = {text = "Stardust",    kind = "Stardust", qty = true},
    ["Knobs Booster"] = {text = "Knobs Boost", kind = "Boost",    qty = true},
    ["Admin"]         = {text = "Admin Panel", kind = nil,        qty = false},
}
local TYPE_ORDER = {"Knobs", "Revives", "Stardust", "Knobs Booster", "Admin"}

-- ===== visual currency =====
local function fmt(x)
    return (tostring(x):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local orig, target, gen = {}, {}, {}
local session = 0 -- increases on every reset, cancels delayed additions

local function add(kind, amount, sess)
    if sess ~= session then
        return
    end
    local found = 0
    for _, l in ipairs(PG:GetDescendants()) do
        if l:IsA("TextLabel") and l.Text:match("^%s*[%d,]+%s*$") then
            local c = l
            for _ = 1, 4 do
                local cname = c and c.Name:lower() or ""
                -- labels that belong to the booster must not be counted as Knobs
                if kind ~= "Boost" and cname:find("boost") then
                    break
                end
                if c and cname:find(kind:lower()) then
                    found += 1
                    if not orig[l] then
                        orig[l] = l.Text
                    end
                    local cur = tonumber((l.Text:gsub("%D", ""))) or 0
                    target[l] = (target[l] or cur) + amount
                    gen[l] = (gen[l] or 0) + 1
                    local my, tgt = gen[l], target[l]
                    task.spawn(function()
                        for step = 1, 30 do
                            if gen[l] ~= my or sess ~= session then
                                return
                            end
                            l.Text = fmt(cur + (tgt - cur) * step / 30 // 1)
                            task.wait(0.02)
                        end
                        if gen[l] == my and sess == session then
                            l.Text = fmt(tgt)
                        end
                    end)
                    break
                end
                c = c and c.Parent
            end
        end
    end
    if found == 0 then
        pcall(function()
            Fluent:Notify({
                Title = "Label not found",
                Content = "No number label found for \"" .. kind .. "\". Check its name in Dex.",
                Duration = 4,
            })
        end)
    end
end

local function resetCurrency()
    session += 1
    local restored = {}
    local n = 0
    for l, t in pairs(orig) do
        gen[l] = (gen[l] or 0) + 1
        restored[l] = t
        n += 1
        if l.Parent then
            l.Text = t
        end
    end
    orig, target = {}, {}
    -- second pass one frame later, in case something overwrote the labels
    task.defer(function()
        task.wait()
        for l, t in pairs(restored) do
            if l.Parent then
                l.Text = t
            end
        end
    end)
    pcall(function()
        Fluent:Notify({
            Title = "Currency reset",
            Content = n > 0 and ("Labels restored: " .. n) or "Nothing to restore (no additions were made or labels were not found)",
            Duration = 3,
        })
    end)
end

-- ===== booster icon override =====
-- the game module only has Knobs/Revives/Stardust/Admin icons, so for the
-- booster plaque we copy the real booster icon from the HUD onto the Knobs icon
local boostSrc = nil
local boostWarned = false

local function isGameImage(o)
    return (o:IsA("ImageLabel") or o:IsA("ImageButton"))
        and o.Image ~= ""
        and not o:FindFirstAncestor("AchievementsHolder")
end

local function findBoostIcon()
    if boostSrc and boostSrc.Parent then
        return boostSrc
    end
    -- 1) an image whose name contains "boost"
    for _, o in ipairs(PG:GetDescendants()) do
        if isGameImage(o) and o.Name:lower():find("boost") then
            boostSrc = o
            return o
        end
    end
    -- 2) an image next to the number label that belongs to the booster
    for _, l in ipairs(PG:GetDescendants()) do
        if l:IsA("TextLabel") and l.Text:match("^%s*[%d,]+%s*$") and not l:FindFirstAncestor("AchievementsHolder") then
            local c = l
            for _ = 1, 4 do
                if c and c ~= PG and c.Name:lower():find("boost") then
                    local root = c.Parent or c
                    for _, o in ipairs(root:GetDescendants()) do
                        if isGameImage(o) then
                            boostSrc = o
                            return o
                        end
                    end
                    break
                end
                c = c and c.Parent
            end
        end
    end
    return nil
end

local function patchBoostPlaque(plaque)
    pcall(function()
        local frame = plaque:WaitForChild("Frame", 1)
        local details = frame and frame:WaitForChild("Details", 1)
        local title = details and details:WaitForChild("Title", 1)
        if not title or not title.Text:find("Boost") then
            return
        end
        local src = findBoostIcon()
        if not src then
            if not boostWarned then
                boostWarned = true
                Fluent:Notify({
                    Title = "Boost icon not found",
                    Content = "Could not find the booster icon in the HUD. Send me its path from Dex.",
                    Duration = 4,
                })
            end
            return
        end
        local icon = details:FindFirstChild("KnobsIcon")
        if icon then
            icon.Image = src.Image
            icon.ImageRectOffset = src.ImageRectOffset
            icon.ImageRectSize = src.ImageRectSize
            icon.ImageColor3 = src.ImageColor3
        end
    end)
end

local iconConn = nil
do
    local gui = PG:WaitForChild("GlobalUI", 10)
    local holder = gui and gui:WaitForChild("AchievementsHolder", 10)
    if holder then
        iconConn = holder.ChildAdded:Connect(function(child)
            if child.Name == "LiveGift" then
                task.spawn(patchBoostPlaque, child)
            end
        end)
    end
end

-- ===== gift logic =====
local DELAY = 0.5
local queue = {}
local count, busy, spamming = 0, false, false
local idCache = {}

local function getId(name)
    if name == "" then
        return P.UserId
    end
    if idCache[name] then
        return idCache[name]
    end
    local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, name)
    idCache[name] = ok and id or 1
    return idCache[name]
end

-- used only when this place has no GotGift module (no sound in that case)
local function showGiftFallback(title, userId, name)
    task.spawn(function()
        local gui = PG:FindFirstChild("GlobalUI")
        local holder = gui and gui:FindFirstChild("AchievementsHolder")
        local template = holder and holder:FindFirstChild("Gift")
        if not template then
            pcall(function()
                Fluent:Notify({Title = "Gifts", Content = "Gift popup is not available in this place", Duration = 3})
            end)
            return
        end
        local TS = game:GetService("TweenService")
        local card = template:Clone()
        local frame = card:WaitForChild("Frame")
        card.Size = UDim2.new(0, 0, 0, 0)
        frame.Position = UDim2.new(1.1, 0, 0, 0)
        card.Name = "LiveGift"
        card.Visible = true
        pcall(function()
            local details = frame.Details
            details.Title.Text = title
            details.Desc.Text = ("from @%s"):format(name)
            frame.ImageLabel.Image = ("rbxthumb://type=AvatarHeadShot&id=%s&w=100&h=100"):format(tostring(userId))
            local iconName = nil
            if title:find("Knob") then
                iconName = "KnobsIcon"
            elseif title:find("Revive") then
                iconName = "RevivesIcon"
            elseif title:find("Stardust") then
                iconName = "StardustIcon"
            elseif title:find("Admin") then
                iconName = "AdminIcon"
            end
            if iconName then
                details[iconName].Visible = true
            end
        end)
        card.Parent = holder
        card:TweenSize(UDim2.new(1, 0, 0.15, 0), "In", "Quad", 0.8, true)
        task.wait(0.8)
        frame:TweenPosition(UDim2.new(0, 0, 0, 0), "Out", "Quad", 0.5, true)
        local glow = frame:FindFirstChild("Glow")
        if glow then
            TS:Create(glow, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {ImageTransparency = 1}):Play()
        end
        task.wait(8)
        frame:TweenPosition(UDim2.new(1.1, 0, 0, 0), "In", "Quad", 0.5, true)
        task.wait(0.5)
        card:TweenSize(UDim2.new(1, 0, -0.1, 0), "InOut", "Quad", 0.5, true)
        task.wait(0.5)
        card:Destroy()
    end)
end

local function gift(g)
    count += 1
    -- sound always loops 1-5
    setSound((count - 1) % 5 + 1)
    local senderName = g.name ~= "" and g.name or P.Name
    if GotGift then
        task.spawn(GotGift, nil, g.title, getId(g.name), senderName)
    else
        showGiftFallback(g.title, getId(g.name), senderName)
    end
    if g.kind then
        local s = session
        task.delay(1, add, g.kind, g.amount, s)
    end
end

local function runQueue(loop)
    if busy or #queue == 0 then
        return
    end
    busy = true
    count = 0
    setSound(1)
    repeat
        for _, g in ipairs({table.unpack(queue)}) do
            if loop and not spamming then
                break
            end
            gift(g)
            task.wait(DELAY)
        end
    until not loop or not spamming or #queue == 0
    busy = false
end

-- ===== achievements hooks (filled in by the Achievements tab) =====
local Ach = {
    stop = function() end,
    show = function() end,
    save = function()
        return {}
    end,
    load = function() end,
}

-- ===== window =====
local Window = Fluent:CreateWindow({
    Title = "Visual Hub",
    SubTitle = "by Arom",
    TabWidth = 140,
    Size = UDim2.fromOffset(540, 470),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightShift,
})

local Tabs = {
    Gifts    = Window:AddTab({Title = "Gifts",    Icon = "gift"}),
    Ach      = Window:AddTab({Title = "Achievements", Icon = "trophy"}),
    Currency = Window:AddTab({Title = "Currency", Icon = "coins"}),
    Settings = Window:AddTab({Title = "Settings", Icon = "settings"}),
}

local Options = Fluent.Options
local selectedType = "Knobs"
local amountText, nameText = "500", ""

local function buildGift()
    local t = TYPES[selectedType]
    local amount = t.qty and math.max(1, math.floor(tonumber(amountText) or 1)) or 1
    return {
        title = t.qty and (amount .. " " .. t.text) or t.text,
        name = nameText,
        kind = t.kind,
        amount = amount,
    }
end

-- ================= TAB: GIFTS =================
local SecGift = Tabs.Gifts:AddSection("Gift setup")
local amountInput = nil

local function findAmountFrame()
    if amountInput and amountInput.Frame then
        return amountInput.Frame
    end
    local roots = {gethui and gethui() or nil, game:GetService("CoreGui"), PG}
    for _, root in pairs(roots) do
        local ok, found = pcall(function()
            for _, o in ipairs(root:GetDescendants()) do
                if o:IsA("TextLabel") and o.Text == "Amount" then
                    return o.Parent and o.Parent.Parent
                end
            end
            return nil
        end)
        if ok and found then
            return found
        end
    end
    return nil
end

local function setAmountVisible(show)
    if not amountInput then
        return
    end
    local f = findAmountFrame()
    if f then
        f.Visible = show
    end
    if not show then
        amountText = ""
        pcall(function()
            amountInput:SetValue("")
        end)
    end
end

SecGift:AddDropdown("GiftType", {
    Title = "Gift type",
    Values = TYPE_ORDER,
    Default = 1,
    Callback = function(v)
        selectedType = v
        setAmountVisible(TYPES[v].qty)
    end,
})

amountInput = SecGift:AddInput("Amount", {
    Title = "Amount",
    Default = "500",
    Placeholder = "e.g. 500",
    Numeric = true,
    Finished = false,
    Callback = function(v)
        if not TYPES[selectedType].qty then
            if v ~= "" then
                amountText = ""
                pcall(function()
                    amountInput:SetValue("")
                end)
            end
            return
        end
        amountText = v
    end,
})

SecGift:AddInput("Sender", {
    Title = "Sender username",
    Description = "Empty = your account",
    Default = "",
    Placeholder = "e.g. Roblox",
    Finished = false,
    Callback = function(v)
        nameText = v
    end,
})

local function testOnce()
    if busy then
        return
    end
    count = 0
    setSound(1)
    gift(buildGift())
end

local SecAction = Tabs.Gifts:AddSection("Actions")

SecAction:AddButton({
    Title = "Test (once)",
    Description = "Shows the gift right away, does not add it to the list",
    Callback = testOnce,
})

SecAction:AddButton({
    Title = "Add to list",
    Description = "You can see it in the list below",
    Callback = function()
        local g = buildGift()
        table.insert(queue, g)
        if env.GiftRefresh then
            env.GiftRefresh()
        end
        pcall(function()
            Fluent:Notify({
                Title = "Gift added",
                Content = ("%s <- @%s\nPosition in list: %d"):format(g.title, g.name ~= "" and g.name or P.Name, #queue),
                Duration = 3,
            })
        end)
    end,
})

-- ================= TAB: LIST =================
local SecView = Tabs.Gifts:AddSection("Current list")
local queueView = SecView:AddParagraph({Title = "Gifts in order", Content = "empty"})

local function refresh()
    local lines = {}
    for i, g in ipairs(queue) do
        lines[i] = ("%d. %s <- @%s"):format(i, g.title, g.name ~= "" and g.name or P.Name)
    end
    local text = #lines > 0 and table.concat(lines, "\n") or "empty"
    pcall(function()
        queueView:SetDesc(text)
    end)
end
env.GiftRefresh = refresh

local SecEdit = Tabs.Gifts:AddSection("Editing")

SecEdit:AddButton({
    Title = "Remove last",
    Callback = function()
        table.remove(queue)
        refresh()
    end,
})

SecEdit:AddButton({
    Title = "Clear list",
    Callback = function()
        queue = {}
        refresh()
    end,
})

local SecRun = Tabs.Gifts:AddSection("Run")

SecRun:AddButton({
    Title = "Send list",
    Description = "One pass through the list",
    Callback = function()
        task.spawn(runQueue, false)
    end,
})

local spamToggle = SecRun:AddToggle("Spam", {
    Title = "Spam list",
    Description = "Repeats the list in a loop while enabled",
    Default = false,
    Callback = function(v)
        spamming = v
        if v then
            task.spawn(runQueue, true)
        end
    end,
})

-- ================= TAB: ACHIEVEMENTS =================
do
    local TweenService = game:GetService("TweenService")
    local RepStorage = game:GetService("ReplicatedStorage")
    local AchGui = PG:WaitForChild("GlobalUI", 10)
    local AchHolder = AchGui and AchGui:WaitForChild("AchievementsHolder", 10)
    local AchTemplate = AchHolder and AchHolder:WaitForChild("Achievement", 10)

    -- game module, read only (we never call Apply)
    local Info = nil
    pcall(function()
        -- path is resolved at runtime so the editor does not try to check it statically
        local node = RepStorage
        for _, n in ipairs({"ModulesClient", "AchievementInfo"}) do
            node = node:WaitForChild(n, 5)
        end
        Info = require(node)
    end)

    -- ---------- state ----------
    local All = nil -- real achievements: name -> data
    local labelOf, nameOf, allLabels = {}, {}, {}
    local selectedName = nil
    local custom = false
    local addCur = true
    local filterText = ""
    local showMode = "All"
    local lastListKey = nil

    local FIELD_KEYS = {"Title", "Desc", "Extra", "Image", "Knobs", "Revives", "Stardust", "PrizeText", "PrizeImage"}
    local fields = {}
    for _, key in ipairs(FIELD_KEYS) do
        fields[key] = ""
    end

    local customList = {} -- saved custom achievements: name -> fields
    local selectedCustom = nil
    local suppress = false

    local selectDropdown = nil
    local customDropdown = nil

    local function say(text)
        pcall(function()
            Fluent:Notify({Title = "Achievements", Content = text, Duration = 3})
        end)
    end

    -- ---------- popup (same look and animation as the game) ----------
    local function showPrize(prizeFrame, key, value)
        local label = prizeFrame:FindFirstChild(key)
        local icon = prizeFrame:FindFirstChild(key .. "Icon")
        local on = value ~= nil
        if label then
            label.Visible = on
            if on then
                label.Text = tostring(value)
            end
        end
        if icon then
            icon.Visible = on
        end
    end

    -- adds one extra prize row (text + image) by cloning the Knobs row
    local function addCustomPrize(prizeFrame, text, image)
        local srcLabel = prizeFrame:FindFirstChild("Knobs")
        local srcIcon = prizeFrame:FindFirstChild("KnobsIcon")
        if not srcLabel or not srcIcon then
            return
        end
        -- put the new row after the existing ones (works when the frame uses a UIListLayout)
        local maxOrder = 0
        for _, c in ipairs(prizeFrame:GetChildren()) do
            if c:IsA("GuiObject") and c.LayoutOrder > maxOrder then
                maxOrder = c.LayoutOrder
            end
        end
        local base = maxOrder + 1 - math.min(srcLabel.LayoutOrder, srcIcon.LayoutOrder)

        local hasText = text ~= nil and text ~= ""
        local id = tostring(image or "")
        if tonumber(id) then
            id = "rbxassetid://" .. id
        end

        local icon = srcIcon:Clone()
        icon.Name = "CustomPrizeIcon"
        icon.Visible = id ~= ""
        if id ~= "" then
            pcall(function()
                icon.Image = id
                icon.ImageRectOffset = Vector2.new(0, 0)
                icon.ImageRectSize = Vector2.new(0, 0)
                icon.ImageColor3 = Color3.new(1, 1, 1)
            end)
        end
        icon.LayoutOrder = srcIcon.LayoutOrder + base
        icon.Parent = prizeFrame

        local label = srcLabel:Clone()
        label.Name = "CustomPrize"
        label.Text = hasText and tostring(text) or ""
        label.Visible = hasText
        label.LayoutOrder = srcLabel.LayoutOrder + base
        label.Parent = prizeFrame
    end

    local function popup(info)
        if not AchTemplate or not AchHolder then
            say("Achievement popup template not found in this place")
            return
        end
        task.spawn(function()
            local card = AchTemplate:Clone()
            card.Size = UDim2.new(0, 0, 0, 0)
            local frame = card:WaitForChild("Frame")
            frame.Position = UDim2.new(1.1, 0, 0, 0)
            card.Name = "LiveAchievement"
            card.Visible = true

            local details = frame:FindFirstChild("Details")
            if details then
                local hit = {}
                -- a key whose name equals a label name sets its text (same rule as the game)
                for key, value in pairs(info) do
                    if typeof(key) == "string" and typeof(value) ~= "table" then
                        local l = details:FindFirstChild(key)
                        if l then
                            local ok = pcall(function()
                                l.Text = tostring(value)
                            end)
                            if ok then
                                hit[l] = true
                            end
                        end
                    end
                end
                -- custom Title / Desc: find the labels by name
                local labels = {}
                for _, c in ipairs(details:GetChildren()) do
                    if c:IsA("TextLabel") then
                        table.insert(labels, c)
                    end
                end
                local titleLabel = nil
                local descLabel = nil
                for _, l in ipairs(labels) do
                    local n = l.Name:lower()
                    if not titleLabel and (n:find("title") or n:find("name")) then
                        titleLabel = l
                    elseif not descLabel and n:find("desc") then
                        descLabel = l
                    end
                end
                titleLabel = titleLabel or labels[1]
                if not descLabel then
                    for _, l in ipairs(labels) do
                        if l ~= titleLabel then
                            descLabel = l
                            break
                        end
                    end
                end
                if titleLabel and not hit[titleLabel] and info.Title then
                    titleLabel.Text = tostring(info.Title)
                    hit[titleLabel] = true
                end
                if descLabel and not hit[descLabel] and info.Desc then
                    descLabel.Text = tostring(info.Desc)
                    hit[descLabel] = true
                end
                -- labels still holding template text get Extra (or nothing)
                for _, l in ipairs(labels) do
                    if not hit[l] then
                        l.Text = tostring(info.Extra or "")
                    end
                end
            end

            if info.Image and info.Image ~= "" then
                local img = frame:FindFirstChild("ImageLabel")
                if img then
                    local id = tostring(info.Image)
                    if tonumber(id) then
                        id = "rbxassetid://" .. id
                    end
                    img.Image = id
                end
            end

            local prizeFrame = frame:FindFirstChild("Prize")
            if prizeFrame then
                local prize = typeof(info.Prize) == "table" and info.Prize or nil
                local cpText = info.CustomPrizeText
                local cpImage = info.CustomPrizeImage
                local hasCustom = (cpText ~= nil and cpText ~= "") or (cpImage ~= nil and cpImage ~= "")
                if prize or hasCustom then
                    local p = prize or {}
                    showPrize(prizeFrame, "Knobs", p.Knobs)
                    showPrize(prizeFrame, "Revives", p.Revives)
                    showPrize(prizeFrame, "Stardust", p.Stardust)
                    local skin = prizeFrame:FindFirstChild("Skin")
                    if skin then
                        skin.Visible = false
                    end
                    if hasCustom then
                        addCustomPrize(prizeFrame, cpText, cpImage)
                    end
                else
                    prizeFrame.Visible = false
                end
            end

            card.Parent = AchHolder
            local sound = card:FindFirstChild("Sound")
            if sound then
                sound:Play()
            end
            card:TweenSize(UDim2.new(1, 0, 0.2, 0), "In", "Quad", 0.8, true)
            task.wait(0.8)
            frame:TweenPosition(UDim2.new(0, 0, 0, 0), "Out", "Quad", 0.5, true)
            local glow = frame:FindFirstChild("Glow")
            if glow then
                TweenService:Create(glow, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {ImageTransparency = 1}):Play()
            end
            task.wait(8)
            frame:TweenPosition(UDim2.new(1.1, 0, 0, 0), "In", "Quad", 0.5, true)
            task.wait(0.5)
            card:TweenSize(UDim2.new(1, 0, -0.1, 0), "InOut", "Quad", 0.5, true)
            task.wait(0.5)
            card:Destroy()
        end)
    end

    -- ---------- show the selected achievement ----------
    local function giveCurrency(prize)
        if typeof(prize) ~= "table" then
            return
        end
        local s = session
        for key, kind in pairs({Knobs = "Knob", Revives = "Revive", Stardust = "Stardust"}) do
            local n = tonumber(prize[key])
            if n and n > 0 then
                task.delay(1, add, kind, n, s)
            end
        end
    end

    local function buildInfo()
        if custom then
            local prize = {}
            for _, key in ipairs({"Knobs", "Revives", "Stardust"}) do
                local n = tonumber(fields[key])
                if n and n > 0 then
                    prize[key] = math.floor(n)
                end
            end
            return {
                Title = fields.Title ~= "" and fields.Title or "Achievement",
                Desc = fields.Desc,
                Extra = fields.Extra,
                Image = fields.Image,
                Prize = next(prize) and prize or nil,
                CustomPrizeText = fields.PrizeText,
                CustomPrizeImage = fields.PrizeImage,
            }
        end
        if not selectedName then
            say("Select an achievement first")
            return nil
        end
        local data = All and All[selectedName]
        if typeof(data) ~= "table" then
            say("The achievement list is still loading")
            return nil
        end
        local copy = {}
        for k, v in pairs(data) do
            copy[k] = v
        end
        return copy
    end

    local function showSelected()
        local info = buildInfo()
        if not info then
            return
        end
        popup(info)
        if addCur then
            giveCurrency(info.Prize)
        end
    end

    -- ---------- copy a real achievement into the custom fields (button only) ----------
    local function pickLabels(details)
        local labels = {}
        for _, c in ipairs(details:GetChildren()) do
            if c:IsA("TextLabel") then
                table.insert(labels, c)
            end
        end
        local titleLabel = nil
        local descLabel = nil
        for _, l in ipairs(labels) do
            local n = l.Name:lower()
            if not titleLabel and (n:find("title") or n:find("name")) then
                titleLabel = l
            elseif not descLabel and n:find("desc") then
                descLabel = l
            end
        end
        titleLabel = titleLabel or labels[1]
        if not descLabel then
            for _, l in ipairs(labels) do
                if l ~= titleLabel then
                    descLabel = l
                    break
                end
            end
        end
        local others = {}
        for _, l in ipairs(labels) do
            if l ~= titleLabel and l ~= descLabel then
                table.insert(others, l)
            end
        end
        return titleLabel, descLabel, others
    end

    local function copyToFields()
        if not selectedName then
            say("Select an achievement first")
            return
        end
        local data = All and All[selectedName]
        if typeof(data) ~= "table" then
            say("The achievement list is still loading")
            return
        end
        local title = data.Title
        local desc = data.Desc
        local extra = nil
        local frame = AchTemplate and AchTemplate:FindFirstChild("Frame")
        local details = frame and frame:FindFirstChild("Details")
        if details then
            local tl, dl, others = pickLabels(details)
            if tl and data[tl.Name] ~= nil then
                title = data[tl.Name]
            end
            if dl and data[dl.Name] ~= nil then
                desc = data[dl.Name]
            end
            for _, l in ipairs(others) do
                local v = data[l.Name]
                if typeof(v) == "string" and v ~= "" then
                    extra = v
                    break
                end
            end
        end
        local image = ""
        if data.Image ~= nil then
            image = tostring(data.Image):match("%d+") or tostring(data.Image)
        end
        local prize = typeof(data.Prize) == "table" and data.Prize or {}
        local values = {
            Title = title,
            Desc = desc,
            Extra = extra,
            Image = image,
            Knobs = prize.Knobs,
            Revives = prize.Revives,
            Stardust = prize.Stardust,
            PrizeText = "",
            PrizeImage = "",
        }
        for _, key in ipairs(FIELD_KEYS) do
            pcall(function()
                Options["Ach" .. key]:SetValue(tostring(values[key] or ""))
            end)
        end
        say("Copied to the custom fields. Turn on Custom achievement to use them.")
    end

    -- ---------- real list (dropdown) ----------
    local function rebuildValues()
        local list = {}
        local f = filterText:lower()
        for _, label in ipairs(allLabels) do
            local d = All and All[nameOf[label]]
            local have = typeof(d) == "table" and d.Have == true
            local modeOk = showMode == "All"
                or (showMode == "Obtained" and have)
                or (showMode == "Not obtained" and not have)
            if modeOk and (f == "" or label:lower():find(f, 1, true)) then
                table.insert(list, label)
            end
        end
        if #list == 0 then
            list = {"(nothing found)"}
        end
        local listKey = table.concat(list, "\1")
        if listKey ~= lastListKey then
            lastListKey = listKey
            pcall(function()
                selectDropdown:SetValues(list)
            end)
        end
        local cur = selectedName and labelOf[selectedName]
        local target = list[1]
        if cur and table.find(list, cur) then
            target = cur
        end
        pcall(function()
            selectDropdown:SetValue(target)
        end)
    end

    task.spawn(function()
        if not Info then
            say("Achievement module not found, only custom mode works")
            return
        end
        local ok, data = pcall(Info.GetAll)
        if not ok or typeof(data) ~= "table" then
            say("Could not load the list, only custom mode works")
            return
        end
        All = data
        for name, d in pairs(data) do
            if typeof(d) == "table" then
                local title = d.Title
                local lname = tostring(name):lower()
                -- "Progress" is a placeholder entry, not a real achievement
                local skip = lname == "progress" or (title ~= nil and tostring(title):lower() == "progress")
                if not skip then
                    local label = tostring(name)
                    if title and title ~= "" and tostring(title) ~= label then
                        label = tostring(title) .. " [" .. tostring(name) .. "]"
                    end
                    labelOf[name] = label
                    nameOf[label] = name
                    table.insert(allLabels, label)
                end
            end
        end
        table.sort(allLabels, function(a, b)
            return a:lower() < b:lower()
        end)
        rebuildValues()
        local haveCount = 0
        for _, label in ipairs(allLabels) do
            local d = data[nameOf[label]]
            if typeof(d) == "table" and d.Have == true then
                haveCount += 1
            end
        end
        say(#allLabels .. " achievements loaded, " .. haveCount .. " obtained")
    end)

    -- ---------- saved custom list ----------
    local function refreshCustomList(select)
        local names = {}
        for name in pairs(customList) do
            table.insert(names, name)
        end
        table.sort(names, function(a, b)
            return a:lower() < b:lower()
        end)
        suppress = true
        pcall(function()
            customDropdown:SetValues(names)
        end)
        if select and customList[select] then
            selectedCustom = select
            pcall(function()
                customDropdown:SetValue(select)
            end)
        elseif not (selectedCustom and customList[selectedCustom]) then
            selectedCustom = nil
        end
        suppress = false
    end

    local function loadCustomIntoFields(name)
        local entry = customList[name]
        if not entry then
            return
        end
        for _, key in ipairs(FIELD_KEYS) do
            pcall(function()
                Options["Ach" .. key]:SetValue(tostring(entry[key] or ""))
            end)
        end
        pcall(function()
            Options.AchCustom:SetValue(true)
        end)
    end

    -- ---------- UI: real achievement ----------
    local SecSel = Tabs.Ach:AddSection("Achievement")

    local searchToken = 0

    SecSel:AddInput("AchFilter", {
        Title = "Search",
        Description = "Filter the list by title or name",
        Default = "",
        Placeholder = "e.g. hat",
        Finished = false,
        Callback = function(v)
            filterText = v
            searchToken += 1
            local mine = searchToken
            -- wait until typing stops, then rebuild the list once
            task.delay(0.6, function()
                if mine == searchToken then
                    rebuildValues()
                end
            end)
        end,
    })

    SecSel:AddDropdown("AchShow", {
        Title = "Show",
        Description = "Filter by what the game says you have",
        Values = {"All", "Obtained", "Not obtained"},
        Default = 1,
        Callback = function(v)
            showMode = v
            rebuildValues()
        end,
    })

    selectDropdown = SecSel:AddDropdown("AchSelect", {
        Title = "Real achievement",
        Values = {"Loading..."},
        Default = 1,
        Callback = function(v)
            local n = nameOf[v]
            if n then
                selectedName = n
            end
        end,
    })

    SecSel:AddToggle("AchCurrency", {
        Title = "Add prize to currency",
        Description = "Knobs, Revives and Stardust from the prize are added visually",
        Default = true,
        Callback = function(v)
            addCur = v
        end,
    })

    SecSel:AddButton({
        Title = "Test (show selected)",
        Description = "Shows the selected achievement right now",
        Callback = function()
            showSelected()
        end,
    })

    -- ---------- UI: custom achievement ----------
    local SecCustom = Tabs.Ach:AddSection("Custom fields")

    SecCustom:AddToggle("AchCustom", {
        Title = "Custom achievement",
        Description = "On = the bind shows the fields below instead of the real achievement",
        Default = false,
        Callback = function(v)
            custom = v
        end,
    })

    SecCustom:AddButton({
        Title = "Copy selected achievement to fields",
        Description = "Takes text, image id and prizes of the real achievement chosen above",
        Callback = copyToFields,
    })

    local function field(id, key, title, placeholder, numeric)
        SecCustom:AddInput(id, {
            Title = title,
            Default = "",
            Placeholder = placeholder,
            Numeric = numeric,
            Finished = false,
            Callback = function(v)
                fields[key] = v
            end,
        })
    end

    field("AchTitle", "Title", "Title", "e.g. My Achievement", false)
    field("AchDesc", "Desc", "Description", "e.g. Some text", false)
    field("AchExtra", "Extra", "Third line", "optional", false)
    field("AchImage", "Image", "Image id", "e.g. 123456789", false)
    field("AchKnobs", "Knobs", "Prize: Knobs", "0", true)
    field("AchRevives", "Revives", "Prize: Revives", "0", true)
    field("AchStardust", "Stardust", "Prize: Stardust", "0", true)
    field("AchPrizeText", "PrizeText", "Custom prize: text", "e.g. Item Skin", false)
    field("AchPrizeImage", "PrizeImage", "Custom prize: image id", "e.g. 123456789", false)

    -- ---------- UI: saved custom achievements ----------
    local SecSaved = Tabs.Ach:AddSection("Custom list")

    customDropdown = SecSaved:AddDropdown("AchCustomSaved", {
        Title = "Saved custom achievements",
        Description = "Pick one to load it into the fields above",
        Values = {},
        Default = nil,
        Callback = function(v)
            if suppress or not customList[v] then
                return
            end
            selectedCustom = v
            loadCustomIntoFields(v)
        end,
    })

    SecSaved:AddButton({
        Title = "Save custom achievement",
        Description = "Saves the fields above under its title (same title = overwrite)",
        Callback = function()
            local name = (fields.Title:gsub("^%s+", ""):gsub("%s+$", ""))
            if name == "" then
                say("Enter a title first, it is used as the name")
                return
            end
            local entry = {}
            for _, key in ipairs(FIELD_KEYS) do
                entry[key] = fields[key]
            end
            customList[name] = entry
            refreshCustomList(name)
            say("Saved \"" .. name .. "\" to the custom list")
        end,
    })

    SecSaved:AddButton({
        Title = "Delete selected",
        Callback = function()
            if not selectedCustom or not customList[selectedCustom] then
                say("Select a saved custom achievement first")
                return
            end
            local name = selectedCustom
            customList[name] = nil
            selectedCustom = nil
            refreshCustomList()
            say("Deleted \"" .. name .. "\"")
        end,
    })

    -- ---------- hooks used by config and close ----------
    function Ach.stop()
    end

    function Ach.show()
        showSelected()
    end

    function Ach.save()
        return {
            custom = custom,
            currency = addCur,
            selected = selectedName,
            fields = fields,
            show = showMode,
            customList = customList,
            customSelected = selectedCustom,
        }
    end

    function Ach.load(d)
        if type(d) ~= "table" then
            return
        end
        if type(d.customList) == "table" then
            customList = d.customList
            refreshCustomList(d.customSelected)
        end
        if type(d.fields) == "table" then
            for _, key in ipairs(FIELD_KEYS) do
                if d.fields[key] ~= nil then
                    pcall(function()
                        Options["Ach" .. key]:SetValue(tostring(d.fields[key]))
                    end)
                end
            end
        end
        if d.custom ~= nil then
            pcall(function()
                Options.AchCustom:SetValue(d.custom)
            end)
        end
        if d.currency ~= nil then
            pcall(function()
                Options.AchCurrency:SetValue(d.currency)
            end)
        end
        if d.show then
            pcall(function()
                Options.AchShow:SetValue(d.show)
            end)
        end
        if d.selected then
            selectedName = d.selected
            if labelOf[d.selected] then
                pcall(function()
                    selectDropdown:SetValue(labelOf[d.selected])
                end)
            end
        end
    end
end

-- ================= TAB: CURRENCY =================
local SecCur = Tabs.Currency:AddSection("Visual currency")

SecCur:AddParagraph({
    Title = "How it works",
    Content = "Knobs, Revives and Stardust are added locally on the labels. The button below restores the numbers to what they were before the first addition.",
})

SecCur:AddButton({
    Title = "Reset currency",
    Description = "Restore the numbers to the original values",
    Callback = resetCurrency,
})

-- ================= TAB: SETTINGS =================
local SecBinds = Tabs.Settings:AddSection("Keybinds")

local menuBind = SecBinds:AddKeybind("MenuKeybind", {
    Title = "Hide / show interface",
    Mode = "Toggle",
    Default = "RightShift",
    ChangedCallback = function() end,
})
Fluent.MinimizeKeybind = menuBind

SecBinds:AddKeybind("SpamKeybind", {
    Title = "Spam on / off",
    Mode = "Toggle",
    Default = "",
    Callback = function()
        spamToggle:SetValue(not spamToggle.Value)
    end,
})

SecBinds:AddKeybind("AchShowKeybind", {
    Title = "Show selected achievement",
    Mode = "Toggle",
    Default = "",
    Callback = function()
        Ach.show()
    end,
})

-- ================= CONFIG SYSTEM =================
local selectedConfig = nil
local configDropdown = nil
local configNameText = ""

local function canFiles()
    return writefile and readfile and isfile and isfolder and makefolder and true or false
end

local function ensureDir()
    if canFiles() and not isfolder(CONFIG_DIR) then
        pcall(makefolder, CONFIG_DIR)
    end
end

local function cleanName(s)
    return (tostring(s):gsub("[^%w _%-]", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function configPath(name)
    return CONFIG_DIR .. "/" .. name .. ".json"
end

local function notify(text)
    pcall(function()
        Fluent:Notify({Title = "Config", Content = text, Duration = 3})
    end)
end

local function listConfigs()
    local names = {}
    if not (listfiles and isfolder and isfolder(CONFIG_DIR)) then
        return names
    end
    local ok, files = pcall(listfiles, CONFIG_DIR)
    if not ok then
        return names
    end
    for _, path in ipairs(files) do
        local name = path:match("([^/\\]+)%.json$")
        if name then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

local function refreshConfigList(select)
    local names = listConfigs()
    pcall(function()
        configDropdown:SetValues(names)
    end)
    if select and table.find(names, select) then
        selectedConfig = select
    elseif not (selectedConfig and table.find(names, selectedConfig)) then
        selectedConfig = names[1]
    end
    if selectedConfig then
        pcall(function()
            configDropdown:SetValue(selectedConfig)
        end)
    end
end

local function saveConfig(name)
    if not canFiles() then
        notify("Your executor does not support file functions")
        return
    end
    name = cleanName(name or "")
    if name == "" then
        notify("Enter a config name first")
        return
    end
    ensureDir()
    local data = {
        queue = queue,
        menuBind = Options.MenuKeybind and Options.MenuKeybind.Value or "RightShift",
        spamBind = Options.SpamKeybind and Options.SpamKeybind.Value or "",
        giftType = selectedType,
        amount = amountText,
        sender = nameText,
        achShowBind = Options.AchShowKeybind and Options.AchShowKeybind.Value or "",
        ach = Ach.save(),
    }
    local ok, err = pcall(function()
        writefile(configPath(name), HttpService:JSONEncode(data))
        writefile(LAST_FILE, name)
    end)
    if ok then
        notify("Saved \"" .. name .. "\" (" .. #queue .. " gifts)")
        refreshConfigList(name)
    else
        notify("Save failed: " .. tostring(err))
    end
end

local function loadConfig(name, silent)
    if not canFiles() then
        if not silent then
            notify("Your executor does not support file functions")
        end
        return
    end
    if not name or name == "" or not isfile(configPath(name)) then
        if not silent then
            notify("Select a saved config first")
        end
        return
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(configPath(name)))
    end)
    if not ok or type(data) ~= "table" then
        notify("Config \"" .. name .. "\" is corrupted")
        return
    end

    queue = type(data.queue) == "table" and data.queue or {}
    refresh()
    Ach.load(data.ach)
    if data.achShowBind and data.achShowBind ~= "" then
        pcall(function()
            Options.AchShowKeybind:SetValue(data.achShowBind, "Toggle")
        end)
    end

    if data.menuBind and data.menuBind ~= "" then
        pcall(function()
            Options.MenuKeybind:SetValue(data.menuBind, "Toggle")
        end)
    end
    if data.spamBind and data.spamBind ~= "" then
        pcall(function()
            Options.SpamKeybind:SetValue(data.spamBind, "Toggle")
        end)
    end
    if data.giftType and TYPES[data.giftType] then
        pcall(function()
            Options.GiftType:SetValue(data.giftType)
        end)
    end
    if data.amount and TYPES[selectedType].qty then
        pcall(function()
            Options.Amount:SetValue(data.amount)
        end)
    end
    if data.sender then
        pcall(function()
            Options.Sender:SetValue(data.sender)
        end)
    end

    pcall(writefile, LAST_FILE, name)
    if not silent then
        notify("Loaded \"" .. name .. "\" (" .. #queue .. " gifts)")
    end
end

local function deleteConfig(name)
    if not (delfile and isfile) or not name or not isfile(configPath(name)) then
        notify("Select a saved config first")
        return
    end
    pcall(delfile, configPath(name))
    if isfile(LAST_FILE) and readfile(LAST_FILE) == name then
        pcall(delfile, LAST_FILE)
    end
    notify("Deleted \"" .. name .. "\"")
    selectedConfig = nil
    refreshConfigList()
end

local SecConfig = Tabs.Settings:AddSection("Config")

SecConfig:AddParagraph({
    Title = "What is saved",
    Content = "Gift list, saved custom achievements, achievement fields, hide keybind, spam keybind, show-achievement keybind, gift type, amount and sender. The last used config loads automatically on start.",
})

SecConfig:AddInput("ConfigName", {
    Title = "Config name",
    Description = "Type a name and press Save config",
    Default = "",
    Placeholder = "e.g. my setup",
    Finished = false,
    Callback = function(v)
        configNameText = v
    end,
})

configDropdown = SecConfig:AddDropdown("ConfigList", {
    Title = "Saved configs",
    Values = {},
    Default = nil,
    Callback = function(v)
        selectedConfig = v
    end,
})

SecConfig:AddButton({
    Title = "Save config",
    Description = "Saves under the typed name (or the selected one if empty)",
    Callback = function()
        local name = configNameText ~= "" and configNameText or selectedConfig
        saveConfig(name)
    end,
})

SecConfig:AddButton({
    Title = "Load config",
    Description = "Loads the config selected in the list",
    Callback = function()
        loadConfig(selectedConfig, false)
    end,
})

SecConfig:AddButton({
    Title = "Delete config",
    Description = "Deletes the config selected in the list",
    Callback = function()
        deleteConfig(selectedConfig)
    end,
})

SecConfig:AddButton({
    Title = "Refresh list",
    Callback = function()
        refreshConfigList()
    end,
})

env.GiftClose = function()
    spamming = false
    Ach.stop()
    session += 1
    pcall(function()
        iconConn:Disconnect()
    end)
    pcall(function()
        Fluent:Destroy()
    end)
    env.GiftClose = nil
    env.GiftRefresh = nil
end

-- ===== start =====
queue = {
    {title = "500 Knobs", name = "Roblox", kind = "Knob", amount = 500},
    {title = "2 Revives", name = "builderman", kind = "Revive", amount = 2},
    {title = "Admin Panel", name = "", kind = nil, amount = 1},
}
refresh()
Window:SelectTab(1)

-- fill the config list and auto-load the last used config
ensureDir()
local lastName = nil
if canFiles() and isfile(LAST_FILE) then
    local ok, content = pcall(readfile, LAST_FILE)
    if ok then
        lastName = cleanName(content)
    end
end
refreshConfigList(lastName)
if lastName and lastName ~= "" then
    loadConfig(lastName, true)
end

-- ===== keep typed text visible in long input boxes =====
local function fixTextBoxes()
    local function patch(root)
        for _, o in ipairs(root:GetDescendants()) do
            if o:IsA("TextBox") then
                o.ClipsDescendants = true
                o.TextWrapped = false
            end
        end
    end
    local gui = Fluent.GUI
    if typeof(gui) == "Instance" then
        pcall(patch, gui)
        return
    end
    -- fallback: find the window by its title
    local roots = {gethui and gethui() or nil, game:GetService("CoreGui"), PG}
    for _, root in pairs(roots) do
        pcall(function()
            for _, g in ipairs(root:GetChildren()) do
                if g:IsA("ScreenGui") then
                    for _, o in ipairs(g:GetDescendants()) do
                        if o:IsA("TextLabel") and o.Text == "Visual Hub" then
                            patch(g)
                            return
                        end
                    end
                end
            end
        end)
    end
end
fixTextBoxes()
task.delay(1, fixTextBoxes)