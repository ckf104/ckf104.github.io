* 每个Node会连若干条边，每条边都对应一个`Port`，`Port`的数据类型为`BO`，由`EdgeO`生成, `upward parameter`从`sink node`流向`source node`，`downward parameter`从`source node`流向`sink node`。
* `a :*=* b` 将根据`a, b`的实际连接情况，退化为`a :*= b`（当`a, b`仅出现在`:*=`连接符中时），或退化为`a :=* b`（当`a, b`仅出现在`:=*`中时），如果在`:*=*`的可达子图中的节点出现在了`:*=`和`:=*`中，报错。如果`a, b`的`flexibleArityDirection`均为`false`，`a :*=* b`退化为`a := b`

