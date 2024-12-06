软件上试了一下 rdesktop 和 xfreerdp，rdesktop 慢的不行并且部分形状的光标渲染不出来，鼠标直接消失了，见 [Mouse Cursor Invisible](https://github.com/rdesktop/rdesktop/issues/86)。xfreerdp 用着挺好的，但不知道为啥偶尔应用会有些卡顿，但没啥大问题。我使用的命令为
```shell
xfreerdp  /dynamic-resolution /u:username /v:ip:port
```
`/dynamic-resolution` 使得窗口大小可以动态调整

如果不在同一个局域网内的话可以用 ssh 的 local forward 和 remote forward 打洞

问题1：ssh port remote forwarding 一直有问题，用 telnet 连接显示
```
Connection closed by foreign host
```
[Win32 OpenSSH Reverse Connection Tunnelling is not working](https://github.com/PowerShell/Win32-OpenSSH/issues/1265) 中讨论了这个问题，windows 上的 localhost 默认情况下是表示 ipv6 的 loopback 地址 `::1`，如果应用只监听了 ipv4 的地址，那就会报错

根据 [How to support both IPv4 and IPv6 connections](https://stackoverflow.com/questions/1618240/how-to-support-both-ipv4-and-ipv6-connections)，关闭 socket 的 `IPV6_V6ONLY` 选项后可以同时监听 ipv4 和 ipv6 协议。[IPv4-mapped IPv6 addresses](https://en.wikipedia.org/wiki/IPv6#IPv4-mapped_IPv6_addresses) 中阐述了 ipv4 地址是如何映射到 ipv6 地址的。例如 socket 关闭 `IPV6_V6ONLY` 后并监听在 `::` 地址上时，ipv4 本地回环的 127.0.0.1 连接过来，那么这个监听套接字收到的 ip 地址为 `::ffff:127.0.0.1`

问题2：小键盘偶尔会失灵
发现切出去之后在 host 上重新启用小键盘就又能用了，暂时先这样吧
