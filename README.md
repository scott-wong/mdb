# MDB

MDB 是一个面向 openEuler 的 Valkey 容器发行版：保留 Valkey 核心行为，使用
私有 Tongsuo 运行时提供标准 TLS 和 RFC 8998 TLS 1.3 国密能力，只交付
`linux/amd64` 容器镜像。

当前版本线：

```text
9.1.3-mdb.1
```

> 阶段 A 只生成 `candidate-*` 镜像标签；下文的正式不可变标签要经过单独发布审批后才会存在。

MDB 不是新的缓存引擎，也不是 Valkey 的长期源码 fork。它不包含 Valkey
Search/JSON/Bloom 模块、代理层、Operator、控制面或自研数据结构。

## 快速开始

默认镜像保持 Valkey 容器的使用方式，默认不启用 TLS：

```sh
docker run --rm -p 6379:6379 \
  -v mdb-data:/data \
  ghcr.io/scott-wong/mdb:9.1.3-mdb.1-openeuler
```

生产环境至少应使用 ACL 密码或 mTLS。默认镜像不提供密码，也不会自动生成证书。

## TLS 模式

镜像提供两种相互独立的 TLS 模式。单个 Valkey 监听器只有一套证书，因此标准
TLS 和国密 TLS 不能在同一端口同时提供：

- `MDB_TLS_MODE=standard`：TLS 1.2 + TLS 1.3，标准证书，默认 mTLS。
- `MDB_TLS_MODE=gm`：RFC 8998 TLS 1.3，SM2 证书/SM2 签名，SM3，SM4-GCM，默认 mTLS。
- `MDB_TLS_MODE=off`：TLS 关闭；如果配置中启用 TLS，entrypoint 会拒绝启动。

证书输入约定：

```text
/etc/mdb/tls/server.crt   # 服务器证书，PEM
/etc/mdb/tls/server.key   # 未加密的服务器私钥，PEM
/etc/mdb/tls/ca.crt       # 客户端和节点证书 CA
/etc/mdb/tls/client.crt   # 可选，主从/Cluster 节点作为客户端时使用
/etc/mdb/tls/client.key   # 可选，必须与 client.crt 成对
```

entrypoint 会把输入材料复制到 `/run/mdb/tls`，所有者 `999:999`，私钥
`0400`、证书和 CA `0444`。私钥必须未加密；v1 不支持 passphrase。

### 标准 TLS

```sh
docker run --rm -p 6379:6379 \
  -e MDB_TLS_MODE=standard \
  -v "$PWD/tls:/etc/mdb/tls:ro" \
  -v mdb-data:/data \
  ghcr.io/scott-wong/mdb:9.1.3-mdb.1-openeuler \
  valkey-server /usr/local/share/mdb/examples/standard.conf
```

### 国密 TLS

```sh
docker run --rm -p 6379:6379 \
  -e MDB_TLS_MODE=gm \
  -v "$PWD/tls:/etc/mdb/tls:ro" \
  -v mdb-data:/data \
  ghcr.io/scott-wong/mdb:9.1.3-mdb.1-openeuler \
  valkey-server /usr/local/share/mdb/examples/gm.conf
```

国密模式只承诺 RFC 8998 的 TLS 1.3 国密单证书，不承诺 TLCP/NTLS 双证书握手。
`gm.cnf` 会强制 `Groups=SM2`、`SignatureAlgorithms=sm2sig_sm3` 和
`Enable_sm_tls13_strict=on`；Tongsuo 在编译时没有启用 `enable-ntls`。

## 运行契约

- 基础镜像：openEuler 24.03 LTS SP4，`linux/amd64`。
- 应用用户/组：UID/GID `999`，进程不以 root 运行。
- 数据目录：`/data`，权限 `0770`。
- 运行时目录：`/run/mdb`，权限 `0700`；需要可写 tmpfs。
- PID 1：`tini`；entrypoint 负责 root 降权。
- 默认配置：`/usr/local/etc/mdb/valkey.conf`。
- 默认端口：`6379`。
- `STOPSIGNAL SIGTERM`；不内置 `HEALTHCHECK`。
- 最终镜像不含编译器、头文件、源码包或 `redis-*` 别名。

工具别名：

```text
mdb-server mdb-sentinel mdb-cli mdb-benchmark mdb-check-rdb mdb-check-aof
```

它们分别映射到同名 `valkey-*` 工具，不提供裸 `mdb` 命令。

## 国密客户端示例

在镜像内：

```sh
OPENSSL_CONF=/usr/local/etc/mdb/openssl-gm.cnf \
  mdb-cli --tls \
  --cacert /run/mdb/tls/ca.crt \
  --cert /run/mdb/tls/client.crt \
  --key /run/mdb/tls/client.key \
  --tls-ciphersuites TLS_SM4_GCM_SM3 \
  -h <host> -p 6379 PING
```

外部客户端必须自己支持 RFC 8998，或显式使用 Tongsuo/OpenSSL 兼容工具；普通
OpenSSL 客户端无法与 SM2 证书的国密监听器握手。

## 构建

需要 Linux、Docker Buildx、网络和约 2 GB 临时空间：

```sh
make verify
make fetch
make build
make smoke
```

`make full-matrix` 还需要可用的 Docker 网络和足够的本地资源，会启动主从、
Sentinel 和六节点 Cluster 测试拓扑。

所有上游版本、commit、源码 SHA256 和 openEuler 基础镜像 digest 都在
[`scripts/baseline.env`](scripts/baseline.env)。最终镜像使用 rpath 私有链接
`/opt/tongsuo/lib`，不依赖系统 OpenSSL。

## 版本与标签

```text
ghcr.io/scott-wong/mdb:9.1.3-mdb.1-openeuler  # 不可移动完整版本
ghcr.io/scott-wong/mdb:9.1.3-openeuler        # 上游线别名
ghcr.io/scott-wong/mdb:latest-openeuler       # 浮动别名
```

任何镜像内容变化都必须 bump `mdb.N`，包括基础镜像 digest、RPM 集合、Tongsuo、
Valkey、默认配置、示例配置和 entrypoint。`README.md`、`CHANGELOG.md`、
`docs/**` 等纯仓库文档不进入镜像，不要求 bump，也不触发镜像构建。

## 验收边界

已覆盖：

- Valkey 9.1.3 核心启动、标准 TLS 1.2/1.3、mTLS、国密 TLS 1.3；
- SM2 证书、SM2 签名、SM2 曲线、SM3 和 SM4-GCM 的真实握手；
- 主从复制、Sentinel 到 Valkey 节点的 TLS、Cluster 和 Cluster bus TLS；
- 非 root 进程、只读 rootfs、`/data` 持久化、工具别名和私有 Tongsuo 链接；
- SBOM、Trivy 报告、Cosign keyless 签名和 digest 固定发布。

不承诺：

- TLCP/NTLS、TLS 1.2 国密套件、FIPS 合规或国密产品认证；
- 与官方 Valkey 镜像在同一端口同时提供标准证书和 SM2 证书；
- Sentinel 客户端控制端口的 TLS；上游 Sentinel 的 `26379` 控制端口保持明文，
  MDB 只验证 Sentinel 到 Valkey 节点的出站 TLS；
- 磁盘加密、KMS、密钥轮换、HSM 或全盘加密；
- “零漏洞”或 Tongsuo 与标准 OpenSSL 的 CVE 等价性。

更完整的决策记录见 [`docs/adr/`](docs/adr/)。
