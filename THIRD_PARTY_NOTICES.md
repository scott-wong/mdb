# Third-Party Notices

MDB 自有代码使用 Apache License 2.0。

最终镜像包含以下主要第三方组件：

- **Valkey 9.1.3**：BSD-3-Clause。许可证文本见
  [`licenses/valkey-COPYING`](licenses/valkey-COPYING)。
- **Tongsuo 8.5.0**：Apache License 2.0，源码基线对应 OpenSSL 3.5.4。许可证文本见
  [`licenses/tongsuo-LICENSE`](licenses/tongsuo-LICENSE)。
- **tini 0.19.0**：MIT。许可证文本见 [`licenses/tini-LICENSE`](licenses/tini-LICENSE)。
- **openEuler 24.03 LTS SP4 RPM**：由 openEuler 及其上游项目提供，具体包和版本
  记录在镜像的 `/usr/local/share/mdb/rpm-manifest.txt` 及发布 SBOM 中。

构建阶段使用的工具（GitHub Actions、Docker Buildx、Syft、Trivy、Cosign、
crane 等）不进入最终运行时镜像；其版本和校验和记录在
[`scripts/baseline.env`](scripts/baseline.env) 和发布工作流中。
