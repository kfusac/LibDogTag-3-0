local MAJOR_VERSION = "LibDogTag-3.0"
local MINOR_VERSION = tonumber(("$Revision$"):match("%d+")) or 0

if MINOR_VERSION > _G.DogTag_MINOR_VERSION then
	_G.DogTag_MINOR_VERSION = MINOR_VERSION
end

DogTag_funcs[#DogTag_funcs+1] = function()

local DogTag = _G.DogTag

local L = DogTag__L

local FakeGlobals = DogTag.FakeGlobals
local Tags = DogTag.Tags
local newList, newDict, newSet, del = DogTag.newList, DogTag.newDict, DogTag.newSet, DogTag.del

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

local function select2(min, max, ...)
	if min <= max then
		return select(min, ...), select2(min+1, max, ...)
	end
end

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

local unpackNamespaceList = setmetatable({}, {__index = function(self, key)
	local t = newList((";"):split(key))
	self[key] = t
	return t
end, __call = function(self, key)
	return unpack(self[key])
end})

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

local kwargsKeyPool = { [""] = {} }
local function kwargsToKey(kwargs)
	if not kwargs then
		return kwargsKeyPool[""]
	end
	local kwargsKey = newList()
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
		kwargsKey[k] = type_v
	end
	keys = del(keys)
	local s = table.concat(t)
	t = del(t)
	local kwargsKeyPool_s = kwargsKeyPool[s]
	if kwargsKeyPool_s then
		kwargsKey = del(kwargsKey)
		return kwargsKeyPool_s
	end
	kwargsKeyPool[s] = kwargsKey
	return kwargsKey
end
DogTag.kwargsToKey = kwargsToKey

local codeToFunction
do
	local codeToFunction_mt_mt = {__index = function(self, code)
		if not code then
			return self[""]
		end
		local nsList = self[1]
		local kwargsKey = self[2]
		
		local s = DogTag:CreateFunctionFromCode(code, true, kwargsKey, unpackNamespaceList(nsList))
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
	local codeToFunction_mt = {__index = function(self, kwargsKey)
		local t = setmetatable(newList(self[1], kwargsKey), codeToFunction_mt_mt)
		self[kwargsKey] = t
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
			if #ast == 2 and not ast.kwarg then
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

local figureGlobals
do
	function figureGlobals(ast, nsList, kwargsKey)
		local globals = newList()
		if type(ast) ~= "table" then
			return globals
		end
		local astType = ast[1]
		if astType == 'tag' then
			local tag = ast[2]
			for _,ns in ipairs(unpackNamespaceList[nsList]) do
				local Tags_ns = Tags[ns]
				if Tags_ns then
					local Tags_ns_tag = Tags_ns[tag]
					if Tags_ns_tag then
						local Tags_ns_tag_globals = Tags_ns_tag.globals
						if Tags_ns_tag_globals then
							local g = newList((";"):split(Tags_ns_tag_globals))
							for _,v in ipairs(g) do
								globals[v] = true
							end
							g = del(g)
							break
						end
					end
				end
			end
			if ast.kwarg then
				for k,v in pairs(ast.kwarg) do
					local g = figureGlobals(v, nsList, kwargsKey)
					for k in pairs(g) do
						globals[k] = true
					end
					g = del(g)
				end
			end
		end
		for i = 2, #ast do
			local g = figureGlobals(ast[i], nsList, kwargsKey)
			for k in pairs(g) do
				globals[k] = true
			end
			g = del(g)
		end
		return globals
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
				return Tags_ns_tag
			end
		end
	end
end

local function getKwargsForAST(ast, nsList, extraKwargs)
	if type(ast) ~= "table" then
		return nil, ("%s is not a tag"):format(tostring(ast))
	end
	local tag, startArgs
	if ast[1] == "tag" then
		tag = ast[2]
		startArgs = 3
	else
		tag = ast[1]
		startArgs = 2
	end
	
	local tagData = getTagData(tag, nsList)
	if not tagData then
		return nil, ("Unknown tag %s"):format(tag)
	end
	
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
	
	for i = startArgs, #ast do
		local argName = arg[(i-startArgs)*3 + 1]
		local argTypes = arg[(i-startArgs)*3 + 2]
		if argTypes == "list-string" or argTypes == "list-number" then
			for j = i, #ast do
				kwargs[argName .. (j-i+1)] = ast[j]
			end
			break
		end
		if not argName then
			kwargs = del(kwargs)
			return nil, ("Too many args for %s"):format(tag)
		end
		kwargs[argName] = ast[i]
	end
	
	if ast.kwarg then
		for k,v in pairs(ast.kwarg) do
			kwargs[k] = v
		end
	end
	
	-- validate all args are met
	for i = 1, #arg, 3 do
		local argName, argType, default = arg[i], arg[i+1], arg[i+2]
		
		if not kwargs[argName] and argType ~= "list-string" and argType ~= "list-number"then
			if default == "@req" then
				kwargs = del(kwargs)
				return nil, ("Arg #%d (%s) req'd for %s"):format((i-1)/3+1, argName, tag)
			else
				kwargs[argName] = default
			end
		end
	end
	
	return kwargs
end

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

local function forceTypes(storeKey, types, forceToTypes, t)
	if not storeKey then
		return nil, types
	end
	types = newSet((";"):split(types))
	forceToTypes = newSet((";"):split(forceToTypes))
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
		if type(storeKey) ~= "string" or (not storeKey:match("^arg%d+$") and storeKey ~= "value") then
			storeKey = "(" .. storeKey .. ")"
		end
		return storeKey, types
	end
	
	if unfulfilledTypes['nil'] then
		-- we have a possible unrequested nil
		if forceToTypes['string'] then
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
			finalTypes['string'] = true
		elseif forceToTypes['number'] then
			t[#t+1] = [=[if not ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ then ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ = ]=]
			t[#t+1] = [=[0;]=]
			t[#t+1] = [=[end;]=]
			finalTypes['number'] = true
		end
	elseif unfulfilledTypes['number'] then
		-- we have a possible unrequested number
		if forceToTypes['string'] then
			if type(storeKey) == "string" and storeKey:match("^arg%d+$") then
				t[#t+1] = storeKey
				t[#t+1] = [=[ = tostring(]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[)]=]
			else
				storeKey = ("%q"):format(tostring(storeKey+0))
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
		if forceToTypes['number'] then
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
				t[#t+1] = [=[ = nil]=]
			else
				storeKey = "nil"
			end
			finalTypes['nil'] = true
		end
	end
	unfulfilledTypes = del(unfulfilledTypes)
	forceToTypes = del(forceToTypes)
	local types = joinSet(finalTypes, ';')
	finalTypes = del(finalTypes)
	if type(storeKey) ~= "string" or (not storeKey:match("^arg%d+$") and storeKey ~= "value") then
		storeKey = "(" .. storeKey .. ")"
	end
	return storeKey, types
end

function compile(ast, nsList, t, cachedTags, extraKwargs, forceToTypes, storeKey)
	local astType = getASTType(ast)
	if astType == 'string' then
		if ast == '' then
			return compile(nil, nsList, t, cachedTags, extraKwargs, forceToTypes, storeKey)
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
			t[#t+1] = ("%.22f"):format(ast)
			t[#t+1] = [=[;]=]
			return forceTypes(storeKey, "number", forceToTypes, t)
		else
			return forceTypes(("%.22f"):format(ast), "number", forceToTypes, t)
		end
	elseif astType == 'nil' then
		if storeKey then
			t[#t+1] = storeKey
			t[#t+1] = [=[ = ]=]
			t[#t+1] = "nil"
			t[#t+1] = [=[;]=]
			return forceTypes(storeKey, "nil", forceToTypes, t)
		else
			return forceTypes("nil", "nil", forceToTypes, t)
		end
	elseif astType == 'tag' or operators[astType] then
		local tag = ast[astType == 'tag' and 2 or 1]
		local tagData = getTagData(tag, nsList)
		if not storeKey then
			storeKey = newUniqueVar()
		end
		if tagData then
			local caching, cachingFirst
			if astType == 'tag' and #ast == 2 and not ast.kwarg and cachedTags[tag] then
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
			end
			local kwargs, errMessage = getKwargsForAST(ast, nsList, extraKwargs)
			if not kwargs then
				return nil, errMessage
			end
			
			local code = tagData.code
			local arg = tagData.arg
			local ret = tagData.ret
			
			local compiledKwargs = newList()
			for k,v in pairs(kwargs) do
				if v == extraKwargs then
					compiledKwargs[k] = newList(("kwargs[%q]"):format(k), extraKwargs[k])
				else
					local argTypes = "nil;number;string"
					if not k:match("^...%d+$") then
						for i = 1, #arg, 3 do
							if arg[i] == k then
								argTypes = arg[i+1]
								break
							end
						end
					else
						for i = 1, #arg, 3 do
							if arg[i] == "..." then
								if arg[i+1] == "list-string" then
									argTypes = "string"
								elseif arg[i+1] == "list-number" then
									argTypes = "number"
								else
									break
								end
							end
						end
					end
					local arg, types = compile(v, nsList, t, cachedTags, extraKwargs, argTypes)
					if not arg then
						for k,v in pairs(compiledKwargs) do
							compiledKwargs[k] = del(v)
						end
						compiledKwargs = del(compiledKwargs)
						return nil, types
					end
					compiledKwargs[k] = newList(arg, types)
				end
			end
			
			local passData = newList()
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
			if type(ret) == "function" then
				ret = ret(passData)
			end
			if type(code) == "function" then
				code = code(passData)
			end
			for k, v in pairs(passData) do
				passData[k] = del(v)
			end
			passData = del(passData)
			
			interpolationHandler__compiledKwargs = compiledKwargs
			code = code:gsub(",%s*${%.%.%.}", tuple_interpolationHandler)
			interpolationHandler__compiledKwargs = compiledKwargs
			code = code:gsub("${(.-)}", interpolationHandler)
			interpolationHandler__compiledKwargs = nil
			
			code = code:gsub("return ", storeKey .. " = ")
			t[#t+1] = code
			t[#t+1] = [=[;]=]
			
			for k,v in pairs(compiledKwargs) do
				if v[1]:match("^arg%d+$") then
					t[#t+1] = v[1]
					delUniqueVar(v[1])
					t[#t+1] = [=[ = nil;]=]
				end
				compiledKwargs[k] = del(v)
			end
			compiledKwargs = del(compiledKwargs)
			
			if caching then
				t[#t+1] = [=[cache_]=]
				t[#t+1] = tag
				t[#t+1] = [=[ = ]=]
				t[#t+1] = storeKey
				t[#t+1] = [=[;]=]
				if not cachingFirst then
					t[#t+1] = [=[end;]=]
				end
			end
			
			kwargs = del(kwargs)
			return forceTypes(storeKey, ret, forceToTypes, t)
		else
			return nil, ("Unknown tag %s"):format(tag)
		end
	elseif astType == ' ' then
		local t_num = #t
		local args = newList()
		local argTypes = newList()
		for i = 2, #ast do
			local t_num = #t
			local arg, err = compile(ast[i], nsList, t, cachedTags, extraKwargs, "nil;number;string")
			if not arg then
				args = del(args)
				argTypes = del(argTypes)
				return nil, err
			end
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
			t[#t+1] = [=[if tonumber(]=]
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
		local arg, firstResults = compile(ast[2], nsList, t, cachedTags, extraKwargs, "nil;number;string", storeKey)
		if not arg then
			return nil, firstResults
		end
		firstResults = newSet((";"):split(firstResults))
		local totalResults = newList()
		t[#t+1] = [=[end;]=]
		if firstResults["nil"] then
			t[#t+1] = [=[if ]=]
			if astType == 'or' then
				t[#t+1] = [=[not ]=]
			end
			t[#t+1] = storeKey
			t[#t+1] = [=[ then ]=]
			local arg, secondResults = compile(ast[3], nsList, t, cachedTags, extraKwargs, "nil;number;string", storeKey)
			if not arg then
				firstResults = del(firstResults)
				totalResults = del(totalResults)
				return nil, secondResults
			end
			secondResults = newSet((";"):split(secondResults))
			t[#t+1] = [=[end;]=]
			for k in pairs(firstResults) do
				if k ~= "nil" then
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
			local arg, secondResults = compile(ast[3], nsList, t, cachedTags, extraKwargs, "nil;number;string", storeKey)
			if not arg then
				firstResults = del(firstResults)
				totalResults = del(totalResults)
				return nil, secondResults
			end
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
		local t_num = #t
		t[#t+1] = [=[do ]=]
		local storeKey, condResults = compile(ast[2], nsList, t, cachedTags, extraKwargs, "nil;number;string", storeKey)
		if not storeKey then
			return nil, condResults
		end
		condResults = newSet((';'):split(condResults))
		t[#t+1] = [=[end;]=]
		if condResults["nil"] and (condResults["string"] or condResults["number"]) then
			condResults = del(condResults)
			t[#t+1] = [=[if ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ then ]=]
			local arg, firstResults = compile(ast[3], nsList, t, cachedTags, extraKwargs, forceToTypes, storeKey)
			if not arg then
				return nil, firstResults
			end
			local totalResults = newSet((";"):split(firstResults))
			t[#t+1] = [=[ else ]=]
			local secondResults
			if ast[4] then
				storeKey, secondResults = compile(ast[4], nsList, t, cachedTags, extraKwargs, forceToTypes, storeKey)
				if not storeKey then
					totalResults = del(totalResults)
					return nil, secondResults
				end
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
			local storeKey, totalResults = compile(ast[4], nsList, t, cachedTags, extraKwargs, forceToTypes, storeKey)
			if not storeKey then
				return nil, totalResults
			end
			return storeKey, totalResults
		else
			-- non-nil
			condResults = del(condResults)
			for i = t_num, #t do
				t[i] = nil
			end
			if type(cond) == "string" and cond:match("^arg%d+$") then
				delUniqueVar(cond)
			end
			local storeKey, totalResults = compile(ast[3], nsList, t, cachedTags, extraKwargs, forceToTypes, storeKey)
			if not storeKey then
				return nil, totalResults
			end
			return storeKey, totalResults
		end
	elseif astType == 'not' then
		local t_num = #t
		local s, results = compile(ast[2], nsList, t, cachedTags, extraKwargs, "nil;number;string", storeKey)
		if not s then
			return nil, results
		end
		results = newSet((";"):split(results))
		if results["nil"] and (results["string"] or results["number"]) then
			results = del(results)
			storeKey = s
			
			t[#t+1] = storeKey
			t[#t+1] = [=[ = ]=]
			t[#t+1] = storeKey
			t[#t+1] = [=[ and ]=]
			t[#t+1] = ("%q"):format(L["True"])
			t[#t+1] = [=[ or nil;]=]
			return forceTypes(storeKey, "nil;string", forceToTypes, t)
		elseif results["nil"] then	
			-- just nil
			results = del(results)
			
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
	end
	error(("Unknown astType: %q"):format(tostring(astType or '')))
end

function DogTag:CreateFunctionFromCode(code, ...)
	if type(code) ~= "string" then
		error(("Bad argument #2 to `CreateFunctionFromCode'. Expected %q, got %q."):format("string", type(code)), 2)
	end
	local notDebug = (...) == true
	local kwargsKey = kwargsToKey()
	local nsList
	if notDebug then
		kwargsKey = select(2, ...)
		nsList = getNamespaceList(select(3, ...))
	else
		local n = select('#', ...)
		local kwargs = n > 0 and select(n, ...)
		if type(kwargs) == "table" then
			kwargsKey = kwargsToKey(kwargs)
			n = n - 1
		end
		for i = 1, n do
			if type(select(i, ...)) ~= "string" then
				error(("Bad argument #%d to `CreateFunctionFromCode'. Expected %q, got %q"):format(i+2, "string", type(select(i, ...))), 2)
			end
		end
		nsList = getNamespaceList(select2(1, n, ...))
	end
	
	local ast = DogTag.parse(code)
	ast = DogTag.standardize(ast)
	correctASTCasing(ast)
	
	local t = newList()
	t[#t+1] = ([=[local DogTag = _G.LibStub(%q);]=]):format(MAJOR_VERSION)
	t[#t+1] = [=[local colors = DogTag.__colors;]=]
	t[#t+1] = [=[local NIL = DogTag.__NIL;]=]
	t[#t+1] = [=[local cleanText = DogTag.__cleanText;]=]
	
	local globals = figureGlobals(ast, nsList, nil)
	globals['table.concat'] = true
	globals['tonumber'] = true
	globals['type'] = true
	for global in pairs(globals) do
		if global:find("^[A-Za-z0-9%-]+%-%d+%.%d+$") then
			if Rock then
				Rock(global, false, true) -- try to lod
			end
			if AceLibrary then
				AceLibrary:HasInstance(global) -- try to load
			end
			if LibStub(global, true) then -- catches Rock and AceLibrary libs as well
				t[#t+1] = [=[local ]=]
				t[#t+1] = global:gsub("%-.-$", "")
				if not global:find("^Lib") then
					t[#t+1] = [=[Lib]=]
				end
				t[#t+1] = [=[ = LibStub("]=]
				t[#t+1] = k
				t[#t+1] = [=[");]=]
			end
		else
			t[#t+1] = [=[local ]=]
			t[#t+1] = global:gsub("%.", "_")
			t[#t+1] = [=[ = ]=]
			t[#t+1] = global
			t[#t+1] = [=[;]=]
		end
	end
	globals = del(globals)
	t[#t+1] = [=[return function(kwargs) ]=]
	t[#t+1] = [=[local value, opacity;]=]
	
	local cachedTags = figureCachedTags(ast)
	for k in pairs(cachedTags) do
		t[#t+1] = [=[local cache_]=]
		t[#t+1] = k
		t[#t+1] = [=[ = NIL;]=]
	end
	
	local u = newList()
	local extraKwargs = newList()
	for k, v in pairs(kwargsKey) do
		local arg = newUniqueVar()
		u[#u+1] = arg
		u[#u+1] = [=[ = kwargs["]=]
		u[#u+1] = k
		u[#u+1] = [=["];]=]
		extraKwargs[k] = newList(arg, v)
	end
	local ret, types = compile(ast, nsList, u, cachedTags, extraKwargs, 'nil;number;string', 'value')
	for k, v in pairs(extraKwargs) do
		extraKwargs[k] = del(v)
	end
	extraKwargs = del(extraKwargs)
	ast = deepDel(ast)
	if not ret then
		for i = 1, #u do
			u[i] = nil
		end
		u[#u+1] = [=[value = ]=]
		u[#u+1] = ("%q"):format(types)
		u[#u+1] = [=[;]=]
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
		t[#t+1] = [=[if value == '' then value = nil; elseif tonumber(value) then value = value+0; end;]=]
	end
	types = del(types)
	
	t[#t+1] = [=[return value, opacity;]=]
	
	t[#t+1] = [=[end]=]
	
	cachedTags = del(cachedTags)
	local s = table.concat(t)
	t = del(t)
	if not notDebug then
		s = enumLines(s) -- avoid interning the new string if not debugging
	end
	return s
end

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
	local kwargsKey = kwargsToKey(kwargs)
	
	
	DogTag.__isMouseOver = false
	
	local func = codeToFunction[nsList][kwargsKey][code]
	
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

end