# Security Policy

## Supported versions

MDB `9.1.x-mdb.N` 是当前支持线。已被新 `mdb.N` 取代的镜像不再承诺安全更新；
发布镜像的完整版本 tag 不移动，安全重建通过新的 `mdb.N` 发布。

## Reporting

请通过 GitHub Security Advisory 私下报告漏洞。不要在公开 issue 中提交私钥、
密码、客户端证书、生产地址或可利用细节。

## Scope

本仓库关注：

- Valkey 与 Tongsuo 的构建/链接错误；
- TLS 模式配置导致的明文降级；
- 证书、私钥和 CA 的权限或校验缺陷；
- 容器权限、只读 rootfs、数据目录和工具别名问题；
- 发布供应链、SBOM、签名和 digest 晋级问题。

## Non-goals

- MDB 不宣称 FIPS 合规、商用密码产品认证或“零漏洞”。
- MDB 不实现 TLCP/NTLS；`MDB_TLS_MODE=gm` 只覆盖 RFC 8998 TLS 1.3。
- MDB 不提供磁盘加密、KMS、HSM 或多密钥热轮换。
- MDB 不提供 Sentinel 控制端口的 TLS；上游 Sentinel 的 `26379` 控制端口保持明文，
  MDB 验证的是 Sentinel 到 Valkey 节点的出站 TLS。
- MDB 不对 openEuler RPM 提供 Trivy 未覆盖的等价 CVE 结论；Release 会公开扫描
  缺口和 `dnf updateinfo --security` 证据。

## Build and release controls

- 所有上游源码和工具下载均校验 SHA256。
- 基础镜像按 index digest 固定；RPM 由签名仓库解析并执行安全更新。
- 正式 tag 只从已验证的 candidate digest 晋级，禁止移动已有 tag。
- 使用 GitHub OIDC keyless Cosign 签名，并附加 CycloneDX SBOM attestation。
- 发布资产包含 SBOM、Trivy SARIF/文本、release manifest 和校验和。
