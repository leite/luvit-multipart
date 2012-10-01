-- ----------------------------------------------------------------------------
-- "THE BEER-WARE LICENSE" (Revision 42):
-- <xxleite@gmail.com> wrote this file. As long as you retain this notice you
-- can do whatever you want with this stuff. If we meet some day, and you think
-- this stuff is worth it, you can buy me a beer in return
-- ----------------------------------------------------------------------------

-- multipart stream parse

local fs     = require 'fs'
local tb     = require 'table'
local st     = require 'string'
local co     = require 'coroutine'
local math   = require 'math'
local writer = require './stream'

local stream_read, exists, create, status, yield, resume, match, gsub, sub, lower, insert, concat, random, seed = 
				fs.createReadStream, fs.exists, co.create, co.status, co.yield, co.resume, st.match, st.gsub, st.sub, st.lower, tb.insert, tb.concat, math.random, math.randomseed

local temp_path, finish_callback, coroutine, stream_handler, errors, headers, header, queue, stream, m_boundary, m_eos, line, last_line, i =
				'', function() end, nil, nil, false, {}, {}, {}, '', '', '', '', '', 0

fs, tb, st, co, math = nil, nil, nil, nil, nil

-- parse mime/multipart headers
local function get_headers(data)
	local header, headers = match(data, "^"..m_boundary.."\n(.-%c)%c"), {}
	local headers_loop    = function(k, v) headers[k] = v end
	if header then
		gsub(header, '%s?([^%:?%=?]+)%:?%s?%=?%"?([^%"?%;?%c?]+)%"?%;?%c?', headers_loop)
		return headers, sub(data, #m_boundary+#header+3)
	end
	return nil, data
end

--
local function unique_file_name(name)
	seed(192837465)
	return temp_path .. '/' .. random(19375, 293847560) .. name
end

-- finish data blocks
local function finish_data_block()
	if not stream_handler.is_free then
		-- close file handler
		stream_handler.close(write_data_block)
	else
end

local function write_data_block(err) 
	if err then
		-- cannot write or close file ... permission?, disk failure?, wtf!
	end
	resume(coroutine)
end

-- parse body/multipart
local function parse(data)

	line = match(data, "([^\n?$?]*)\n?$?")
	if not line then
		finish_callback()
		return false
	end

	if line == m_boundary then
		finish_data_block()
		yield()
		insert(headers, header)
		header, stream = get_headers(data)
		if not header then
			finish_callback()
			return false
		end
	elseif line == m_eos then
		finish_data_block()
		yield()
		insert(headers, header)
		stream = sub(data, #line)
		finish_callback()
		return false
	else
		if header.filename then
			if stream_handler.is_free then
				stream_handler.new(unique_file_name(header.filename))
			end
			stream_handler.write(line, write_data_block)
			yield()
		else
			header.value = (last_line==m_boundary or last_line=='') and line or header.value.."\n"..line
		end
		stream = sub(data, #line+2)
	end
	last_line = line
	parse(stream)
end

local function on_stream_arrival(chunk, length) 

	if not coroutine then
		coroutine = create(parse)
		stream    = chunk
	elseif status(coroutine)=='dead' then
		coroutine = create(parse)
		stream    = stream .. concat(queue) .. chunk
		queue     = {}
	else
		insert(queue, chunk)
		return
	end

	if m_boundary=='' or not header then
		-- read first bundary 
		m_boundary = m_boundary==''                and match(stream, "^([^\n]+)\n") or m_boundary
		m_eos      = (#m_boundary>0 and m_eos=='') and m_boundary..'--'             or m_eos
		if not m_boundary then 
			return
		end
		-- get headers
		header, stream = get_headers(stream)
		if not header then
			return
		end			
		-- initialize stream writer
		stream_handler = writer('')	
	end

	resume(coroutine, stream)
end

-- 
return function (ops)

	ops               = ops            and ops            or {}
	tmp_path          = ops.tmp_path   and ops.tmp_path   or './tmp'
	ops.endpoints     = ops.end_points and ops.end_points or {'POST .'}
	exists(ops.tmp_path, function(err, _exists) errors = (err~=nil or not _exists) end)
  
  -- handler
  return function (req, res, nxt)
  	if not errors then

  		local function on_stream_finish()
				on_stream_arrival('', 0)
				finish_callback = function()
					if #queue==0 then
						nxt()
					else
						stream = stream .. concat(queue)
						queue  = {}
						parse(stream)
					end
				end
			end

	  	req:on('data', on_stream_arrival)
	  	req:on('end',  on_stream_finish)
		else
			p('error ocurred')
			nxt()
		end
	end
end

--
--local stream = stream_read(__dirname .. '/multipart_form')
--local chunks = ''
--stream:on('data', function(chunk, len) chunks = chunks .. chunk end)
--stream:on('end', function() parse(chunks) end)
--
