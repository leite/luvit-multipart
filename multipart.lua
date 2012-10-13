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
local os     = require 'os'
local co     = require 'coroutine'
local math   = require 'math'
local uv     = require 'uv'
local writer = require './stream'

local exists, create, status, yield, resume, find, format, match, gsub, sub, lower, insert, concat, each, random, seed, time, timer = 
        fs.exists, co.create, co.status, co.yield, co.resume, st.find, st.format, st.match, st.gsub, st.sub, st.lower, tb.insert, tb.concat, tb.foreach, math.random, math.randomseed, os.time, uv.Timer

local temp_path, finish_callback, coroutine, stream_handler, errors, suspended, headers, header, queue, stream, m_boundary, m_eos, line, i =
        '', function() return true end, nil, nil, false, false, {}, {}, {}, '', '', '', '', 0

fs, tb, st, os, co, math, uv = nil, nil, nil, nil, nil, nil, nil

local function detect(table, value)
  local function _each_pairs(k, v)
    if v==value then return true end
  end
  return each(table, _each_pairs)==true
end

-- parse mime/multipart headers
local function get_headers()
  local header, headers = match(stream, "^"..m_boundary.."\r?\n(.-\r?\n\r?\n)"), {}
  local headers_loop    = function(k, v) headers[k] = v end
  if header then
    gsub(header, '%s?([^%:?%=?]+)%:?%s?%=?%"?([^%"?%;?%c?]+)%"?%;?%c?', headers_loop)
    stream = sub(stream, #m_boundary+#header+3)
    return headers
  end
  return nil
end

--
local function unique_file_name(name)
  seed(192837465)
  return format("%s/%d_%d_%s", temp_path, random(19375, 293847560), time(), name)
end

local function write_data_block(err) 
  if err then
    -- cannot write or close file ... permission?, disk failure?, wtf!
  end
  resume(coroutine)
end

-- finish data blocks
local function finish_data_block()
  if not stream_handler.is_free() then
    -- close file handler
    stream_handler.close(write_data_block)
    yield()
  end
end

-- parse body/multipart
local function parse()

  local boundary_position, new_line_position = 0, 0

  while true do

    boundary_position = find(stream, m_boundary) or 0
    if boundary_position>3 then
      line = sub(stream, 1, boundary_position-3)
    else
      new_line_position = find(stream, "\n") or 0
      if new_line_position>1 and boundary_position==1 then
        line = sub(stream, 1, new_line_position)
      else
        new_line_position = find(stream, "\n", (-1*(#m_boundary+1))) or #stream
        line = #stream>0 and sub(stream, 1, new_line_position) or line
      end
    end

    if not line then
      if finish_callback() then 
        suspended = true
        yield()
      end
    elseif find(line, m_eos, 1, true) then
      finish_data_block()
      insert(headers, header)
      stream = ''
      if finish_callback() then break end
    elseif boundary_position==1 then
      finish_data_block()
      insert(headers, header)
      header = get_headers()
      if not header then
        if finish_callback() then
          suspended = true
          yield()
        end
      end
    else
      if header.filename then
        if stream_handler.is_free() then
          header.filename  = unique_file_name(header.filename)
          stream_handler.new(header.filename)
        end
        stream_handler.write(line, write_data_block)
        yield()
      else
        header.value = header.value==nil and line or header.value.."\n"..line
      end
      stream = sub(stream, #line+(boundary_position>2 and 3 or 1))
    end
    line = nil
  end
end

local function on_stream_arrival(chunk, length) 

  if not coroutine then
    coroutine = create(parse)
    stream    = chunk
  elseif suspended then
    stream    = stream .. concat(queue) .. chunk
    queue     = {}
    suspended = false
  else
    insert(queue, chunk)
    return
  end

  if m_boundary=='' or not header then
    -- read first bundary 
    m_boundary = m_boundary==''                and match(stream, "^([^\r?\n?]+)\n?\r?") or m_boundary
    m_eos      = (#m_boundary>0 and m_eos=='') and m_boundary..'--'                     or m_eos
    if not m_boundary then 
      return
    end
    -- get headers
    header = get_headers()
    if not header then
      return
    end      
    -- initialize stream writer
    stream_handler = writer('')  
  end

  resume(coroutine)
end

-- 
return function (ops)

  ops               = ops            and ops            or {}
  temp_path         = ops.temp_path  and ops.temp_path  or './tmp'
  ops.methods       = ops.methods    and ops.methods    or {'POST'}
  ops.endpoints     = ops.end_points and ops.end_points or {'.'}
  exists(temp_path, function(err, _exists) errors = (err~=nil or not _exists) end)
  
  -- handler
  return function (req, res, nxt)
    if not errors and req.headers['content-type'] and detect(ops.methods, req.method) then
      if find(req.headers['content-type'], "multipart/form-data", 1, true) then

        local function on_stream_finish()
          on_stream_arrival('', 0)
          finish_callback = function()
            if #queue==0 then
              -- reset
              p(headers)
              suspended, stream, m_boundary, m_eos, headers = false, '', '', '', {}
              req:emit('continue')
              return true
            else
              stream = stream .. concat(queue)
              queue  = {}
              return false
            end
          end
        end

        coroutine = nil
        req:on('data', on_stream_arrival)
        req:on('end',  on_stream_finish)
        req:on('continue', nxt)
      elseif find(req.headers['content-type'], "x-www-form-urlencoded", 1, true) then
        p('x-www-form-urlencoded found')
      else
        nxt()
      end
    else
      nxt()
    end
  end
end