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

	vim.api.nvim_create_autocmd('BufWinEnter', {
		group = vim.api.nvim_create_augroup('NeoView', { clear = true }),
		callback = function()
			pcall(function()
				-- This is an attempt to allow functions that take you
				-- to other files not have their cursor positions moved
				-- from the spot they're taking you to.
				-- ex. telescope grep
				local r, c = unpack(vim.api.nvim_win_get_cursor(0))
				-- check for the start of the buffer. using 2 is arbitrary since I
				-- THINK the original cursor position is (1,0) but I can't guarentee that'll
				-- always be the case.
				if (r < 2 and c < 2) then
					NeoView.restore_view()
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd({ 'BufUnload', 'BufWinLeave' }, {
		group = 'NeoView',
		callback = function()
			pcall(function() NeoView.save_view() end)
			pcall(function() NeoView.save_cursor_position() end)
		end,
	})

	vim.api.nvim_create_user_command('ClearNeoView', require('NeoView').clear_neoview, {})
end

function NeoView.save_view()
	if NeoView.valid_buffer() then
		vim.cmd('silent! mkview!')
	end
end

function NeoView.restore_view()
	if NeoView.valid_buffer() then
		vim.cmd('silent! loadview')
		vim.schedule(NeoView.restore_cursor_position)
	end
end

function NeoView.notify_neoview()
	local timer = vim.loop.new_timer()
	vim.notify('NeoView Data Cleared')

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
	NeoView.notify_neoview()
end

function NeoView.restore_cursor_position()
	if not NeoView.valid_buffer() then return end

	if vim.fn.filereadable(CURSOR_FILE) == 1 then
		local file_content = table.concat(vim.fn.readfile(CURSOR_FILE))
		local cursor_data_all = vim.fn.json_decode(file_content)
		if not cursor_data_all then return end
		local file_path_key = vim.fn.expand('%:p')
		local cursor_data = cursor_data_all[file_path_key]

		if cursor_data then
			vim.fn.setpos('.', cursor_data.cursor)
		end
	end
end

function NeoView.save_cursor_position()
	local file_path_key = vim.fn.expand('%:p')
	local cursor_position = vim.fn.getpos('.')

	if not NeoView.valid_buffer() then return end

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
	if vim.tbl_contains(disabled_filetypes, filetype) then return false end

	return true
end

return NeoView
