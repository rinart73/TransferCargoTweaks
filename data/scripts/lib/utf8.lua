--[[
Author: Rinart73
Version: 0.1.0

This UTF-8 lib was made specifically for Avorion to help modders and to show devs that we need native UTF-8 support in Lua.
I tried to collect and construct the best implementations of functions with a goal of achieving max performance while keeping input and output relatively close to the native Lua 5.2/5.3 functions.
These functions will assume that you will pass correct utf-8 strings and arguments (no checks made).

While this lib can be used in other projects, some functions (such as `utf8.compare`) may produce wrong results because they depend on specific language data that only exists for languages that Avorion has translation for.

Feel free to contribute.

TODO List:
+ string.byte
+ string.char
~ string.find (only `plain = true`)
- string.gmatch
- string.gsub
+ string.len
+ string.lower - Depends on 'utf8-lower.lua'
- string.match
+ string.reverse
+ string.sub
+ string.upper - Depends on 'utf8-lower.lua'
+ utf8.offset
+ utf8.codepoint
+ utf8.codes

New functions:
+ utf8.singlebyte (c)
    Returns codepoint for a single utf8 character. Basically equal to utf8.byte(char), but faster
+ utf8.table (s)
    Returns string as char table
+ utf8.compare(a, b, sensitive)
    Returns 'true' if string `a` should be placed before `b` and 'false' otherwise. You can pass 'sensitive=true' to not ignore case
    Depends on 'utf8-compare.lua'

Thanks to:
* https://gist.github.com/Stepets/3b4dbaf5e6e6a60f3862
* https://stackoverflow.com/a/29217368/3768314

]]

local utf8 = {}

local gmatch = string.gmatch
local len = string.len
local byte = string.byte
local char = string.char
local lower = string.lower
local upper = string.upper
local find = string.find
local concat = table.concat
local insert = table.insert
local sort = table.sort
local remove = table.remove
local floor = math.floor

-- data will be loaded once but only if lower/upper/compare functions were called
local lowerCase
local upperCase
local alphabetSort

local lang = getCurrentLanguage ~= nil and getCurrentLanguage() or "en" -- use english for console server


utf8.charpattern = "([%z\1-\127\194-\244][\128-\191]*)"

--[[
Returns string as utf8 char table
]]
function utf8.table(s)
    local r = {}
    for chr in gmatch(s, utf8.charpattern) do
        r[#r+1] = chr
    end
    return r
end

--[[
Returns codepoint for a single utf8 character. Basically equal to utf8.byte(char), but faster
]]
function utf8.singlebyte(c)
    local bytes = len(c)
    if bytes == 1 then return byte(c) end
    if bytes == 2 then
        local byte0, byte1 = byte(c, 1, 2)
        return (byte0 - 0xC0) * 0x40 + (byte1 - 0x80)
    end
    if bytes == 3 then
        local byte0, byte1, byte2 = byte(c, 1, 3)
        return (byte0 - 0xE0) * 0x1000 + (byte1 - 0x80) * 0x40 + (byte2 - 0x80)
    end
    local byte0, byte1, byte2, byte3 = byte(c, 1, 4)
    return (byte0 - 0xF0) * 0x40000 + (byte1 - 0x80) * 0x1000 + (byte2 - 0x80) * 0x40 + (byte3 - 0x80) 
end

function utf8.byte(s, i, j) -- string.byte (s [, i [, j]])
    if not i then i = 1 end
    if not j then j = i end
    j = j - i + 1
    
    local r = {}
    for chr in gmatch(s, utf8.charpattern) do
        if i == 1 then
            if j ~= 0 then
                r[#r+1] = utf8.singlebyte(chr)
                j = j - 1
            else
                return unpack(r)
            end
        else
            i = i - 1
        end
    end
    return unpack(r)
end

--[[
The same as utf8.char but for a single code. For performance reasons, because calling utf8.char for 1 codepoint is SLOW
]]
function utf8.singlechar(code)
    if code < 0x80 then
        return char(code)
    end
    if code < 0x7FF then
        return char(floor(code / 0x40) + 0xC0, code % 0x40 + 0x80)
    end
    if code < 0xFFFF then
        local byte0 = floor(code / 0x1000) + 0xE0
        code = code % 0x1000
        return char(byte0, floor(code / 0x40) + 0x80, code % 0x40 + 0x80)
    end
    local byte0 = floor(code / 0x40000) + 0xF0
    code = code % 0x40000
    local byte1 = floor(code / 0x1000) + 0x80
    code = code % 0x1000
    return char(byte0, byte1, floor(code / 0x40) + 0x80, code % 0x40 + 0x80)
end

function utf8.char(...) -- string.char (...)
    local r = {...}
    local code
    for i = 1, #r do
        r[i] = utf8.singlechar(r[i])
    end
    return concat(r)
end

local function str_bytes(s, l)
    if not l then l = 0 end
    local r = {}
    local bytes = 1
    for chr in gmatch(s, utf8.charpattern) do
        r[#r+1] = bytes
        if #r == l then return r end
        bytes = bytes + len(chr)
    end
    return r
end

--[[
Currently only supports `plain` = true (no patterns)
]]
function utf8.find(s, pattern, init, plain, simple) -- string.find (s, pattern [, init [, plain]])
    plain = true
    if init == nil then init = 1
    elseif init > 1 then
        local bytes = str_bytes(s, init)
        if not bytes[init] then return nil end
        init = bytes[init]
    elseif init < 0 then
        local bytes = str_bytes(s)
        init = bytes[#bytes + init + 1]
    end
    local r
    if plain then
        r = { find(s, pattern, init, true) } -- will return start and end pos in bytes
    else
        -- TODO
    end
    if #r == 0 then return end
    if simple then return true end
    -- Search for char pos and correct end pos
    local posBegin = 0
    local posEnd = 0
    local bytes = 1
    local pos = 0
    for chr in gmatch(s, utf8.charpattern) do
        pos = pos + 1
        if posBegin == 0 and r[1] == bytes then
            posBegin = pos
        elseif posEnd == 0 then
            if r[2] == bytes then
                posEnd = pos
            elseif r[2] < bytes then -- correcting end pos
                posEnd = pos - 1
            end
        end
        if posBegin > 0 and posEnd > 0 then break end
        bytes = bytes + len(chr)
    end
    if posEnd == 0 then posEnd = pos end
    r[1] = posBegin
    r[2] = posEnd
    return unpack(r)
end

function utf8.len(s) -- string.len (s)
    local r = 0
    for _ in gmatch(s, utf8.charpattern) do
        r = r + 1
    end
    return r
end

--[[
Optional argument `asTable` - return as char table
]]
function utf8.lower(s, asTable) -- string.lower (s)
    if not lowerCase then
        local c, b
        if lowerCase ~= false then
            lowerCase = false
            c, b = pcall(include, 'utf8-lower')
        end
        if not c then
            eprint("[ERROR][TransferCargoTweaks] utf8 library failed to load 'upper to lower' file")
            return not asTable and lower(s) or utf8.table(lower(s))
        end
        lowerCase = b
    end
    local r = {}
    for chr in gmatch(s, utf8.charpattern) do
        r[#r+1] = lowerCase[chr] and lowerCase[chr] or chr
    end
    return not asTable and concat(r) or r
end

function utf8.reverse(s) -- string.reverse (s)
    local r = {}
    for chr in gmatch(s, utf8.charpattern) do
        r[#r+1] = chr
    end
    for i = 1, floor(#r * 0.5) do
        r[i], r[#r - i + 1] = r[#r - i + 1], r[i]
    end
    return concat(r)
end

function utf8.sub(s, i, j) -- string.sub (s, i [, j])
    local str = {}
    for chr in gmatch(s, utf8.charpattern) do
        str[#str+1] = chr
    end
    if j == nil or j == -1 then j = #str end
    if i < 0 then i = #str + i + 1 end
    if i < 1 then i = 1 end
    return concat({unpack(str, i, j)})
end

--[[
Added optional argument `asTable` - return as char table
]]
function utf8.upper(s, asTable) -- string.upper (s)
    if not upperCase then
        if not lowerCase then
            local c, b
            if lowerCase ~= false then
                lowerCase = false
                c, b = pcall(include, 'utf8-lower')
            end
            if not c then
                eprint("[ERROR][TransferCargoTweaks] utf8 library failed to load 'upper to lower' file")
                return not asTable and upper(s) or utf8.table(upper(s))
            end
            lowerCase = b
        end
        upperCase = {}
        for k, v in pairs(lowerCase) do
            if not upperCase[v] then
                upperCase[v] = k
            end
        end
    end
    local r = {}
    for chr in gmatch(s, utf8.charpattern) do
        r[#r+1] = upperCase[chr] and upperCase[chr] or chr
    end
    return not asTable and concat(r) or r
end

function utf8.offset(s, n, i) -- utf8.offset (s, n [, i])
    local length = 0
    local pos = {}
    for k, v in utf8.codes(s) do
        length = length + 1
        pos[#pos+1] = k
    end

    if i == nil or i < 1 then
        i = n >= 0 and 1 or length + 1
    end
    i = i + n
    if n ~= 0 then
        return pos[i] ~= nil and pos[i] or nil
    else -- special case
        for j = 0, #pos do
            if pos[j] > i then
                return j - 1
            end
        end
        return pos[#pos]
    end
end

function utf8.codepoint(s, i, j) -- utf8.codepoint (s [, i [, j]])
    if not i then i = 1 end
    if not j then j = i end
    local r = {}
    local bytes = 1
    for chr in gmatch(s, utf8.charpattern) do
        if bytes > j then return unpack(r) end
        if bytes >= i then
            r[#r+1] = utf8.singlebyte(chr)
        end
        bytes = bytes + len(chr)
    end
    return unpack(r)
end

function utf8.codes(s) -- utf8.codes (s)
    local order = {}
    local r = {}
    local bytes = 1
    for chr in gmatch(s, utf8.charpattern) do
        order[#order+1] = bytes
        r[bytes] = utf8.singlebyte(chr)
        bytes = bytes + len(chr)
    end
    r = {order, r}
    local k = 0
    return function()
        k = k + 1
        local bytes = r[1][k]
        if bytes then
            return bytes, r[2][bytes]
        else
            return nil
        end
    end
end

--[[
Returns 'true' if string a should be placed before b and 'false' otherwise.
You can pass 'sensitive=true' to not ignore case
Example: table.sort(mytable, utf8.compare)
Example: table.sort(mytable, function(a,b) return utf8.compare(a, b, true) end) or table.sort(mytable, utf8.comparesensitive)
]]
function utf8.comparesensitive(a, b)
    return utf8.compare(a, b, true)
end

function utf8.compare(a, b, sensitive)
    if not sensitive then
        a = utf8.lower(a, true)
        b = utf8.lower(b, true)
    else
        a = utf8.table(a)
        b = utf8.table(b)
    end
    
    if not alphabetSort then
        alphabetSort = {}
        local c, b = pcall(include, 'utf8-compare')
        if c then
            if b[lang] then alphabetSort = b[lang] end
        else
            eprint("[ERROR][TransferCargoTweaks] utf8 library failed to load 'alphabet sorting' file")
        end
    end

    local i = 1
    while i <= math.min(#a, #b) do
        local val, af, bf, _type
        val = alphabetSort[a[i]]
        if val then
            _type = type(val)
            if _type ~= 'function' then
                a[i] = val
            else
                a[i] = val(a, i)
            end
            if _type ~= 'string' then af = true end
        end
        val = alphabetSort[b[i]]
        if val then
            _type = type(val)
            if _type ~= 'function' then
                b[i] = val
            else
                b[i] = val(b, i)
            end
            if _type ~= 'string' then bf = true end
        end
        if af and not bf then b[i] = utf8.singlebyte(b[i]) end
        if not af and bf then a[i] = utf8.singlebyte(a[i]) end
        
        if a[i] < b[i] then
            return true
        elseif a[i] > b[i] then
            return false
        end
        
        i = i + 1
    end
    
    return #a < #b
end

return utf8