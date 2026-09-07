# nanolander

> 帶著整套裝備降落在任何一台機器上。

一支腳本，在 macOS、Ubuntu、Amazon Linux 2 與 Amazon Linux 2023 上安裝同一套現代終端機工具，並自動完成 shell 設定。套件庫有的用套件庫，沒有的抓官方 GitHub Release。

| 項目 | 內容 |
| --- | --- |
| 主程式 | `bin/nanolander` |
| 附加工具 | `bin/iterm-tune`（macOS 的 iTerm2 效能調校） |
| 工具數量 | 44 |
| 安裝來源 | 系統套件管理器優先，缺少時改用官方 GitHub Release |
| 安裝位置 | 套件管理器預設路徑，或 `~/.local/bin` |
| 日誌 | `~/nanolander-YYYYMMDD-HHMMSS.log` |

---

## 目錄

- [支援環境](#支援環境)
- [快速開始](#快速開始)
- [命令列選項](#命令列選項)
- [安裝工具總覽](#安裝工具總覽)
- [腳本內部功能說明](#腳本內部功能說明)
- [Shell 設定變更內容](#shell-設定變更內容)
- [日誌與回傳狀態](#日誌與回傳狀態)
- [注意事項與疑難排解](#注意事項與疑難排解)
- [本次更新內容](#本次更新內容)

---

## 支援環境

### 作業系統

| 作業系統 | 套件管理器 | Shell 設定檔 |
| --- | --- | --- |
| macOS | Homebrew | `~/.zshrc`（另設定 `~/.zprofile`） |
| Ubuntu | APT | `~/.bashrc` |
| Amazon Linux 2／舊版 | YUM | `~/.zshrc` |
| Amazon Linux 2023 | DNF | `~/.zshrc` |

### CPU 架構

| 架構 | 支援程度 |
| --- | --- |
| `x86_64` / `amd64` | 全部工具 |
| `arm64` / `aarch64` | 全部工具 |
| `armv7` | 多數工具（`dive` 無官方 armv7 版本） |
| `armv6` | 僅部分工具，其餘會標示為失敗並可略過 |

---

## 快速開始

```bash
git clone https://github.com/hikohong/nanolander.git
cd nanolander
./bin/nanolander
```

也可以明確使用 Bash 執行：

```bash
bash bin/nanolander
```

想在任何目錄都能直接呼叫，把它連到 PATH 上：

```bash
ln -s "$PWD/bin/nanolander" ~/.local/bin/nanolander
```

安裝完成後啟用設定：

```bash
# Ubuntu
source ~/.bashrc

# macOS／Amazon Linux
source ~/.zshrc
```

或直接登出後重新登入。

---

## 命令列選項

所有選項都可以組合使用，例如：

```bash
./bin/nanolander --set-default-shell --with-aliases --configure-git
```

### `--help` / `-h`

顯示使用說明與範例，不進行任何安裝。

```bash
./bin/nanolander --help
```

### `--list-tools`

列出腳本可安裝的所有工具（指令名稱、工具名稱、用途），方便先確認清單再決定是否要用 `--only` 或 `--skip` 過濾。

```bash
./bin/nanolander --list-tools
```

### `--only a,b,c`

只安裝指定的工具，其餘一律標示為 `SKIPPED`。適合只想補裝少數幾項，或在網路受限的機器上快速安裝必要工具。名稱可以用指令名或工具名，逗號分隔。

```bash
./bin/nanolander --only nvim,tmux,fzf,ripgrep
```

### `--skip a,b,c`

安裝全部工具，但排除指定項目。適合沒有 Docker 的機器（略過 `lazydocker`、`dive`），或不想重複安裝已有工具的情況。

```bash
./bin/nanolander --skip lazydocker,dive
```

### `--set-default-shell`

在 macOS 與 Amazon Linux 上，把目前使用者的登入 shell 改成 zsh。若登入 shell 已經是 zsh 就不會重複變更。Ubuntu 使用 bash 設定，此選項不會生效。

```bash
./bin/nanolander --set-default-shell
```

### `--with-aliases`

在 shell 設定檔中加入一段可選的別名區塊，把常用指令導向新工具。每一行都會先確認工具存在才生效，因此工具沒裝也不會讓 shell 出錯。

| 別名 | 實際執行 |
| --- | --- |
| `ls` | `eza --group-directories-first` |
| `ll` | `eza -lah --group-directories-first --git` |
| `lt` | `eza --tree --level=2` |
| `cat` | `bat --paging=never` |
| `du` | `dust` |
| `df` | `duf` |
| `top` | `btm` |

區塊以 `# >>> nanolander aliases >>>` 與 `# <<< nanolander aliases <<<` 標記，之後想移除只要刪掉這兩行之間的內容即可。不加此選項時，腳本不會覆寫任何既有指令。

### `--configure-git`

把 git-delta 設為全域 Git 分頁器，讓 `git diff`、`git log`、`git show` 都有語法高亮與行號。實際寫入的設定：

```gitconfig
core.pager = delta
interactive.diffFilter = delta --color-only
delta.navigate = true
delta.line-numbers = true
merge.conflictStyle = zdiff3
```

若 `git` 或 `delta` 任一不存在，腳本會顯示警告並略過，不會寫入設定。

---

## 安裝工具總覽

以下每項都附上用途說明與一行上手指令。

### 系統與資源監控

| 工具 | 指令 | 用途與範例 |
| --- | --- | --- |
| **btop** | `btop` | 圖形化資源監控，CPU、記憶體、磁碟、網路都有即時曲線；滑鼠可直接點選程序。<br>`btop` |
| **htop** | `htop` | 經典互動式程序檢視器，適合快速排序找出吃資源的程序並送出訊號。<br>`htop -u $(whoami)` |
| **bottom** | `btm` | 另一套監控介面，欄位可設定、程序表可搜尋，在低階或遠端機器上比 btop 輕量。<br>`btm --basic` |
| **fastfetch** | `fastfetch` | 快速列出系統資訊（OS、核心、CPU、記憶體），登入遠端主機時確認環境很實用。<br>`fastfetch` |

### Git 與開發流程

| 工具 | 指令 | 用途與範例 |
| --- | --- | --- |
| **lazygit** | `lazygit` | Git 的終端機圖形介面，可逐段暫存、互動式 rebase、瀏覽歷史，不必背指令。<br>`lazygit` |
| **tig** | `tig` | ncurses 介面的 Git 瀏覽器，看 log、blame 與逐行變更比純 CLI 直覺。<br>`tig blame src/main.c` |
| **git-delta** | `delta` | Git diff 專用分頁器，提供語法高亮、行號與並排比較。<br>`git diff \| delta`（或加 `--configure-git` 全域啟用） |
| **difftastic** | `difft` | 結構化 diff，比較語法樹而非文字行，重排與縮排變動不會被誤判。<br>`difft old.py new.py` |
| **GitHub CLI** | `gh` | 在終端機操作 GitHub：PR、Issue、Release、Actions。<br>`gh pr create --fill` |
| **Git** | `git` | 版本控制本體，四種平台都會確認安裝並驗證版本。<br>`git status -sb` |

### 程式碼導覽與品質

| 工具 | 指令 | 用途與範例 |
| --- | --- | --- |
| **universal-ctags** | `ctags` | 產生 tag 索引，讓 Vim／Neovim 直接跳到函式與變數定義。<br>`ctags -R --exclude=.git .` |
| **cscope** | `cscope` | C／C++ 交叉參照瀏覽器，查詢符號、呼叫者與被呼叫者。<br>`cscope -Rbq` |
| **ShellCheck** | `shellcheck` | Shell 腳本靜態檢查，找出引號、可攜性與常見寫法問題。<br>`shellcheck bin/nanolander` |
| **shfmt** | `shfmt` | Shell 腳本格式化工具，統一 sh／bash 縮排與寫法。<br>`shfmt -i 2 -w script.sh` |

### 專案工作流程

| 工具 | 指令 | 用途與範例 |
| --- | --- | --- |
| **just** | `just` | 專案任務執行器，recipe 寫法比 Makefile 單純。<br>`just --list` |
| **entr** | `entr` | 監看檔案變動就重跑指令，寫測試迴圈很好用。<br>`fd -e py \| entr -c pytest` |
| **direnv** | `direnv` | 進入目錄自動載入環境變數，離開自動卸載，安裝後自動啟用。<br>`direnv allow` |

### 容器

| 工具 | 指令 | 用途與範例 |
| --- | --- | --- |
| **lazydocker** | `lazydocker` | Docker 的終端機圖形介面，檢視容器、映像檔、Volume 與即時日誌。<br>`lazydocker` |
| **dive** | `dive` | 逐層拆解 Docker 映像檔，找出多餘檔案與可精簡的空間。<br>`dive nginx:latest` |

### 終端機環境

| 工具 | 指令 | 用途與範例 |
| --- | --- | --- |
| **Neovim** | `nvim` | 現代化 Vim 分支，支援 Lua 設定與 LSP，作為預設終端編輯器。<br>`nvim file.py` |
| **tmux** | `tmux` | 終端多工器，可保留 session、分割視窗；SSH 斷線後工作不會中斷。<br>`tmux new -s dev` |
| **Starship** | `starship` | 跨 shell 的快速提示字元，顯示 Git 狀態、語言版本與執行時間。<br>安裝後自動寫入 shell 設定 |
| **zoxide** | `zoxide` | 記憶造訪頻率的 `cd` 進化版，輸入片段就能跳到常用目錄。<br>`z proj`（`z` 由 shell 整合提供） |

### 檔案瀏覽與搜尋

| 工具 | 指令 | 用途與範例 |
| --- | --- | --- |
| **eza** | `eza` | `ls` 的現代替代品，支援顏色、圖示、樹狀檢視與 Git 狀態。<br>`eza -lah --git` |
| **bat** | `bat` | 具語法高亮與行號的 `cat`，也可當 `less` 的替代閱讀器。<br>`bat script.sh` |
| **fd** | `fd` | 快速且好記的 `find` 替代品，預設忽略 `.gitignore` 內容。<br>`fd --extension py` |
| **ripgrep** | `rg` | 極快的遞迴文字搜尋，適合在大型專案中找字串。<br>`rg "TODO" --type py` |
| **sd** | `sd` | 直覺的文字取代工具，語法比 `sed -i` 單純。<br>`sd 'old_name' 'new_name' src/*.py` |
| **fzf** | `fzf` | 模糊搜尋器，可過濾任何清單；已設定 `Ctrl-R` 搜尋歷史、`Ctrl-T` 選檔案。<br>`vim $(fzf)` |
| **tree** | `tree` | 以縮排樹狀顯示目錄結構。<br>`tree -L 2` |

### 磁碟與空間

| 工具 | 指令 | 用途與範例 |
| --- | --- | --- |
| **dust** | `dust` | 視覺化的 `du`，直接指出佔用空間最多的目錄。<br>`dust -d 2` |
| **duf** | `duf` | 易讀的 `df`，以表格與使用率長條顯示已掛載檔案系統。<br>`duf` |
| **ncdu** | `ncdu` | 互動式磁碟用量瀏覽器，可直接在介面中刪除大檔。<br>`ncdu /var` |

### 資料處理與文件

| 工具 | 指令 | 用途與範例 |
| --- | --- | --- |
| **jq** | `jq` | JSON 查詢與轉換的標準工具。<br>`curl -s api/url \| jq '.items[].name'` |
| **yq** | `yq` | jq 風格的 YAML／JSON／TOML／XML 處理器，適合改 K8s 或 CI 設定檔。<br>`yq '.services.web.image' docker-compose.yml` |
| **glow** | `glow` | 在終端機漂亮地呈現 Markdown 文件。<br>`glow README.md` |
| **tldr** | `tldr` | 社群維護的精簡指令範例，比 man page 更快找到用法。<br>`tldr tar` |

### 網路與量測

| 工具 | 指令 | 用途與範例 |
| --- | --- | --- |
| **xh** | `xh` | 快速的 HTTP 用戶端，語法接近 HTTPie，適合手動打 API。<br>`xh GET httpbin.org/get name==value` |
| **gping** | `gping` | 附即時折線圖的 `ping`，容易看出延遲抖動。<br>`gping 8.8.8.8 google.com` |
| **hyperfine** | `hyperfine` | 指令效能量測工具，含暖機與統計數據。<br>`hyperfine 'rg TODO' 'grep -r TODO .'` |
| **wget** | `wget` | 非互動式下載工具，支援續傳與整站抓取。<br>`wget -c https://example.com/file.iso` |

### 基本系統工具

| 工具 | 指令 | 用途與範例 |
| --- | --- | --- |
| **watch** | `watch` | 固定間隔重複執行指令並觀察輸出變化。<br>`watch -n 2 'kubectl get pods'` |
| **rsync** | `rsync` | 可靠的增量檔案同步，本機或透過 SSH 都適用。<br>`rsync -avz ./src/ user@host:/dst/` |
| **unzip** | `unzip` | 解開 `.zip` 壓縮檔。<br>`unzip archive.zip -d target/` |

> macOS 與多數 Linux 發行版已內建 `rsync`、`unzip`、`watch`，此時摘要會顯示 `existing`，腳本不會重複安裝。

---

## 腳本內部功能說明

這一節說明腳本各個函式的職責，方便日後維護或擴充。

### 環境偵測

啟動時以 `uname -s` 與 `/etc/os-release` 判斷作業系統，決定套件管理器（brew／apt-get／dnf／yum）與 shell 設定目標；同時把 `uname -m` 正規化成 `x86_64`、`arm64`、`armv7`、`armv6`，作為之後挑選 GitHub Release 檔案的依據。遇到不支援的系統會直接結束並回傳 `1`。

### `wants_tool`

`--only` 與 `--skip` 的過濾判斷。比對時會忽略大小寫與空白，指令名或工具名皆可命中；被過濾掉的工具在摘要中標為 `SKIPPED`，不會被視為失敗。

### `print_tool_catalog`

輸出 `--list-tools` 的內容。工具清單集中在腳本開頭的 `TOOL_CATALOG` 變數，新增工具時同步更新該處即可。

### `setup_homebrew`

僅 macOS 使用。若找不到 `brew`，會下載官方安裝程式並以非互動模式執行，接著載入 `/opt/homebrew` 或 `/usr/local` 的 `brew shellenv`。安裝失敗時腳本會中止，因為 macOS 後續步驟都依賴 Homebrew。

### `package_available` / `package_installed` / `install_package`

分別對應「套件庫是否有這個套件」、「本機是否已安裝」、「執行安裝」。三者都依 `PKG_MANAGER` 切換成 `apt-cache`／`dpkg-query`／`rpm`／`brew list` 等對應指令，讓上層邏輯不必關心平台差異。已安裝的套件會直接跳過。

### `try_package_candidates`

同一工具在不同發行版的套件名稱可能不同（例如 `fd-find` 與 `fd`、`tlrc` 與 `tldr`、`procps-ng` 與 `procps`）。此函式依序嘗試候選名稱，任一成功即返回。

### `github_install`

套件庫沒有的工具走這條路徑：

1. 呼叫 GitHub API 取得該專案最新 Release。
2. 依 CPU 架構對應的關鍵字挑出正確的壓縮檔。
3. 下載後，若 GitHub 有提供 SHA-256 digest 就進行雜湊驗證，不符即中止。
4. 解壓縮並找出執行檔，安裝到 `~/.local/bin`。
5. 挑檔時先比對完整結尾再退回關鍵字包含，避免 `linux_arm` 誤選到 `linux_arm64`。
6. 部分專案在壓縮檔內使用不同檔名（例如 yq 為 `yq_linux_amd64`），此時會以正確名稱取出並改名安裝。
7. 部分專案直接發佈單一執行檔而非壓縮檔（例如 shfmt、direnv），會略過解壓縮步驟直接安裝。
8. Neovim 需要完整 runtime 目錄，會安裝到 `~/.local/opt/nvim-github` 並建立 `~/.local/bin/nvim` 連結。

若有設定 `GITHUB_TOKEN` 環境變數，會自動帶入認證標頭以提高 API 額度。

### `make_compat_links`

Ubuntu／Debian 的套件會把執行檔命名為 `fdfind` 與 `batcat`。此函式在 `~/.local/bin` 建立 `fd` 與 `bat` 連結，讓各平台的使用習慣一致。

### `command_works`

驗證工具是否真的可用：先確認指令存在，再實際執行版本查詢。`tmux` 使用 `-V`、`unzip` 使用 `-v`，其餘使用 `--version`；`entr` 沒有版本參數，因此以存在於 PATH 為準。只有通過驗證才會記為成功。

### `ensure_linux_tool` / `ensure_brew_tool`

每項工具的安裝流程主體。順序為：過濾判斷 → 已安裝就跳過 → 套件管理器安裝 → 需要時改用 GitHub Release → 最終驗證 → 記錄結果與來源。`ensure_brew_tool` 是 macOS 的簡化版本，只走 Homebrew。

### Shell 環境設定

寫入設定檔前一律用完整字串比對，重複執行不會產生重複行。實際寫入的內容見下一節。

### 安裝摘要

結束時輸出表格，逐項顯示工具、狀態（`SUCCESS`／`FAILED`／`SKIPPED`）、來源（`existing`、`package manager`、`GitHub release`、`filter`）與路徑，並統計成功、略過與失敗數量。

---

## Shell 設定變更內容

腳本會依平台寫入 `~/.bashrc` 或 `~/.zshrc`：

| 設定 | 內容 | 條件 |
| --- | --- | --- |
| PATH | `export PATH="$HOME/.local/bin:$PATH"` | 一律寫入 |
| Homebrew | 在 `~/.zprofile` 加入 `eval "$(brew shellenv)"` | 僅 macOS |
| zoxide | `eval "$(zoxide init zsh\|bash)"` | zoxide 安裝成功 |
| Starship | `eval "$(starship init zsh\|bash)"` | Starship 安裝成功 |
| direnv | `eval "$(direnv hook zsh\|bash)"` | direnv 安裝成功 |
| fzf 快捷鍵 | `eval "$(fzf --zsh\|--bash)"`，啟用 `Ctrl-R`、`Ctrl-T` | fzf 安裝成功 |
| fzf 搜尋來源 | `export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'` | fzf 與 fd 皆可用 |
| 別名區塊 | 見 `--with-aliases` 說明 | 指定 `--with-aliases` |

fzf 相關設定都加了 `command -v fzf` 判斷與錯誤抑制，即使日後移除 fzf 或使用舊版本，也不會讓 shell 啟動時噴錯。

---

## 日誌與回傳狀態

### 日誌

每次執行都會產生一份與畫面完全相同的日誌：

```
~/nanolander-YYYYMMDD-HHMMSS.log
```

安裝失敗時，可用工具名稱在日誌中搜尋對應區段，例如 `== Installing yq ==`。

### 回傳狀態

| 代碼 | 意義 |
| --- | --- |
| `0` | 全部工具安裝並驗證成功（含被過濾略過的項目） |
| `1` | 環境準備或必要步驟失敗（例如無法辨識系統、套件庫更新失敗） |
| `2` | 部分工具安裝失敗或不可用 |
| `64` | 參數錯誤 |
| `130` | 使用者中斷執行 |

---

## 注意事項與疑難排解

- **sudo 密碼**：Linux 安裝系統套件時可能要求輸入密碼；腳本開頭會先驗證 sudo 權限。
- **Homebrew**：macOS 若尚未安裝 Homebrew，腳本會下載並執行官方安裝程式。
- **GitHub API 限制**：未登入的 API 呼叫額度較低，一次安裝多項工具時可能出現 `403`。建議先設定 token 再執行：

  ```bash
  export GITHUB_TOKEN=ghp_xxx
  ./bin/nanolander
  ```

- **Docker 相關工具**：`lazydocker` 與 `dive` 需要本機有可用的 Docker 環境才能實際運作；沒有 Docker 的機器可用 `--skip lazydocker,dive`。
- **只有套件庫來源的工具**：`tig`、`cscope`、`entr`、`ctags` 沒有官方跨平台執行檔，只能靠發行版套件庫。Amazon Linux 2023 未內建 EPEL，這幾項可能會標示為 `FAILED`，可用 `--skip tig,cscope,entr` 排除，或自行啟用 EPEL 後再跑一次。
- **Amazon Linux 2**：套件庫較舊，多數現代工具會改用 GitHub Release 安裝到 `~/.local/bin`，屬正常行為。
- **armv6 機器**：官方 Release 支援有限，未提供對應版本的工具會標示為 `FAILED`；可用 `--only` 指定確定可用的項目。
- **安裝失敗時**：先看摘要中的 `FAILED` 列，再到日誌對應區段查看原因；其餘成功的工具不受影響，可正常使用。
- **重複執行**：腳本可安全重跑，已安裝的工具會顯示 `existing`，shell 設定也不會重複加入。

---

## 專案結構

```
nanolander/
├── bin/
│   ├── nanolander      主安裝腳本
│   └── iterm-tune      iTerm2 效能調校（僅 macOS）
├── docs/
│   ├── index.html      彩色版說明（中文）
│   └── index.en.html   彩色版說明（英文）
├── README.md
└── LICENSE
```

`docs/` 可以直接開 GitHub Pages 當專案網站。

## iTerm2 效能調校

macOS 使用者可以順便調整 iTerm2 的渲染設定。先看現況，確認後再套用：

```bash
./bin/iterm-tune              # 只顯示，不改任何東西
./bin/iterm-tune --apply      # 備份後套用（必須先關閉 iTerm2）
./bin/iterm-tune --restore    # 還原最近一次備份
```

會處理的項目：GPU 渲染在電池模式下不被關閉、吞吐量優先、關閉透明與模糊、關閉連字、scrollback 改為有上限。觸發器數量與背景圖片只提醒不改動。

## 本次更新內容

### 新增工具（19 → 44 項）

監控與檔案類：`bottom`、`dive`、`sd`、`tree`、`duf`、`yq`、`glow`、`xh`、`gping`、`hyperfine`、`watch`、`rsync`、`wget`、`unzip`

寫程式常用：`git`、`tig`、`git-delta`、`difftastic`、`ctags`、`cscope`、`ShellCheck`、`shfmt`、`just`、`entr`、`direnv`

四種作業系統與各 CPU 架構的安裝路徑均已補齊：macOS 走 Homebrew，Linux 優先使用套件庫，缺少時改用官方 GitHub Release，並已確認各專案的檔案命名與壓縮檔結構。

### 新增選項

`--list-tools`、`--only`、`--skip`、`--with-aliases`、`--configure-git`；同時支援多個選項並用（原本僅接受單一參數）。

### 其他調整

- `github_install` 支援壓縮檔內外檔名不同的專案（yq）、直接發佈單一執行檔的專案（shfmt、direnv），挑檔改為先比對完整結尾。
- direnv 安裝後自動加入 shell hook。
- 新增 fzf 快捷鍵與搜尋來源整合。
- `command_works` 加入 `unzip -v` 與 `entr` 的驗證方式。
- 腳本本身已通過 ShellCheck（warning 以上零問題）。
- 摘要新增 `SKIPPED` 狀態與略過數量統計，被過濾的工具不會影響回傳狀態。
