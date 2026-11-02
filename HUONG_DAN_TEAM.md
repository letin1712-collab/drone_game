# Drone Simulator (RescueDrone): hướng dẫn cho team

Tài liệu này giúp thành viên mới **cài Godot, mở project, chạy từng màn chơi** và **xuất game thành file `.exe`** để chia sẻ.

- Engine: **Godot 4.x (bản Standard, không phải bản .NET)**, hiện dùng **4.7.2**
- Ngôn ngữ: **GDScript**
- Trình soạn code: **VS Code** (tùy chọn nhưng khuyên dùng)
- Nền tảng: PC (Windows, macOS)

---

## 1. Cài đặt môi trường

### 1.1. Tải Godot (miễn phí, không cần cài đặt)

1. Vào trang chính thức **https://godotengine.org/download** (không tải từ trang khác).
2. Chọn bản **Godot Engine (Standard)** cho hệ điều hành của bạn. **Không chọn bản .NET.**
3. Giải nén file `.zip`, chạy trực tiếp file `Godot_v4.x-stable_win64.exe` (Windows) hoặc `Godot.app` (macOS). Không cần cài đặt hay tạo tài khoản.

> Cả team nên dùng **cùng một phiên bản Godot** (hiện là 4.7.2) để tránh lỗi tương thích khi mở project.

### 1.2. Cài VS Code và kết nối với Godot (tùy chọn)

1. Cài **VS Code** từ https://code.visualstudio.com.
2. Trong VS Code, cài extension **godot-tools** (tác giả geequlim).
3. Trong Godot: **Editor → Editor Settings** rồi bật công tắc **Advanced Settings** (góc trên bên phải), sau đó lọc `exec`:
   - Bật **Text Editor → External → Use External Editor**.
   - **Exec Path**: đường dẫn tới VS Code (Windows: `...\Microsoft VS Code\Code.exe`; macOS: `code` sau khi chạy lệnh *Install 'code' command in PATH* trong VS Code).
   - **Exec Flags**: `{project} --goto {file}:{line}:{col}`
4. Mở thư mục project bằng VS Code (**File → Open Folder**). Giữ cửa sổ Godot mở để VS Code nhận gợi ý code.

---

## 2. Mở project

1. Nhận project từ người chia sẻ (file `.zip` hoặc repo Git) và giải nén.
   - **Không cần** thư mục `.godot/` (Godot tự tạo lại, có thể xóa nếu muốn nhẹ).
2. Mở Godot, trong **Project Manager** chọn **Import** (hoặc **Open**), chọn file `project.godot`, bấm **Import & Edit**.
3. Lần đầu mở, Godot sẽ import tài nguyên (model `.glb`, v.v.), đợi thanh tiến trình chạy xong.
4. Nếu VS Code báo gạch đỏ kiểu `Could not find type "..."`: trong Godot chọn **Project → Reload Current Project**, rồi trong VS Code nhấn `Ctrl+Shift+P` → `Developer: Reload Window`. Đây là lỗi nhận diện `class_name`, không phải lỗi code.

### 2.1. Cấu trúc thư mục

```
res://
└── res/
    ├── models/            person.glb (nhân vật nạn nhân)
    ├── scenes/            các file .tscn
    └── scripts/
        ├── core/          game_session.gd   (Autoload "Session")
        ├── input/         drone_input.gd    (Autoload "DroneInput") và các file xử lý input
        ├── flight/        vật lý drone, mô hình, âm thanh
        ├── camera/        camera FPV/TPV, hiệu ứng Thermal / Night Vision
        ├── environment/   địa hình, gió, thời tiết, bầu trời
        ├── mission/       chế độ Cứu hộ (nạn nhân, vật phẩm, chấm điểm)
        ├── race/          chế độ Đua FPV (vòng đua, bấm giờ, huy chương)
        ├── editor/        trình tạo map
        └── ui/            menu chính, HUD, bảng hướng dẫn
```

### 2.2. Autoload bắt buộc

Kiểm tra trong **Project → Project Settings → Globals → Autoload** phải có đúng hai dòng:

| Tên (Node Name) | Script |
|---|---|
| `DroneInput` | `res://res/scripts/input/drone_input.gd` |
| `Session` | `res://res/scripts/core/game_session.gd` |

Thiếu một trong hai thì game báo lỗi `Identifier "DroneInput" / "Session" not declared`. Tên Autoload phải **khác** `class_name` của script (xem lỗi "invalid name" khi thêm Autoload).

### 2.3. Cài đặt project nên kiểm tra

**Project → Project Settings** (bật Advanced Settings):

| Mục | Giá trị |
|---|---|
| Application → Run → Main Scene | `main_menu.tscn` |
| Physics → Common → Physics Ticks per Second | `120` |
| Display → Window → Size → Viewport Width / Height | `1920` / `1080` |
| Display → Window → Size → Resizable | bật |
| Display → Window → Stretch → Mode | `canvas_items` |
| Display → Window → Stretch → Aspect | `expand` |
| Display → Window → V-Sync → Mode | Enabled |

---

## 3. Mở và chạy các scene (`.tscn`)

### 3.1. Cách mở một scene

- Trong dock **FileSystem** (góc dưới bên trái), mở thư mục `res/scenes/` rồi **double-click** file `.tscn`. Scene hiện thành một tab phía trên khung nhìn.
- Hoặc: **Scene → Open Scene...** (`Ctrl+O`), chọn file.
- Nhiều scene có thể mở cùng lúc dưới dạng các tab. Lưu bằng **Ctrl+S** (lưu scene hiện tại) hoặc **Ctrl+Alt+S** (lưu tất cả).

### 3.2. Cách chạy

| Phím | Tác dụng |
|---|---|
| **F5** | Chạy cả game, bắt đầu từ **Main Scene** (menu chính) |
| **F6** | Chạy **scene đang mở trong tab** |
| **F8** | Dừng game |

Lỗi và cảnh báo xem ở tab **Debugger → Errors** (dưới cùng). Nút **Clear** để xóa log cũ trước khi chạy lại.

### 3.3. Các scene trong project

| Scene | Vai trò | Ghi chú |
|---|---|---|
| `main_menu.tscn` | **Menu chính**: chọn map, chế độ chơi, chất lượng đồ họa | Đặt làm Main Scene. Node gốc có 3 ô: **Rescue Scene**, **Race Scene**, **Editor Scene** phải trỏ đúng file `.tscn` |
| `test_flight.tscn` | **Chế độ Cứu hộ** | Có Terrain, Home, Drone, Mission, Payload, Sensor, Weather, Audio, HUD |
| `race_track.tscn` | **Chế độ Đua FPV** | Có Terrain, Course, Race, Drone, RaceHUD |
| `map_editor.tscn` | **Trình tạo map** | Chỉ cần node gốc gắn `map_editor.gd`, mọi thứ còn lại do code tạo |
| `test_input.tscn` | Scene thử input (debug) | Không cần cho game |

**Lưu ý đường dẫn:** các ô scene trong Inspector (`Rescue Scene`, `Race Scene`, `Editor Scene`, `Menu Scene` của node `Nav`) phải trỏ tới file `.tscn`, **không phải `.gd`**. Cách chắc chắn: bấm biểu tượng thư mục cạnh ô rồi chọn trực tiếp file. Nếu bạn di chuyển file, hãy **kéo thả trong dock FileSystem của Godot** (không di chuyển bằng Explorer) để Godot tự cập nhật tham chiếu.

### 3.4. Nếu một scene báo lỗi khi mở

| Lỗi | Cách xử lý |
|---|---|
| `invalid UID ... using text path instead` | Cảnh báo vô hại, nhấn `Ctrl+S` để Godot ghi lại UID |
| `Cannot open file 'res://.../xxx.tscn'` | Sai đường dẫn scene trong Inspector (xem 3.3) |
| Ô tham chiếu (Drone, Terrain...) bị trống | Kéo node tương ứng từ dock Scene vào ô đó |
| `Node configuration warning` ở node `World` | Vô hại: Environment được tạo lúc chạy |
| `Jolt Physics job system exceeded...` | Cảnh báo vàng khi quá nhiều vật va chạm, giảm `Tree Count` của node `Terrain` |
| `WASAPI: GetBufferSize error` | Lỗi driver âm thanh Windows (đổi/rút tai nghe), có thể bỏ qua |

---

## 4. Điều khiển và phím tắt

### 4.1. Điều khiển bay (bàn phím và tay cầm)

| Hành động | Bàn phím | Tay cầm |
|---|---|---|
| Ga lên/xuống | `W` / `S` | Cần trái lên/xuống |
| Xoay mũi trái/phải | `A` / `D` | Cần trái trái/phải |
| Chúi/ngả | `↑` / `↓` | Cần phải lên/xuống |
| Nghiêng trái/phải | `←` / `→` | Cần phải trái/phải |
| Đổi chế độ lái Angle / Acro | `M` | D-Pad ↑ |
| Đổi FPV / TPV | `C` | D-Pad → |
| Đổi nhìn Thường / Nhiệt / Đêm | `V` | D-Pad ← |
| Chọn vật phẩm | `Tab` | RB |
| Thả vật phẩm | `Space` | A |

Game tự chuyển giữa bàn phím và tay cầm, không cần cài đặt.

### 4.2. Phím hệ thống

| Phím | Tác dụng |
|---|---|
| `R` | Chơi lại (cứu hộ: sinh nạn nhân mới; đua: chạy lại cùng đường) |
| `F1` | Bảng hướng dẫn (tạm dừng game) |
| `F2` | Đổi thời tiết (để thử) |
| `F3` | Đường đua mới (chế độ đua) |
| `F4` | Bảng FPS / hiệu năng |
| `F10` | Về menu (hoặc về trình tạo map nếu đang chơi thử) |
| `F11` | Bật/tắt toàn màn hình |
| `T` | Chế độ đua: về vòng trước (phạt +5 giây) |
| `[` / `]` | Giảm/tăng góc nhìn (FOV) camera |

### 4.3. Trình tạo map

Giữ **chuột phải** + `W/A/S/D` để bay camera, `Q/E` xuống/lên, `Shift` nhanh, lăn chuột tiến/lùi. Công cụ `1` đến `5` (cây, nhà, nạn nhân, vòng đua, xóa), `Z/X` xoay vật sắp đặt, `Ctrl+S` lưu, `F10` về menu. Map lưu dạng JSON ở thư mục dữ liệu người dùng (xem mục 6).

---

## 5. Xuất game thành file `.exe`

### 5.1. Cài Export Templates (làm một lần)

1. Trong Godot: **Editor → Manage Export Templates...**
2. Bấm **Download and Install** (cần Internet, khoảng vài trăm MB). Chọn đúng phiên bản trùng với Godot đang dùng.
3. Chờ cài xong rồi đóng cửa sổ.

> Nếu máy không có Internet: tải file `.tpz` từ trang Godot (mục *Export templates*), rồi trong cửa sổ trên chọn **Install From File**.

### 5.2. Tạo cấu hình xuất

1. Vào **Project → Export...**
2. Bấm **Add...** → chọn **Windows Desktop**.
3. Kiểm tra:
   - **Export Path**: bấm biểu tượng thư mục, chọn nơi lưu và đặt tên, ví dụ `build/DroneSimulator.exe`.
   - **Binary Format → Embed PCK**: **bật** để gộp dữ liệu vào một file `.exe` duy nhất (dễ chia sẻ). Nếu tắt, bạn sẽ có 2 file `.exe` và `.pck` phải để chung thư mục.
   - **Binary Format → 64 Bits**: bật.
   - Ở dưới cùng, tick **Export With Debug** thành **tắt** khi xuất bản chính thức.
4. Tab **Resources**: giữ **Export all resources in the project** (mặc định). Model `.glb` và scene đều được đóng gói.
5. Tab **Features** và **Options**: để mặc định. Nếu muốn đổi icon `.exe`, cần cài `rcedit` (tùy chọn, không bắt buộc).

### 5.3. Xuất

1. Trong cửa sổ Export, bấm **Export Project...**
2. Đặt tên file, **bỏ tick "Export With Debug"**, bấm **Save**.
3. Chờ vài chục giây. Kết quả là file `.exe` (và `.pck` nếu không bật Embed PCK).
4. Chạy thử file `.exe` trên máy sạch trước khi gửi cho người khác.

Có thể bấm **Project → Export... → Export All** nếu có nhiều cấu hình.

### 5.4. Chia sẻ cho người khác

- Nén thư mục `build` thành `.zip` rồi gửi (Google Drive, OneDrive...).
- Người nhận chỉ cần giải nén và chạy `.exe`, **không cần cài Godot**.
- Windows có thể hiện cảnh báo **SmartScreen** ("Windows protected your PC") vì file chưa ký số. Chọn **More info → Run anyway**.
- Một số phần mềm diệt virus có thể báo nhầm file mới, hãy để người nhận thêm ngoại lệ nếu cần.

### 5.5. Xuất cho macOS và Linux (tóm tắt)

- Làm tương tự, **Add... → macOS** hoặc **Linux**. Template phải được cài (mục 5.1).
- macOS không ký số sẽ bị Gatekeeper chặn: người dùng chuột phải app → **Open** để cho phép. Phát hành chính thức cần tài khoản Apple Developer để ký và công chứng.

### 5.6. Lỗi thường gặp khi xuất

| Lỗi | Nguyên nhân / cách xử lý |
|---|---|
| `No export template found` | Chưa cài template (mục 5.1) hoặc sai phiên bản |
| Xuất xong chạy báo thiếu scene | Đường dẫn scene sai (xem 3.3), hãy chạy thử bằng F5 trước khi xuất |
| Game xuất ra không có âm thanh/sáng khác bản trong editor | Kiểm tra mức Đồ họa ở menu, và thiết bị âm thanh mặc định của Windows |
| File `.exe` quá lớn | Bình thường (khoảng 100 MB đến 300 MB do model và template) |

---

## 6. Dữ liệu người chơi (không nằm trong project)

Game lưu ở thư mục dữ liệu người dùng. Trong Godot: **Project → Open User Data Folder**. Với bản `.exe` đã xuất, thư mục thường ở `%APPDATA%\Godot\app_userdata\<tên project>\`.

| File / thư mục | Nội dung |
|---|---|
| `maps/*.json` | Map do người chơi tạo (có thể gửi cho đồng đội, chép vào đúng thư mục này) |
| `input_bindings.cfg` | Phím đã gán lại |
| `settings.cfg` | Chất lượng đồ họa |
| `scores.cfg` | Điểm cao chế độ Cứu hộ |
| `race_records.cfg` | Kỷ lục và điểm cao chế độ Đua |

Xóa file `input_bindings.cfg` nếu phím không hoạt động đúng sau khi cập nhật code.

---

## 7. Làm việc nhóm với Git (khuyên dùng)

Tạo file `.gitignore` ở thư mục gốc project:

```
# Godot
.godot/
*.translation
export_presets.cfg      # bỏ dòng này nếu muốn cả team dùng chung cấu hình xuất
build/
```

Quy tắc đề xuất:

1. **Mỗi người sửa scene khác nhau** nếu có thể (file `.tscn` khó gộp khi hai người cùng sửa).
2. Thay đổi code script (`.gd`) tách riêng commit với thay đổi scene.
3. Di chuyển/đổi tên file trong **dock FileSystem của Godot**, không dùng Explorer.
4. Trước khi commit: chạy thử `F5`, vào cả hai chế độ, và đảm bảo tab **Errors** không có lỗi đỏ.

---

## 8. Ghi chú và giấy phép

- Model nhân vật `res/models/person.glb` (PS2 Styled Character V2, Sketchfab, giấy phép Sketchfab Standard): cần ghi nguồn/tác giả trong credits và đọc kỹ điều khoản nếu phát hành rộng rãi.
- Nếu xóa file `person.glb`, game tự dùng nhân vật dựng bằng code.
- Mọi âm thanh (động cơ, gió, mưa, còi pin) được tạo bằng code, không cần file ngoài.
