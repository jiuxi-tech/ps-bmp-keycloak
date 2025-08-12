# ps-bmp-keycloak

党校业务中台后端 keycloak 服务

## 项目简介

本项目是基于 Keycloak 的身份认证和访问管理解决方案，为党校业务中台提供统一的身份认证服务。Keycloak 是一个开源的身份和访问管理解决方案，支持现代应用程序和服务。

## 主要功能

- 单点登录 (SSO)
- 身份代理和社交登录
- 用户联合
- 客户端适配器
- 管理控制台
- 账户管理控制台
- 标准协议支持 (OpenID Connect, OAuth 2.0, SAML 2.0)
- 授权服务

## 环境要求

- **JDK 17** 或 **JDK 21** (不支持更新版本)
- Git
- Maven (或使用项目内置的 Maven wrapper)

## 构建和部署

### 从源码构建

1. 克隆项目：
   ```bash
   git clone <repository-url>
   cd ps-bmp-keycloak
   ```

2. 构建项目：
   ```bash
   ./mvnw clean install
   ```

3. 构建包含适配器的完整分发版：
   ```bash
   ./mvnw clean install -Pdistribution
   ```

4. 仅构建服务器：
   ```bash
   ./mvnw -pl quarkus/deployment,quarkus/dist -am -DskipTests clean install
   ```

### 启动服务

构建完成后，启动 Keycloak 开发模式：

```bash
java -jar quarkus/server/target/lib/quarkus-run.jar start-dev
```

停止服务器请按 `Ctrl + C`。

## 项目结构

- `adapters/` - 客户端适配器
- `authz/` - 授权服务
- `core/` - 核心模块
- `crypto/` - 加密相关
- `docs/` - 项目文档
- `federation/` - 用户联合
- `js/` - JavaScript 相关组件
- `model/` - 数据模型
- `quarkus/` - Quarkus 运行时
- `services/` - 核心服务
- `themes/` - 主题模板
- `tests/` - 测试用例

## 开发指南

### 代码风格

项目遵循 WildFly 的代码风格规范。详细的格式化规则可以从 [Wildfly ide-configs](https://github.com/wildfly/wildfly-core/tree/main/ide-configs) 获取。

### IDE 构建

项目的某些部分依赖于 Maven 插件生成的代码。在 IDE 中构建时可能会跳过这些步骤导致编译错误。解决方法：

1. 首先使用 Maven 构建项目
2. 之后可以在 IDE 中构建，它会使用之前生成的类
3. 避免在 IDE 中重新构建整个项目

## 相关文档

- [构建和开发指南](docs/building.md)
- [贡献指南](CONTRIBUTING.md)
- [项目治理](GOVERNANCE.md)
- [维护者列表](MAINTAINERS.md)

## 许可证

本项目基于 [Apache License 2.0](LICENSE) 许可证开源。

## 注意事项

- `org.keycloak.testsuite.*` 包下的类不适用于生产环境
- 如果在代理环境中构建失败，可以添加 `-DskipProtoLock=true` 参数跳过协议兼容性检查
