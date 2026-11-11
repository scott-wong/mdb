# 变更日志

本文件记录 MDB 的重要变更，格式参考 Keep a Changelog。只有镜像内容变化需要
bump `mdb.N`；纯文档变更不需要。

## [未发布]

## [9.1.3-mdb.1] - 2026-11-11

### 新增

- 首个 MDB `9.1.3-mdb.1` 版本，面向 openEuler 24.03 LTS SP4。
- 基于 Valkey 9.1.3，私有链接 Tongsuo 8.5.0。
- 标准 TLS 1.2/1.3 profile（默认 mTLS）和 RFC 8998 TLS 1.3 国密 profile。
- `mdb-*` 工具别名，以及 TLS 证书、私钥、CA 的启动预检。
- Candidate CI、完整矩阵冒烟测试、SBOM、Trivy、Cosign 和发布工作流。
- Sentinel 到被监控 Valkey 节点的出站 TLS；上游 Sentinel 明文控制端口列为
  明确非目标。
