# 共享排行榜服务

同一个 Python 进程提供游戏页面和成绩接口，只用 Python 标准库，不需要额外安装包。开发时可以用静态服务器看游戏；需要测试全服榜单时，必须启动这个服务。

## 启动和部署

在项目根目录运行：

```powershell
$env:WEB_ROOT="web"
$env:SCORE_DATA_DIR="E:/xiabandemo/score-test-data"
$env:PORT="8031"
python server.py
```

Docker 部署的目录应包含构建后的 `index.html`、`assets/`、`js/`、`css/`、`vendor/`，以及 `server.py`、`Dockerfile`。Docker 默认端口 7860，数据库为 `/mnt/workspace/scores.sqlite3`。平台必须为该目录提供持久存储，才能保证容器替换后仍保留数据；单纯写在容器文件系统不能代替持久卷和备份。数据库、测试数据与本地环境文件不进入部署代码仓库。

页面由服务端注入开关，自动启用在线排行榜。浏览器使用异步请求，游戏循环只读取缓存，不会为查榜或提交成绩同步等待网络。请求超时为 10 秒；失败会显示错误，玩家可以重试，同一局的 `run_id` 不变。

## 接口

- `GET /api/health`：运行状态。
- `GET /api/config`：当前版本、平衡规则和成绩来源。
- `GET /api/leaderboard?mode=endless`：无尽榜。`mode=campaign` 查看普通关卡榜。
- `POST /api/leaderboard`：提交 JSON，字段见下例。

```json
{
  "run_id": "30c38db1-6547-4a92-a6de-43d2505026eb",
  "name": "今天准点下班123",
  "mode": "endless",
  "hero": "intern",
  "version": "office-expansion-v3",
  "ruleset": "balance-2026-11-07-v2",
  "balanceVersion": "balance-2026-11-07-v2",
  "wave": 6,
  "boss": 2,
  "level": 4,
  "kills": 50,
  "time": 125,
  "score": 10135
}
```

名字保留中文、英文、数字、表情和标点，去首尾空白、拒绝空名与控制字符，不使用旧版 12 字限制。请求体上限 64 KiB。每个连接来源地址每分钟最多提交 60 次、查榜 180 次；代理环境下同一出口可能共用额度，这只是基础限流，不是用户身份识别。

服务端按整秒重新计算分数：波次（普通关卡为已清理房间数）×1000 + 击败 Boss 数×1500 + 击杀数×12 + 等级×40 + 用时秒数（最多3600）×3。兼容旧客户端的小数秒差异0—2分，但保存重新计算后的整数结果。

榜单按分数降序、进度降序、用时升序、提交时间和记录编号升序排列。模式、版本、平衡规则隔离；旧本地成绩不会上传或混进当前在线榜单。同局重复请求只保留一条；修改已提交局的内容返回冲突。

**这些是客户端上报成绩。** 服务端检查输入范围、计分公式和重复请求，不重新模拟整场战斗，因此无法证明某个击杀数真实发生，也不具备完整防作弊能力。名字是显示昵称，不是已认证账号。

## 验证

```powershell
python -m unittest discover -s tests -p test_score_server.py
node web/tools/test-score-bridge.mjs
node web/tools/run-lua-tests.mjs Leaderboard
```

第一组启动真实 HTTP 服务，检查 Unicode、请求限制、并发幂等、规则隔离和 SQLite 重启保留。第二组用实际浏览器桥的相同代码连接真实服务，验证异步状态、错误、重试和模式切换。第三组为 Lua 数据层回归测试。
