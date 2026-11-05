local _, WT = ...

WT.Utils.DataTransfer = {}
local DataTransfer = WT.Utils.DataTransfer

local bit = _G.bit
local lshift, rshift, band = bit.lshift, bit.rshift, bit.band

local string_char = string.char
local string_byte = string.byte

local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64table = {}
for i = 1, 64 do b64table[i - 1] = b64chars:sub(i, i) end

local b64decode = {}
for i = 1, 64 do b64decode[string.byte(b64chars, i)] = i - 1 end

local strsplit = strsplit or string.split or function(d, s)
    if not s then return nil end
    local t, i = {}, 1
    while true do
        local j = string.find(s, d, i, true)
        if not j then table.insert(t, string.sub(s, i)) break end
        table.insert(t, string.sub(s, i, j - 1))
        i = j + #d
    end
    return (unpack or rawget(table, "unpack"))(t)
end

local Unsecret = WT.Utils.Safety.Unsecret

function DataTransfer:EncodeBase64(data)
    if not data or data == "" then return "" end
    local n = #data
    local out = {}
    local o = 1
    for i = 1, n, 3 do
        local c1, c2, c3 = string_byte(data, i, i + 2)
        local b1 = rshift(c1, 2)
        local b2 = lshift(band(c1, 3), 4) + (c2 and rshift(c2, 4) or 0)
        local b3 = c2 and (lshift(band(c2, 15), 2) + (c3 and rshift(c3, 6) or 0)) or nil
        local b4 = c3 and band(c3, 63) or nil

        out[o] = b64table[b1] .. b64table[b2] .. (b3 and b64table[b3] or "=") .. (b4 and b64table[b4] or "=")
        o = o + 1
    end
    return table.concat(out)
end

function DataTransfer:DecodeBase64(data)
    data = Unsecret(data)
    if not data or data == "" then return "" end
    data = string.gsub(tostring(data), '[^A-Za-z0-9%+/=]', '')
    local n = #data
    local out = {}
    local o = 1
    for i = 1, n, 4 do
        local c1, c2, c3, c4 = string_byte(data, i, i + 3)
        if not c1 or not c2 then break end
        local v1 = b64decode[c1] or 0
        local v2 = b64decode[c2] or 0
        local v3 = (c3 and c3 ~= 61) and b64decode[c3] or nil -- 61 is '='
        local v4 = (c4 and c4 ~= 61) and b64decode[c4] or nil

        local b1 = lshift(v1, 2) + rshift(v2, 4)
        local b2 = v3 and (lshift(band(v2, 15), 4) + rshift(v3, 2)) or nil
        local b3 = (v3 and v4) and (lshift(band(v3, 3), 6) + v4) or nil

        if b3 then out[o] = string_char(b1, b2, b3)
        elseif b2 then out[o] = string_char(b1, b2)
        else out[o] = string_char(b1) end
        
        o = o + 1
    end
    return table.concat(out)
end

function DataTransfer:ExportProfile(db)
    local parts = {}
    local pIdx = 1
    for category, data in pairs(db) do
        if category == "Internal" and type(data) == "table" then
            -- Ensure we strictly only export safe layout parameters
            for k, v in pairs(data) do 
                if k == "Positions" or k == "Scales" then
                    for frameName, frameData in pairs(v) do
                        local valStr = nil
                        if k == "Positions" and type(frameData) == "table" then
                            valStr = "POS:" .. tostring(frameData.point) .. "," .. tostring(frameData.relativeTo) .. "," .. tostring(frameData.relativePoint) .. "," .. tostring(frameData.xOfs) .. "," .. tostring(frameData.yOfs)
                            if frameData.width and frameData.height then
                                valStr = valStr .. "," .. tostring(frameData.width) .. "," .. tostring(frameData.height)
                            end
                        elseif k == "Scales" then
                            valStr = "SCALE:" .. tostring(frameData)
                        end
                        if valStr then
                            parts[pIdx] = category .. ":" .. k .. "|" .. frameName .. "=" .. self:EncodeBase64(valStr)
                            pIdx = pIdx + 1
                        end
                    end
                end
            end
        elseif category ~= "Internal" and type(data) == "table" then
            for k, v in pairs(data) do
                    local valStr = nil
                    if type(v) == "table" then
                        if v.r and v.g and v.b then
                            valStr = "COLOR:" .. tostring(v.r) .. "," .. tostring(v.g) .. "," .. tostring(v.b) .. "," .. tostring(v.a or 1)
                        end
                    else
                        valStr = tostring(v)
                    end
                    
                    if valStr then
                            -- Only process safe primitives to avoid silent table address exports
                            if type(v) == "table" and string.match(valStr, "^COLOR:") then
                                parts[pIdx] = category .. ":" .. k .. "=" .. self:EncodeBase64(valStr)
                                pIdx = pIdx + 1
                            elseif type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
                                parts[pIdx] = category .. ":" .. k .. "=" .. self:EncodeBase64(valStr)
                                pIdx = pIdx + 1
                            end
                end
            end
        end
    end
    local rawStr = table.concat(parts, ";")
    local b64Str = self:EncodeBase64(rawStr)
    
    -- Fast-Path: Use native C regex to insert a newline every 76 characters
    local wrapped = string.gsub(b64Str, ".{76}", "%0\n")
    
    return "W1LD!\n" .. wrapped .. "\n"
end

function DataTransfer:ImportProfile(str, targetDB)
    str = Unsecret(str)
    if not str or type(str) ~= "string" or not string.match(str, "^W1LD!") then return false end
    
    local b64 = string.gsub(str, "^W1LD!", "")
    local success, decoded = pcall(self.DecodeBase64, self, b64)
    if not success or not decoded or decoded == "" then return false end
    
    local importedAnything = false
    for category, k, valStrEncoded in string.gmatch(decoded, "([^:;]+):([^=]+)=([^;]*)") do
        if category == "Internal" then
            local subCat, frameName = string.match(k, "^([^|]+)|(.+)$")
            if subCat and frameName then
                local valStr = self:DecodeBase64(valStrEncoded)
                if not targetDB.Internal then targetDB.Internal = {} end
                if not targetDB.Internal[subCat] then targetDB.Internal[subCat] = {} end
                
                if subCat == "Positions" then
                    local p, rT, rP, x, y, w, h = strsplit(",", string.sub(valStr, 5))
                    local nX, nY, nW, nH = tonumber(x), tonumber(y), tonumber(w), tonumber(h)
                    if p and rT and rP and nX and nY then
                        local posData = { point = p, relativeTo = rT, relativePoint = rP, xOfs = nX, yOfs = nY }
                        if nW and nH then posData.width = nW; posData.height = nH end
                        targetDB.Internal[subCat][frameName] = posData
                        importedAnything = true
                    end
                elseif subCat == "Scales" then
                    local s = string.sub(valStr, 7)
                    if s and tonumber(s) then targetDB.Internal[subCat][frameName] = tonumber(s); importedAnything = true end
                end
            end
        elseif targetDB[category] then
            -- Always allow import if the root category exists, bypass previous 'nil' checks 
            -- that skipped importing values the user had previously reset.
            local valStr = self:DecodeBase64(valStrEncoded)
            local val
            local defaultVal = WT.Config.Defaults[category] and WT.Config.Defaults[category][k]
            
            if type(defaultVal) == "boolean" then
                val = (valStr == "true")
            elseif type(defaultVal) == "number" then
                val = tonumber(valStr) or defaultVal
            elseif type(defaultVal) == "table" and defaultVal.r then
                local r, g, b, a = string.match(valStr, "^COLOR:(.-),(.-),(.-),(.+)$")
                local nR, nG, nB, nA = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
                if nR and nG and nB and nA then val = { r = nR, g = nG, b = nB, a = nA } else val = defaultVal end
            else
                val = valStr
            end
            
            targetDB[category][k] = val
            importedAnything = true
        end
    end
    return importedAnything
end