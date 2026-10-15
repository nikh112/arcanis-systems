local CaveGenerator = {}

local CaveNoiseCache = {}
local OldCaveNoiseCache = {}

local MossCache = {}
local OldMossCache = {}

local GravelCache = {}
local OldGravelCache = {}

local _CacheSize = 0

local _Seed = 0
local _Offset
local _CaveYLimit = 0

local Vectors = {
	vector.create(-1, 0, 0),
	vector.create(1, 0, 0),
	vector.create(0, -1, 0),
	vector.create(0, 1, 0),
	vector.create(0, 0, 1),
	vector.create(0, 0, -1),
}

local _invOffset = 0

local function GetHash(x, y, z)
	return (x * 73856093) + (y * 19349663) + (z * 83492791)
end

local function CheckCacheSize()
    _CacheSize += 1
    if _CacheSize > 300000 then
        OldCaveNoiseCache = CaveNoiseCache
        CaveNoiseCache = {}
        
        OldMossCache = MossCache
        MossCache = {}
        
        OldGravelCache = GravelCache
        GravelCache = {}
        
        _CacheSize = 0
    end
end

function CaveGenerator.SetSeed(seed: number, offset: number, caveYLimit: number)
	_Seed = seed
	_Offset = offset
	_invOffset = 1 / offset
	_CaveYLimit = caveYLimit
	CaveNoiseCache = {}
	MossCache = {}
	_CacheSize = 0
end

function CaveGenerator.ClearCache()
    CaveNoiseCache = {}
    OldCaveNoiseCache = {}
    MossCache = {}
    OldMossCache = {}
    GravelCache = {}
    OldGravelCache = {}
    _CacheSize = 0
end

function CaveGenerator.isCave(x: number, y: number, z: number): boolean
    if y >= _CaveYLimit then return false end

    local gridX = math.floor(x * _invOffset + 0.5)
    local gridY = math.floor(y * _invOffset + 0.5)
    local gridZ = math.floor(z * _invOffset + 0.5)
    local hash = GetHash(gridX, gridY, gridZ)

    if CaveNoiseCache[hash] ~= nil then
        return CaveNoiseCache[hash]
    end
    
    if OldCaveNoiseCache[hash] ~= nil then
        CaveNoiseCache[hash] = OldCaveNoiseCache[hash]
        return OldCaveNoiseCache[hash]
    end

    local Noise = math.noise(((x + _Seed) / 130), (((_CaveYLimit - y) + _Seed) / 100), ((z + _Seed) / 130))
    local result = (Noise <= 0.82 and Noise >= 0.51) or (Noise <= -0.51 and Noise >= -0.82)

    CaveNoiseCache[hash] = result
    CheckCacheSize()

    return result
end

function CaveGenerator.IsMossyPosition(Vec: vector): boolean
	local gridX = math.floor(Vec.x * _invOffset + 0.5)
	local gridY = math.floor(Vec.y * _invOffset + 0.5)
	local gridZ = math.floor(Vec.z * _invOffset + 0.5)
	local hash = GetHash(gridX, gridY, gridZ)

	if MossCache[hash] ~= nil then
		return MossCache[hash]
	end

	local n1 = math.noise(Vec.x / 25, Vec.y / 25 + _Seed * 0.1, Vec.z / 25)
	local n2 = math.noise(Vec.x / 15 + _Seed, Vec.y / 15, Vec.z / 15 - _Seed)
	local sharpened = math.sign(n1 * 0.65 + n2 * 0.35) * (math.abs(n1 * 0.65 + n2 * 0.35) ^ 0.5)
	local result = sharpened > 0.5

	MossCache[hash] = result
	CheckCacheSize()
	return result
end

function CaveGenerator.IsGravelPosition(Vec: vector): boolean
	local gridX = math.floor(Vec.x * _invOffset + 0.5)
	local gridY = math.floor(Vec.y * _invOffset + 0.5)
	local gridZ = math.floor(Vec.z * _invOffset + 0.5)
	local hash = GetHash(gridX, gridY, gridZ)

	if GravelCache[hash] ~= nil then
		return GravelCache[hash]
	end

	local n1 = math.noise(Vec.x / 30 + _Seed, Vec.y / 30, Vec.z / 30 - _Seed)
	local result = n1 > 0.6

	GravelCache[hash] = result
	CheckCacheSize()
	return result
end

function CaveGenerator.IsExposedToCave(Vec: vector, offset: number?): boolean
	local useOffset = offset or _Offset
	for _, dir in Vectors do
		local neighbor = Vec + (dir * useOffset)
		if CaveGenerator.isCave(neighbor.x, neighbor.y, neighbor.z) then
			return true
		end
	end
	return false
end

function CaveGenerator.SetCacheEntry(x: number, y: number, z: number, value: boolean)
	local gridX = math.floor(x * _invOffset + 0.5)
	local gridY = math.floor(y * _invOffset + 0.5)
	local gridZ = math.floor(z * _invOffset + 0.5)
	local hash = GetHash(gridX, gridY, gridZ)

	if CaveNoiseCache[hash] == nil then
		CheckCacheSize()
	end
	CaveNoiseCache[hash] = value
end

return CaveGenerator