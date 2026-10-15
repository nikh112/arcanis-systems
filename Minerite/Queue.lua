local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local BlockQueue = {}

-- Constants
local COMPACT_AT = 15000 
local BASE_BUDGET = 0.008
local MAX_BUDGET = 0.014
local MAX_BUCKETS = 10 
local MAX_POOLED_JOBS = 2000

local QueueBuckets = table.create(MAX_BUCKETS)
local BucketHeads = table.create(MAX_BUCKETS, 1)

for i = 1, MAX_BUCKETS do
	QueueBuckets[i] = {}
end

local JobPool = {}
local poolCount = 0

local _IsCave
local isQueueRunning = false
local backgroundProcess = nil

local _PlaceBlockSync, _GetListBlock, _SetListBlock, _CreateBarrier

--------------------------------------------------
-- POOLING HELPERS
--------------------------------------------------
local function GetJob(vec, guid, depth)
	if poolCount > 0 then
		local job = JobPool[poolCount]
		JobPool[poolCount] = nil
		poolCount -= 1

		job.Vec = vec
		job.GUID = guid
		job.Depth = depth
		return job
	end

	return { Vec = vec, GUID = guid, Depth = depth }
end

local function ReturnJob(job)
	job.Vec = nil 
	job.GUID = nil

	if poolCount < MAX_POOLED_JOBS then
		poolCount += 1
		JobPool[poolCount] = job
	end
end

--------------------------------------------------
-- QUEUE HELPERS
--------------------------------------------------
local function getFrameBudget(): number
    local heartbeat = Stats.HeartbeatTime
    
    if heartbeat < 0.015 then return 0.030 end 
    
    if heartbeat < 0.025 then return 0.015 end 
    
    return 0.008 
end

local function hasWork()
	for i = 1, MAX_BUCKETS do
		if BucketHeads[i] <= #QueueBuckets[i] then
			return true
		end
	end
	return false
end

local function popJob()
	for i = 1, MAX_BUCKETS do
		local head = BucketHeads[i]
		local q = QueueBuckets[i]

		if head <= #q then
			local job = q[head]
			BucketHeads[i] = head + 1
			return job
		end
	end
	return nil
end

local function compact()
	for i = 1, MAX_BUCKETS do
		local head = BucketHeads[i]
		if head > COMPACT_AT then
			local q = QueueBuckets[i]
			local newLen = math.max(#q - head + 1, 0)
			local newQ = table.create(newLen)

			table.move(q, head, #q, 1, newQ)
			QueueBuckets[i] = newQ
			BucketHeads[i] = 1
		end
	end
end

--------------------------------------------------
-- PROCESSOR
--------------------------------------------------
local function processQueue()
	isQueueRunning = true
	while hasWork() do
		local t0 = os.clock()
		local n = 0
		local budget = getFrameBudget()

		while true do
			local job = popJob()
			if not job then break end

			_PlaceBlockSync(job.Vec, job.GUID, job.Depth) 

			ReturnJob(job)
			n += 1

			if n % 50 == 0 and (os.clock() - t0) >= budget then break end
		end

		compact()

		if hasWork() then 
			RunService.Heartbeat:Wait() 
		end
	end
	isQueueRunning = false
end

--------------------------------------------------
-- PUBLIC 
--------------------------------------------------
function BlockQueue.Init(placeBlockSyncFn, getListBlockFn, setListBlockFn, createBarrierFn, isCaveFn)
	_PlaceBlockSync = placeBlockSyncFn
	_GetListBlock   = getListBlockFn
	_SetListBlock   = setListBlockFn
	_CreateBarrier  = createBarrierFn
	_IsCave         = isCaveFn
end

function BlockQueue.Queue(Vec, GUID, depth, priorityLevel)
	if _GetListBlock(Vec) then return end
	_SetListBlock(Vec, "RESERVED")

	if not _IsCave(Vec.x, Vec.y, Vec.z) then
		_CreateBarrier(Vec)
	end

	local bucketIndex = math.clamp(priorityLevel or 5, 1, MAX_BUCKETS)
	local job = GetJob(Vec, GUID, depth)
	local q = QueueBuckets[bucketIndex]
	q[#q + 1] = job
	if not isQueueRunning then
		backgroundProcess = task.spawn(processQueue)
	end
end

function BlockQueue.Clear()
    if backgroundProcess then
        task.cancel(backgroundProcess)
        backgroundProcess = nil
    end
    for i = 1, MAX_BUCKETS do
        table.clear(QueueBuckets[i])
        BucketHeads[i] = 1
    end
    table.clear(JobPool) 
    poolCount = 0        
    isQueueRunning = false
end

return BlockQueue