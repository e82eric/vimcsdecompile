require'plenary.job'
local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local previewers = require "telescope.previewers"
local entry_display = require("telescope.pickers.entry_display")
local strings = require "plenary.strings"
local Job = require('plenary.job')
local log = require('omnisharp-lua.log')

local M = {}

M._state = {
	SolutionLoadingState = nil,
	OmniSharpRequests = {},
	SolutionLoaded = false,
	NumberOfProjects = 0,
	NumberOfFailedProjects = 0,
	NumberOfProjectsLoaded = 0,
	SolutionName = '',
	AssembliesLoaded = false,
	NextSequence = 1001,
	StartSent = false
}

M.OpenLog = function()
	log.open()
end

M.StartDecompiler = function()
	if M._state.StartSent then
		print 'Decompiler has already been started'
	else
		local dir = vim.fn.fnamemodify(vim.fn.expand('%'), ':p:h')
		local slnFiles = {}
		M._findSolutions(dir, slnFiles)
		if next(slnFiles) == nil then
			print('No solution file found')
		elseif table.getn(slnFiles) == 1 then
			M.StartOmnisharp(slnFiles[1])
		else
			M._openSolutionTelescope(slnFiles, M._createSolutionFileDisplayer)
		end
	end
end

M._findSolutions = function(dir, resultFiles)
	local slnFiles = vim.fn.split(vim.fn.globpath(dir, '*.sln'), '\n')
	if next(slnFiles) ~= nil then
		for k, v in ipairs(slnFiles) do
			local fullFileName = vim.fn.fnamemodify(v, ':p')
			table.insert(resultFiles, fullFileName)
		end
	else
		local parentDir = vim.fn.fnamemodify(dir, ':p:h:h')
		if dir == parentDir then
			print('Not found, hit root ' .. parentDir)
		else
			M._findSolutions(parentDir, resultFiles)
		end
	end
end

M._createSolutionFileDisplayer = function()
	local resultFunc = function(entry)
		local displayer = entry_display.create {
			separator = "  ",
			items = {
				{ remaining = true },
			}
		}

		local ordinal = entry.value
		local make_display = function(entry)
			return displayer {
				{ entry, "TelescopeResultsIdentifier" },
			}
		end

		return {
			value = entry,
			display = make_display,
			ordinal = ordinal
		}
	end
	return resultFunc
end

M._openSolutionTelescope = function(data)
	opts = opts or {}
	local timer = vim.loop.new_timer()
	timer:start(1000, 0, vim.schedule_wrap(function()
	pickers.new(opts, {
		layout_strategy='vertical',
		prompt_title = "Select Solution File",
		finder = finders.new_table {
			results = data,
		},
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				M.StartOmnisharp(selection.value)
				actions.close(prompt_bufnr)
			end)
			return true
		end,
		sorter = conf.generic_sorter(opts),
	}):find()
	end))
end

M.GetCurrentOperationMessage = function()
	local currentCommand = M._state.CurrentCommand
	if currentCommand == nil then
		return "0#: No pending operations"
	end
	local duration = currentCommand.Duration
	if duration == nil then
		duration = os.difftime(os.time(), currentCommand.StartTime)
	end
	local result = '0#: ' .. currentCommand.Status .. ' ' .. currentCommand.Name .. ' ' .. duration .. 's'
	return result
end

M.GetSolutionLoadingStatus = function()
	local statusString = ''
	local numberOfProjectsString = '(' ..  M._state.NumberOfProjectsLoaded .. ' of ' .. M._state.NumberOfProjects .. ')'
	if M._state.NumberOfFailedProjects ~= 0 then
		numberOfProjectsString = numberOfProjectsString .. ' (' .. M._state.NumberOfFailedProjects .. ' failed)'
	end
	if M._state.SolutionLoadingState == nil then
		statusString = "Not running"
	elseif M._state.SolutionLoadingState == "loading" then
		-- statusString = M._state.SolutionName .. ' loading...' .. numberOfProjectsString
		statusString = M._state.SolutionName .. ' loading... ' .. numberOfProjectsString
	elseif M._state.SolutionLoadingState == "done" then
		statusString = M._state.SolutionName .. ' ' .. numberOfProjectsString
	end
	local result = 'O#: ' .. statusString
	return result
end

local on_output = function(err, data)
	-- print(data)
	local timer = vim.loop.new_timer()
	timer:start(100, 0, vim.schedule_wrap(function()
		log.debug(data)
	end))
	local ok, json = pcall(
		vim.json.decode,
		data	
	)

	if ok == true then
		local messageType = json["Event"]
		if messageType == "SOLUTION_PARSED" then
			M._state.NumberOfProjects	= json.Body.NumberOfProjects
			M._state.SolutionName = json.Body.SolutionName
			print(vim.inspect(json))
		end
		if messageType == "PROJECT_LOADED" then
			M._state.NumberOfProjectsLoaded = M._state.NumberOfProjectsLoaded + 1
			print(vim.inspect(json))
		end
		if messageType == "PROJECT_FAILED" then
			M._state.NumberOfFailedProjects = M._state.NumberOfFailedProjects + 1
			print(vim.inspect(json))
		end
		if messageType == "ASSEMBLIES_LOADED" then
			M._state.AssembliesLoaded = true
			print(vim.inspect(json))
			if M._state.SolutionLoadingState ~= 'done' and
				M._state.NumberOfProjects > 0 and
				M._state.NumberOfProjectsLoaded + M._state.NumberOfFailedProjects == M._state.NumberOfProjects and
				M._state.AssembliesLoaded == true then
				M._state.SolutionLoadingState = "done"
			end
		end
		local mType = json["Type"]
		if mType == "event" then
			if messageType == "log" then
				if json.Body.LogLevel == 'Error' then
					log.Error(data)
				end
				-- if string.sub(json.Body.Message, 0, string.len("Queue project update")) == "Queue project update" then
				-- 	-- M._state.NumberOfProjects = M._state.NumberOfProjects + 1
				-- elseif string.sub(json.Body.Message, 0, string.len("Successfully loaded project file")) == "Successfully loaded project file" then
				-- 	-- M._state.NumberOfProjectsLoaded = M._state.NumberOfProjectsLoaded + 1
				-- elseif string.sub(json.Body.Message, 0, string.len("^Failed to load project")) == "^Failed to load project" then
				-- 	M._state.NumberOfFailedProjects = M._state.NumberOfFailedProjects + 1
				-- end
			end
		elseif mType == 'response' then
			local commandState = M._state.OmniSharpRequests[json.Request_seq]
			M._state.OmniSharpRequests[json.Request_seq] = nil
			local duration = os.difftime(os.time(), M._state.CommandStartTime)
			commandState.Duration = duration
			if json.Success then
				commandState.Status = "Done"
				local commandCallback = commandState.Callback
				local startTime = commandState.StartTime
				local data = commandState.Data
				commandCallback(json, data)
			else
				commandState.Status = 'Failed'
			end
		end
	end
end

M.StartOmnisharp = function (solutionPath)
	M._state['StartSent'] = true
	print('Starting Decompiler ' .. solutionPath)
	if solutionPath == nil then
		solutionPath = vim.fn.expand('%:p')
		-- M._state.SolutionName = vim.fn.expand('%:p:t')
	end
	local job = Job:new({
		-- command = 'H:\\st\\omnisharp\\OmniSharp.exe',
		command = 'C:\\src\\TryOmnisharpExtension\\StdIoHost\\bin\\Debug\\StdIoHost.exe',
		-- command = 'C:\\src\\omnisharp-clean\\bin\\Debug\\OmniSharp.Stdio.Driver\\net472\\OmniSharp.exe',
		-- args = { '--plugin', 'c:\\src\\OmnisharpExtensions\\TryOmnisharpExtension.dll', '-s',  solutionPath },
		args = {  solutionPath },
		cwd = '.',
		on_stdout = on_output,
		on_exit = function(j, return_val)
		end,
	})
	M._state.SolutionLoadingState = 'loading'

	job:start()

	M._state["job"] = job
end

M._sendStdIoRequest = function(request, callback, callbackData)
	local nextSequence = M._state.NextSequence + 1

	local command = { Callback = callback, StartTime = os.time(), Data = callbackData, Name = request.Command, Status = 'Running' }
	M._state.OmniSharpRequests[nextSequence] = command

	M._state.NextSequence = nextSequence
	request["Seq"] = nextSequence
	local requestJson = vim.json.encode(request) .. '\n'
	M._state.CurrentCommand = command
	M._state.job.stdin:write(requestJson)
	M._state.CommandStartTime = os.time()
	M._state.EndTime = nil
	M._state.CurrentSeq = nextSequence
end

M._decompileRequest = function(url, callback, callbackData)
	local cursorPos = vim.api.nvim_win_get_cursor(0)
	local line = cursorPos[1]
	local column = cursorPos[2] + 1
	local decompiled = vim.b.IsDecompiled == true
	local assemblyFilePath = vim.b.AssemblyFilePath
	local fileName = vim.fn.expand('%:p')

	local request = {
		Command = url,
		Arguments = {
			FileName = fileName,
			AssemblyFilePath = vim.b.AssemblyFilePath,
			ContainingTypeFullName = vim.b.ContainingTypeFullName,
			Column = column,
			Line = line,
			IsDecompiled = decompiled,
		},
	}
	M._sendStdIoRequest(request, callback, callbackData)
end

M.StartAddExternalDirectory = function(directoryFilePath)
	local request = {
		Command = "/addexternalassemblydirectory",
		Arguments = {
			DirectoryFilePath = directoryFilePath
		}
	}
	M._sendStdIoRequest(request, M.HandleAddExternalDirectory);
end

M.HandleAddExternalDirectory = function(response)
	print(vim.inspect(response))
end

M.StartGetAssemblies = function()
	local request = {
		Command = "/getassemblies",
		Arguments = {
			Load = true,
		}
	}
	M._sendStdIoRequest(request, M.HandleGetAssemblies);
end

M.HandleGetAssemblies = function(response)
	M._openAssembliesTelescope(response.Body.Assemblies)
end

M.StartGetAssemblyTypes = function(filePath)
	local request = {
		Command = "/getassemblytypes",
		Arguments = {
			AssemblyFilePath = filePath,
		}
	}
	M._sendStdIoRequest(request, M.HandleGetAllTypes)
end

M._openAssembliesTelescope = function(data)
	local widths = {
		FullName = 0,
		TargetFrameworkId = 0,
	}

	local parse_line = function(entry)
		for key, value in pairs(widths) do
			widths[key] = math.max(value, strings.strdisplaywidth(entry[key] or ""))
		end
	end

	for _, line in ipairs(data) do
		parse_line(line)
	end

	opts = opts or {}
	local timer = vim.loop.new_timer()
	timer:start(1000, 0, vim.schedule_wrap(function()
	pickers.new(opts, {
		layout_strategy='vertical',
		prompt_title = "Assemblies",
		finder = finders.new_table {
			results = data,
			entry_maker = function(entry)
				local displayer = entry_display.create {
					separator = "  ",
					items = {
						{ width = widths.FullName },
						{ remaining = true },
					},
				}
				local make_display = function(entry)
					return displayer {
						{ M._blankIfNil(entry.value.FullName), "TelescopeResultsIdentifier" },
						{ M._blankIfNil(entry.value.TargetFrameworkId), "TelescopeResultsClass" },
					}
				end
				return {
					value = entry,
					display = make_display,
					ordinal = entry.FullName
				}
			end
		},
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)
				M.StartGetAssemblyTypes(selection.value.FilePath)
			end)
			return true
		end,
		sorter = conf.generic_sorter(opts),
	}):find()
	end))
end

M.StartGetAllTypes = function(searchString)
	local request = {
		Command = "/gettypes",
		Arguments = {
			SearchString = searchString
		}
	}
	M._sendStdIoRequest(request, M.HandleGetAllTypes);
end

M.HandleGetAllTypes = function(response)
	M._openTelescope(response.Body.Implementations, M._createSearchTypesDisplayer, 'Search Types')
end

M.StartDecompileGotoDefinition = function()
	M._decompileRequest('/gotodefinition', M.HandleDecompileGotoDefinitionResponse)
end

M.StartFindUsages = function()
	M._decompileRequest("/findusages", M.HandleUsages)
end

M.HandleUsages = function(response)
	M._openTelescope(response.Body.Implementations, M._createUsagesDisplayer, 'Find Usages')
end

M.StartGetDecompiledSource = function(
	assemblyFilePath,
	containingTypeFullName,
	line,
	column,
	callbackData)

	local request = {
		Command = "/decompiledsource",
		Arguments = {
			AssemblyFilePath = assemblyFilePath,
			ContainingTypeFullName = containingTypeFullName,
			Line = line,
			Column = column,
		},
		Seq = M._state.NextSequence,
	}

	M._sendStdIoRequest(request, M.HandleDecompiledSource, callbackData)
end

M.StartGetTypeMembers = function()
	M._decompileRequest('/gettypemembers', M.HandleGetTypeMembers)
end

M.HandleGetTypeMembers = function(response)
	M._openTelescope(response.Body.Implementations, M._createUsagesDisplayer, 'Type Members')
end

M.StartFindImplementations = function()
	M._decompileRequest('/findimplementations', M.HandleFindImplementations)
end

M.HandleFindImplementations = function(response)
	if #response.Body.Implementations == 0 then
		print 'No implementations found'
	elseif #response.Body.Implementations == 1 then
		local timer = vim.loop.new_timer()
		timer:start(1000, 0, vim.schedule_wrap(function()
			M._openSourceFileOrDecompile(response.Body.Implementations[1])
		end))
	else
		M._openTelescope(response.Body.Implementations, M._createUsagesDisplayer, 'Find Implementations')
	end
end

M._openSourceFileOrDecompile = function(value)
	if value.Type == 1 then
		local bufnr = vim.uri_to_bufnr(value.FileName)
		vim.api.nvim_win_set_buf(0, bufnr)
		vim.api.nvim_win_set_cursor(0, { value.Line, value.Column })
	else
		M.StartGetDecompiledSource(
			value.AssemblyFilePath,
			value.ContainingTypeFullName,
			value.Line,
			value.Column,
			{ Entry = value, BufferNumber = 0, WindowId = 0, })
	end
end

M.HandleDecompileGotoDefinitionResponse = function(response)
	local body = response.Body
	local location = body.Location
	local fileName = location.FileName
	local column = location.Column - 1
	local line = location.Line

	if location.Type == 1 then
		local timer = vim.loop.new_timer()
		timer:start(100, 0, vim.schedule_wrap(function()
			local bufnr = vim.uri_to_bufnr(fileName)
			vim.api.nvim_win_set_buf(0, bufnr)
			vim.api.nvim_win_set_cursor(0, { line, column })
		end))
	else
		local fileText = body.SourceText
		if response.Request_seq == M._state.CurrentSeq then
			local timer = vim.loop.new_timer()
			timer:start(100, 0, vim.schedule_wrap(function()
				local bufnr = vim.uri_to_bufnr("c:\\TEMP\\DECOMPILED_" .. location.ContainingTypeFullName .. ".cs")
				local lines = {}
				vim.list_extend(lines, vim.split(fileText, "\r\n"))
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
				vim.api.nvim_win_set_buf(0, bufnr)
				vim.api.nvim_win_set_cursor(0, { line, column })
				vim.api.nvim_buf_set_option(bufnr, "syntax", "cs")
				vim.api.nvim_buf_set_option(bufnr, "filetype", "cs")
				-- vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
				vim.api.nvim_buf_set_option(bufnr, "buflisted", true)
				vim.b.IsDecompiled = body.IsDecompiled
				vim.b.AssemblyFilePath = location.AssemblyFilePath
				vim.b.ContainingTypeFullName = location.ContainingTypeFullName
			end))
		end
	end
end

M.HandleDecompiledSource = function(response, data)
	local body = response.Body
	local fileText = body.SourceText
	local line = body.Line
	local column = body.Column
	local bufnr = data.BufferNumber
	local winid = data.WindowId

	local timer = vim.loop.new_timer()
	timer:start(100, 0, vim.schedule_wrap(function()
		if response.Request_seq == M._state.CurrentSeq then
			if bufnr == 0 then
				bufnr = vim.uri_to_bufnr("c:\\TEMP\\DECOMPILED_" .. data.Entry.ContainingTypeFullName .. ".cs")
			end
			local lines = {}
			vim.list_extend(lines, vim.split(fileText, "\r\n"))
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
			vim.api.nvim_win_set_buf(winid, bufnr)
			vim.api.nvim_win_set_cursor(winid, { line, column })
			vim.api.nvim_buf_set_option(bufnr, "syntax", "cs")
			vim.api.nvim_buf_set_option(bufnr, "filetype", "cs")
			-- vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
			vim.api.nvim_buf_set_option(bufnr, "buflisted", true)
			vim.api.nvim_buf_add_highlight(bufnr, -1, "TelescopePreviewLine", line -1, 0, -1)
			vim.b.IsDecompiled = body.IsDecompiled
			vim.b.AssemblyFilePath = body.AssemblyFilePath
			vim.b.ContainingTypeFullName = body.ContainingTypeFullName
		end
	end))
end

M._blankIfNil = function(val)
	local result = ''
	if val ~= nil then
		return val
	end
	return ''
end

M._createFindImplementationsDisplayer = function(widths)
	local resultFunc = function(entry)
		local make_display = nil
		if entry.Type == 0 then
			local displayer = entry_display.create {
				separator = "  ",
				items = {
					{ width = widths.ContainingTypeFullName },
					{ width = widths.NamespaceName },
					{ width = widths.AssemblyName + widths.AssemblyVersion + 1 },
					{ width = widths.DotNetVersion + 6 },
					{ remaining = true },
				},
			}

			make_display = function(entry)
				return displayer {
					{ M._blankIfNil(entry.value.ContainingTypeFullName), "TelescopeResultsClass" },
					{ M._blankIfNil(entry.value.NamespaceName), "TelescopeResultsIdentifier" },
					{ string.format("%s %s", entry.value.AssemblyName, entry.value.AssemblyVersion), "TelescopeResultsIdentifier" },
					{ string.format("%s %s", '.net ', entry.value.DotNetVersion), "TelescopeResultsIdentifier" },
					{ M._blankIfNil(entry.value.AssemblyFilePath), "TelescopeResultsIdentifier" }
				}
			end
		else
			local displayer = entry_display.create {
				separator = "  ",
				items = {
					{ width = widths.ContainingTypeFullName },
					{ width = widths.NamespaceName },
					{ remaining = true },
				},
			}

			make_display = function(entry)
				return displayer {
					{ M._blankIfNil(entry.value.ContainingTypeFullName), "TelescopeResultsClass" },
					{ M._blankIfNil(entry.value.NamespaceName), "TelescopeResultsIdentifier" },
					{ string.format("%s:%s:%s", entry.value.FileName, entry.value.Line, entry.value.Column), "TelescopeResultsIdentifier" }
				}
			end
		end

		return {
			value = entry,
			display = make_display,
			ordinal = entry.SourceText
		}
	end

	return resultFunc
end

M._createSearchTypesDisplayer = function(widths)
	local resultFunc = function(entry)
		local displayer = entry_display.create {
			separator = "  ",
			items = {
				{ width = widths.SourceText },
				{ width = widths.AssemblyFilePath },
				{ remaining = true },
			},
		}

		local make_display = function(entry)
			return displayer {
				{ M._blankIfNil(entry.value.SourceText), "TelescopeResultsClass" },
				{ M._blankIfNil(entry.value.AssemblyName), "TelescopeResultsClass" },
				{ M._blankIfNil(entry.value.AssemblyFilePath), "TelescopeResultsIdentifier" }
			}
		end

		return {
			value = entry,
			display = make_display,
			ordinal = entry.SourceText
		}
	end
	return resultFunc
end

M._createUsagesDisplayer = function(widths)
	local resultFunc = function(entry)
		local make_display = nil
		local ordinal = nil
		if entry.Type == 1 then
			local displayer = entry_display.create {
				separator = "  ",
				items = {
					{ width = widths.ContainingTypeShortName },
					{ remaining = true },
				}
			}

			ordinal = M._blankIfNil(entry.FileName) .. M._blankIfNil(entry.SourceText)
			make_display = function(entry)
				return displayer {
					{ string.format("%s", entry.value.ContainingTypeShortName), "TelescopeResultsClass" },
					{ string.format("%s", entry.value.SourceText), "TelescopeResultsIdentifier" },
				}
			end
		else
			local displayer = entry_display.create {
				separator = "  ",
				items = {
					{ width = widths.ContainingTypeShortName },
					{ remaining = true },
					-- { remaining = true },
				},
			}

			ordinal = M._blankIfNil(entry.ContainingTypeFullName) .. M._blankIfNil(entry.SourceText)
			make_display = function(entry)
				return displayer {
					{ string.format("%s", entry.value.ContainingTypeShortName), "TelescopeResultsClass" },
					{ M._blankIfNil(entry.value.SourceText), "TelescopeResultsIdentifier" },
				}
			end
		end

		return {
			value = entry,
			display = make_display,
			ordinal = ordinal
		}
	end
	return resultFunc
end

M._openTelescope = function(data, displayFunc, promptTitle)
	local widths = {
		ContainingTypeFullName = 0,
		ContainingTypeShortName = 0,
		TypeName = 0,
		NamespaceName = 0,
		AssemblyName = 0,
		DotNetVersion = 0,
		AssemblyVersion = 0,
		Line = 0,
		Column = 0,
		FileName = 0,
		SourceText = 0,
	}

	local parse_line = function(entry)
		for key, value in pairs(widths) do
			widths[key] = math.max(value, strings.strdisplaywidth(entry[key] or ""))
		end
	end

	for _, line in ipairs(data) do
		parse_line(line)
	end

	local entryMaker = displayFunc(widths)

	opts = {}
	local timer = vim.loop.new_timer()
	timer:start(1000, 0, vim.schedule_wrap(function()
	pickers.new(opts, {
		layout_strategy='vertical',
		layout_config = {
			width = 0.95,
			height = 0.95,
		},
		prompt_title = promptTitle,
		finder = finders.new_table {
			results = data,
			entry_maker = entryMaker,
		},
		preview = opts.previewer,
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)
				M._openSourceFileOrDecompile(selection.value)
			end)
			return true
		end,
		previewer = previewers.new_buffer_previewer {
			dyn_title = function (_, entry)
				local titleResult = ''
				if entry.value.Type == 1 then
					titleResult = vim.fn.fnamemodify(entry.value.FileName, ':.')
				else
					titleResult = entry.value.ContainingTypeShortName
				end
				return titleResult
			end,
			get_buffer_by_name = function(_, entry)
				return entry.value
			end,
			define_preview = function(self, entry)
				if entry.value.Type == 1 then
					local bufnr = self.state.bufnr
					local winid = self.state.winid

					conf.buffer_previewer_maker(entry.value.FileName, self.state.bufnr, {
						use_ft_detect = true,
						bufname = self.state.bufname,
						winid = self.state.winid,
						callback = function(bufnr)
							local currentWinId = vim.fn.bufwinnr(bufnr)
							if currentWinId ~= -1 then
								local startColumn = entry.value.Column
								local endColumn = entry.value.Column
								vim.api.nvim_buf_add_highlight(bufnr, -1, "TelescopePreviewLine", entry.value.Line -1, 0, -1)
								vim.api.nvim_win_set_cursor(self.state.winid, { entry.value.Line, 0 })
							end
						end
					})
				else
					local bufnr = self.state.bufnr
					local winid = self.state.winid

					M.StartGetDecompiledSource(
						entry.value.AssemblyFilePath,
						entry.value.ContainingTypeFullName,
						entry.value.Line,
						entry.value.Column,
						{ Entry = entry.value, BufferNumber = bufnr, WindowId = winid, })

					vim.api.nvim_buf_set_option(self.state.bufnr, "syntax", "cs")
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { 'Decompiling ' .. entry.value.SourceText .. '...'})
				end
			end
		},
		sorter = conf.generic_sorter(opts),
	}):find()
	end))
end

return M
