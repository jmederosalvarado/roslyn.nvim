local uv = vim.uv
local log = require("vim.lsp.log")
local protocol = require("vim.lsp.protocol")
local validate, schedule, schedule_wrap = vim.validate, vim.schedule, vim.schedule_wrap

--- Embeds the given string into a table and correctly computes `Content-Length`.
---
---@param encoded_message (string)
---@return string containing encoded message and `Content-Length` attribute
local function format_message_with_content_length(encoded_message)
    return table.concat({
        "Content-Length: ",
        tostring(#encoded_message),
        "\r\n\r\n",
        encoded_message,
    })
end

--- Parses an LSP Message's header
---
---@param header string: The header to parse.
---@return table # parsed headers
local function parse_headers(header)
    assert(type(header) == "string", "header must be a string")
    local headers = {}
    for line in vim.gsplit(header, "\r\n", { plain = true }) do
        if line == "" then
            break
        end
        local key, value = line:match("^%s*(%S+)%s*:%s*(.+)%s*$")
        if key then
            key = key:lower():gsub("%-", "_")
            headers[key] = value
        else
            local _ = log.error() and log.error("invalid header line %q", line)
            error(string.format("invalid header line %q", line))
        end
    end
    headers.content_length = tonumber(headers.content_length)
        or error(string.format("Content-Length not found in headers. %q", header))
    return headers
end

-- This is the start of any possible header patterns. The gsub converts it to a
-- case insensitive pattern.
local header_start_pattern = ("content"):gsub("%w", function(c)
    return "[" .. c .. c:upper() .. "]"
end)

--- The actual workhorse.
local function request_parser_loop()
    local buffer = "" -- only for header part
    while true do
        -- A message can only be complete if it has a double CRLF and also the full
        -- payload, so first let's check for the CRLFs
        local start, finish = buffer:find("\r\n\r\n", 1, true)
        -- Start parsing the headers
        if start then
            -- This is a workaround for servers sending initial garbage before
            -- sending headers, such as if a bash script sends stdout. It assumes
            -- that we know all of the headers ahead of time. At this moment, the
            -- only valid headers start with "Content-*", so that's the thing we will
            -- be searching for.
            -- TODO(ashkan) I'd like to remove this, but it seems permanent :(
            local buffer_start = buffer:find(header_start_pattern)
            if not buffer_start then
                error(
                    string.format(
                        "Headers were expected, a different response was received. The server response was '%s'.",
                        buffer
                    )
                )
            end
            local headers = parse_headers(buffer:sub(buffer_start, start - 1))
            local content_length = headers.content_length
            -- Use table instead of just string to buffer the message. It prevents
            -- a ton of strings allocating.
            -- ref. http://www.lua.org/pil/11.6.html
            local body_chunks = { buffer:sub(finish + 1) }
            local body_length = #body_chunks[1]
            -- Keep waiting for data until we have enough.
            while body_length < content_length do
                local chunk = coroutine.yield() or error("Expected more data for the body. The server may have died.") -- TODO hmm.
                table.insert(body_chunks, chunk)
                body_length = body_length + #chunk
            end
            local last_chunk = body_chunks[#body_chunks]

            body_chunks[#body_chunks] = last_chunk:sub(1, content_length - body_length - 1)
            local rest = ""
            if body_length > content_length then
                rest = last_chunk:sub(content_length - body_length)
            end
            local body = table.concat(body_chunks)
            -- Yield our data.
            buffer = rest
                .. (
                    coroutine.yield(headers, body)
                    or error("Expected more data for the body. The server may have died.")
                ) -- TODO hmm.
        else
            -- Get more data since we don't have enough.
            buffer = buffer
                .. (coroutine.yield() or error("Expected more data for the header. The server may have died.")) -- TODO hmm.
        end
    end
end

local M = {}

--- Mapping of error codes used by the client
--- @nodoc
local client_errors = {
    INVALID_SERVER_MESSAGE = 1,
    INVALID_SERVER_JSON = 2,
    NO_RESULT_CALLBACK_FOUND = 3,
    READ_ERROR = 4,
    NOTIFICATION_HANDLER_ERROR = 5,
    SERVER_REQUEST_HANDLER_ERROR = 6,
    SERVER_RESULT_CALLBACK_ERROR = 7,
}

--- @type table<string|integer, string|integer>
--- @nodoc
M.client_errors = vim.deepcopy(client_errors)
for k, v in pairs(client_errors) do
    M.client_errors[v] = k
end

local default_dispatchers = {}

---@private
--- Default dispatcher for notifications sent to an LSP server.
---
---@param method (string) The invoked LSP method
---@param params (table): Parameters for the invoked LSP method
function default_dispatchers.notification(method, params)
    local _ = log.debug() and log.debug("notification", method, params)
end

---@private
--- Default dispatcher for requests sent to an LSP server.
---
---@param method (string) The invoked LSP method
---@param params (table): Parameters for the invoked LSP method
---@return nil
---@return table `vim.lsp.protocol.ErrorCodes.MethodNotFound`
function default_dispatchers.server_request(method, params)
    local _ = log.debug() and log.debug("server_request", method, params)
    return nil, vim.lsp.rpc.rpc_response_error(protocol.ErrorCodes.MethodNotFound)
end

---@private
--- Default dispatcher for when a client exits.
---
---@param code (integer): Exit code
---@param signal (integer): Number describing the signal used to terminate (if
---any)
function default_dispatchers.on_exit(code, signal)
    local _ = log.info() and log.info("client_exit", { code = code, signal = signal })
end

---@private
--- Default dispatcher for client errors.
---
---@param code (integer): Error code
---@param err (any): Details about the error
---any)
function default_dispatchers.on_error(code, err)
    local _ = log.error() and log.error("client_error:", M.client_errors[code], err)
end

---@private
function M.create_read_loop(handle_body, on_no_chunk, on_error)
    local parse_chunk = coroutine.wrap(request_parser_loop)
    parse_chunk()
    return function(err, chunk)
        if err then
            on_error(err)
            return
        end

        if not chunk then
            if on_no_chunk then
                on_no_chunk()
            end
            return
        end

        while true do
            local headers, body = parse_chunk(chunk)
            if headers then
                handle_body(body)
                chunk = ""
            else
                break
            end
        end
    end
end

---@class RpcClient
---@field message_index integer
---@field message_callbacks table
---@field notify_reply_callbacks table
---@field transport table
---@field dispatchers table

---@class RpcClient
local Client = {}

function Client:encode_and_send(payload)
    local _ = log.debug() and log.debug("rpc.send", payload)
    if self.transport.is_closing() then
        return false
    end
    local encoded = vim.json.encode(payload)
    self.transport.write(format_message_with_content_length(encoded))
    return true
end

--- Sends a notification to the LSP server.
---@param method (string) The invoked LSP method
---@param params (any): Parameters for the invoked LSP method
---@return boolean `true` if notification could be sent, `false` if not
function Client:notify(method, params)
    return self:encode_and_send({
        jsonrpc = "2.0",
        method = method,
        params = params,
    })
end

--- sends an error object to the remote LSP process.
function Client:send_response(request_id, err, result)
    return self:encode_and_send({
        id = request_id,
        jsonrpc = "2.0",
        error = err,
        result = result,
    })
end

--- Sends a request to the LSP server and runs {callback} upon response.
---
---@param method (string) The invoked LSP method
---@param params (table|nil) Parameters for the invoked LSP method
---@param callback fun(err: lsp.ResponseError|nil, result: any) Callback to invoke
---@param notify_reply_callback (function|nil) Callback to invoke as soon as a request is no longer pending
---@return boolean success, integer|nil request_id true, request_id if request could be sent, `false` if not
function Client:request(method, params, callback, notify_reply_callback)
    validate({
        callback = { callback, "f" },
        notify_reply_callback = { notify_reply_callback, "f", true },
    })
    self.message_index = self.message_index + 1
    local message_id = self.message_index
    local result = self:encode_and_send({
        id = message_id,
        jsonrpc = "2.0",
        method = method,
        params = params,
    })
    local message_callbacks = self.message_callbacks
    local notify_reply_callbacks = self.notify_reply_callbacks
    if result then
        if message_callbacks then
            if method == "textDocument/hover" then
                message_callbacks[message_id] = schedule_wrap(self.process_hover_response(self, callback))
            else
                message_callbacks[message_id] = schedule_wrap(callback)
            end
        else
            return false
        end
        if notify_reply_callback and notify_reply_callbacks then
            notify_reply_callbacks[message_id] = schedule_wrap(notify_reply_callback)
        end
        return result, message_id
    else
        return false
    end
end

---@private
---@return fun(err: lsp.ResponseError|nil, result: any)
function Client:process_hover_response(callback)
    return function(err, result)
        if
            result ~= nil
            and result.contents.kind == "markdown"
            and result.contents.value ~= nil
            and result.contents.value ~= ""
        then
            result.contents.value = result.contents.value:gsub("```csharp", "```c_sharp")
        end
        callback(err, result)
    end
end

function Client:on_error(errkind, ...)
    assert(M.client_errors[errkind])
    -- TODO what to do if this fails?
    pcall(self.dispatchers.on_error, errkind, ...)
end

---@private
function Client:pcall_handler(errkind, status, head, ...)
    if not status then
        self:on_error(errkind, head, ...)
        return status, head
    end
    return status, head, ...
end

---@private
function Client:try_call(errkind, fn, ...)
    return self:pcall_handler(errkind, pcall(fn, ...))
end

-- TODO periodically check message_callbacks for old requests past a certain
-- time and log them. This would require storing the timestamp. I could call
-- them with an error then, perhaps.

function Client:handle_body(body)
    local ok, decoded = pcall(vim.json.decode, body, { luanil = { object = true } })
    if not ok then
        self:on_error(M.client_errors.INVALID_SERVER_JSON, decoded)
        return
    end
    local _ = log.debug() and log.debug("rpc.receive", decoded)

    if type(decoded.method) == "string" and decoded.id then
        local err
        -- Schedule here so that the users functions don't trigger an error and
        -- we can still use the result.
        schedule(function()
            coroutine.wrap(function()
                local status, result
                status, result, err = self:try_call(
                    M.client_errors.SERVER_REQUEST_HANDLER_ERROR,
                    self.dispatchers.server_request,
                    decoded.method,
                    decoded.params
                )
                local _ = log.debug()
                    and log.debug("server_request: callback result", { status = status, result = result, err = err })
                if status then
                    if result == nil and err == nil then
                        error(
                            string.format(
                                "method %q: either a result or an error must be sent to the server in response",
                                decoded.method
                            )
                        )
                    end
                    if err then
                        assert(
                            type(err) == "table",
                            "err must be a table. Use rpc_response_error to help format errors."
                        )
                        local code_name = assert(
                            protocol.ErrorCodes[err.code],
                            "Errors must use protocol.ErrorCodes. Use rpc_response_error to help format errors."
                        )
                        err.message = err.message or code_name
                    end
                else
                    -- On an exception, result will contain the error message.
                    err = vim.lsp.rpc.rpc_response_error(protocol.ErrorCodes.InternalError, result)
                    result = nil
                end
                self:send_response(decoded.id, err, result)
            end)()
        end)
    -- This works because we are expecting vim.NIL here
    elseif decoded.id and (decoded.result ~= vim.NIL or decoded.error ~= vim.NIL) then
        -- We sent a number, so we expect a number.
        local result_id = assert(tonumber(decoded.id), "response id must be a number")

        -- Notify the user that a response was received for the request
        local notify_reply_callbacks = self.notify_reply_callbacks
        local notify_reply_callback = notify_reply_callbacks and notify_reply_callbacks[result_id]
        if notify_reply_callback then
            validate({
                notify_reply_callback = { notify_reply_callback, "f" },
            })
            notify_reply_callback(result_id)
            notify_reply_callbacks[result_id] = nil
        end

        local message_callbacks = self.message_callbacks

        -- Do not surface RequestCancelled to users, it is RPC-internal.
        if decoded.error then
            local mute_error = false
            if decoded.error.code == protocol.ErrorCodes.RequestCancelled then
                local _ = log.debug() and log.debug("Received cancellation ack", decoded)
                mute_error = true
            end

            if mute_error then
                -- Clear any callback since this is cancelled now.
                -- This is safe to do assuming that these conditions hold:
                -- - The server will not send a result callback after this cancellation.
                -- - If the server sent this cancellation ACK after sending the result, the user of this RPC
                -- client will ignore the result themselves.
                if result_id and message_callbacks then
                    message_callbacks[result_id] = nil
                end
                return
            end
        end

        local callback = message_callbacks and message_callbacks[result_id]
        if callback then
            message_callbacks[result_id] = nil
            validate({
                callback = { callback, "f" },
            })
            if decoded.error then
                decoded.error = setmetatable(decoded.error, {
                    __tostring = vim.lsp.rpc.format_rpc_error,
                })
            end
            self:try_call(M.client_errors.SERVER_RESULT_CALLBACK_ERROR, callback, decoded.error, decoded.result)
        else
            self:on_error(M.client_errors.NO_RESULT_CALLBACK_FOUND, decoded)
            local _ = log.error() and log.error("No callback found for server response id " .. result_id)
        end
    elseif type(decoded.method) == "string" then
        -- Notification
        self:try_call(
            M.client_errors.NOTIFICATION_HANDLER_ERROR,
            self.dispatchers.notification,
            decoded.method,
            decoded.params
        )
    else
        -- Invalid server message
        self:on_error(M.client_errors.INVALID_SERVER_MESSAGE, decoded)
    end
end

---@return RpcClient
local function new_client(dispatchers, transport)
    local state = {
        message_index = 0,
        message_callbacks = {},
        notify_reply_callbacks = {},
        transport = transport,
        dispatchers = dispatchers,
    }
    return setmetatable(state, { __index = Client })
end

---@param client RpcClient
local function public_client(client)
    local result = {}

    ---@private
    function result.is_closing()
        return client.transport.is_closing()
    end

    ---@private
    function result.terminate()
        client.transport.terminate()
    end

    --- Sends a request to the LSP server and runs {callback} upon response.
    ---
    ---@param method (string) The invoked LSP method
    ---@param params (table|nil) Parameters for the invoked LSP method
    ---@param callback fun(err: lsp.ResponseError | nil, result: any) Callback to invoke
    ---@param notify_reply_callback (function|nil) Callback to invoke as soon as a request is no longer pending
    ---@return boolean success, integer|nil request_id true, message_id if request could be sent, `false` if not
    function result.request(method, params, callback, notify_reply_callback)
        return client:request(method, params, callback, notify_reply_callback)
    end

    --- Sends a notification to the LSP server.
    ---@param method (string) The invoked LSP method
    ---@param params (table|nil): Parameters for the invoked LSP method
    ---@return boolean `true` if notification could be sent, `false` if not
    function result.notify(method, params)
        return client:notify(method, params)
    end

    return result
end

local function merge_dispatchers(dispatchers)
    if not dispatchers then
        return default_dispatchers
    end
    ---@diagnostic disable-next-line: no-unknown
    for name, fn in pairs(dispatchers) do
        if type(fn) ~= "function" then
            error(string.format("dispatcher.%s must be a function", name))
        end
    end
    ---@type vim.lsp.rpc.Dispatchers
    local merged = {
        notification = (
            dispatchers.notification and vim.schedule_wrap(dispatchers.notification)
            or default_dispatchers.notification
        ),
        on_error = (dispatchers.on_error and vim.schedule_wrap(dispatchers.on_error) or default_dispatchers.on_error),
        on_exit = dispatchers.on_exit or default_dispatchers.on_exit,
        server_request = dispatchers.server_request or default_dispatchers.server_request,
    }
    return merged
end

--- Starts an LSP server process and create an LSP RPC client object to
--- interact with it. Communication with the spawned process happens via stdio. For
--- communication via TCP, spawn a process manually and use |vim.lsp.rpc.connect()|
---
---@param cmd (string) Command to start the LSP server.
---@param cmd_args (table) List of additional string arguments to pass to {cmd}.
--- server process. May contain:
--- - {cwd} (string) Working directory for the LSP server process
--- - {env} (table) Additional environment variables for LSP server process
---@return function
function M.start_uds(cmd, cmd_args)
    return function(dispatchers)
        if log.info() then
            log.info("Starting RPC client", { cmd = cmd, args = cmd_args })
        end

        validate({
            cmd = { cmd, "s" },
            cmd_args = { cmd_args, "t" },
            dispatchers = { dispatchers, "t", true },
        })

        dispatchers = merge_dispatchers(dispatchers)

        local sysobj ---@type vim.SystemObj
        local write_queue = {}
        -- no idea what the ipc arg is for, but set to false for now
        local pipe, _, err_msg = uv.new_pipe(false)
        if not pipe then
            error(string.format("Failed to create pipe: %s", err_msg))
        end

        local client = new_client(dispatchers, {
            write = function(msg)
                if write_queue ~= nil then
                    table.insert(write_queue, msg)
                else
                    pipe:write(msg)
                end
            end,
            is_closing = function()
                return sysobj == nil or sysobj:is_closing()
            end,
            terminate = function()
                sysobj:kill(15)
            end,
        })

        local stdout_handler = function(_, data)
            -- vim.notify("got data " .. data, vim.log.levels.INFO)
            -- read lines until we can decode json object
            if not data then
                vim.notify(string.format("data evaluates: (%s, %s) ", #data, data[1]), vim.log.levels.INFO)
                return
            end

            -- try parse data as json
            -- vim.notify("will try to parse json from " .. data, vim.log.levels.INFO)
            local success, json_obj = pcall(vim.json.decode, data)
            if not success then
                return
            end

            local pipe_name = json_obj["pipeName"]
            -- vim.notify("will try to connect to " .. pipe_name, vim.log.levels.INFO)
            pipe:connect(pipe_name, function(err)
                if err then
                    vim.schedule(function()
                        vim.notify(
                            string.format("Could not connect to %s, reason: %s", pipe_name, vim.inspect(err)),
                            vim.log.levels.WARN
                        )
                    end)
                    return
                end
                local handle_body = function(body)
                    client:handle_body(body)
                end
                pipe:read_start(M.create_read_loop(handle_body, nil, function(read_err)
                    client:on_error(M.client_errors.READ_ERROR, read_err)
                end))
                pipe:write(write_queue)
                write_queue = nil
            end)
        end

        local stderr_handler = function(_, chunk)
            if chunk and log.error() then
                log.error("rpc", cmd, "stderr", chunk)
            end
        end

        local ok, sysobj_or_err = pcall(vim.system, { cmd, unpack(cmd_args) }, {
            stdout = stdout_handler,
            stderr = stderr_handler,
            detach = not uv.os_uname().version:find("Windows"),
        }, function(obj)
            dispatchers.on_exit(obj.code, obj.signal)
        end)

        if not ok then
            local err = sysobj_or_err --[[@as string]]
            local msg = string.format("Spawning language server with cmd: `%s` failed", cmd)
            if string.match(err, "ENOENT") then
                msg = msg .. ". The language server is either not installed, missing from PATH, or not executable."
            else
                msg = msg .. string.format(" with error message: %s", err)
            end
            vim.notify(msg, vim.log.levels.WARN)
            return
        end

        sysobj = sysobj_or_err --[[@as vim.SystemObj]]

        return public_client(client)
    end
end

return M
