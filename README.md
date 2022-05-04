docker-rotating-proxy
=====================

[![Docker Pulls](https://img.shields.io/docker/pulls/mattes/rotating-proxy.svg)](https://hub.docker.com/r/mattes/rotating-proxy/)

```
               Docker Container
               -------------------------------------
                        <->  Proxy 1
Client <---->  HAproxy  <->  Proxy 2
                        <->  Proxy n
```
__Why:__ Lots of IP addresses. One single endpoint for your client.
Load-balancing by HAproxy with Sticky session and basic oauth.

Usage
-----

```bash
# build docker container
docker build -t mattes/rotating-proxy:latest .

# ... or pull docker container
docker pull mattes/rotating-proxy:latest

# start docker container
docker run -d -p 5566:5566 -p 4444:4444 --env proxies_url=proxy_url_json mattes/rotating-proxy

# test with ...
curl --proxy 127.0.0.1:5566 https://api.my-ip.io/ip

# monitor
http://127.0.0.1:4444/haproxy?stats
```


Further Readings
----------------

 * [HAProxy Manual](http://cbonte.github.io/haproxy-dconv/configuration-1.5.html)


--------------

