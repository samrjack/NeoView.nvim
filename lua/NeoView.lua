--[[

 /$$   /$$                     /$$    /$$ /$$
| $$$ | $$                    | $$   | $$|__/
| $$$$| $$  /$$$$$$   /$$$$$$ | $$   | $$ /$$  /$$$$$$  /$$  /$$  /$$
| $$ $$ $$ /$$__  $$ /$$__  $$|  $$ / $$/| $$ /$$__  $$| $$ | $$ | $$
| $$  $$$$| $$$$$$$$| $$  \ $$ \  $$ $$/ | $$| $$$$$$$$| $$ | $$ | $$
| $$\  $$$| $$_____/| $$  | $$  \  $$$/  | $$| $$_____/| $$ | $$ | $$
| $$ \  $$|  $$$$$$$|  $$$$$$/   \  $/   | $$|  $$$$$$$|  $$$$$/$$$$/
|__/  \__/ \_______/ \______/     \_/    |__/ \_______/ \_____/\___/

--]]

-- TODO
-- 1. Make an acual config to set things up.
-- 1.1. Directories
-- 1.2. Disabled filetypes
-- 1.3. Disable opening fold under cursor at startup
-- 2. Save views settings and wrap it so the view gets changed when used by neoview but then set back to the user defined settings.
-- 3. Experiment if this can be done with just `mkview` and not need the extra cursor position saving.
local NeoView = {}
-- Save stuff in here for now I guess
local user_options = {}

local NEOVIEW_DIR = vim.fn.stdpath('cache') .. '/NeoView'
local VIEWS_DIR = NEOVIEW_DIR .. '/views'
local CURSOR_FILE = NEOVIEW_DIR .. '/cursor_data.json'

vim.fn.mkdir(NEOVIEW_DIR, 'p')
vim.fn.mkdir(VIEWS_DIR, 'p')

NeoView.setup = function(opts)
	if vim.g.neoview_setup then
		return
	end

	if opts ~= nil then user_options = opts end

	vim.g.neoview_setup = true

	vim.cmd('silent! set viewdir=' .. VIEWS_DIR)

	vim.opt.viewoptions = { "folds" }

	local group = vim.api.nvim_create_augroup('NeoView', { clear = true })

	vim.api.nvim_create_autocmd('BufWinEnter', {
		group = group,
		callback = function()
			pcall(function()
				vim.schedule(NeoView.restore_cursor_position)
			end)
		end,
	})

	vim.api.nvim_create_autocmd({ 'BufUnload', 'BufWinLeave' }, {
		group = group,
		callback = function()
			pcall(function() NeoView.save_folds() end)
			pcall(function() NeoView.save_cursor_position() end)
		end,
	})

	vim.api.nvim_create_user_command('ClearNeoView', require('NeoView').clear_neoview, {})
end

function NeoView.save_folds()
	if NeoView.valid_buffer() then
		vim.cmd('silent! mkview!')
	end
end

-- If the code at the cursor is folded, unfold it. This may not always be desired,
-- but I feel generally it's better to see the code at the point of entry
-- TODO find a way to only upen the folds under cursor, not all folds in the area.
-- This can happen when the cursor is in the middle of many nested folds. ex:
--	function()
--		if() then
--			...
--		end
--		if() then
--			... <- Cursor here
--		end
--		if() then
--			...
--		end
--	end
-- In the above example, if everything is closed, we will open ALL the if statements. Don't want that.
local function open_current_fold()
	vim.cmd('silent! exe "normal! zO"')
end

function NeoView.restore_folds()
	if NeoView.valid_buffer() then
		vim.cmd('silent! loadview')
	end
end

function NeoView.notify_neoview(s)
	local timer = vim.loop.new_timer()
	vim.notify(s)

	if timer then
		timer:start(3000, 0, vim.schedule_wrap(function()
			vim.cmd.echo('""')

			timer:stop()
			timer:close()
		end))
	end
end

function NeoView.clear_neoview()
	vim.cmd('silent! exec "delete ' .. VIEWS_DIR .. '/*"')

	if vim.fn.filereadable(CURSOR_FILE) == 1 then
		vim.fn.delete(CURSOR_FILE)
	end
	NeoView.notify_neoview('NeoView Data Cleared')
end

function NeoView.restore_cursor_position()
	if not NeoView.valid_buffer() then return end

	-- Get Starting cursor position. If you were brought to the
	-- current file via a link or reference, then the cursor will
	-- be on the relevant line and not on the first line. In that case,
	-- restore the folds and then set the cursor to the original position.
	--
	-- If the cursor is at the start of the file, then load the cursor's saved
	-- location if one exists.
	local r, _ = unpack(vim.api.nvim_win_get_cursor(0)) -- unused char character

	-- Case where cursor is already on something
	if r > 1 then
		-- Re-getting cursor's position since this is in the format needed below.
		local cur_pos = vim.fn.getpos('.')
		NeoView.restore_folds()
		vim.fn.setpos('.', cur_pos)
		open_current_fold()
		return
	end


	-- Case where we need to load cursor's position from file
	NeoView.restore_folds()
	if vim.fn.filereadable(CURSOR_FILE) == 1 then
		local file_content = table.concat(vim.fn.readfile(CURSOR_FILE))
		local cursor_data_all = vim.fn.json_decode(file_content)
		if not cursor_data_all then return end
		local file_path_key = vim.fn.expand('%:p')
		local cursor_data = cursor_data_all[file_path_key]

		if cursor_data then
			vim.fn.setpos('.', cursor_data.cursor)
			open_current_fold()
		end
	end
end

function NeoView.save_cursor_position()
	if not NeoView.valid_buffer() then return end

	local file_path_key = vim.fn.expand('%:p')
	local cursor_position = vim.fn.getpos('.')

	local cursor_data_all = {}
	if vim.fn.filereadable(CURSOR_FILE) == 1 then
		local file_content = table.concat(vim.fn.readfile(CURSOR_FILE))
		cursor_data_all = vim.fn.json_decode(file_content) or {}
	end

	cursor_data_all[file_path_key] = { cursor = cursor_position }
	local encoded_data = vim.fn.json_encode(cursor_data_all)
	vim.fn.writefile({ encoded_data }, CURSOR_FILE)
end

function NeoView.valid_buffer()
	-- Check buffer type for a special buffer
	local buftype = vim.bo.buftype
	local disabled_buftypes = { 'help', 'prompt', 'nofile', 'terminal' }
	if vim.tbl_contains(disabled_buftypes, buftype) then return false end

	-- Check filetypes
	-- TODO add this to the opts
	local filetype = vim.bo.filetype
	local disabled_filetypes = user_options.disabled_filetypes or { 'NeogitCommitMessage' }
	-- If the code at the cursor is folded, unfold it. This may not always be desired,
	-- but I feel generally it's better to see the code at the point of entry
	if vim.tbl_contains(disabled_filetypes, filetype) then return false end

	return true
end

return NeoView
