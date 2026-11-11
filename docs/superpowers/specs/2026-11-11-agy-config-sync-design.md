# Thiết kế: Bộ cấu hình agy dùng chung, tự sao lưu và tự cập nhật

Ngày: 2026-11-11 · Repo: `DanGuangLT/Pre-configured-skills-for-the-antigravity-agent` (công khai)

## 1. Mục đích và lý do

Người dùng (chủ repo) đã mất công cấu hình Antigravity CLI (`agy`): quy tắc làm việc, quyền lệnh, skill, plugin. Họ muốn:

- **Không bao giờ phải setup lại từ đầu**: đổi máy thì một lệnh là máy mới giống hệt máy cũ.
- **Không mất bản sao lưu**: mọi thay đổi trên máy tự được đẩy lên repo.
- **Theo kịp công nghệ**: AI thay đổi rất nhanh, nên skill/plugin phải tự cập nhật lên bản mới, nhưng vẫn quay lại được bản cũ khi bản mới hỏng.
- **Tự lập**: sau khi xây xong, mọi việc bảo trì do chính `agy` làm theo lời người dùng; không cần Claude Code hay ai khác.
- **Chia sẻ**: repo công khai để người Việt và người dùng quốc tế đều cài được, và đóng góp qua quy trình PR.

## 2. Mục tiêu, không làm, điều tối kỵ

**Mục tiêu**

1. Cài mới trên một máy chỉ có `agy`: một lệnh duy nhất, xong là agy có đủ quy tắc, quyền, skill, plugin và cơ chế tự động.
2. Máy của chủ repo tự đồng bộ máy → repo sau mỗi phiên agy và theo lịch.
3. Máy owner tự cập nhật skill/plugin từ nguồn gốc mỗi tuần, có khóa phiên bản để quay lui. Mọi máy tự nhận cập nhật repo → máy, chỉ từ nhánh `main`.
4. agy có một skill riêng để tự bảo trì cấu hình này theo lời người dùng.
5. README hướng dẫn người vừa tải agy về, bằng tiếng Anh (`README.md`) và tiếng Việt (`README.vi.md`).

**Không làm (lúc này)**

- Ứng dụng Antigravity bản desktop/IDE: chỉ lo agy CLI.
- macOS/Linux: thiết kế để người đóng góp thêm sau; bản đầu chỉ Windows.
- Đồng bộ cấu hình Claude Code.

**Điều tối kỵ** (xảy ra là thất bại dù mọi thứ "chạy được")

- Bí mật (token, mật khẩu, khóa API, email cá nhân) lọt lên repo công khai.
- Lịch sử hội thoại, log, cache của agy lọt lên repo.
- Code chưa được chủ repo duyệt tự chạy trên máy người dùng.
- Một bản cập nhật làm hỏng agy mà không quay lại được.
- Ghi đè mất thiết lập riêng của người dùng trong `settings.json`.

## 3. Bản đồ cấu hình agy (đã kiểm chứng trên máy chủ repo, agy 1.5.5)

| Thứ | Vị trí trên máy | Cách quản lý trong repo |
|---|---|---|
| Quy tắc chung | `~/.gemini/GEMINI.md` | Sinh từ `core` + `profile` (mục 5.2) |
| Cài đặt CLI | `~/.gemini/antigravity-cli/settings.json` | Chỉ trộn khóa `permissions.allow`; giữ nguyên mọi khóa khác |
| Skill lẻ | `~/.gemini/config/skills/<tên>/` | Công cụ `skills` của vercel-labs (`npx skills add … -g -a antigravity`), khóa ở `~/.agents/.skill-lock.json` |
| Plugin | `~/.gemini/config/plugins/<tên>/` (có `plugin.json` + `skills/`) | Xem mục 4 |
| Danh sách plugin chợ | `~/.gemini/config/config.json` → `plugins` | Đọc bằng `agy plugin list --json` |
| MCP | `~/.gemini/config/mcp_config.json` | Lưu định nghĩa server; giá trị bí mật thay bằng `${TÊN_BIẾN}` |
| Hook toàn cục | `~/.gemini/config/hooks.json` | Không dùng; hook đi kèm plugin riêng của repo |
| Lịch sử, log, cache | `~/.gemini/antigravity*/{conversations,brain,cache,…}`, `*.db`, `history.jsonl`, `cli.log` | **Không bao giờ** đồng bộ |

Đặc tính agy đã kiểm chứng, bản thiết kế dựa vào:

- `permissions.allow` so khớp **chính xác** cả câu lệnh (`command(git status)` không cho `git status --short`); không hỗ trợ `*`.
- `agy plugin install <đường-dẫn-thư-mục>` cài plugin cục bộ; `agy plugin validate <thư-mục>` kiểm tra plugin.
- Plugin có thể mang `hooks.json` riêng. Sự kiện có sẵn: `SessionStart`, `PreToolUse`, `PostToolUse`, `PreInvocation`, `PostInvocation`, `Stop`. Hook chạy qua `cmd /c` trên Windows, mặc định hết giờ sau 30 giây, nhận JSON qua stdin và phải in JSON ra stdout.
- Ở chế độ `--print` (chạy nền), lệnh chưa được cho phép bị từ chối tự động.

## 4. Nguồn skill và plugin: ghi nguồn, không chép

Repo **không chứa bản sao** skill của bên thứ ba. Repo chỉ ghi chúng lấy từ đâu (`sources.json`) và phiên bản đã chạy tốt (`sources.lock.json`). Lợi: luôn lấy được bản mới, repo nhẹ, đúng giấy phép, quay lui được.

Năm loại nguồn. Mọi nguồn trên GitHub đều tải bằng `git` ở đúng SHA commit, vì cách đó khóa và quay lui được chắc chắn:

| Loại | Ví dụ hiện có | Cài (ở SHA khóa) | Cập nhật | Khóa phiên bản |
|---|---|---|---|---|
| `github-skills` | `mattpocock/skills` (38 skill), `vercel-labs/skills` (find-skills) | Tải thư mục từng skill (sparse checkout) rồi chép vào `~/.gemini/config/skills/<tên>` | Lấy SHA mới nhất của nhánh mặc định | SHA commit |
| `git-plugin` | `obra/superpowers` (MIT) | `git clone` vào `~/.gemini/config/plugins/<tên>`, `checkout` SHA | `git fetch` + SHA mới nhất | SHA commit |
| `packaged-plugin` | `anthropics/knowledge-work-plugins` → `engineering`, `design`; `anthropics/skills` → `mcp-builder`, `pdf`, `docx`, `xlsx`, `pptx` | Tải thư mục con, đóng gói thành plugin (`plugin.json` + `skills/`), rồi `agy plugin install <thư-mục>` | Tải bản mới nhất, đóng gói lại | SHA commit |
| `pip-tool` | `graphifyy` (graphify; Apache-2.0 + MIT). Là công cụ **bản đồ dự án mặc định**; chỉ cài khi profile chọn nó (mục 5.1) | `python -m pip install --user graphifyy==<phiên bản>` rồi `graphify install --platform antigravity-windows` (công cụ tự cài skill cho Antigravity) | Cài bản mới nhất trên PyPI rồi chạy lại `graphify install` | Số phiên bản PyPI |
| `marketplace` | `chrome-devtools-plugin`, `gemini-api`, `modern-web-guidance-plugin` (chợ `antigravity-plugins-official`) | `agy plugin install <tên>@<chợ>` | Cài lại bản mới nhất | Ghi số phiên bản để theo dõi. `agy` không cho cài đúng một phiên bản, nên loại này **chấp nhận trôi phiên bản**; để quay lui, giữ bản sao lần chạy tốt gần nhất ở `~/.agy-config-state/snapshots/<tên>/` |

Công cụ `skills` của vercel-labs (`npx skills …`) chỉ dùng để **tìm** skill mới, và để `sync` biết người dùng vừa tự cài skill gì: đọc nguồn + đường dẫn từ `~/.agents/.skill-lock.json` rồi ghi thành mục `github-skills`.

Giấy phép đã kiểm chứng trên repo gốc: `obra/superpowers` MIT, `mattpocock/skills` MIT, `anthropics/knowledge-work-plugins` Apache-2.0, `anthropics/skills` Apache-2.0 (README của repo ghi rõ cả `docx`, `pdf`, `pptx`, `xlsx` đều Apache-2.0).

Vì sao `engineering`, `design` là plugin chứ không là skill lẻ: chúng có skill trùng tên với skill lẻ (`code-review` có cả ở Matt Pocock lẫn `engineering`). Plugin có không gian tên riêng nên không đè nhau.

**Phân loại skill/plugin tìm thấy trên máy** (quy tắc duy nhất, `sync` áp dụng):

1. Khớp một mục trong `sources.json` → là nguồn ngoài, chỉ ghi nguồn.
2. Có tên trong `ownSkills`/`ownPlugins` của `profile.json` → là đồ tự viết. Lưu nguyên văn trong `profiles/<tên>/skills/` hoặc `profiles/<tên>/plugins/` và được đẩy lên.
3. Có tên trong `ignored` của `profile.json` → bỏ qua.
4. Còn lại là **chưa rõ**. Thứ chưa rõ **không bao giờ** được đẩy lên; nó chỉ được ghi vào `~/.agy-config-state/unknown.json`. Skill `agy-self-config` hỏi người dùng rồi xếp vào một trong ba nhóm trên: khai báo nguồn, đánh dấu tự viết, hoặc bỏ qua.

## 5. Cấu trúc repo

```text
README.md                 # tiếng Anh, có link sang README.vi.md
README.vi.md              # tiếng Việt
LICENSE                   # MIT cho phần của repo
THIRD_PARTY.md            # nguồn + giấy phép của mọi nguồn trong sources.json
CONTRIBUTING.md / CONTRIBUTING.vi.md
SECURITY.md               # cách báo lỗ hổng
core/
  GEMINI.core.md          # quy tắc dùng chung (tiếng Anh, không gắn ngôn ngữ trả lời)
  permissions.json        # 8 lệnh git chỉ đọc
  sources.json            # nguồn dùng chung (mục 4)
  sources.lock.json       # phiên bản đã kiểm chứng
  plugins/agy-self-config/  # plugin riêng của repo: skill tự bảo trì + hook
profiles/
  _template/              # mẫu cho người mới
  lianharman/             # profile của chủ repo
    profile.json          # ngôn ngữ, cờ owner/sync, nguồn thêm, quyền thêm
    GEMINI.profile.md     # quy tắc riêng (vd. trả lời tiếng Việt)
    sources.json / sources.lock.json   # nguồn chỉ profile này dùng
    plugins/ skills/      # đồ tự viết
scripts/
  install.ps1             # cài lần đầu
  apply.ps1               # repo → máy
  sync.ps1                # máy → repo (chỉ profile owner)
  update.ps1              # cập nhật từ nguồn gốc hằng tuần
  lib/                    # hàm dùng chung
tests/                    # Pester
.github/
  workflows/validate.yml  # kiểm tra mọi PR
  CODEOWNERS
  PULL_REQUEST_TEMPLATE.md
docs/
```

### 5.1 `profile.json`

```json
{
  "name": "lianharman",
  "language": "vi",
  "sync": { "debounceMinutes": 10 },
  "update": { "day": "Sunday" },
  "projectMap": { "tool": "graphify" },
  "ownSkills": [],
  "ownPlugins": [],
  "ignored": []
}
```

`projectMap.tool` là skill agy dùng để có bản đồ kiến thức của dự án khi vào dự án (mục 7):

- `"graphify"` (mặc định): cài nguồn `graphifyy`.
- Tên một skill khác người dùng đang dùng: không cài graphify; quy tắc định hướng gọi skill đó.
- `"none"`: bỏ bước bản đồ dự án.

### 5.3 Vai trò của từng máy

Vai trò được quyết **theo máy**, không ghi trong file dùng chung. `install` thử `git push --dry-run` lên `origin`, rồi lưu kết quả cùng tên profile vào `~/.agy-config-state/machine.json`:

- **owner**: có quyền đẩy lên `origin`. Máy chạy `sync` để đẩy lên và chạy `update` để cập nhật nguồn.
- **follower**: không có quyền đẩy. Máy chỉ chạy `apply` và chạy đúng theo file khóa trên `main`. Không bao giờ commit.

Người dùng khác được khuyên **fork repo rồi cài từ bản fork của mình**. Khi đó họ là owner của bản fork, cấu hình của họ cũng được sao lưu. Muốn lấy cải tiến từ repo gốc thì bấm "Sync fork" trên GitHub, hoặc nhờ agy (skill `agy-self-config`) gộp `upstream/main`. Việc gộp này không tự động. Clone trực tiếp repo gốc vẫn được, nhưng chỉ ở vai trò follower và không có sao lưu.

### 5.2 `GEMINI.md` sinh ra

`apply` ghép file theo vùng đánh dấu:

```markdown
<!-- agy-config:core:start -->
…nội dung core/GEMINI.core.md…
<!-- agy-config:core:end -->
<!-- agy-config:profile:start -->
…nội dung profiles/<tên>/GEMINI.profile.md, gồm quy tắc ngôn ngữ…
<!-- agy-config:profile:end -->
```

`sync` đọc ngược theo vùng: phần sửa trong vùng `profile` → `GEMINI.profile.md`. Phần sửa trong vùng `core` → `core/GEMINI.core.md`, chỉ khi profile là owner. Chữ nằm ngoài các vùng được gộp vào vùng `profile`.

## 6. Các luồng

### 6.1 Cài lần đầu (`install.ps1`)

Cách chạy, ghi trong README:

1. `git clone` repo, rồi chạy `.\scripts\install.ps1` (khuyên dùng: đọc được script trước khi chạy).
2. Hoặc một dòng `irm <raw-url>/scripts/install.ps1 | iex`. Cách này tự clone vào `~/.agy-config`.

Các bước của script:

1. Kiểm tra `git`, `node`/`npx`, `agy`; thiếu thì in link cài và dừng.
2. Hỏi profile: dùng profile có sẵn, hoặc tạo mới từ `_template`. Khi tạo mới thì hỏi:
   - ngôn ngữ trả lời (`vi`/`en`/khác);
   - công cụ bản đồ dự án: Enter để dùng graphify; hoặc gõ tên skill khác đang dùng; hoặc `none`.
3. Sao lưu cấu hình hiện có của agy vào `~/.agy-config-backup/<thời-gian>/` trước khi đổi gì.
4. Chạy `apply`.
5. Xác định vai trò máy (mục 5.3). Đăng ký tác vụ Windows Task Scheduler cho người dùng hiện tại, không cần quyền admin: mọi máy chạy `apply` lúc đăng nhập; máy owner chạy thêm `sync` hằng ngày và `update` hằng tuần.
6. In tóm tắt đã cài những gì, kèm cách gỡ.

Chạy lại `install.ps1` nhiều lần vẫn an toàn (idempotent).

### 6.2 Repo → máy (`apply.ps1`)

0. **Thu về trước**: chạy phần "gom" của `sync` (bước 1 mục 6.3), ghi vào cây làm việc của repo, không commit. Vậy chỗ người dùng sửa tay `GEMINI.md` không bị bước 4 xóa mất. Máy owner thì chạy `sync` đầy đủ.
1. `git pull --ff-only` nhánh `main`. Không fast-forward được thì dừng và ghi log.
2. Cài/cập nhật mọi nguồn trong `core` + profile **đúng theo file khóa**. Thứ nào lần `apply` trước đã cài mà nay không còn trong repo thì gỡ. Danh sách đã cài nằm ở `~/.agy-config-state/applied.json`. `apply` chỉ gỡ những gì chính nó đã cài, không động vào thứ người dùng tự cài ngoài hệ thống.
3. Cài plugin `agy-self-config` và đồ tự viết của profile.
4. Sinh `GEMINI.md` (5.2).
5. Trộn `permissions.allow`: thêm lệnh còn thiếu, giữ nguyên các khóa khác.
6. Ghi `mcp_config.json`: server còn thiếu thì thêm, `${TÊN_BIẾN}` lấy từ biến môi trường của người dùng.
7. Kiểm tra: `agy plugin validate` từng plugin đã cài và `agy plugin list --json` có đủ tên.

### 6.3 Máy → repo (`sync.ps1`, chỉ owner)

Kích hoạt từ ba chỗ:

- Hook `Stop` của plugin `agy-self-config`, sau mỗi lượt agy làm xong. Hook khởi chạy `sync` ở tiến trình tách rời rồi in `{}` ngay để không làm chậm agy.
- Tác vụ hằng ngày.
- Lệnh tay.

Chống chạy dồn: không chạy nếu lần trước cách chưa đủ `debounceMinutes`, hoặc đang có một tiến trình sync khác (file khóa).

Các bước:

1. Gom về repo theo kiểu **ba chiều**: so trạng thái máy hiện tại với `~/.agy-config-state/applied.json` (lần `apply` gần nhất), rồi chỉ ghi vào repo những gì **máy này** đã thêm hoặc gỡ từ lần đó. Một máy cũ hay vừa cài sẽ không xóa đồ của máy khác. Những thứ được gom:
   - Vùng `GEMINI.md` (5.2).
   - `permissions.allow` trừ phần đã có trong `core`.
   - Danh sách skill-cli từ `~/.agents/.skill-lock.json` (nguồn + tên skill + hash).
   - Danh sách plugin chợ từ `agy plugin list --json`.
   - Plugin/skill tự viết (thứ không khớp nguồn nào).
   - Định nghĩa MCP, với giá trị bí mật thay bằng `${TÊN_BIẾN}`.
2. **Không gom**: `trustedWorkspaces`, `model`, tên máy, lịch sử, log, cache, skill không rõ nguồn (ghi vào báo cáo cục bộ).
3. Quét bí mật trên mọi file sắp commit. Thấy dấu hiệu (`ghp_`, `github_pat_`, `sk-`, `AIza`, `-----BEGIN`, phép gán giá trị cho `password`, email, đường dẫn `C:\Users\<tên>`) thì **dừng hẳn, không commit**, ghi log.
4. Không có thay đổi thì thoát.
5. Có thay đổi: commit `sync(<profile>): <ngày giờ>`, `git pull --rebase`, `git push`. Rebase xung đột thì hủy rebase, đẩy sang nhánh `sync/<profile>-<thời-gian>`, ghi log để agy xử lý (mục 7).

Log ở `~/.agy-config-state/logs/`, nằm ngoài repo.

### 6.4 Cập nhật công nghệ (`update.ps1`, hằng tuần, chỉ máy owner)

1. Với từng nguồn: lấy SHA/phiên bản mới nhất và cài thử trên máy owner.
2. Kiểm tra từng nguồn (`agy plugin validate`, có `SKILL.md` hợp lệ). Nguồn nào lỗi thì **quay về phiên bản trong file khóa**, các nguồn khác vẫn lên bản mới.
3. Ghi phiên bản mới vào file khóa. File khóa mới đến `main` theo cách ở mục 6.5.
4. Ghi một dòng tóm tắt vào log: nguồn nào lên bản nào, nguồn nào bị quay lui.

Máy follower không bao giờ tự tải bản mới nhất từ nguồn ngoài. Nó nhận bản mới khi file khóa trên `main` đổi, qua `apply` lúc đăng nhập.

### 6.5 File khóa mới đi lên `main` thế nào

Chủ repo chọn: **qua PR, một cú bấm mỗi tuần**.

1. `update` đẩy file khóa mới lên nhánh `update/sources`, rồi mở PR "Weekly source updates / Cập nhật nguồn tuần này" vào `main`. Nội dung PR là bảng: nguồn, phiên bản cũ → mới, nguồn bị quay lui. Nếu PR tuần trước chưa merge thì cập nhật luôn PR đó thay vì mở PR mới.
2. Máy owner vẫn **dùng bản mới ngay**: bản khóa đang chờ được giữ ở `~/.agy-config-state/pending.lock.json`. Trên máy owner, `apply` ưu tiên bản chờ cho các nguồn có trong đó, nên không bị hạ phiên bản lúc đăng nhập. PR được merge thì xóa bản chờ. PR bị đóng mà không merge thì lần `apply` sau quay về file khóa trên `main`.
3. **Không cần cài gì thêm trên máy** để mở PR: máy owner chỉ `git push` nhánh `update/sources`. Workflow `.github/workflows/update-pr.yml` chạy trên GitHub khi nhánh đó được đẩy lên, rồi tạo hoặc cập nhật PR bằng `GITHUB_TOKEN` có sẵn.
   - Repo cần bật một lần: Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests". README ghi rõ bước này cho chủ repo và người fork.
   - PR do `GITHUB_TOKEN` tạo không tự kích hoạt workflow khác, nên `validate.yml` chạy cả khi có push lên `update/**`. Kết quả kiểm tra gắn với commit, nên vẫn hiện trên PR.
   - Nếu workflow không mở được PR (chưa bật quyền), nó ghi link "Create pull request" vào phần tóm tắt của lần chạy; `update` cũng ghi link đó vào log trên máy.
4. Thay đổi cấu hình cá nhân của owner (`sync`: quy tắc, skill tự viết, quyền) vẫn đẩy thẳng lên `main`, không qua PR.

## 7. Tự bảo trì: plugin `agy-self-config`

Plugin của repo, cài trên mọi máy. Gồm:

- **Hook `Stop`** gọi `sync` (mục 6.3; chỉ có tác dụng khi profile là owner).
- **Skill `agy-self-config`**, mô tả kích hoạt khi người dùng muốn: đổi cách agy làm việc; cài, gỡ hay tìm skill/plugin; sao lưu, khôi phục, chuyển máy; cập nhật; xem vì sao đồng bộ lỗi. Skill hướng dẫn agy:
  - Sửa đúng file: thay đổi riêng thì sửa trong profile; thay đổi dùng chung thì sửa trong `core` (chỉ owner); thêm skill/plugin bên ngoài thì thêm vào `sources.json` của profile.
  - Chạy `apply`/`sync`/`update` và đọc log trong `~/.agy-config-state/logs/`.
  - Gỡ xung đột nhánh `sync/*` cùng người dùng.
  - Tìm skill mới bằng `npx skills find` và gợi ý cho người dùng.
  - Gửi đóng góp lên repo gốc bằng PR khi người dùng không phải owner.
- `core/GEMINI.core.md` có thêm bước **bản đồ dự án** trong phần định hướng khi vào dự án, dùng công cụ trong `projectMap.tool`. `apply` ghi tên công cụ vào vùng `profile` của `GEMINI.md`.
  - Với graphify: có `graphify-out/` thì đọc `GRAPH_REPORT.md` và dùng `graphify query/path/explain` thay vì mở nhiều file. Chưa có thì tự chạy `/graphify .` để tạo, rồi báo cho người dùng.
  - Với công cụ khác: gọi skill đó theo cách tương tự.
  - Lý do (chủ repo yêu cầu): agy có ngay bản đồ kiến thức của dự án, ít tốn token khi tìm file.
- `core/GEMINI.core.md` có một dòng trỏ tới skill này. Sau khi cài, mọi yêu cầu kiểu "từ giờ bạn hãy…" đều đi qua skill, nên cấu hình luôn theo ý người dùng và được sao lưu.

## 8. Đóng góp và an toàn

- Nhánh `main` được bảo vệ: phải qua PR, 1 người duyệt, CI xanh. Chủ repo được bỏ qua để `sync` đẩy thẳng (GitHub branch protection, "allow bypass" cho owner).
- `CODEOWNERS`: `scripts/`, `core/plugins/`, `.github/`, `core/sources*.json` bắt buộc chủ repo duyệt, vì đây là chỗ chạy lệnh trên máy người dùng hoặc quyết định tải code về.
- `validate.yml` chạy trên mọi PR:
  - JSON hợp lệ.
  - `SKILL.md` có `name` + `description`.
  - `plugin.json` hợp lệ.
  - Quét bí mật (gitleaks).
  - Cấm đường dẫn cá nhân và email.
  - Cấm file nhị phân > 1 MB.
  - Mỗi nguồn trong `sources.json` có mục trong `THIRD_PARTY.md`.
  - PSScriptAnalyzer cho `scripts/`.
  - Chạy test Pester.
- Máy chỉ nhận cập nhật từ `main`.
- `install.ps1` in ra những gì sẽ làm và hỏi xác nhận trước khi đăng ký tác vụ tự động.

## 9. Ràng buộc

- Windows 10/11, Windows PowerShell 5.1 (có sẵn), không cần quyền admin.
- Cần sẵn: `git`, `agy` ≥ 1.5, Node.js (chỉ để tìm skill bằng `npx skills`). Chỉ khi chọn graphify mới cần Python ≥ 3.10. Không cần GitHub CLI.
- Chọn graphify mà thiếu Python: `install` vẫn cài mọi thứ khác, báo rõ graphify chưa cài được kèm cách cài Python (`winget install Python.Python.3.13`). `apply` thử lại ở mỗi lần đăng nhập.
- Script gọi agy qua lệnh CLI (`agy plugin …`), không sửa trực tiếp file nội bộ của agy ngoài các file trong bảng mục 3. Lý do: agy đổi định dạng file nội bộ thì script vẫn chạy.
- Hook phải trả lời trong 30 giây, nên mọi việc nặng chạy tách rời.

## 10. Quyết định của chủ repo

- Repo công khai; mọi người dùng được và đóng góp qua PR.
- Người dùng nhắm tới: cả người Việt lẫn quốc tế.
- Tự động: tự đồng bộ, tự cập nhật công nghệ trên máy owner, không hỏi trước.
- Bản cập nhật nguồn chỉ đến máy người khác sau khi chủ repo merge PR hằng tuần (mục 6.5).
- Không cài GitHub CLI trên máy; PR do GitHub Actions mở.
- Bước định hướng luôn dùng một công cụ bản đồ dự án. graphify là mặc định, không bắt buộc: người dùng đã có skill khác tương tự thì dùng skill đó và không cài graphify.
- Chủ repo đã duyệt toàn bộ bản thiết kế (2026-11-11).
- Tự lập: sau khi xây xong, việc bảo trì do agy làm, không cần Claude Code.
- README hướng dẫn người vừa tải agy về.

## 11. Quyết định do người thiết kế chọn (chủ repo có thể đổi)

- Giấy phép MIT cho phần của repo.
- README chính tiếng Anh + bản tiếng Việt; script cài hỏi ngôn ngữ trả lời.
- Không chép skill bên thứ ba vào repo; ghi nguồn + khóa phiên bản.
- Thay 3 plugin Anthropic đang cài tay trên máy chủ repo (từ `~/.gemini/local-plugins`) bằng bản tải từ repo gốc qua `packaged-plugin`.
- Không đồng bộ `trustedWorkspaces`, `model`, tên máy.
- Thư mục clone mặc định `~/.agy-config`; nếu người dùng clone chỗ khác và chạy `install.ps1` từ đó thì dùng chỗ đó.
- Mọi nguồn GitHub tải bằng `git` ở SHA commit (không dùng `npx skills add` để cài); công cụ `skills` chỉ để tìm skill và phát hiện skill người dùng vừa tự cài.
- Plugin chợ chấp nhận trôi phiên bản, quay lui bằng bản sao lưu lần chạy tốt gần nhất.
- Vai trò owner/follower quyết theo quyền đẩy của từng máy; người khác được khuyên fork.
- `sync` ghi theo kiểu ba chiều so với lần `apply` gần nhất; `apply` chỉ gỡ những gì chính nó đã cài.
- Đồ tự viết phải được khai trong `ownSkills`/`ownPlugins`; thứ chưa rõ nguồn không bao giờ tự đẩy lên.
- Chống dồn sync 10 phút; cập nhật hằng tuần vào Chủ nhật.
- Skill không rõ nguồn/giấy phép không tự đẩy lên.
- Windows trước; macOS/Linux để người đóng góp thêm.

## 12. Để người xây dựng tự quyết

- Chi tiết bên trong script, định dạng log, biểu thức quét bí mật cụ thể.
- Thông báo cho người dùng khi sync/update lỗi (toast Windows hay chỉ log).
- Cấu trúc thư mục `tests/` và cách giả lập agy trong test.
- Nội dung chi tiết của README, CONTRIBUTING (bám mục 6 và 8).
