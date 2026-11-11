[English](README.md)

# Bộ skill cấu hình sẵn cho Antigravity agent

Bộ thiết lập Windows cho Antigravity CLI (`agy`), gồm quy tắc làm việc, skill và plugin dùng chung.
Bản fork GitHub của bạn có thể tự sao lưu cấu hình và khôi phục trên máy khác.
Cập nhật nguồn hằng tuần đi qua pull request để duyệt; bạn có thể trò chuyện với agy để bảo trì bộ cấu hình.

## Vừa cài agy? Bắt đầu ở đây

Mở Windows PowerShell trên Windows 10 hoặc 11. Các script dùng Windows PowerShell 5.1, chạy dưới tài khoản hiện tại và không cần quyền quản trị.

Các lệnh chạy script bên dưới dùng `powershell -NoProfile -ExecutionPolicy Bypass -File` để chạy khi mặc định chưa cho phép script cục bộ. Tùy chọn này chỉ áp dụng cho tiến trình đó, không đổi chính sách thực thi đã lưu của bạn. Hãy đọc script trước khi chạy.

1. Kiểm tra `agy --version`; cần agy từ 1.5 trở lên.
2. Kiểm tra `git --version`. Nếu chưa có Git, chạy `winget install Git.Git`, mở lại PowerShell rồi kiểm tra lại.
3. Nếu dùng công cụ bản đồ dự án mặc định là graphify, cài Python từ 3.10 trở lên khi cần: `winget install Python.Python.3.13`. Sau đó kiểm tra `python --version`.
4. Node.js và `npx` là tùy chọn để tìm skill mới bằng `npx skills find`. Máy của bạn không cần GitHub CLI.

Bạn có thể chọn một skill bản đồ dự án khác đã cài, hoặc `none`, thay cho graphify. Nếu chọn graphify mà chưa có Python, trình cài vẫn cài phần còn lại, báo phần còn thiếu, và `apply` sẽ thử lại ở những lần đăng nhập sau.

## Cài đặt

### Khuyên dùng: fork và clone để có bản sao lưu riêng

Trước hết, fork [repo này](https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent) trên GitHub. Thay `<your-account>` trong lệnh dưới bằng tài khoản sở hữu bản fork. Thiết lập xác thực Git để máy có quyền đẩy lên bản fork đó.

```powershell
git clone https://github.com/<your-account>/Pre-configured-skills-for-the-antigravity-agent.git
cd Pre-configured-skills-for-the-antigravity-agent
Get-Content .\scripts\install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Chọn hoặc tạo profile riêng khi được hỏi. Trình cài hỏi ngôn ngữ trả lời và công cụ bản đồ dự án, sao lưu cấu hình hiện có, hiển thị các việc sẽ làm, rồi hỏi xác nhận trước khi đăng ký tác vụ tự động. Bạn có thể chạy lại an toàn.

Vai trò được xác định theo từng máy bằng một lần thử đẩy lên `origin` không ghi thay đổi, rồi lưu cục bộ. Máy có quyền đẩy là **owner**: tự sao lưu thay đổi cấu hình và cập nhật nguồn hằng tuần. Máy không có quyền đẩy là **follower**: nhận cấu hình và cập nhật từ `main`, không công bố thay đổi. Clone trực tiếp repo gốc công khai thường khiến bạn thành follower và không có bản sao lưu tự động trên GitHub.

### Dùng cấu hình chung dưới vai trò follower

```powershell
git clone https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent.git
cd Pre-configured-skills-for-the-antigravity-agent
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

### Cài bằng một dòng

Đọc [install.ps1](https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent/blob/main/scripts/install.ps1) trước: lệnh này tải và chạy script đó. Mặc định script clone repo gốc vào `~/.agy-config`; hãy dùng cách fork và clone ở trên để có bản sao lưu riêng.

```powershell
irm https://raw.githubusercontent.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent/main/scripts/install.ps1 | iex
```

Trong bản clone, các tùy chọn được hỗ trợ là:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -ProfileName my-profile -Language vi -ProjectMapTool graphify
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -ProfileName my-profile -Language vi -ProjectMapTool none -Yes -RepoPath .
```

`-ProfileName` chọn hoặc tạo profile; `-Language` chọn ngôn ngữ trả lời; `-ProjectMapTool` chọn graphify, skill khác đã cài, hoặc `none`. `-RepoPath` chọn vị trí repo. `-Yes` chấp nhận các việc đã hiển thị mà không hỏi xác nhận. Nếu đã có bản clone, script dùng ngay vị trí đó. Giao diện đầy đủ là `install.ps1 [-ProfileName <name>] [-Language <code>] [-ProjectMapTool <name|none>] [-Yes] [-RepoPath <path>]`.

## Những gì được cài

Bảng này dựa trên [core/sources.json](core/sources.json). Profile có thể thêm nguồn hoặc thay nguồn trong core có cùng `id`.

| Nguồn | Skill hoặc plugin | Cách cài |
|---|---|---|
| [Skill của Matt Pocock](https://github.com/mattpocock/skills) | Các skill kỹ thuật, lập kế hoạch, nghiên cứu, viết và những skill khác được liệt kê trong file nguồn | Skill lẻ ở commit Git đã khóa |
| [Vercel Labs skills](https://github.com/vercel-labs/skills) | `find-skills` | Skill lẻ ở commit Git đã khóa |
| [Superpowers](https://github.com/obra/superpowers) | Plugin quy trình phát triển | Plugin Git ở commit đã khóa |
| [Anthropic Engineering](https://github.com/anthropics/knowledge-work-plugins) | `engineering` | Plugin đóng gói ở commit Git đã khóa |
| [Anthropic Design](https://github.com/anthropics/knowledge-work-plugins) | `design` | Plugin đóng gói ở commit Git đã khóa |
| [Skill lập trình và tài liệu của Anthropic](https://github.com/anthropics/skills) | `anthropic-dev-skills`: tạo MCP, PDF, Word, Excel, PowerPoint | Plugin đóng gói ở commit Git đã khóa |
| [graphifyy](https://pypi.org/project/graphifyy/) | Bản đồ dự án `graphify` | Gói Python ở phiên bản đã khóa, chỉ cài khi được chọn |
| [Chrome DevTools](core/sources.json) | `chrome-devtools-plugin` | Chợ `antigravity-plugins-official` |
| [Gemini API](core/sources.json) | `gemini-api` | Chợ `antigravity-plugins-official` |
| [Hướng dẫn web hiện đại](core/sources.json) | `modern-web-guidance-plugin` | Chợ `antigravity-plugins-official` |

Repo cũng cài plugin riêng `agy-self-config`, quy tắc chung, quy tắc profile và tám quyền Git chỉ đọc. Các cài đặt CLI khác được giữ nguyên. Định nghĩa MCP của profile dùng biến môi trường dạng `${SERVICE_TOKEN}`; hãy đặt các biến môi trường người dùng tương ứng riêng trên mỗi máy.

Nội dung bên thứ ba được tải từ nguồn gốc, không lưu trong repo này. Nguồn Git dùng commit đã khóa, công cụ Python dùng phiên bản gói đã khóa. Chợ không hỗ trợ cài đúng một phiên bản: script ghi lại phiên bản và giữ bản sao plugin chạy tốt gần nhất để quay lui.

## Dùng hằng ngày

Trò chuyện với agy như bình thường, ví dụ: “Từ giờ hãy giải thích thay đổi trước khi chạy,” “Cài skill X,” hoặc “Tôi sắp chuyển sang máy mới.” Skill `agy-self-config` giúp sửa đúng profile hoặc file nguồn, chạy script và kiểm tra log. Bạn không cần một coding agent khác để bảo trì bộ cấu hình này.

| Khi nào | Mọi máy | Máy owner chạy thêm |
|---|---|---|
| Lúc đăng nhập | `agy-config-apply`: nhận cấu hình từ `main` | `agy-config-sync`: thu thay đổi cục bộ |
| Sau khi agy hoàn tất một lượt | Hook Stop trả lời ngay | Khởi chạy sync ở tiến trình tách rời |
| Hằng ngày lúc 12:00 | — | `agy-config-sync` |
| Chủ nhật lúc 10:00 | — | `agy-config-update`: thử cập nhật nguồn gốc và đẩy `update/sources` |

Sync chờ ít nhất 10 phút giữa các lần chạy tự động và ngăn chạy chồng nhau. Thay đổi cấu hình của owner đi thẳng lên `main`. Phiên bản nguồn hằng tuần được duyệt qua PR trước khi follower nhận; nguồn cập nhật lỗi được quay lui riêng. Owner dùng các phiên bản đã thử trong bản khóa chờ ở máy mình khi PR chưa được duyệt. Hãy duyệt và merge PR hằng tuần để công bố những phiên bản đó.

Các lệnh chạy tay trong bản clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\apply.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync.ps1 -Force
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\update.ps1 -NoPush
```

`sync` và `update` chỉ công bố thay đổi trên máy owner; `-NoPush` thử cập nhật nguồn tại máy mà không đẩy lên. Quá trình thu cấu hình bỏ qua `trustedWorkspaces`, model đang chọn, tên máy, lịch sử hội thoại, log, cache và skill chưa được phân loại. Phát hiện bí mật sẽ dừng công bố. Vì repo có thể công khai, hãy xem lại quy tắc riêng và nội dung tự viết đã khai báo trước khi chia sẻ.

## Chuyển sang máy mới

1. Cài agy và Git, thêm Python nếu dùng graphify.
2. Clone bản fork, xác thực Git để có quyền đẩy nếu muốn máy owner, rồi chạy `scripts/install.ps1`.
3. Chọn cùng profile và đặt các biến môi trường người dùng cần cho server MCP. Bí mật không được khôi phục từ Git.
4. Kiểm tra phần tóm tắt của trình cài và log. Cấu hình hiện có được sao lưu vào `~/.agy-config-backup/<yyyyMMdd-HHmmss>` trước khi thay đổi.

Bản fork nhận cải tiến từ repo gốc khi bạn dùng **Sync fork** trên GitHub hoặc nhờ agy gộp `upstream/main`; đây là thao tác chủ động, riêng với việc sao lưu tự động.

## Thiết lập repo một lần cho chủ repo và chủ bản fork

Trong repo của bạn trên GitHub:

1. Mở **Settings → Actions → General**, bật **Allow GitHub Actions to create and approve pull requests**. Workflow hằng tuần dùng `GITHUB_TOKEN` có sẵn, nên máy không cần GitHub CLI hay token PR riêng.
2. Bảo vệ `main`: yêu cầu pull request, một lượt duyệt chấp thuận và CI xanh. Bật yêu cầu code owner duyệt các đường dẫn nhạy cảm trong [CODEOWNERS](.github/CODEOWNERS).
3. Cho phép chủ repo bỏ qua các yêu cầu đó để đồng bộ cấu hình tự động có thể đẩy thẳng lên `main`.

Workflow hằng tuần tạo hoặc cập nhật một PR từ `update/sources`. Nếu GitHub không cho tạo PR, workflow vẫn thành công và ghi link so sánh **Create pull request** vào phần tóm tắt lần chạy; log cập nhật cục bộ cũng có link đó. Hãy mở link để tạo thủ công. Kiểm tra cũng chạy khi đẩy lên `update/**` vì PR do `GITHUB_TOKEN` tạo không tự kích hoạt các workflow khác.

## Gỡ cài đặt

Trong bản clone:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
# Có thể khôi phục bản sao lưu; thay mốc ví dụ bằng mốc của bạn.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -RestoreBackup 20261111-120000
```

Giao diện là `scripts/uninstall.ps1 [-RestoreBackup <stamp>]`. Script gỡ các tác vụ tự động và plugin `agy-self-config`. Skill bên thứ ba vẫn được giữ. Thêm `-RestoreBackup` để khôi phục cấu hình đã lưu ở `~/.agy-config-backup/<stamp>`.

## Xử lý sự cố

- Đọc `~/.agy-config-state/logs` để xem kết quả install, apply, sync và update. Bắt đầu với file mới nhất của script bị lỗi.
- Xem `~/.agy-config-state/unknown.json` để tìm skill hoặc plugin chưa được phân loại. Nhờ agy khai báo nguồn gốc, đánh dấu là đồ tự viết trong `ownSkills`/`ownPlugins`, hoặc thêm vào `ignored`. Chúng ở lại máy cho đến khi được phân loại.
- Nếu thiếu graphify, cài Python từ 3.10 trở lên, rồi chạy `scripts/apply.ps1` hoặc đăng nhập lại.
- Nếu thiếu biến MCP, đặt các biến môi trường người dùng được nêu và mở lại PowerShell trước khi apply.
- Nếu sync báo xung đột, nhờ agy duyệt và merge nhánh `sync/<profile>-<yyyyMMdd-HHmmss>`. Những chỉnh sửa xung đột được giữ ở đó để xem xét.
- Nếu cập nhật không mở được PR, dùng link so sánh trong phần tóm tắt workflow hoặc log cập nhật, rồi kiểm tra thiết lập repo ở trên.

## Giấy phép và đóng góp

Code của repo dùng [giấy phép MIT](LICENSE). Nội dung nguồn gốc giữ giấy phép riêng; xem [THIRD_PARTY.md](THIRD_PARTY.md). Đọc [CONTRIBUTING.vi.md](CONTRIBUTING.vi.md) để thêm nguồn hoặc cải tiến script, và [SECURITY.md](SECURITY.md) để báo lỗ hổng riêng tư.
