FROM openresty/openresty:1.13.6.1-2-windows AS builder

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

WORKDIR C:/build

RUN [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 ; \
    Invoke-WebRequest 'https://github.com/lippertmarkus/lua-resty-resolver/archive/master.zip' -OutFile resolver.zip ; \
    Expand-Archive .\resolver.zip . ; \
    mv .\*resolver*\lib\* C:\openresty\lualib\ ; \
    \
    Invoke-WebRequest 'https://github.com/cloudflare/lua-resty-cookie/archive/master.zip' -OutFile cookie.zip ; \
    Expand-Archive .\cookie.zip . ; \
    mv .\*cookie*\lib\resty\* C:\openresty\lualib\resty\ ;


# copy customized libs and config
COPY ./libs/ C:/openresty/lualib/
COPY ./nginx.conf C:/openresty/conf/nginx.conf


FROM microsoft/windowsservercore

WORKDIR C:/openresty
CMD ["powershell", "C:\\start.ps1"]
HEALTHCHECK --timeout=10s \
    CMD ["powershell", "-Command", "Invoke-WebRequest -Uri 'http://127.0.0.1:8080/health' -DisableKeepAlive -UseBasicParsing"]

ENV UP_HOSTNAME=""
COPY ./start.ps1 C:/start.ps1

COPY --from=builder C:/openresty C:/openresty