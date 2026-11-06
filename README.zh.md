# iris-kaggle-importer &nbsp; [![English](https://img.shields.io/badge/README-English-blue)](README.md)

将 [Kaggle](https://www.kaggle.com/datasets) 数据集导入 InterSystems IRIS，变为真正的 SQL 表——**只需一条 SQL 语句**。

```sql
SELECT IrisKaggle.API_ImportSimple('uciml/iris');
```

```text
{"status":"ok","dataset":"uciml/iris","file":"Iris.csv","table":"KG_uciml_iris_Iris",
 "rowsImported":150,"columns":6,"failedRows":0,"bytesDownloaded":4258,"elapsedSeconds":3}
```

导入器通过 Kaggle API 认证，下载数据集压缩包，解压，选取 CSV 文件，推断列类型，创建表并流式写入。全部运行在 IRIS 内部：**无需 pip 包，无需 sidecar 服务**。

---

## 前提条件

- **Docker**（容器化运行）或已有的 InterSystems IRIS 2023.1+ 实例。
- **[Kaggle API 凭证](https://www.kaggle.com/settings)** —— 从 kaggle.com 下载数据集必须提供。没有凭证时仍可导入本地 CSV 文件（`ImportFile`），演示脚本会自动使用内置示例 CSV。

  在 kaggle.com 获取凭证：**Settings → API → Create New Token**，下载 `kaggle.json` 文件（含 `username` 和 `key`）。

## 为什么

Kaggle 是公开表格数据最集中的地方，但把数据集搬进 IRIS 往往需要写一次性下载脚本、手动解压、手写 DDL。本项目将其压缩为一次调用，可从 SQL、ObjectScript 或终端使用，并保留审计记录。

## 快速开始

### 1. 获取 Kaggle API 密钥

在 kaggle.com：**头像 → Settings → API → Create New Token**。下载 `kaggle.json`：

```json
{"username":"your_user","key":"0123456789abcdef0123456789abcdef"}
```

### 2. 启动 IRIS

```bash
git clone https://github.com/foxchengyu/iris-kaggle-importer.git
cd iris-kaggle-importer
KAGGLE_USERNAME=your_user KAGGLE_KEY=0123456789abcdef docker compose up -d --build
```

IRIS 启动在 <http://localhost:52773/csp/sys/UtilHome.csp>（`_SYSTEM` / `SYS`）。

运行演示导入：

```bash
docker compose exec iris iris session IRIS < docker/demo.script
```

或打开 **管理门户 → 系统资源管理器 → SQL**，执行：

```sql
SELECT IrisKaggle.API_ImportSimple('uciml/iris')
```

### 现有 IRIS 实例

1. 通过 **管理门户 → 系统资源管理器 → 类 → 导入**，或终端命令：

   ```objectscript
   Do $SYSTEM.OBJ.LoadDir("<repo>/src/cls", "ck")
   ```

2. 存储凭据一次（或使用环境变量）：

   ```objectscript
   Do ##class(IrisKaggle.CLI).Setup("your_user", "0123456789abcdef")
   ```

## 用法

### 从 SQL

```sql
-- 单参数：下载并导入最大的 CSV
SELECT IrisKaggle.API_ImportSimple('uciml/iris');

-- 完整控制：数据集、目标表、文件名、最大行数、数据集版本
SELECT IrisKaggle.API_ImportDataset('uciml/iris', 'SQLUser.Iris', 'Iris.csv', 1000, 0);

-- 导入已在 IRIS 服务器上的 CSV 文件
SELECT IrisKaggle.API_ImportFile('/data/train.csv', 'SQLUser.Train', 0);

-- 不使用环境变量，直接传凭据
SELECT IrisKaggle.API_SetCredentials('your_user', '0123456789abcdef');

-- 查看已导入记录
SELECT IrisKaggle.API_ListImports();
```

### 从 ObjectScript

```objectscript
Do ##class(IrisKaggle.CLI).Setup("your_user", "0123456789abcdef")
Do ##class(IrisKaggle.CLI).Demo()                             ; uciml/iris
Do ##class(IrisKaggle.CLI).Import("uciml/iris")               ; 全部行
Do ##class(IrisKaggle.CLI).Import("uciml/iris", "SQLUser.Iris", "Iris.csv", 500)
Do ##class(IrisKaggle.CLI).ImportFile("/data/train.csv", "SQLUser.Train")
```

### 查询结果

```sql
SELECT TOP 5 * FROM KG_uciml_iris_Iris
```

因为是普通表，索引、连表、BI 工具、嵌入式 Python 和互操作产品等全部可用。

## 选项

| 参数 | 含义 | 默认值 |
| --- | --- | --- |
| `dataset` | 数据集 slug，格式 `所有者/名称` | 必填 |
| `targetTable` | 目标表，可选 `模式.表名` | 从数据集名 + 文件名派生 |
| `fileName` | 压缩包内 CSV 文件名（精确或后缀匹配） | 最大的 CSV |
| `maxRows` | 行数上限，`0` = 全部 | `0` |
| `version` | 数据集版本号，`0` = 最新 | `0` |

默认表名为 `KG_<所有者>_<名称>_<文件主名>`，已清洗为合法 IRIS 标识符。

### 代理与受限网络

出站 HTTPS 必须能访问 `www.kaggle.com` 和存储压缩包的主机。在内网代理环境下，设置 `KAGGLE_PROXY`；客户端会通过 HTTP `CONNECT` 隧道建立 TLS 连接：

```bash
KAGGLE_PROXY=http://proxy.example.com:8080 docker compose up -d --build
```

在 ObjectScript 中改为设置 `IrisKaggle.Client` 的 `Proxy` 属性。

### TLS 配置

IRIS 每次 HTTPS 调用都需要客户端 SSL 配置。部分镜像没有预置，所有请求会报 `#6159` 错误。导入器会在首次使用时检查并自动创建 `IrisKaggleTLS`。如需使用其他配置，设置 `IrisKaggle.Client` 的 `SSLConfiguration` 属性即可。同名配置已存在时不会重复创建。

## 工作原理

```
SQL / ObjectScript
        │
        ▼
 IrisKaggle.Importer ──► IrisKaggle.Client ──► https://www.kaggle.com/api/v1
        │                     基本认证, /datasets/download/{所有者}/{名称}
        ▼
 IrisKaggle.Archive ──► 用 Python 标准库 zipfile 解压
        │
        ▼
 IrisKaggle.Csv ──► 流式 RFC 4180 阅读器（支持引号、转义引号、字段内换行）
        │
        ▼
 IrisKaggle.Schema ──► int / float / bool / date / string 推断
        │
        ▼
 IrisKaggle.Writer ──► CREATE TABLE + 批量 INSERT（250 行 / 400 KB）
        │
        ▼
 IrisKaggle.Manifest ──► 审计记录（数据集、文件、表、行数、状态、耗时）
```

设计要点：

* **流式 CSV。** 文件从不被全部加载为单个字符串。状态机读取逻辑记录（跟随引号内的换行），并批量写入多行 `INSERT`，大文件内存占用保持平稳。
* **可靠写入。** 若某批失败，会逐行重试；失败项收集上报而不是中断加载。
* **类型推断。** 对列进行采样（最长 200 行），分类为 `BIGINT`、`DOUBLE`、`BOOLEAN`、`DATE` 或带长度的 `VARCHAR`/`LONGVARCHAR`。与推断类型不匹配的值存储为 `NULL`。
* **仅使用 Python 标准库** 进行解压，标准的 `iris-community` 镜像无需安装任何额外包即可运行。
* **审计追踪。** 每次导入记录在 `IrisKaggle.Manifest` 中。

### 类型推断

| 采样值 | IRIS 类型 |
| --- | --- |
| `0` / `1` / `true` / `false` | `%Library.Boolean`（0/1） |
| 整数 | `BIGINT` |
| 小数 / 科学计数 | `DOUBLE` |
| `YYYY-MM-DD` | `DATE` |
| 其他 | `VARCHAR(255)` 或 `LONGVARCHAR`（按采样长度决定） |

## 局限性

* 受**比赛规则**保护的数据集需先在 kaggle.com 上接受规则。若 API 拒绝下载，可手动下载文件后使用 `ImportFile`。
* 压缩包解压到进程独立的临时目录。不会自动删除，以便排查失败的导入。
* 仅导入 CSV 文件。仅含 Parquet 或 JSON 的压缩包需提前转换。
* 超大压缩包受限于 Kaggle API 和空闲磁盘空间。

## 开发

```
src/cls/IrisKaggle/Utils.cls        标识符与字面量辅助函数
src/cls/IrisKaggle/Credentials.cls  凭据解析
src/cls/IrisKaggle/Client.cls       Kaggle REST 客户端
src/cls/IrisKaggle/TLS.cls          出站 TLS 配置辅助类
src/cls/IrisKaggle/Archive.cls      zip 解压（嵌入式 Python 标准库）
src/cls/IrisKaggle/Csv.cls          流式 CSV 阅读器
src/cls/IrisKaggle/Schema.cls       类型推断
src/cls/IrisKaggle/Writer.cls       批量 INSERT 写入
src/cls/IrisKaggle/Importer.cls     编排控制器
src/cls/IrisKaggle/Manifest.cls     审计追踪
src/cls/IrisKaggle/API.cls          SQL 入口
src/cls/IrisKaggle/CLI.cls          终端辅助
```

修改源码后重建：

```bash
docker compose up -d --build
```

## 许可证

MIT — 详见 [LICENSE](LICENSE)。