# Network programs (3.0)

Programs on the data disk that use the network through `SYS_NET` (`../kernel/network.md`). The regression run puts them on a disk of their own (`net.img`) and answers DNS and HTTP with `tools/netserve.py` on the host.

## wget (`run wget <url> [file|-]`)

Fetches an `http://host[:port]/path` URL (the `http://` may be left out) with HTTP/1.1 and saves the body to `<file>`, or to the last part of the path (`index.htm` for `/`), or prints it with `-`. At the end it prints one line:

    wget: 200, 34 bytes, sum 2948 -> hello.txt

The sum is the body's bytes added together modulo 65536, to compare with the server's copy. A status other than 2xx is printed (`wget: 404, 9 bytes, sum 799`) and no file is kept. Errors: `not an http:// URL` (including `https://`), `host not found`, `no connection`, `the reply broke off`, `too many redirects`, `disk full`. The exit code is 0 for a 2xx answer.

The client is `programs/http.inc`, a library any program can include after `net.inc`:

- `http_get` (esi = URL, edi = callback) resolves the host, connects, sends `GET` with `Host`, `User-Agent: SquirrelOS2-wget/3.0`, `Accept` and `Connection: close`, and reads the status line and headers.
- The body is handed to the callback (esi = bytes, ecx = count; CF set stops) as it arrives: exactly `Content-Length` bytes, or a chunked body (chunk extensions and trailers are read past), or everything until the server closes.
- 301, 302, 303, 307 and 308 with a `Location` are followed, four times at most; a `Location` starting with `/` keeps the host and port.
- `http_status`, `http_clen` and `http_got` describe the last response.

Checks: `wget-len`, `wget-saved`, `wget-chunked`, `wget-redirect`, `wget-404`, `wget-big` (20 000 bytes through the TCP window), `wget-headers`, `wget-nohost`, `wget-https`.

## Network Settings (`run netcfg`)

A window with the card's MAC address, how the settings were made (`manual`, or `dhcp` with the lease), and four fields: address, mask, gateway and DNS server.

| Key | Action |
|-----|--------|
| Up, Down, Tab | pick a field (yellow) |
| digits, `.`, Backspace | edit it |
| Enter or Apply | set the four values (`Applied`, `Bad address`, or `Gateway is not on that subnet`) |
| F2 or DHCP | ask a DHCP server and show what it gave |
| F3 or Save | write `network.cfg` |
| left click | picks a field or presses a button |
| Esc | closes |

From the shell, without the window:

| Command | Does |
|---------|------|
| `run netcfg show` | prints the settings |
| `run netcfg dhcp` | asks DHCP, then prints them |
| `run netcfg set <ip> <mask> <gw> <dns>` | sets them by hand |
| `run netcfg save` | writes `network.cfg`: `dhcp`, or `static <ip> <mask> <gw> <dns>` |
| `run netcfg load` | applies `network.cfg`; put it in `autoexec.bat` to set the network at boot |

Checks: `netcfg-set`, `netcfg-offnet`, `netcfg-load`, `netcfg-gui-dhcp`, `netcfg-gui-apply`.
