local MAJOR_VERSION = "LibDogTag-3.0"
local MINOR_VERSION = tonumber(("$Revision$"):match("%d+")) or 0

if MINOR_VERSION > _G.DogTag_MINOR_VERSION then
	_G.DogTag_MINOR_VERSION = MINOR_VERSION
end

DogTag_funcs[#DogTag_funcs+1] = function(DogTag)

local L = DogTag.L

local FakeGlobals = DogTag.FakeGlobals
local Tags = DogTag.Tags
local newList, newDict, newSet, del, deepCopy, deepDel = DogTag.newList, DogTag.newDict, DogTag.newSet, DogTag.del, DogTag.deepCopy, DogTag.deepDel

local getNamespaceList = DogTag.getNamespaceList
local select2 = DogTag.select2
local joinSet = DogTag.joinSet
local unpackNamespaceList = DogTag.unpackNamespaceList
local getASTType = DogTag.getASTType
local kwargsToKwargTypes = DogTag.kwargsToKwargTypes
local memoizeTable = DogTag.memoizeTable
local unparse, parse, standardize, codeToEventList, clearCodes
DogTag_funcs[#DogTag_funcs+1] = function()
	unparse = DogTag.unparse
	parse = DogTag.parse
	standardize = DogTag.standardize
	codeToEventList = DogTag.codeToEventList
	clearCodes = DogTag.clearCodes
end

local compilationSteps = {}
do
	local mt = {__index = function(self, ns)
		self[ns] = newList()
		return self[ns]
	end}
	compilationSteps.pre = setmetatable({}, mt)
	compilationSteps.start = setmetatable({}, mt)
	compilationSteps.tag = setmetatable({}, mt)
	compilationSteps.tagevents = setmetatable({}, mt)
	compilationSteps.finish = setmetatable({}, mt)
end

local correctTagCasing = setmetatable({}, {__index = function(self, tag)
	for ns, data in pairs(Tags) do
		if data[tag] then
			self[tag] = tag
			return tag
		end
	end
	
	local tag_lower = tag:lower()
	for ns, data in pairs(Tags) do
		for t in pairs(data) do
			if tag_lower == t:lower() then
				self[tag] = t
				return t
			end
		end
	end
	self[tag] = tag
	return tag
end})

local function correctASTCasing(ast)
	if type(ast) ~= "table" then
		return
	end
	local astType = ast[1]
	if astType == "tag" or astType == "mod" then
		ast[2] = correctTagCasing[ast[2]]
		if ast.kwarg then
			for k,v in pairs(ast.kwarg) do
				correctASTCasing(v)
			end
		end
	end
	for i = 1, #ast do
		correctASTCasing(ast[i])
	end
end

local codeToFunction
do
	local codeToFunction_mt_mt = {__index = function(self, code)
		if not code then
			return self[""]
		end
		local nsList = self[1]
		local kwargTypes = self[2]
		
		local s = DogTag:CreateFunctionFromCode(code, true, kwargTypes, unpackNamespaceList(nsList))
		for i, ns in ipairs(unpackNamespaceList[nsList]) do
			local data = FakeGlobals[ns]
			if data then
				for k, v in pairs(data) do
					DogTag[k] = v
				end
			end
		end
		local func, err = loadstring(s)
		local val
		if not func then
			geterrorhandler()(("%s: Error (%s) loading code %q. Please inform ckknight."):format(MAJOR_VERSION, err, code))
			val = self[""]
		else
			local status, result = pcall(func)
			if not status then
				geterrorhandler()(("%s: Error (%s) running code %q. Please inform ckknight."):format(MAJOR_VERSION, result, code))
				val = self[""]
			else
				val = result
			end
		end
		for i, ns in ipairs(unpackNamespaceList[nsList]) do
			local data = FakeGlobals[ns]
			if data then
				for k in pairs(data) do
					DogTag[k] = nil
				end
			end
		end
		self[code] = val
		return val
	end}
	local codeToFunction_mt = {__index = function(self, kwargTypes)
		local t = setmetatable(newList(self[1], kwargTypes), codeToFunction_mt_mt)
		self[kwargTypes] = t
		return t
	end}
	codeToFunction = setmetatable({}, {__index = function(self, nsList)
		local t = setmetatable(newList(nsList), codeToFunction_mt)
		self[nsList] = t
		return t
	end})
end
DogTag.codeToFunction = codeToFunction

local figureCachedTags
do
	local function _figureCachedTags(ast)
		local cachedTags = newList()
		if type(ast) ~= "table" then
			return cachedTags
		end
		local astType = ast[1]
		if astType == 'tag' then
			if not ast.kwarg then
				local tagName = ast[2]
				cachedTags[tagName] = (cachedTags[tagName] or 0) + 1
			else
				if ast.kwarg then
					for key, value in pairs(ast.kwarg) do
						local data = _figureCachedTags(value)
						for k,v in pairs(data) do
							cachedTags[k] = (cachedTags[k] or 0) + v
						end
						data = del(data)
					end
				end
			end
		end
		for i = 2, #ast do
			local data = _figureCachedTags(ast[i])
			for k, v in pairs(data) do
				cachedTags[k] = (cachedTags[k] or 0) + v
			end
			data = del(data)
		end
		return cachedTags
	end
	function figureCachedTags(ast)
		local cachedTags = newList()
		local data = _figureCachedTags(ast)
		for k,v in pairs(data) do
			if v > 1 then
				cachedTags[k] = 1
			end
		end
		data = del(data)
		return cachedTags
	end
end

local function enumLines(text)
	text = text:gsub(";", ";\n"):gsub("\r\n", "\n"):gsub("\t", "    "):gsub("%f[A-Za-z_]do%f[^A-Za-z_]", "do\n"):gsub("%f[A-Za-z_]then%f[^A-Za-z_]", "then\n"):gsub("%f[A-Za-z_]else%f[^A-Za-z_]", "else\n"):gsub("\n *", "\n"):gsub("function(%b()) ", "function%1\n")
	local lines = newList(('\n'):split(text))
	local t = newList()
	local indent = 0
	for i = #lines, 1, -1 do
		local v = lines[i]
		if v:match("^%s*$") then
			table.remove(lines, i)
		end
	end
	for i, v in ipairs(lines) do
		if v:match("end;?$") or v:match("else$") or v:match("^ *elseif") then
			indent = indent - 1
		end
		for j = 1, indent do
			t[#t+1] = "    "
		end
		t[#t+1] = v:gsub(";\s*$", "")
		t[#t+1] = " -- "
		t[#t+1] = i
		t[#t+1] = "\n"
		if v:match("then$") or v:match("do$") or v:match("else$") or v:match("function%(.-%)") then
			indent = indent + 1
		end
	end
	lines = del(lines)
	local s = table.concat(t)
	t = del(t)
	return s
end

local newUniqueVar, delUniqueVar, clearUniqueVars, getNumUniqueVars
do
	local num = 0
	local pool = {}
	function newUniqueVar()
		local t = next(pool)
		if t then
			pool[t] = nil
			return t
		end
		num = num + 1
		return 'arg' .. num
	end
	function delUniqueVar(t)
		pool[t] = true
	end
	function clearUniqueVars()
		for k in pairs(pool) do
			pool[k] = nil
		end
		num = 0
	end
	function getNumUniqueVars()
		return num
	end
end


local compile

local function getTagData(tag, nsList)
	for _, ns in ipairs(unpackNamespaceList[nsList]) do
		local Tags_ns = Tags[ns]
		if Tags_ns then
			local Tags_ns_tag = Tags_ns[tag]
			if Tags_ns_tag then
				return Tags_ns_tag, ns
			end
		end
	end
end

local function getKwargsForAST(ast, nsList, extraKwargs)
	local tag
	if ast[1] == "tag" then
		tag = ast[2]
	else
		tag = ast[1]
	end
	
	local tagData = getTagData(tag, nsList)
	
	local arg = tagData.arg
	if not arg then
		return newList() -- no issue, but no point
	end
	
	local kwargs = newList()
	if extraKwargs then
		-- extra kwargs specified on fontstring registration, e.g. { unit = "player" }
		for k,v in pairs(extraKwargs) do
			kwargs[k] = extraKwargs
		end
	end
	
	if ast.kwarg then
		for k,v in pairs(ast.kwarg) do
			kwargs[k] = v
		end
	end
	
	return kwargs
end

local function mytonumber(value)
	local type_value = type(value)
	if type_value == "number" then
		return value
	elseif type_value ~= "string" then
		return nil
	end
	if value:match("^0x") then
		return nil
	end
	return tonumber(value)
end
DogTag.__mytonumber = mytonumber

local interpolationHandler__compiledKwargs
local function interpolationHandler(str)
	local compiledKwargs = interpolationHandler__compiledKwargs
	
	if str == "#..." then
		local num = 1
		while compiledKwargs["..." .. num] do
			num = num + 1
		end
		return num-1
	end
	
	local str, strModifier = (':'):split(str, 2)
	
	local compiledKwargs_str = compiledKwargs[str]
	if compiledKwargs_str then
		local result, resultTypes = compiledKwargs_str[1], compiledKwargs_str[2]
		
		if strModifier == "type" then
			if resultTypes:find(";") then
				return "type(" .. result .. ")"
			else
				return ("%q"):format(resultTypes)
			end
		elseif strModifier == "string" then	
			if resultTypes == "string" then
				return result
			elseif resultTypes == "number" then
				if tonumber(result:sub(2, -2)) then
					return ("(%q)"):format(tostring(0+result:sub(2, -2)))
				else
					return "tostring(" .. result .. ")"
				end
			elseif resultTypes == "nil" then
				return "('')"
			elseif resultTypes == "number;string" then
				return "tostring(" .. result .. ")"
			elseif resultTypes == "nil;string" then
				return "(" .. result .. " or '')"
			elseif resultTypes == "boolean" or resultTypes == "boolean;nil" then
				return "(" .. result .. (" and %q or '')"):format(L["True"])
			elseif resultTypes == "boolean;string" or resultTypes == "boolean;nil;string" then
				return "(type(" .. result .. ") == 'string' and " .. result .. " or " .. result .. (" and %q or '')"):format(L["True"])
			elseif resultTypes == "boolean;number" or resultTypes == "boolean;nil;number" then
				return "(type(" .. result .. ") == 'number' and " .. result .. " or " .. result .. " and 1 or 0)"
			elseif resultTypes == "boolean;number;string" or resultTypes == "boolean;nil;number;string" then
				return "(" .. result .. (" == true and %q or "):format(L["True"]) .. result .. " or '')"
			else--if resultTypes == "nil;number" or resultTypes == "nil;number;string" then
				return "tostring(" .. result .. " or '')"
			end
		else
			return result
		end
	elseif str == "..." then
		local num = 1
		local t = newList()
		local compiledKwargs_str_num = compiledKwargs[str .. num]
		while compiledKwargs_str_num do
			local result, resultTypes = compiledKwargs_str_num[1], compiledKwargs_str_num[2]
			
			t[#t+1] = result
			num = num + 1
			compiledKwargs_str_num = compiledKwargs[str .. num]
		end
		local s = table.concat(t, ', ')
		t = del(t)
		return s
	end
end

local function tuple_interpolationHandler()
	local result = interpolationHandler('...')
	if result and result ~= '' then
		return ", " .. result
	else
		return ''
	end
end

local operators = {
	["+"] = true,
	["-"] = true,
	["*"] = true,
	["/"] = true,
	["%"] = true,
	["^"] = true,
	["<"] = true,
	[">"] = true,
	["<="] = true,
	[">="] = true,
	["="] = true,
	["~="] = true,
	["unm"] = true,
}

local allOperators = {
	[" "] = true,
	["and"] = true,
	["or"] = true,
	["if"] = true,
	["not"] = true,
}
for k in pairs(operators) do
	allOperators[k] = true
end

local function forceTypes(storeKey, types, forceToTypes, t)
	types = newSet((";"):split(types))
	forceToTypes = newSet((";"):split(forceToTypes))
	if forceToTypes["undef"] then
		forceToTypes["undef"] = nil
		forceToTypes["nil"] = true
	end
	
	if types["boolean"] then
		assert(type(storeKey) == "string" and (storeKey:match("^arg%d+$") or storeKey == "result"))
		if not types["string"] then
			if not types["number"] then
				t[#t+1] = storeKey
				t[#t+1] = [=[ = not not ]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[;]=]
			else
				t[#t+1] = [=[if type(]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[) ~= "number" then ]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[ = not not ]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[;]=]
				t[#t+1] = [=[end;]=]
			end
		else
			t[#t+1] = [=[if ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ == true then ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ = ]=]
			t[#t+1] = ([=[%q]=]):format(L["True"])
			t[#t+1] = [=[;end;]=]
			types["boolean"] = nil
			types["nil"] = true
		end
	end
	
	local unfulfilledTypes = newList()
	local finalTypes = newList()
	for k in pairs(types) do
		if not forceToTypes[k] then
			unfulfilledTypes[k] = true
		else
			finalTypes[k] = true
		end
	end
	types = del(types)
	if not next(unfulfilledTypes) then
		unfulfilledTypes = del(unfulfilledTypes)
		local types = joinSet(finalTypes, ';')
		finalTypes = del(finalTypes)
		forceToTypes = del(forceToTypes)
		if type(storeKey) ~= "string" or (not storeKey:match("^arg%d+$") and storeKey ~= "result" and not storeKey:match("^%(.*%)$")) then
			storeKey = "(" .. storeKey .. ")"
		end
		return storeKey, types
	end
	if unfulfilledTypes['nil'] then
		-- we have a possible unrequested nil
		if forceToTypes['boolean'] then
			if type(storeKey) == "string" and storeKey:match("^arg%d+$") then
				t[#t+1] = storeKey
				t[#t+1] = [=[ = ]=]
				if unfulfilledTypes['number'] or unfulfilledTypes['string'] then
					-- and a possible unrequested number or string
					t[#t+1] = [=[not not ]=]
					t[#t+1] = storeKey
					t[#t+1] = [=[;]=]
				else
					t[#t+1] = [=[false;]=]
				end
			else
				assert(storeKey == "nil" or storeKey == "(nil)")
				storeKey = "false"
			end
			finalTypes['boolean'] = true
		elseif forceToTypes['string'] then
			if type(storeKey) == "string" and storeKey:match("^arg%d+$") then
				t[#t+1] = storeKey
				t[#t+1] = [=[ = ]=]
				if unfulfilledTypes['number'] then
					-- and a possible unrequested number
					t[#t+1] = [=[tostring(]=]
					t[#t+1] = storeKey
					t[#t+1] = [=[ or '');]=]
				else
					t[#t+1] = [=['';]=]
				end
			else
				if storeKey == "nil" then
					storeKey = "''"
				else
					storeKey = tostring(storeKey or "''")
				end
			end
			finalTypes['string'] = true
		elseif forceToTypes['number'] then
			if type(storeKey) == "string" and storeKey:match("^arg%d+$") then
				t[#t+1] = [=[if not ]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[ then ]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[ = ]=]
				t[#t+1] = [=[0;]=]
				t[#t+1] = [=[end;]=]
			else
				if storeKey == "nil" then
					storeKey = "0"
				else
					storeKey = tonumber(storeKey) or "0"
				end
			end	
			finalTypes['number'] = true
		end
	elseif unfulfilledTypes['number'] then
		-- we have a possible unrequested number
		if forceToTypes['boolean'] then
			if type(storeKey) == "string" and storeKey:match("^arg%d+$") then
				t[#t+1] = storeKey
				t[#t+1] = [=[ = true;]=]
			else
				storeKey = "true"
			end
			finalTypes['boolean'] = true
		elseif forceToTypes['string'] then
			if type(storeKey) == "string" and storeKey:match("^arg%d+$") then
				if forceToTypes['nil'] then
					t[#t+1] = [=[if ]=]
					t[#t+1] = storeKey
					t[#t+1] = [=[ then ]=]
				end
				t[#t+1] = storeKey
				t[#t+1] = [=[ = tostring(]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[);]=]
				if forceToTypes['nil'] then
					t[#t+1] = [=[end;]=]
				end
			else
				if not forceToTypes['nil'] and storeKey ~= 'nil' and storeKey ~= '(nil)' then
					if storeKey:match("^%(.*%)$") then
						storeKey = storeKey:sub(2, -2)+0
					else
						storeKey = storeKey+0
					end
					storeKey = ("%q"):format(tostring(storeKey))
				end
			end
			finalTypes['string'] = true
		elseif forceToTypes['nil'] then
			if type(storeKey) == "string" and storeKey:match("^arg%d+$") then
				t[#t+1] = storeKey
				t[#t+1] = [=[ = nil;]=]
			else
				storeKey = "nil"
			end
			finalTypes['nil'] = true
		end
	elseif unfulfilledTypes['string'] then
		-- we have a possible unrequested string
		if forceToTypes['boolean'] then
			if type(storeKey) == "string" and storeKey:match("^arg%d+$") then
				t[#t+1] = storeKey
				t[#t+1] = [=[ = true;]=]
			else
				storeKey = "true"
			end
			finalTypes['boolean'] = true
		elseif forceToTypes['number'] then
			if type(storeKey) == "string" and storeKey:match("^arg%d+$") then
				t[#t+1] = storeKey
				t[#t+1] = [=[ = tonumber(]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[)]=]
				if not forceToTypes['nil'] then
					t[#t+1] = [=[ or 0]=]
				else
					finalTypes['nil'] = true
				end
				t[#t+1] = [=[;]=]
			else
				storeKey = tonumber(storeKey)
				if not forceToTypes['nil'] and not storeKey then
					storeKey = 0
				end
				storeKey = tostring(storeKey)
			end
			finalTypes['number'] = true
		elseif forceToTypes['nil'] then
			if type(storeKey) == "string" and storeKey:match("^arg%d+$") then
				t[#t+1] = storeKey
				t[#t+1] = [=[ = nil;]=]
			else
				storeKey = "nil"
			end
			finalTypes['nil'] = true
		end
	elseif unfulfilledTypes["boolean"] then
		if forceToTypes["string"] then
			t[#t+1] = [=[if ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ then ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ = ]=]
			t[#t+1] = ([=[%q]=]):format(L["True"])
			t[#t+1] = [=[; else ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ = ]=]
			if forceToTypes["nil"] then
				t[#t+1] = [=[nil]=]
				finalTypes['nil'] = true
			else
				t[#t+1] = [=['']=]
			end
			t[#t+1] = [=[;end;]=]
			finalTypes['string'] = true
		elseif forceToTypes["number"] then
			t[#t+1] = [=[if ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ then ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ = 1; else ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ = ]=]
			if forceToTypes["nil"] then
				t[#t+1] = [=[nil]=]
				finalTypes['nil'] = true
			else
				t[#t+1] = [=[0]=]
			end
			t[#t+1] = [=[;end;]=]
			finalTypes['number'] = true
		elseif forceToTypes["nil"] then
			t[#t+1] = storeKey
			t[#t+1] = [=[ = nil;]=]
			finalTypes['nil'] = true
		end
	end
	unfulfilledTypes = del(unfulfilledTypes)
	forceToTypes = del(forceToTypes)
	local types = joinSet(finalTypes, ';')
	finalTypes = del(finalTypes)
	if type(storeKey) ~= "string" or (not storeKey:match("^arg%d+$") and storeKey ~= "result" and not storeKey:match("^%(.*%)$")) then
		storeKey = "(" .. storeKey .. ")"
	end
	return storeKey, types
end

local function numberToString(num)
	if num == 1/0 then
		return "1/0"
	elseif num == -1/0 then
		return "-1/0"
	elseif math.floor(num) == num then
		return tostring(num)
	else
		return ("%.22f"):format(num)
	end
end

function compile(ast, nsList, t, cachedTags, globals, events, extraKwargs, forceToTypes, storeKey, saveFirstArg)
	local astType = getASTType(ast)
	if astType == 'nil' or ast == "@undef" then
		if storeKey then
			t[#t+1] = storeKey
			t[#t+1] = [=[ = ]=]
			t[#t+1] = "nil"
			t[#t+1] = [=[;]=]
			return forceTypes(storeKey, "nil", forceToTypes, t)
		else
			return forceTypes("nil", "nil", forceToTypes, t)
		end
	elseif astType == 'kwarg' then
		local kwarg = extraKwargs[ast[2]]
		local arg, types = kwarg[1], kwarg[2]
		if storeKey then
			t[#t+1] = storeKey
			t[#t+1] = [=[ = ]=]
			t[#t+1] = arg
			t[#t+1] = [=[;]=]
			return forceTypes(storeKey, types, forceToTypes, t)
		else
			return forceTypes(arg, types, forceToTypes, t)
		end
	elseif astType == 'string' then
		if ast == '' then
			return compile(nil, nsList, t, cachedTags, globals, events, extraKwargs, forceToTypes, storeKey)
		else
			if storeKey then
				t[#t+1] = storeKey
				t[#t+1] = [=[ = ]=]
				t[#t+1] = ([=[%q]=]):format(ast)
				t[#t+1] = [=[;]=]
				return forceTypes(storeKey, "string", forceToTypes, t)
			else
				return forceTypes(([=[%q]=]):format(ast), "string", forceToTypes, t)
			end
		end
	elseif astType == 'number' then
		if storeKey then
			t[#t+1] = storeKey
			t[#t+1] = [=[ = ]=]
			t[#t+1] = numberToString(ast)
			t[#t+1] = [=[;]=]
			return forceTypes(storeKey, "number", forceToTypes, t)
		else
			return forceTypes(numberToString(ast), "number", forceToTypes, t)
		end
	elseif astType == 'tag' or operators[astType] then
		local tag = ast[astType == 'tag' and 2 or 1]
		local tagData, tagNS = getTagData(tag, nsList)
		if not storeKey then
			storeKey = newUniqueVar()
		end
		local caching, cachingFirst
		if astType == 'tag' and not ast.kwarg and cachedTags[tag] then
			caching = true
			cachingFirst = cachedTags[tag] == 1
			cachedTags[tag] = 2
		end
		if caching and not cachingFirst then
			t[#t+1] = [=[if cache_]=]
			t[#t+1] = tag
			t[#t+1] = [=[ ~= NIL then ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ = cache_]=]
			t[#t+1] = tag
			t[#t+1] = [=[; else ]=]
		else
			t[#t+1] = [=[do ]=]
		end
		local kwargs = getKwargsForAST(ast, nsList, extraKwargs)
		
		local arg = tagData.arg
		
		local firstAndNonNil_t_num = #t
		local compiledKwargs = newList()
		local firstAndNonNil
		local firstMaybeNumber = false
		for k,v in pairs(kwargs) do
			if v == extraKwargs then
				compiledKwargs[k] = newList(unpack(extraKwargs[k]))
			else
				local argTypes = "nil;number;string;boolean"
				local arg_num
				local arg_default = false
				if not k:match("^%.%.%.%d+$") then
					for i = 1, #arg, 3 do
						if arg[i] == k then
							argTypes = arg[i+1]
							arg_num = (i-1)/3 + 1
							arg_default = arg[i+2]
							break
						end
					end
				else
					for i = 1, #arg, 3 do
						if arg[i] == "..." then
							arg_num = (i-1)/3 + 1
							if arg[i+1]:match("^tuple%-") then
								argTypes = arg[i+1]:sub(7)
							else
								break
							end
						end
					end
				end
				if arg_num == 1 and (arg_default == "@req" or arg_default == "@undef") then
					local a = newSet((";"):split(argTypes))
					firstAndNonNil = not a["nil"] and not a["boolean"] and k
					if firstAndNonNil then
						a["undef"] = nil
						a["nil"] = true
						argTypes = joinSet(a, ";")
					end
					a = del(a)
				end
				local arg, types
				if arg_num == 1 then
					local rawTypes
					arg, rawTypes = compile(v, nsList, t, cachedTags, globals, events, extraKwargs, "boolean;nil;number;string")
					arg, types = forceTypes(arg, rawTypes, argTypes, t)
					local a = newSet((";"):split(rawTypes))
					firstMaybeNumber = a['number'] and rawTypes
					a = del(a)
				else
					arg, types = compile(v, nsList, t, cachedTags, globals, events, extraKwargs, argTypes)
				end
				if firstAndNonNil == k then
					local returns = newSet((";"):split(types))
					if v == "@undef" then
						firstAndNonNil = nil
						firstAndNonNil_t_num = nil
					elseif not returns["nil"] then
						firstAndNonNil = nil
						firstAndNonNil_t_num = nil
					elseif returns["string"] or returns["number"] then
						firstAndNonNil_t_num = nil
					end
					returns = del(returns)
				end
				compiledKwargs[k] = newList(arg, types)
			end
		end
		if firstAndNonNil then
			local compiledKwargs_firstAndNonNil = compiledKwargs[firstAndNonNil]
			t[#t+1] = [=[if ]=]
			t[#t+1] = compiledKwargs_firstAndNonNil[1]
			t[#t+1] = [=[ then ]=]
			local args = newSet((';'):split(compiledKwargs_firstAndNonNil[2]))
			args['nil'] = nil
			compiledKwargs_firstAndNonNil[2] = joinSet(args, ';')
			args = del(args)
		end
		
		for step in pairs(compilationSteps.tag[tagNS]) do
			step(ast, t, tag, tagData, kwargs, extraKwargs, compiledKwargs)
		end
		
		local passData = newList() -- data that will be passed into functions like ret, code, etc.
		for k, v in pairs(kwargs) do
			local passData_k = newList()
			passData[k] = passData_k
			if type(v) ~= "table" or v[1] == "nil" then
				local value = type(v) ~= "table" and v or nil
				passData_k.isLiteral = true
				passData_k.value = value
				passData_k.types = type(value)
			else
				passData_k.isLiteral = false
				passData_k.value = v
				passData_k.types = compiledKwargs[k][2]
			end
		end
		
		local code = tagData.code
		local ret = tagData.ret
		local globs = tagData.globals
		local evs = tagData.events
		
		if type(ret) == "function" then
			ret = ret(passData)
		end
		if type(code) == "function" then
			code = code(passData)
		end
		if type(globs) == "function" then
			globs = globs(passData)
		end
		if type(evs) == "function" then
			evs = evs(passData)
		end
		for k, v in pairs(passData) do
			passData[k] = del(v)
		end
		passData = del(passData)
		
		if globs then
			globs = newSet((";"):split(globs))
			for k in pairs(globs) do
				globals[k] = true
			end
			globs = del(globs)
		end
		
		local evs = evs and newSet((";"):split(evs)) or newSet()
		for step in pairs(compilationSteps.tagevents[tagNS]) do
			step(ast, t, tag, tagData, kwargs, extraKwargs, compiledKwargs, evs)
		end
		
		for k in pairs(evs) do
			local ev, param = ("#"):split(k, 2)
			local events_ev = events[ev]
			if events_ev ~= true then
				if param then
					if param:match("^%$") then
						local real_param = param:sub(2)
						local compiledKwargs_real_param = compiledKwargs[real_param]
						if not compiledKwargs_real_param then
							error(("Unknown event parameter %q for tag %s. Please inform ckknight."):format(real_param, tag))
						end
						local compiledKwargs_real_param_1 = compiledKwargs_real_param[1]
						if not compiledKwargs_real_param_1:match("^kwargs_[a-z]+$") then
							local kwargs_real_param = kwargs[real_param]
							if type(kwargs_real_param) == "table" then
								param = unparse(kwargs_real_param)
							else
								param = kwargs_real_param or true
							end
						end
					end
					if type(events_ev) == "table" then
						if param == true then
							del(events_ev)
							events[ev] = true
						else
							events_ev[param] = true
						end
					elseif events_ev and events_ev ~= param then
						if param == true then
							events[ev] = true
						else
							events[ev] = newSet(events_ev, param)
						end
					else
						events[ev] = param
					end
				else
					if type(events_ev) == "table" then
						del(events_ev)
					end
					events[ev] = true
				end
			end
		end
		evs = del(evs)
		
		interpolationHandler__compiledKwargs = compiledKwargs
		code = code:gsub(",%s*${%.%.%.}", tuple_interpolationHandler)
		interpolationHandler__compiledKwargs = compiledKwargs
		code = code:gsub("${(.-)}", interpolationHandler)
		interpolationHandler__compiledKwargs = nil
		
		code = code:gsub("return ", storeKey .. " = ")
		t[#t+1] = code
		t[#t+1] = [=[;]=]
		
		local savedArg, savedArgTypes
		for k,v in pairs(compiledKwargs) do
			if saveFirstArg and k == arg[1] then
				savedArg = v[1]
				savedArgTypes = v[2]
			elseif v[1]:match("^arg%d+$") then
				t[#t+1] = v[1]
				delUniqueVar(v[1])
				t[#t+1] = [=[ = nil;]=]
			end
			compiledKwargs[k] = del(v)
		end
		compiledKwargs = del(compiledKwargs)
		
		if firstAndNonNil then
			t[#t+1] = [=[end;]=]
			local returns = newSet((";"):split(ret))
			returns["nil"] = true
			ret = joinSet(returns, ";")
			returns = del(returns)
			if firstAndNonNil_t_num then
				for i = firstAndNonNil_t_num+1, #t do
					t[i] = nil
				end
			end
		end
		
		if caching then
			t[#t+1] = [=[cache_]=]
			t[#t+1] = tag
			t[#t+1] = [=[ = ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[;]=]
		end
		t[#t+1] = [=[end;]=]
		
		kwargs = del(kwargs)
		if firstMaybeNumber then
			local types = newSet((";"):split(forceToTypes))
			if types['number'] then
				local retData = newSet((";"):split(ret))
				if retData['string'] and not retData['number'] then
					t[#t+1] = [=[if DogTag___mytonumber(]=]
					t[#t+1] = storeKey
					t[#t+1] = [=[) then ]=]
					t[#t+1] = storeKey
					t[#t+1] = [=[ = ]=]
					t[#t+1] = storeKey
					t[#t+1] = [=[+0;end;]=]
					retData['number'] = true
					ret = joinSet(retData, ';')
				end
				retData = del(retData)
			end
			types = del(types)
		end
		local a, b = forceTypes(storeKey, ret, forceToTypes, t)
		return a, b, savedArg, savedArgTypes
	elseif astType == ' ' then
		local t_num = #t
		local args = newList()
		local argTypes = newList()
		for i = 2, #ast do
			local t_num = #t
			local arg, err = compile(ast[i], nsList, t, cachedTags, globals, events, extraKwargs, "nil;number;string")
			args[#args+1] = arg
			argTypes[#argTypes+1] = err
			if #t ~= t_num then
				table.insert(t, t_num+1, [=[do ]=])
				t[#t+1] = [=[end;]=]
			end
		end
		if not storeKey then
			storeKey = newUniqueVar()
		end
		t[#t+1] = storeKey
		t[#t+1] = [=[ = ]=]
		local finalTypes = newList()
		for i,v in ipairs(args) do
			if i > 1 then
				t[#t+1] = [=[ .. ]=]
			end
			local types = argTypes[i]
			types = newSet((';'):split(types))
			if types['nil'] and (types['string'] or types['number']) then
				t[#t+1] = "("
				t[#t+1] = v
				t[#t+1] = " or '')"
			elseif types['nil'] then
				-- just nil
				t[#t+1] = "''"
			else
				-- non-nil
				t[#t+1] = v
			end
			if types['nil'] then
				if not next(finalTypes) then
					finalTypes['nil'] = true
				end
			else
				finalTypes['nil'] = nil
			end
			if types['number'] and not finalTypes['string'] then
				if finalTypes['number'] then
					finalTypes['string'] = true
				end
				finalTypes['number'] = true
			end
			if types['string'] then
				if not types['number'] then
					finalTypes['number'] = nil
				end
				finalTypes['string'] = true
			end
			types = del(types)
		end
		t[#t+1] = [=[;]=]
		if finalTypes['number'] then
			t[#t+1] = [=[if DogTag___mytonumber(]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[) then ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ = ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[+0;]=]
		end
		if finalTypes['nil'] then
			if finalTypes['number'] then
				t[#t+1] = [=[elseif ]=]
			else
				t[#t+1] = [=[if ]=]
			end
			t[#t+1] = storeKey
			t[#t+1] = [=[ == '' then ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ = nil;]=]
			t[#t+1] = [=[end;]=]
		else
			if finalTypes['number'] then
				t[#t+1] = [=[end;]=]
			end
		end
		for i,v in ipairs(args) do
			if type(v) == "string" and v:match("^arg%d+$") then
				t[#t+1] = v
				delUniqueVar(v)
				t[#t+1] = [=[ = nil;]=]
			end
		end
		args = del(args)
		argTypes = del(argTypes)
		local s = joinSet(finalTypes, ';')
		finalTypes = del(finalTypes)
		return forceTypes(storeKey, s, forceToTypes, t)
	elseif astType == 'and' or astType == 'or' then
		if not storeKey then
			storeKey = newUniqueVar()
		end
		local t_num = #t
		t[#t+1] = [=[do ]=]
		local arg, firstResults = compile(ast[2], nsList, t, cachedTags, globals, events, extraKwargs, astType == 'and' and "boolean;nil;number;string" or "nil;number;string", storeKey)
		firstResults = newSet((";"):split(firstResults))
		local totalResults = newList()
		t[#t+1] = [=[end;]=]
		if firstResults["nil"] or firstResults['boolean'] then
			t[#t+1] = [=[if ]=]
			if astType == 'or' then
				t[#t+1] = [=[not ]=]
			end
			t[#t+1] = storeKey
			t[#t+1] = [=[ then ]=]
			local arg, secondResults = compile(ast[3], nsList, t, cachedTags, globals, events, extraKwargs, "nil;number;string", storeKey)
			secondResults = newSet((";"):split(secondResults))
			t[#t+1] = [=[end;]=]
			for k in pairs(firstResults) do
				if k ~= "nil" and k ~= "boolean" then
					totalResults[k] = true
				end
			end
			for k in pairs(secondResults) do
				totalResults[k] = true
			end
			secondResults = del(secondResults)
		elseif astType == 'and' then
			for i = t_num, #t do
				t[i] = nil
			end
			local arg, secondResults = compile(ast[3], nsList, t, cachedTags, globals, events, extraKwargs, "nil;number;string", storeKey)
			secondResults = newSet((";"):split(secondResults))
			for k in pairs(totalResults) do
				totalResults[k] = nil
			end
			for k in pairs(secondResults) do
				totalResults[k] = true
			end
			secondResults = del(secondResults)
		else
			for k in pairs(firstResults) do
				totalResults[k] = true
			end
		end
		firstResults = del(firstResults)
		local s = joinSet(totalResults, ';')
		totalResults = del(totalResults)
		return forceTypes(storeKey, s, forceToTypes, t)
	elseif astType == 'if' then
		if not storeKey then
			storeKey = newUniqueVar()
		end
		local hasElse = not not ast[4]
		local t_num = #t
		t[#t+1] = [=[do ]=]
		local storeKey, condResults = compile(ast[2], nsList, t, cachedTags, globals, events, extraKwargs, "boolean;nil;number;string", storeKey)
		condResults = newSet((';'):split(condResults))
		t[#t+1] = [=[end;]=]
		if condResults["boolean"] or (condResults["nil"] and (condResults["string"] or condResults["number"])) then
			condResults = del(condResults)
			t[#t+1] = [=[if ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ then ]=]
			local arg, firstResults = compile(ast[3], nsList, t, cachedTags, globals, events, extraKwargs, forceToTypes, storeKey)
			local totalResults = newSet((";"):split(firstResults))
			t[#t+1] = [=[ else ]=]
			local secondResults
			if hasElse then
				storeKey, secondResults = compile(ast[4], nsList, t, cachedTags, globals, events, extraKwargs, forceToTypes, storeKey)
			else
				t[#t+1] = storeKey
				t[#t+1] = [=[ = nil;]=]
				storeKey, secondResults = forceTypes(storeKey, "nil", forceToTypes, t)
			end
			secondResults = newSet((";"):split(secondResults))
			for k in pairs(secondResults) do
				totalResults[k] = true
			end
			secondResults = del(secondResults)
			t[#t+1] = [=[end;]=]
			
			local s = joinSet(totalResults, ';')
			totalResults = del(totalResults)
			return forceTypes(storeKey, s, forceToTypes, t)
		elseif condResults["nil"] then
			-- just nil
			condResults = del(condResults)
			for i = t_num, #t do
				t[i] = nil
			end
			if type(cond) == "string" and cond:match("^arg%d+$") then
				delUniqueVar(cond)
			end
			return compile(ast[4], nsList, t, cachedTags, globals, events, extraKwargs, forceToTypes, storeKey)
		else
			-- non-nil
			condResults = del(condResults)
			for i = t_num, #t do
				t[i] = nil
			end
			if type(cond) == "string" and cond:match("^arg%d+$") then
				delUniqueVar(cond)
			end
			return compile(ast[3], nsList, t, cachedTags, globals, events, extraKwargs, forceToTypes, storeKey)
		end
	elseif astType == 'not' then
		local t_num = #t
		local s, results, savedArg, savedArgTypes = compile(ast[2], nsList, t, cachedTags, globals, events, extraKwargs, "boolean;nil;number;string", storeKey, true)
		results = newSet((";"):split(results))
		if results["boolean"] or (results["nil"] and (results["string"] or results["number"])) then
			results = del(results)
			storeKey = s
			
			local types = newList()
			
			if savedArg then
				types["nil"] = true
				t[#t+1] = [=[if ]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[ then ]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[ = nil; else ]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[ = ]=]
				t[#t+1] = savedArg
				savedArgTypes = newSet((";"):split(savedArgTypes))
				if savedArgTypes["nil"] then
					t[#t+1] = [=[ or ]=]
					t[#t+1] = ("%q"):format(L["True"])
					savedArgTypes["string"] = true
					savedArgTypes["nil"] = nil
				end
				for k in pairs(savedArgTypes) do
					types[k] = true
				end
				savedArgTypes = del(savedArgTypes)
				t[#t+1] = [=[;]=]
				t[#t+1] = [=[end;]=]
				if savedArg:match("^arg%d+$") then
					t[#t+1] = savedArg
					delUniqueVar(savedArg)
					t[#t+1] = [=[ = nil;]=]
				end
			else
				t[#t+1] = storeKey
				t[#t+1] = [=[ = not ]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[;]=]
				types["boolean"] = true
			end
			local s = joinSet(types, ";")
			types = del(types)
			return forceTypes(storeKey, s, forceToTypes, t)
		elseif results["nil"] then	
			-- just nil
			results = del(results)
			
			if savedArg then
				storeKey = s
				
				local types = newList()
				t[#t+1] = storeKey
				t[#t+1] = [=[ = ]=]
				t[#t+1] = savedArg
				savedArgTypes = newSet((";"):split(savedArgTypes))
				if savedArgTypes["nil"] then
					t[#t+1] = [=[ or ]=]
					t[#t+1] = ("%q"):format(L["True"])
					savedArgTypes["string"] = true
					savedArgTypes["nil"] = nil
				end	
				t[#t+1] = [=[;]=]
				for k in pairs(savedArgTypes) do
					types[k] = true
				end
				savedArgTypes = del(savedArgTypes)
				local s = joinSet(types, ';')
				types = del(types)
				return forceTypes(storeKey, s, forceToTypes, t)
			else
				for i = t_num, #t do
					t[i] = nil
				end
				if storeKey then
					t[#t+1] = storeKey
					t[#t+1] = [=[ = ]=]
					t[#t+1] = ("%q"):format(L["True"])
					t[#t+1] = [=[;]=]
					return forceTypes(storeKey, "string", forceToTypes, t)
				else
					return forceTypes(("%q"):format(L["True"]), "string", forceToTypes, t)
				end
			end
		else
			-- non-nil
			results = del(results)
			
			for i = t_num, #t do
				t[i] = nil
			end
			if storeKey then
				t[#t+1] = storeKey
				t[#t+1] = [=[ = nil;]=]
				return forceTypes(storeKey, "nil", forceToTypes, t)
			else
				return forceTypes("nil", "nil", forceToTypes, t)
			end
		end
	elseif astType == '...' then
		t[#t+1] = [=[do return "... used inappropriately" end;]=]
		return "nil", "nil"
	end
	error(("Unknown astType: %q"):format(tostring(astType or '')))
end

local unalias
do
	local function replaceArg(ast, argName, value)
		local astType = getASTType(ast)
		if astType ~= "tag" and not allOperators[astType] then
			return
		end
		local argStart = astType == "tag" and 3 or 2
		for i = argStart, #ast do
			local v = ast[i]
			local astType = getASTType(v)
			if astType == "tag" and v[2] == argName then
				deepDel(v)
				ast[i] = deepCopy(value)
			else
				replaceArg(v, argName, value)
			end
		end
		if ast.kwarg then
			for k, v in pairs(ast.kwarg) do
				local astType = getASTType(v)
				if astType == "tag" and v[2] == argName then
					deepDel(v)
					ast.kwarg[k] = deepCopy(value)
				else
					replaceArg(v, argName, value)
				end
			end
		end
	end
	
	local function replaceTupleArg(ast, tupleArgs)
		local astType = getASTType(ast)
		if astType ~= "tag" and not allOperators[astType] then
			return
		end
		local argStart = astType == "tag" and 3 or 2
		for i = argStart, #ast do
			local v = ast[i]
			local astType = getASTType(v)
			if astType == "..." then
				deepDel(v)
				ast[i] = nil
				for j, u in ipairs(tupleArgs) do
					ast[i+j-1] = u
				end
				break
			else
				replaceTupleArg(v, tupleArgs)
			end
		end
	end
	
	function unalias(ast, nsList, kwargTypes)
		if type(ast) ~= "table" then
			return ast
		end
		local astType = getASTType(ast)
		if astType ~= "tag" then
			for i = 2, #ast do
				ast[i] = unalias(ast[i], nsList, kwargTypes)
			end
			return ast
		end
		local tag = ast[2]
		local tagData = getTagData(tag, nsList)
	
		if not tagData or tagData.code then
			for i = 3, #ast do
				ast[i] = unalias(ast[i], nsList, kwargTypes)
			end
			return ast
		end
		
		local alias = "[" .. tagData.alias .. "]"
		local args = newList()
		local tupleArgs = newList()
		local arg = tagData.arg
		for i = 1, #arg, 3 do
			local argName = arg[i]
			if argName == "..." then
				local num = 0
				while true do
					num = num + 1
					local val = ast[(i-1)/3 + 2 + num]
					if not val then
						break
					end
					tupleArgs[num] = val
				end
				break
			else
				local val = ast[(i-1)/3 + 3] or ast.kwarg and ast.kwarg[argName]
				if not val and kwargTypes[argName] then
					val = newList("kwarg", argName)
				end
				if not val and arg[i+2] == "@req" then
					args = del(args)
					return nil, ("Arg #%d (%s) req'd for %s"):format((i-1)/3+1, argName, tag)
				end
				if not val then
					val = arg[i+2]
				end
				args[argName] = val
			end
		end
		local parsedAlias = parse(alias)
		if not parsedAlias then
			return nil, ("Syntax error with alias %s"):format(tag)
		end
		local parsedAlias = standardize(parsedAlias)
		for k,v in pairs(args) do
			replaceArg(parsedAlias, k, v)
		end
		replaceTupleArg(parsedAlias, tupleArgs)
		deepDel(ast)
		
		ast = parsedAlias
		ast = standardize(ast)
		correctASTCasing(ast)
		return unalias(ast, nsList, kwargTypes)
	end
end

local function readjustKwargs(ast, nsList, kwargTypes)
	if type(ast) ~= "table" then
		return ast
	end
	local astType = ast[1]
	for i = 2, #ast do
		local ast_i, err = readjustKwargs(ast[i], nsList, kwargTypes)
		if not ast_i then
			return ast_i, err
		end
		ast[i] = ast_i
	end
	if astType == "tag" or operators[astType] then
		local start = astType == "tag" and 3 or 2
		local tag = astType == "tag" and ast[2] or astType
		local tagData = getTagData(tag, nsList)
		if not tagData then
			return nil, ("Unknown tag %s"):format(tostring(tag))
		end
		local arg = tagData.arg
		if not ast.kwarg then
			ast.kwarg = newList()
		end
		if arg then
			local ast_len = #ast
			local hitTuple = false
			for i = 1, #arg, 3 do
				local argName = arg[i]
				local default = arg[i+2]
				if default == true then
					default = L["True"]
				end
				if argName == "..." then
					hitTuple = true
					for j = start + ((i-1)/3), ast_len do
						local num = j - start - ((i-1)/3) + 1
						ast.kwarg["..." .. num] = ast[j]
						ast[j] = nil
					end
					for j = i+3, #arg, 3 do
						argName = arg[j]
						default = arg[j+2]
						if not ast.kwarg[argName] and not kwargTypes[argName] then
							if default == "@req" then
								return nil, ("Keyword-Arg %s req'd for %s"):format(argName, tag)
							end
							ast.kwarg[argName] = default
						end
					end
					break
				else
					local astVar = ast[start + ((i-1)/3)]
					if not astVar then
						if not ast.kwarg[argName] and not kwargTypes[argName] then
							if default == "@req" then
								return nil, ("Arg #%d (%s) req'd for %s"):format((i-1)/3 + 1, argName, tag)
							end
							ast.kwarg[argName] = default
						end
					else
						ast.kwarg[argName] = astVar
						ast[start + ((i-1)/3)] = nil
					end
				end
			end
			if not hitTuple then
				if #arg/3 < (ast_len - start + 1) then
					return nil, ("Too many args for %s"):format(tag)
				end
			end
		end
		if not next(ast.kwarg) then
			ast.kwarg = del(ast.kwarg)
		end
		assert(#ast == start-1)
	end
	return ast
end

function DogTag:CreateFunctionFromCode(code, ...)
	if type(code) ~= "string" then
		error(("Bad argument #2 to `CreateFunctionFromCode'. Expected %q, got %q."):format("string", type(code)), 2)
	end
	local notDebug = (...) == true
	local kwargTypes = kwargsToKwargTypes[""]
	local nsList
	if notDebug then
		kwargTypes = select(2, ...)
		nsList = getNamespaceList(select(3, ...))
	else
		local n = select('#', ...)
		local kwargs = n > 0 and select(n, ...)
		if type(kwargs) == "table" then
			kwargTypes = kwargsToKwargTypes[kwargs]
			n = n - 1
		end
		for i = 1, n do
			if type(select(i, ...)) ~= "string" then
				error(("Bad argument #%d to `CreateFunctionFromCode'. Expected %q, got %q"):format(i+2, "string", type(select(i, ...))), 2)
			end
		end
		nsList = getNamespaceList(select2(1, n, ...))
	end
	
	
	local ast = parse(code)
	if not ast then
		codeToEventList[nsList][kwargTypes][code] = false
		return ("return function() return %q, nil end"):format("Syntax error")
	end
	ast = standardize(ast)
	correctASTCasing(ast)
	local err
	ast, err = unalias(ast, nsList, kwargTypes)
	if not ast then
		codeToEventList[nsList][kwargTypes][code] = false
		return ("return function() return %q, nil end"):format(err)
	end
	ast, err = readjustKwargs(ast, nsList, kwargTypes)
	if not ast then
		codeToEventList[nsList][kwargTypes][code] = false
		return ("return function() return %q, nil end"):format(err)
	end
	for _, ns in ipairs(unpackNamespaceList[nsList]) do
		for step in pairs(compilationSteps.pre[ns]) do
			ast, err = step(ast, kwargTypes)
			if not ast then
				codeToEventList[nsList][kwargTypes][code] = false
				return ("return function() return %q, nil end"):format(err)
			end
		end
	end
	
	local t = newList()
	t[#t+1] = [=[local _G = _G;]=]
	t[#t+1] = ([=[local DogTag = _G.LibStub(%q);]=]):format(MAJOR_VERSION)
	t[#t+1] = [=[local colors = DogTag.__colors;]=]
	t[#t+1] = [=[local NIL = DogTag.__NIL;]=]
	t[#t+1] = [=[local cleanText = DogTag.__cleanText;]=]
	local globals_t_num = #t
	t[#t+1] = [=[return function(kwargs) ]=]
	t[#t+1] = [=[local result, opacity;]=]
	
	local cachedTags = figureCachedTags(ast)
	for k in pairs(cachedTags) do
		t[#t+1] = [=[local cache_]=]
		t[#t+1] = k
		t[#t+1] = [=[ = NIL;]=]
	end
	
	local u = newList()
	local extraKwargs = newList()
	for k, v in pairs(kwargTypes) do
		local arg = "kwargs_" .. k
		u[#u+1] = [=[local ]=]
		u[#u+1] = arg
		u[#u+1] = [=[ = kwargs["]=]
		u[#u+1] = k
		u[#u+1] = [=["];]=]
		extraKwargs[k] = newList(arg, v)
	end
	
	for _, ns in ipairs(unpackNamespaceList[nsList]) do
		for step in pairs(compilationSteps.start[ns]) do
			step(u, ast, kwargTypes, extraKwargs)
		end
	end
	
	local globals = newList()
	globals['table.concat'] = true
	globals['tonumber'] = true
	globals['tostring'] = true
	globals['unpack'] = true
	globals['type'] = true
	globals['DogTag.__mytonumber'] = true
	local events = newList()
	local ret, types = compile(ast, nsList, u, cachedTags, globals, events, extraKwargs, 'nil;number;string', 'result')
	for k, v in pairs(extraKwargs) do
		extraKwargs[k] = del(v)
	end
	local g = newList()
	for global in pairs(globals) do
		if global:match("^[A-Za-z0-9%-]+%-%d+%.%d+$") then
			if Rock then
				Rock(global, false, true) -- try to load
			end
			if AceLibrary then
				AceLibrary:HasInstance(global) -- try to load
			end
			if LibStub(global, true) then -- catches Rock and AceLibrary libs as well
				g[#g+1] = [=[local ]=]
				g[#g+1] = global:gsub("%-.-$", "")
				if not global:match("^Lib") then
					g[#g+1] = [=[Lib]=]
				end
				g[#g+1] = [=[ = LibStub("]=]
				g[#g+1] = k
				g[#g+1] = [=[");]=]
			end
		else
			g[#g+1] = [=[local ]=]
			g[#g+1] = global:gsub("%.", "_")
			g[#g+1] = [=[ = ]=]
			if not global:match("^DogTag%.") then
				g[#g+1] = [=[_G.]=]
			end
			g[#g+1] = global
			g[#g+1] = [=[;]=]
		end
	end
	globals = del(globals)
	for i,v in ipairs(g) do
		table.insert(t, i + globals_t_num, v)
	end
	g = del(g)
	
	if not next(events) then
		events = del(events)
		codeToEventList[nsList][kwargTypes][code] = false
	else
		events = memoizeTable(events)
		codeToEventList[nsList][kwargTypes][code] = events
	end
	for i = 1, getNumUniqueVars() do
		t[#t+1] = [=[local arg]=]
		t[#t+1] = i
		t[#t+1] = [=[;]=]
	end
	for _,v in ipairs(u) do
		t[#t+1] = v
	end
	u = del(u)
	clearUniqueVars()
	
	types = newSet((";"):split(types))
	if types["string"] then
		t[#t+1] = [=[if result == '' then result = nil; elseif DogTag___mytonumber(result) then result = result+0; end;]=]
	end
	types = del(types)
	
	for _, ns in ipairs(unpackNamespaceList[nsList]) do
		for step in pairs(compilationSteps.finish[ns]) do
			step(t, ast, kwargTypes, extraKwargs)
		end
	end
	
	extraKwargs = del(extraKwargs)
	ast = deepDel(ast)
	
	t[#t+1] = [=[return result or nil, opacity;]=]
	
	t[#t+1] = [=[end]=]
	
	cachedTags = del(cachedTags)
	local s = table.concat(t)
	t = del(t)
	if not notDebug then
		s = enumLines(s) -- avoid interning the new string if not debugging
	end
	return s
end

local function evaluate(code, nsList, kwargs)
	local kwargTypes = kwargsToKwargTypes[kwargs]

	DogTag.__isMouseOver = false

	local func = codeToFunction[nsList][kwargTypes][code]

	local madeKwargs = not kwargs
	if madeKwargs then
		kwargs = newList()
	end
	local success, text, opacity = pcall(func, kwargs)
	if madeKwargs then
		kwargs = del(kwargs)
	end
	if success then
		if opacity then
			if opacity > 1 then
				opacity = 1
			elseif opacity < 0 then
				opacity = 0
			end
		end
		return text, opacity
	else
		geterrorhandler()(("%s.%d: Error with code %q%s. %s"):format(MAJOR_VERSION, MINOR_VERSION, code, nsList == "Base" and "" or " (" .. nsList .. ")", text))
	end
end
DogTag.evaluate = evaluate

function DogTag:Evaluate(code, ...)
	if type(code) ~= "string" then
		error(("Bad argument #2 to `Evaluate'. Expected %q, got %q"):format("string", type(code)), 2)
	end
	local n = select('#', ...)
	local kwargs
	if n > 0 then
		kwargs = select(n, ...)
		if type(kwargs) == "table" then
			n = n - 1
		else
			kwargs = nil
		end
	end
	for i = 1, n do
		if type(select(i, ...)) ~= "string" then
			error(("Bad argument #%d to `Evaluate'. Expected %q, got %q"):format(i+2, "string", type(select(i, ...))), 2)
		end
	end
	local nsList = getNamespaceList(select2(1, n, ...))
	return evaluate(code, nsList, kwargs)
end

function DogTag:AddCompilationStep(namespace, kind, func)
	if type(namespace) ~= "string" then
		error(("Bad argument #2 to `AddCompilationStep'. Expected %q, got %q"):format("string", type(namespace)), 2)
	end
	if type(kind) ~= "string" then
		error(("Bad argument #3 to `AddCompilationStep'. Expected %q, got %q"):format("string", type(kind)), 2)
	elseif kind ~= "pre" and kind ~= "start" and kind ~= "tag" and kind ~= "tagevents" and kind ~= "finish" then
		error(("Bad argument #3 to `AddCompilationStep'. Expected %q, %q, %q, %q, or %q, got %q"):format("pre", "start", "tag", "tagevents", "finish", kind), 2)
	end
	if type(func) ~= "function" then
		error(("Bad argument #4 to `AddCompilationStep'. Expected %q, got %q"):format("function", type(func)), 2)
	end
	compilationSteps[kind][namespace][func] = true
	clearCodes(namespace)
end

function DogTag:RemoveCompilationStep(namespace, kind, func)
	if type(namespace) ~= "string" then
		error(("Bad argument #2 to `AddCompilationStep'. Expected %q, got %q"):format("string", type(namespace)), 2)
	end
	if type(kind) ~= "string" then
		error(("Bad argument #3 to `AddCompilationStep'. Expected %q, got %q"):format("string", type(kind)), 2)
	elseif kind ~= "pre" and kind ~= "start" and kind ~= "tag" and kind ~= "tagevents" and kind ~= "finish" then
		error(("Bad argument #3 to `AddCompilationStep'. Expected %q, %q, %q, %q, or %q, got %q"):format("pre", "start", "tag", "tagevents", "finish", kind), 2)
	end
	if type(func) ~= "function" then
		error(("Bad argument #4 to `AddCompilationStep'. Expected %q, got %q"):format("function", type(func)), 2)
	end
	compilationSteps[kind][namespace][func] = nil
	clearCodes(namespace)
end

function DogTag:RemoveAllCompilationSteps(namespace, kind)
	if type(namespace) ~= "string" then
		error(("Bad argument #3 to `AddCompilationStep'. Expected %q, got %q"):format("string", type(namespace)), 2)
	end
	if kind then
		if type(kind) ~= "string" then
			error(("Bad argument #3 to `AddCompilationStep'. Expected %q, got %q"):format("string", type(kind)), 2)
		elseif kind ~= "pre" and kind ~= "start" and kind ~= "tag" and kind ~= "tagevents" and kind ~= "finish" then
			error(("Bad argument #3 to `AddCompilationStep'. Expected %q, %q, %q, %q, or %q, got %q"):format("pre", "start", "tag", "tagevents", "finish", kind), 2)
		end
		local compilationSteps_kind_namespace = rawget(compilationSteps[kind], namespace)
		if compilationSteps_kind_namespace then
			compilationSteps[kind][namespace] = del(compilationSteps_kind_namespace)
		end
	else
		for kind, data in pairs(compilationSteps) do
			local data_namespace = rawget(data, namespace)
			if data_namespace then
				data[namespace] = del(data_namespace)
			end
		end
	end
	clearCodes(namespace)
end

end