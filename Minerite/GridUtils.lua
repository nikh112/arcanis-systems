local GridUtils = {}
local floor = math.floor
local _inv: number
local _offset: number
local BAND = 131072      -- 2^17 slots per axis
local HALF = 65536
local BAND_SQ = BAND * BAND

function GridUtils.Init(offset: number)
	_inv = 1 / offset
	_offset = offset
end

local function snap(n: number): number
	return floor(n * _inv + 0.5)
end

local function pack(x: number, y: number, z: number): number
	return (x + HALF) * BAND_SQ + (y + HALF) * BAND + (z + HALF)
end

local function unpack(key: number): (number, number, number)
	local z = key % BAND
	key = (key - z) / BAND
	local y = key % BAND
	local x = (key - y) / BAND
	return x - HALF, y - HALF, z - HALF
end

function GridUtils.GetHashFromVec(vec: vector): number
	return pack(snap(vec.x), snap(vec.y), snap(vec.z))
end

function GridUtils.GetSpatialKey(x: number, y: number, z: number): number
	return pack(snap(x), snap(y), snap(z))
end

function GridUtils.GetGridKey(vec: vector): number
	return GridUtils.GetHashFromVec(vec)
end

function GridUtils.KeyToVector(key: number): vector
	local gx, gy, gz = unpack(key)
	return vector.create(gx * _offset, gy * _offset, gz * _offset)
end

function GridUtils.SetListBlock(list, vec, val)
	list[pack(snap(vec.x), snap(vec.y), snap(vec.z))] = val
end

function GridUtils.GetListBlock(list, vec)
	return list[pack(snap(vec.x), snap(vec.y), snap(vec.z))]
end

return GridUtils