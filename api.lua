local http = require("resty.http")

local gvarModule = require "otdd.var"
local gvar = gvarModule["var"]

-- when return directly, the request will be processed by nginx subsequently as normal.
-- when ngx.exit(ngx.status), the request will not be processed by nginx subsequently.
local function process(config)
	-- choose one single worker process to do the works only.
	if config and config.worker_processes and ngx.var.pid % config.worker_processes ~= 0 then
		return
	end
	if ngx.now() - gvar.lasttime > config.interval then 
		if gvar.pass == true or ngx.now() - gvar.lasttime > ( config.interval * 30 ) then
			gvar.lasttime = ngx.now()
			gvar.pass = false
			local httpc = http.new()
			httpc:set_timeout(config.connect_timeout)
			ok, err = httpc:connect(config.dest_ip, config.dest_port)
			if not ok then 
				httpc:close()
				ngx.log(ngx.ERR, "[otdd] http connect err ", err)
				return
			end	
			httpc:set_timeout(config.request_timeout)

			local origin_uri = ngx.var.uri
			local origin_args = ngx.var.args
			local real_uri = string.gsub(ngx.var.request_uri, "?.*", "")
			ngx.req.set_uri(real_uri, false)
			if string.find(ngx.var.request_uri, "?") then
				local param = string.gsub(ngx.var.request_uri, ".*?", "")
				ngx.var.args = param
			else
				ngx.var.args = nil
			end
			ngx.log(ngx.INFO, "[otdd] request uri ", "http://"..config.dest_ip..":"..config.dest_port..ngx.var.request_uri)
			res, err = httpc:proxy_request()
			ngx.req.set_uri(origin_uri, false)
			ngx.var.args = origin_args
			if not res then 
				ngx.log(ngx.ERR, "[otdd] http request error, ", err)
				httpc:close()
				return
			else
				gvar.pass = true
				gvar.lasttime = ngx.now()
				httpc:proxy_response(res)
			end
			httpc:set_keepalive()
			ngx.exit(ngx.status)   			
		end	
	end	
end

local _M = {
	process = process,
}

return _M
