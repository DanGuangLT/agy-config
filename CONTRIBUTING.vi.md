[English](CONTRIBUTING.md)

# Đóng góp

Repo này cấu hình Antigravity CLI (`agy`) trên Windows. Gửi đóng góp bằng pull request tới [repo gốc](https://github.com/DanGuangLT/Pre-configured-skills-for-the-antigravity-agent). Đọc [README.vi.md](README.vi.md) để biết cách cài và mô hình owner/follower.

## Thêm nguồn skill hoặc plugin

1. Fork và clone repo, rồi tạo nhánh cho thay đổi của bạn.
2. Sửa `core/sources.json` cho nguồn dùng chung, hoặc `profiles/<profile>/sources.json` cho nguồn riêng của profile. Dùng `id` duy nhất; mục trong profile thay mục trong core có cùng `id`.
3. Chọn đúng loại: `github-skills`, `git-plugin`, `packaged-plugin`, `pip-tool` hoặc `marketplace`. Làm theo mục có sẵn trong [core/sources.json](core/sources.json), gồm cả `provides` để phân loại. Ví dụ:

   ```json
   {
     "id": "example-skills",
     "type": "github-skills",
     "repo": "https://github.com/example/skills",
     "skills": [{"name": "example-skill", "path": "skills/example-skill"}],
     "provides": ["example-skill"]
   }
   ```

4. Với mỗi nguồn core mới, thêm cả một dòng vào [THIRD_PARTY.md](THIRD_PARTY.md) và phiên bản khóa theo `id` trong [core/sources.lock.json](core/sources.lock.json). Dòng ghi công gồm nguồn, giấy phép và URL `repo` chính xác. Với `pip-tool`, ghi tên `package` và link PyPI thay thế. Mục marketplace ghi tên plugin và chợ. Nguồn riêng của profile cần phiên bản trong `sources.lock.json` của profile đó; URL repo được ghi trong `sources.json` và không cần dòng trong THIRD_PARTY. Không chép skill nguồn gốc vào repo này.
5. Trên máy owner đã cấu hình, chạy `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\update.ps1 -NoPush` để cài và kiểm tra các phiên bản nguồn ứng viên tại máy. Lệnh này thay đổi nguồn đã cài và trạng thái chờ cục bộ; không đẩy nhánh hay mở PR. Xem log cập nhật và ghi commit hoặc phiên bản gói đã thử vào `sources.lock.json` tương ứng cho PR. Nếu không thể cài thử tại máy, để CI kiểm tra cấu trúc repo và nêu hạn chế đó trong PR; CI không thay thế kiểm tra cài nguồn thực tế.
6. Thêm test cho thay đổi hành vi, chạy các kiểm tra dưới đây và mở PR bằng mẫu có sẵn. Nêu thay đổi, lý do và kết quả kiểm tra.

## Quy tắc phát triển và kiểm tra

- Chỉ dùng Windows PowerShell 5.1; mọi `.ps1` phải chỉ chứa ASCII. Văn bản script hiển thị cho người dùng chỉ dùng tiếng Anh, trong `scripts/i18n/en.json`. Ngôn ngữ trả lời của profile tùy chỉnh được; quy tắc được sinh bằng tiếng Anh (ví dụ "Always reply to the user in Vietnamese"). Markdown có thể chứa tiếng Việt.
- Ghi văn bản UTF-8 không BOM qua `Write-TextFile`; dùng lại hàm thư viện trong `scripts/lib/`. Gọi công cụ ngoài và mạng qua `Invoke-External`, `Invoke-Http` để test có thể mock.
- Viết test Pester 5 thất bại trước khi đổi hành vi script, sau đó làm test đạt. Test cần kiểm tra hành vi thực tế.
- Giữ nội dung bên thứ ba tại nguồn gốc với phiên bản đã khóa. Không chép nội dung đó vào repo.
- Không đưa bí mật, email cá nhân, đường dẫn người dùng riêng của máy, lịch sử hội thoại, log hoặc cache vào repo. Định nghĩa MCP dùng `${VARIABLE}`. Skill chưa rõ nguồn ở trong `unknown.json` cục bộ cho đến khi được phân loại.
- Dùng [mẫu PR](.github/PULL_REQUEST_TEMPLATE.md), gồm mục kiểm tra ghi công nguồn khi thêm nguồn mới.

Chạy tại thư mục gốc của repo:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Validate-Repo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/Invoke-Tests.ps1
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
$issues = @(Invoke-ScriptAnalyzer -Path scripts -Recurse -Severity Error)
$issues
if ($issues.Count -gt 0) { throw 'PSScriptAnalyzer reported errors.' }
```

Trình chạy test cần Pester từ 5.5 trở lên và cài cho người dùng hiện tại nếu thiếu. Để chỉ chạy test validator, thêm `-Path tests/unit/ValidateRepo.Tests.ps1` vào lệnh test. Chạy lại toàn bộ bộ test trước khi gửi.

Kiểm tra repo gồm JSON, metadata skill và plugin, ghi công nguồn core, phiên bản khóa cho nguồn core và profile, giới hạn file 1 MB, script ASCII, bí mật và dữ liệu cá nhân. Dữ liệu giả cho scanner trong `tests/` và ghi chú cục bộ `.superpowers/` chỉ được bỏ qua ở bước quét bí mật và dữ liệu cá nhân của validator; các kiểm tra khác vẫn áp dụng. Gitleaks dùng [.gitleaks.toml](.gitleaks.toml) để cho phép dữ liệu test.

## Duyệt và bàn giao

[CODEOWNERS](.github/CODEOWNERS) chỉ định `@DanGuangLT` làm chủ, kèm quy tắc riêng cho `scripts/`, code plugin và hook trong `core/plugins/`, `core/sources*.json`, `.github/`. Các đường dẫn này chạy code hoặc chọn code được tải về và cần code owner duyệt. Thay đổi vào `main` đi qua PR, một lượt duyệt chấp thuận và CI xanh; quyền bỏ qua của owner phục vụ đồng bộ cấu hình tự động.

Kiểm tra chạy trên PR và các lần đẩy lên `main`, `update/**`. Workflow cập nhật hằng tuần tạo hoặc sửa PR cho `update/sources`; khi không được phép tạo PR, phần tóm tắt có link tạo thủ công. Báo lỗ hổng riêng tư theo [SECURITY.md](SECURITY.md).
