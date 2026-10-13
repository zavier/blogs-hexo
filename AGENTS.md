# AGENTS.md

Hexo 静态博客：`source/` 是内容与资源，主题走 npm 依赖，线上由 nginx 提供静态文件。

**动构建、预览、发布或主题配置前，先读 [README.md](README.md)**——部署拓扑、写作约定、以及「故障排除」表（症状 → 原因 → 处理）都在那里。

## 约定

- 主题自定义写进 `_config.butterfly.yml`，只列要覆盖主题默认值的键。主题本体是 `node_modules/hexo-theme-butterfly` 里的 npm 包，改那里的文件会在下次安装时被覆盖。
- 运行脚本放 `bin/`。Hexo 会把站点根目录 `scripts/` 下的**所有**文件当插件加载，`.sh` 会报 `Script load failed: ... SyntaxError`。
- shell 里 `$VAR` 后紧跟中文全角字符时写成 `${VAR}`：macOS 自带 bash 3.2 会把全角字符当成变量名的一部分，`set -u` 下报 unbound variable。
- 提交信息沿用现有风格：`docs: ...` / `feat(butterfly): ...` / `fix(butterfly): ...`，正文说明改了什么、为什么。
- `public/`、`db.json`、`node_modules/` 是生成物或缓存，不提交。

## 验证

改完配置或内容后，跑构建并确认三件事：

```bash
npx hexo clean && npx hexo g
```

1. 输出里 0 个 `ERROR`
2. 生成约 275 个 html，且没有 0 字节的 html
3. `public/404.html` 存在（nginx 的 `error_page 404` 依赖它）

看效果用 `npx hexo s --static`（不带 `--static` 的 `hexo s` 会和 `hexo g` 抢写 `public/`，把上百个 html 变成 0 字节，浏览器里还看不出来）。

## 发布

`npm run deploy` 只在用户明确要求上线时执行：它构建、自检、`rsync --delete` 到生产服务器并抽查线上状态。**发布的是工作区内容**，未提交的文章改动会一起上线。
