# 个人技术博客（zhengw-tech.com）

Hexo 静态博客，主题 Butterfly。中文技术文章为主，当前 **112 篇文章 / 76 个标签 / 0 个分类**。

- 线上地址：https://zhengw-tech.com
- 源码仓库：https://github.com/zavier/blogs-hexo
- 服务器：腾讯云 CentOS 7，nginx 1.20.1（`root@58.87.89.167`）

## 快速开始

```bash
npm ci                                    # 首次安装依赖（Node 24 / npm 11 已验证）

npx hexo new post "文章标题"                # 新建文章 → source/_posts/文章标题.md

npx hexo clean && npx hexo g && npx hexo s --static   # 本地预览 http://localhost:4000

npm run deploy                            # 构建 + 自检 + 同步到服务器 + 线上抽查
```

## 写作约定

- 文章放在 `source/_posts/`，**文件名会成为 URL 的一部分**（`permalink: :year/:month/:day/:title/`）
- front matter 只需要 `title` / `date` / `tags`，现有 112 篇都只有这三项（不加分类，见下文）
- 图片放到 `source/images/`，正文用绝对路径引用：`![说明](/images/xxx.png)`。图片与主题无关，换主题不用改
- 摘要分隔线用 `<!-- more -->`（首页列表显示到这里为止）
- `source/_drafts/` 是草稿目录，`render_drafts: false`，草稿不会被发布
- 每页 20 篇（`per_page`），分页在 `/page/2/` 这类路径

## 本地预览：一定要加 `--static`

```bash
npx hexo clean && npx hexo g && npx hexo s --static
```

`hexo s`（不带 `--static`）会自己再跑一次生成，和 `hexo g` 抢着写 `public/`，实测会把上百个 html 写成 0 字节——**而且浏览器里看不出来**，因为 hexo-server 走内存路由。带 `--static` 就没有这个问题。

浏览器还要注意：CSS/JS 的 URL 带 `?v=5.7.0` 版本号，改样式后需要硬刷新（Cmd+Shift+R）。

## 发布

```bash
npm run deploy
```

它执行 `bin/deploy.sh`，四步，任一步失败就**非零退出且不会动线上**：

1. `hexo clean` + `hexo g`
2. **产物自检**：`index.html` 存在、`404.html` 存在、html 数 ≥ 250、0 字节 html 数为 0（拦的正是上面那个坑）
3. `rsync --delete --delete-excluded` 同步到服务器 `/opt/app/public`，同时清掉历史遗留的 macOS `._*` 垃圾文件
4. **线上抽查**：首页/标签/归档/favicon/atom.xml 必须 200，不存在的地址必须返回主题化 404

两个注意点：

- **发布的是工作区内容，不是 Git 提交内容**。没提交的文章改动会一起上线（脚本会打印一行警告）
- 同步带 `--delete`，服务器目录会被对齐成 `public/` 的样子。手工往服务器上放东西，下次发布会消失

## 部署拓扑

| 项 | 值 |
| --- | --- |
| 网站根目录 | `/opt/app/public`（nginx 的 `root`） |
| nginx 配置 | `/etc/nginx/nginx.conf` 内联的 server 块（不在 `conf.d`），`nginx -t` 校验后用 `nginx -s reload` |
| 证书 | certbot 管理，`/etc/crontab` 里每天 0/12 点自动续期（证书 2026-12-26 到期） |
| 备份 | `/opt/backup/`：`public-<时间戳>.tar.gz`、`nginx.conf.<时间戳>` |
| 同域名的其他服务 | nginx 把 `/expense/`→:8081、`/table/`→:8080、`/api/table/`→:8080 反代出去了，改 nginx 时不要碰 |
| 另一个站点 | `diary.zhengw-tech.com` → `/var/www/wodiary`（独立配置，无关） |
| 已开的 nginx 优化 | gzip（CSS 209KB → 26KB）、HTTP/2、`/css/ /js/ /images/ /img/` 30 天缓存 |

回滚：`ssh root@58.87.89.167 'cd /opt/app && tar xzf /opt/backup/public-<时间戳>.tar.gz'`

## 目录结构

```text
_config.yml              # Hexo 主配置（theme: butterfly、permalink、feed/sitemap 等）
_config.butterfly.yml    # 主题配置：只写要覆盖主题默认值的项
bin/deploy.sh            # 发布脚本（npm run deploy）
source/_posts/           # 文章（112 篇）
source/_drafts/          # 草稿（6 篇，不发布）
source/images/           # 图片（正文引用 + favicon + 404 插图）
source/tags/             # /tags/ 页面
source/categories/       # /categories/ 页面（站点没有分类，入口已隐藏，页面保留备用）
public/  db.json         # 构建产物与缓存，都在 .gitignore 里
```

主题是 **npm 依赖**（`hexo-theme-butterfly@5.7.0`），源码不在仓库里。自定义全部写在 `_config.butterfly.yml`——它只覆盖需要改的键，其余走主题自带默认值，所以升级主题不会和本地改动冲突。**不要直接改 `node_modules` 里的主题文件**，下次安装会被覆盖。

## 故障排除

| 症状 | 原因 | 处理 |
| --- | --- | --- |
| 构建报 `Script load failed: .../xxx.sh SyntaxError` | Hexo 会把站点根目录 `scripts/` 下**所有**文件当插件脚本加载 | 脚本别放 `scripts/`（这就是 `bin/deploy.sh` 的由来） |
| 上百个 html 变成 0 字节 | `hexo s` 与 `hexo g` 并发写 `public/` | 预览加 `--static`；`npm run deploy` 里有自检会拦住 |
| 改了样式页面没变 | CSS URL 带 `?v=` 版本号 | 硬刷新；线上还受 30 天缓存影响 |
| Mermaid 图显示成代码块 | 主题自带的 mermaid 渲染只认 `.mermaid-wrap`，而插件输出的是 `<pre class="mermaid">` | 配置里已关主题渲染 + 用 `inject.bottom` 引 mermaid.js，别把 `_config.butterfly.yml` 里那段删了 |
| 暗色模式下 Mermaid 连线看不见 | 图用亮色主题一次性渲染，不跟随日夜切换 | 已用 `inject.head` 给暗色下的 `pre.mermaid` 加白底 |
| 陌生地址返回 nginx 白页 | nginx 配了 `error_page 404 /404.html`，文件必须存在 | 保持 `error_404.enable: true`（`npm run deploy` 会自检这个文件） |
| 服务器上出现一堆 `._xxx` 文件 | macOS 元数据 | rsync 带 `--delete-excluded` 会自动清 |
| 发布脚本自检失败：`少于 250 个 html` | 构建残缺 | 先看 `hexo g` 的完整输出，别绕过自检 |
| 站点 404 / HTTPS 报错 | 证书或 nginx | `certbot renew --dry-run`、`nginx -t`，备份在 `/opt/backup/` |

## 已知待办

- 依赖漏洞：`npm audit` 48 条（5 critical，都来自 Hexo 6.3 的老依赖树，只在本地构建时执行，线上是纯静态文件）。升级路线：Hexo 6.3 → 8.1.2 + `hexo-generator-index` 4 + `hexo-renderer-stylus` 3。需单独一次带完整回归
- 可删的僵尸依赖（最后发布都在 2022）：`hexo-filter-mermaid-diagrams`、`markdown-it-katex`、`hexo-generator-baidu-sitemap`、`hexo-theme-landscape`
- 服务器系统 CentOS 7 已 EOL（2024-06-30），不再有新 CVE 修补；只跑 nginx + 静态文件，暴露面小
- 未启用：站内搜索、评论。归档/标签/分类页仍有顶部大图（首页已关）
