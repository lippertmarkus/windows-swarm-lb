windows-swarm-lb
===

[![Build status](https://ci.appveyor.com/api/projects/status/ex98maaeice55ysc?svg=true)](https://ci.appveyor.com/project/lippertmarkus/windows-swarm-lb)

Dynamic load balancer inside a Windows Container for Docker Swarm Mode. 

## Background

There are a lot of load balancers for Docker out there. Unfortunately, their support for Windows nodes running in Docker Swarm Mode is very poor. Furthermore, many of them need access to the Docker API for service discovery.

This load balancer uses Docker's internal DNS for service discovery instead. Docker updates the DNS entries of a service immediately when instances of a service are changed. It also respects the health of the instances, what makes them almost perfect for service discovery and it doesn't require any additional services.

## Features

This project uses [OpenResty](http://openresty.org/) as well as two libraries on top:

- Slightly adapted [lua-resty-resolver](https://github.com/lippertmarkus/lua-resty-resolver/) for dynamic DNS resolution without reloading
- [lua-resty-cookie](https://github.com/cloudflare/lua-resty-cookie/) for HTTP cookie manipulation to support cookie based load balancing

OpenResty is highly customizable via various libraries as well as LUA scripting and allows maximum flexibility.

Following **load-balancing mechanisms** are supported:
- Round-robin (for TCP/UDP and HTTP)
- Hash-based with custom key (e.g. use [any variables](http://nginx.org/en/docs/varindex.html)) (for TCP/UDP and HTTP)
- Cookie-based (for HTTP only)

The [start script](./start.ps1) automatically determines the IP of the internal Docker DNS server and ensures that the given DNS name is resolvable before starting the load balancer.

## Usage 

The [`docker-stack.yml`](./docker-stack.yml) shows an example stack which uses this project. The **hostname** which should be dynamically resolved is defined via the `UP_HOSTNAME` environment variable. You can easily add multiple hostnames via additional environment variables. Generally, the hostnames are equal to the name of a service.

The **configuration** is done in the [`nginx.conf`](./nginx.conf) file. Most of the configuration is self-explanatory. Please note that using TCP/UDP and HTTP load balancing simultaneously, as in the [`nginx.conf`](./nginx.conf), requires two shared dictionaries and two instances of the load balancer helper as the `http` and `stream` sections can't share any data. Also, each hostname passed via environment variable needs it's own shared dictionary and instance of the load balancer helper.

You can use the following functions of your instance `lb_inst` inside `balancer_by_lua_block` for the different **load balancing mechanisms**:

- Round-robin (Upstream port 8080): `lb_inst:lb_rr(8080)` \
  Supported in `http` and `stream` section.
- Hash-based (Upstream port 8080 and key containing only the remote IP): `lb_inst:lb_hash(8080, ngx.var.remote_addr)` \
  Supported in `http` and `stream` section. You can also use other [variables](http://nginx.org/en/docs/varindex.html) (`ngx.var.VARIABLE`) or combinations of them
- Cookie-based (Upstream port 8080): `lb_inst:lb_cookie(8080)` \
  Supported in `http` section only.

## ToDos

- Because of a bug/change in [`lua-resty-dns`](https://github.com/openresty/lua-resty-dns) which is used by [`lua-resty-resolver`](https://github.com/lippertmarkus/lua-resty-resolver) we can't use OpenResty v1.13.6.2 which finally provides a 64 bit binary for windows that [allows the use of the much smaller `microsoft/nanoserver` base image](https://github.com/openresty/docker-openresty/pull/70) for OpenResty
- Simplify usage of multiple hostnames

## Demo

This uses the [`docker-stack.yml`](./docker-stack.yml) in the repository and shows the different load balancing mechanisms:


```
PS C:\> docker stack ps mystack
ID                  NAME                IMAGE                         NODE                DESIRED STATE       CURRENT STATE                ERROR               PORTS
ow9ni1quzmn3        mystack_whoami.1    stefanscherer/whoami:latest   t00-dev-mlip03      Running             Running about a minute ago
y14hy1lx3qwb        mystack_proxy.1     swarm/resty:latest            t00-dev-mlip03      Running             Running 45 seconds ago
75o7cpbcrkxa        mystack_whoami.2    stefanscherer/whoami:latest   t00-dev-mlip03      Running             Running about a minute ago
8mfjbiwp3x49        mystack_whoami.3    stefanscherer/whoami:latest   t00-dev-mlip03      Running             Running about a minute ago


################ Test cookie-based load balancing ################

PS C:\> $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
PS C:\> $session.Cookies.Count
0
PS C:\> (Invoke-WebRequest -Uri "http://172.23.62.56:80/" -DisableKeepAlive -UseBasicParsing -WebSession $session).Content
I'm 200da4ca6fdf running on windows/amd64

PS C:\> $session.Cookies.Count
1
PS C:\> (Invoke-WebRequest -Uri "http://172.23.62.56:80/" -DisableKeepAlive -UseBasicParsing -WebSession $session).Content
I'm 200da4ca6fdf running on windows/amd64

PS C:\> (Invoke-WebRequest -Uri "http://172.23.62.56:80/" -DisableKeepAlive -UseBasicParsing -WebSession $session).Content
I'm 200da4ca6fdf running on windows/amd64


################ Test round-robin load-balancing ################

PS C:\> (Invoke-WebRequest -Uri "http://172.23.62.56:81/" -DisableKeepAlive -UseBasicParsing -WebSession $session).Content
I'm 200da4ca6fdf running on windows/amd64

PS C:\> (Invoke-WebRequest -Uri "http://172.23.62.56:81/" -DisableKeepAlive -UseBasicParsing -WebSession $session).Content
I'm 1466144c875a running on windows/amd64

PS C:\> (Invoke-WebRequest -Uri "http://172.23.62.56:81/" -DisableKeepAlive -UseBasicParsing -WebSession $session).Content
I'm b75267c64f30 running on windows/amd64


################ Test IP hash load balancing ################

PS C:\> (Invoke-WebRequest -Uri "http://172.23.62.56:82/" -DisableKeepAlive -UseBasicParsing -WebSession $session).Content
I'm b75267c64f30 running on windows/amd64

PS C:\> (Invoke-WebRequest -Uri "http://172.23.62.56:82/" -DisableKeepAlive -UseBasicParsing -WebSession $session).Content
I'm b75267c64f30 running on windows/amd64

PS C:\> (Invoke-WebRequest -Uri "http://172.23.62.56:82/" -DisableKeepAlive -UseBasicParsing -WebSession $session).Content
I'm b75267c64f30 running on windows/amd64

PS C:\> (Invoke-WebRequest -Uri "http://172.23.62.56:82/" -DisableKeepAlive -UseBasicParsing -WebSession $session).Content
I'm b75267c64f30 running on windows/amd64
```