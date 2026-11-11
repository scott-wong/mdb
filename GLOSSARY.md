# Glossary

- **MDB**：本仓库的 Valkey/openEuler 容器发行版，不是存储引擎名称。
- **Valkey core**：不包含模块、代理或控制面的上游 Valkey 服务端。
- **Tongsuo**：本镜像私有链接的密码库，基线为 8.5.0 / OpenSSL 3.5.4。
- **RFC 8998**：TLS 1.3 国密单证书套件，使用 SM2/SM3/SM4。
- **TLCP / NTLS**：国密双证书传输协议；MDB 明确不实现。
- **standard profile**：TLS 1.2 + TLS 1.3 的标准证书模式。
- **gm profile**：TLS 1.3、SM2 证书、SM2 曲线和 SM4-GCM 的国密模式。
- **MDB_TLS_MODE**：`off`、`standard`、`gm` 三种运行模式。
- **mTLS**：客户端必须提供有效证书；两种 TLS profile 默认都要求。
- **candidate**：通过 CI 构建和验收、尚未获得正式 tag 的镜像。
- **mdb.N**：同一上游 Valkey 版本的发行修订号。
