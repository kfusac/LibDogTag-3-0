local MAJOR_VERSION = "LibDogTag-3.0"
local MINOR_VERSION = tonumber(("$Revision$"):match("%d+")) or 0

if MINOR_VERSION > _G.DogTag_MINOR_VERSION then
	_G.DogTag_MINOR_VERSION = MINOR_VERSION
end

DogTag_funcs[#DogTag_funcs+1] = function(DogTag)

local poolNum = 0
local newList, newDict, newSet, del, deepDel, deepCopy
do
	local pool = setmetatable({}, {__mode='k'})
	function newList(...)
		poolNum = poolNum + 1
		local t = next(pool)
		if t then
			pool[t] = nil
			for i = 1, select('#', ...) do
				t[i] = select(i, ...)
			end
		else
			t = { ... }
		end
		return t
	end
	function newDict(...)
		poolNum = poolNum + 1
		local t = next(pool)
		if t then
			pool[t] = nil
		else
			t = {}
		end
		for i = 1, select('#', ...), 2 do
			t[select(i, ...)] = select(i+1, ...)
		end
		return t
	end
	function newSet(...)
		poolNum = poolNum + 1
		local t = next(pool)
		if t then
			pool[t] = nil
		else
			t = {}
		end
		for i = 1, select('#', ...) do
			t[select(i, ...)] = true
		end
		return t
	end
	function del(t)
		if type(t) ~= "table" then
			error("Bad argument #1 to `del'. Expected table, got nil.", 2)
		end
		if pool[t] then
			error("Double-free syndrome.", 2)
		end
		pool[t] = true
		poolNum = poolNum - 1
		for k in pairs(t) do
			t[k] = nil
		end
		setmetatable(t, nil)
		t[''] = true
		t[''] = nil
		return nil
	end
	local deepDel_data
	function deepDel(t)
		local made_deepDel_data = not deepDel_data
		if made_deepDel_data then
			deepDel_data = newList()
		end
		if type(t) == "table" and not deepDel_data[t] then
			deepDel_data[t] = true
			for k,v in pairs(t) do
				deepDel(v)
				deepDel(k)
			end
			del(t)
		end
		if made_deepDel_data then
			deepDel_data = del(deepDel_data)
		end
		return nil
	end
	function deepCopy(t)
		if type(t) ~= "table" then
			return t
		else
			local u = newList()
			for k, v in pairs(t) do
				u[deepCopy(k)] = deepCopy(v)
			end
			return u
		end
	end
end
DogTag.newList, DogTag.newDict, DogTag.newSet, DogTag.del, DogTag.deepDel, DogTag.deepCopy = newList, newDict, newSet, del, deepDel, deepCopy

local DEBUG = _G.DogTag_DEBUG -- set in test.lua
if DEBUG then
	DogTag.getPoolNum = function()
		return poolNum
	end
	DogTag.setPoolNum = function(value)
		poolNum = value
	end
end

local function sortStringList(s)
	if not s then
		return nil
	end
	local set = newSet((";"):split(s))
	local list = newList()
	for k in pairs(set) do
		list[#list+1] = k
	end
	set = del(set)
	table.sort(list)
	local q = table.concat(list, ';')
	list = del(list)
	return q
end
DogTag.sortStringList = sortStringList

local function getNamespaceList(...)
	local n = select('#', ...)
	if n == 0 then
		return "Base"
	end
	local t = newList()
	t["Base"] = true
	for i = 1, n do
		local v = select(i, ...)
		t[v] = true
	end
	local u = newList()
	for k in pairs(t) do
		u[#u+1] = k
	end
	t = del(t)
	table.sort(u)
	local value = table.concat(u, ';')
	u = del(u)
	return value
end
DogTag.getNamespaceList = getNamespaceList

local function select2(min, max, ...)
	if min <= max then
		return select(min, ...), select2(min+1, max, ...)
	end
end
DogTag.select2 = select2

local function joinSet(set, connector)
	local t = newList()
	for k in pairs(set) do
		t[#t+1] = k
	end
	table.sort(t)
	local s = table.concat(t, connector)
	t = del(t)
	return s
end
DogTag.joinSet = joinSet

local unpackNamespaceList = setmetatable({}, {__index = function(self, key)
	local t = newList((";"):split(key))
	self[key] = t
	return t
end, __call = function(self, key)
	return unpack(self[key])
end})
DogTag.unpackNamespaceList = unpackNamespaceList

local function getASTType(ast)
	if not ast then
		return "nil"
	end
	local type_ast = type(ast)
	if type_ast ~= "table" then
		return type_ast
	end
	return ast[1]
end
DogTag.getASTType = getASTType

local memoizeTable
do
	local function key_sort(alpha, bravo)
		local type_alpha, type_bravo = type(alpha), type(bravo)
		if type_alpha ~= type_bravo then
			return type_alpha < type_bravo
		end
		if type_alpha == "string" or type_alpha == "number" then
			return alpha < bravo
		elseif type_alpha == "boolean" then
			return not alpha and bravo
		elseif type_alpha == "table" then
			local alpha_len, bravo_len = #alpha, #bravo
			if alpha_len ~= bravo_len then
				return alpha_len < bravo_len
			end
			for i, v in ipairs(alpha) do
				local u = bravo[i]
				local one = key_sort(v, u)
				if not one then
					local two = key_sort(u, v)
					if two then
						return false
					end
				else
					return true
				end
			end
			local alpha_klen, bravo_klen = 0, 0
			for k in pairs(alpha) do
				alpha_klen = alpha_klen + 1
			end
			for k in pairs(bravo) do
				bravo_klen = bravo_klen + 1
			end
			if alpha_klen ~= bravo_klen then
				return alpha_klen < bravo_klen
			end
			if alpha_klen ~= alpha_len then
				local alpha_keys, bravo_keys = newList(), newList()
				for k in pairs(alpha) do
					alpha_keys[#alpha_keys+1] = k
				end
				table.sort(alpha_keys, key_sort)
				for k in pairs(bravo) do
					bravo_keys[#bravo_keys+1] = k
				end
				table.sort(bravo_keys, key_sort)
				for i, k in ipairs(alpha_keys) do
					local l = bravo_keys[i]
					local one = key_sort(k, l)
					if not one then
						local two = key_sort(l, k)
						if two then
							alpha_keys, bravo_keys = del(alpha_keys), del(bravo_keys)
							return false
						end
					else
						alpha_keys, bravo_keys = del(alpha_keys), del(bravo_keys)
						return true
					end
					local v, u = alpha[k], bravo[l]
					local one = key_sort(v, u)
					if not one then
						local two = key_sort(u, v)
						if two then
							alpha_keys, bravo_keys = del(alpha_keys), del(bravo_keys)
							return false
						end
					else
						alpha_keys, bravo_keys = del(alpha_keys), del(bravo_keys)
						return true
					end
				end
				alpha_keys, bravo_keys = del(alpha_keys), del(bravo_keys)
			end
			return false
		end
		return false
	end
	local function tableToString(tab, t)
		local type_tab = type(tab)
		if type_tab ~= "table" then
			if type_tab == "number" or type_tab == "string" then
				t[#t+1] = tab
			else
				t[#t+1] = tostring(tab)
			end
			return
		end
		local keys = newList()
		for k in pairs(tab) do
			keys[#keys+1] = k
		end
		table.sort(keys, key_sort)
		for _, k in ipairs(keys) do
			local v = tab[k]
			tableToString(k, t)
			t[#t+1] = '='
			tableToString(v, t)
			t[#t+1] = ';'
		end
		keys = del(keys)
	end
	
	pool = setmetatable({}, {__mode='v'})
	function memoizeTable(tab)
		if type(tab) ~= "table" then
			return tab
		end
		local t = newList()
		tableToString(tab, t)
		local key = table.concat(t)
		t = del(t)
		local pool_key = pool[key]
		if pool_key then
			deepDel(tab)
			return pool_key
		else
			pool[key] = tab
			return tab
		end
	end
end
DogTag.memoizeTable = memoizeTable

local kwargsToKwargTypes = setmetatable({}, { __index = function(self, kwargs)
	if not kwargs then
		return self[""]
	elseif kwargs == "" then
		local t = {}
		self[false] = t
		self[""] = t
		return t
	end
	
	local kwargTypes = newList()
	local keys = newList()
	for k in pairs(kwargs) do
		keys[#keys+1] = k
	end
	table.sort(keys)
	local t = newList()
	for i,k in ipairs(keys) do
		if i > 1 then
			t[#t+1] = ";"
		end
		local v = kwargs[k]
		t[#t+1] = k
		t[#t+1] = "="
		local type_v = type(v)
		t[#t+1] = type_v
		kwargTypes[k] = type_v
	end
	keys = del(keys)
	local s = table.concat(t)
	t = del(t)
	local self_s = rawget(self, s)
	if self_s then
		kwargTypes = del(kwargTypes)
		self[kwargs] = self_s
		return self_s
	end
	self[s] = kwargTypes
	self[kwargs] = kwargTypes
	return kwargTypes
end, __mode='kv' })
DogTag.kwargsToKwargTypes = kwargsToKwargTypes

end