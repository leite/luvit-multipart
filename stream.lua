-- ----------------------------------------------------------------------------
-- "THE BEER-WARE LICENSE" (Revision 42):
-- <xxleite@gmail.com> wrote this file. As long as you retain this notice you
-- can do whatever you want with this stuff. If we meet some day, and you think
-- this stuff is worth it, you can buy me a beer in return
-- ----------------------------------------------------------------------------

local native = require 'uv_native'

local close, open, write = native.fsClose, native.fsOpen, native.fsWrite
native = nil

local writer = function(path)
  -- Lua upvalues and helpers
  local file_handler, file_path = nil, path
  -- on writing or openning error try to close and report first error
  local function on_error_close(err, callback)
    if file_handler then
      close(file_handler, function(_err)
        file_handler = nil
        callback(err or _err)
      end)
    else
      callback(err)
    end
  end
  -- asyncronous writer helper
  local function async_writer(file_data, offset, callback)
    local function _continue_writing(err, written)
      if err then
        on_error_close(err, callback)
      else
        if written == #file_data then
          callback(nil)
        else
          async_writer(file_data, offset + written, callback)
        end
      end
    end
    write(file_handler, offset, file_data, _continue_writing)
  end

  -- write and close
  return {
    is_free = function()
        return file_handler == nil
      end,
    new = function(path)
        file_path = path
      end,
    close = function(callback)
        if file_handler then
          p('closing ... ', type(callback))
          on_error_close(nil, callback)
        end
      end,
    write = function(file_data, callback)
        if not file_handler then
          open(file_path, 'a', 438, function(err, fd)
            file_handler = fd 
            if err then
              on_error_close(err, callback)
            else
              async_writer(file_data, -1, callback)
            end
          end)
        else
          async_writer(file_data, -1, callback)
        end
      end
    }
end

return writer