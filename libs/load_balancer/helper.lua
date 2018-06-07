local ngx = require "ngx"
local setmetatable = setmetatable

local _M = { _VERSION = '0.02' }
local mt = { __index = _M }


function _M.new(class, key, hostname, dns_server, ttl)
    local dns_master, err = require("resolver.master"):new(key, hostname, {dns_server}, ttl, ttl)
    if not dns_master then
        error("failed to create dns resolver master: " .. err)
        ngx.log("err case")
    end

    local self = setmetatable({
        _dns_master    = dns_master,
        _dns_client    = nil
    }, mt)

    return self
end

function _M.init_worker(self)
    if not self._dns_master then
        error("DNS resolver master must be initialized with new() first")
    end

    self._dns_master:init()
    local dns_client, err = self._dns_master:client()
    if not dns_client then
        error("failed to create dns resolver client: " .. err)
    end

    self._dns_client = dns_client
end

local function get_host_ips(client)
    local addrs, err = client:get_all(true)
    if not addrs then
        ngx.log(ngx.ERR, "failed to lookup hosts: ", err)
    end

    return addrs
end

function _M.lb_rr(self, host_port)
    local balancer = require "ngx.balancer"

    -- dns resolver does round robin itself
    local host, err = self._dns_client:get(true)
    if not host then
        ngx.log(ngx.ERR, "failed to lookup host: ", err)
    end

    local ok, err = balancer.set_current_peer(host, host_port)  
    if not ok then  
        ngx.log(ngx.ERR, "failed to set the current peer: ", err)  
        return ngx.exit(500)
    end
end

function _M.lb_hash(self, host_port, key)
    local balancer = require "ngx.balancer"
    local backend = ""

    local addrs = get_host_ips(self._dns_client)
    if not addrs then 
        return ngx.exit(500) -- no hosts in dns entry
    end

    local hash = ngx.crc32_long(key)
    local index = (hash % #addrs) + 1
    backend = addrs[index]

    local ok, err = balancer.set_current_peer(backend, host_port)  
    if not ok then  
        ngx.log(ngx.ERR, "failed to set the current peer: ", backend)  
        return ngx.exit(500)
    end
end

function _M.lb_cookie(self, host_port)
    local ck = require "resty.cookie"
    local cookie, err = ck:new()
    if not cookie then
        ngx.log(ngx.ERR, err)
    end

    --- check if cookie is set, if not set it to random hash and use hash as key for lb_hash function
    local cookie_name = "LBSESSION"
    local cookie_value = cookie:get(cookie_name)

    if not cookie_value then
        cookie_value = ngx.crc32_long(ngx.var.remote_port)

        cookie:set({
            key = cookie_name, 
            value = cookie_value,
            path = "/"
        })
    end

    return self:lb_hash(host_port, cookie_value)
end

return _M