# Phiếu Phản Ánh — K4 Level 3B, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder dưới mỗi câu bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Trần Xuân Đức  Mã học viên: 2A202602768

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống: mình tạo service mới trên Railway, thêm Redis, set `REDIS_URL`
nhưng quên set `AGENT_API_KEY` rồi bấm deploy. Nếu code có mặc định
`"changeme"`, app vẫn khởi động, health check xanh, dashboard báo "Active" —
mình tưởng mọi thứ ổn. Nhưng khóa `"changeme"` nằm công khai trong repo GitHub,
bot quét repo hoặc ai đọc code đều gọi được `/ask` bằng khóa đó và tiêu ngân sách
LLM của mình; mình chỉ phát hiện khi nhìn hóa đơn cuối tháng.

Không có mặc định thì `Settings()` ném `ValidationError: agent_api_key Field
required` ngay lúc import, container crash, deploy báo **failed** trong log
khi mình còn đang ngồi nhìn màn hình. Lỗi hiện ra ở thời điểm rẻ nhất để sửa
(lúc deploy) thay vì thời điểm đắt nhất (sau khi đã bị lạm dụng).

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Log thật khi chạy `uvicorn app.main:app` và gọi `/ask` lần thứ hai với user `sv01`:

```json
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-29T14:31:39.181881+00:00", "user_id": "sv01", "tokens_in": 43, "tokens_out": 47, "cost_usd": 3.465e-05}
```

Hai việc làm được mà `print("đã trả lời xong")` không làm được:

1. **Tổng hợp chi phí theo user**: lọc `event == "ask_completed"`, group by
   `user_id`, sum `cost_usd` → biết ngay user nào tiêu nhiều tiền nhất hôm nay
   (vd. `jq -s 'group_by(.user_id) | map({u: .[0].user_id, cost: map(.cost_usd) | add})'`).
2. **Cảnh báo tự động**: đặt alert trên log platform kiểu "số dòng có
   `level == "error"` trong 5 phút > N" hoặc "`tokens_in` > 10000" (prompt
   phình bất thường). Với chuỗi tự do thì máy không tách được trường nào là số
   token, trường nào là user.

Ngoài ra `timestamp` ISO-8601 UTC giúp ghép log của nhiều container theo đúng
thứ tự thời gian.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f Dockerfile.single -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu, `python:3.11`) | 1.73 GB (nén khi push: 436 MB) |
| Multi-stage (`python:3.11-slim`) | 298 MB (nén khi push: 64.3 MB) |

Đo bằng `docker images` (Docker 29.8.1, máy Mac arm64): bản multi-stage nhỏ
hơn khoảng 5,8 lần.

Giải thích: phần dung lượng chênh lệch đó là những gì?

Chênh lệch đến từ ba nguồn:

1. **Base image**: `python:3.11` bản đầy đủ dựa trên Debian đầy đủ, kèm sẵn
   `gcc`, `make`, header dev (`libssl-dev`, `libpq-dev`...), `git`, ImageMagick
   và rất nhiều thư viện hệ thống — riêng base đã ~1GB. `python:3.11-slim` chỉ
   giữ Python runtime và vài lib tối thiểu (~130MB).
2. **Công cụ build**: ở bản multi-stage, `build-essential` chỉ được cài trong
   stage `builder`; stage `runtime` chỉ `COPY --from=builder /install` — tức
   các package Python đã cài xong — nên compiler không bao giờ vào image cuối.
3. **Rác từ `COPY . .`**: bản 1 stage copy cả `.git`, `tests`, `.venv`, cache
   pip (không có `--no-cache-dir`) vào image. Bản mới chỉ copy `app/` và
   `utils/`, và `.dockerignore` loại `.git`, `.venv`, `.env`, `__pycache__`.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Với Dockerfile hiện tại:

- **Dùng lại cache**: toàn bộ stage `builder` (`FROM`, `apt-get install
  build-essential`, `COPY requirements.txt`, `RUN pip install`) vì
  `requirements.txt` không đổi; ở stage runtime: `FROM`, `ENV`,
  `COPY --from=builder /install`, `RUN useradd`, `WORKDIR`.
- **Chạy lại**: chỉ từ `COPY app ./app` trở xuống (`COPY utils`, `USER`,
  `HEALTHCHECK`, `CMD` — mấy lệnh sau chỉ là metadata nên gần như tức thì).
  Build lại mất vài giây.

Nếu đặt `COPY . .` trước `RUN pip install`: checksum của layer `COPY` đổi mỗi
khi bất kỳ file nào đổi → Docker vô hiệu hóa cache từ layer đó trở đi →
`pip install` chạy lại toàn bộ, tải và cài lại FastAPI, uvicorn, redis...
mỗi lần sửa một dấu phẩy, build chậm hơn hàng chục lần và CI tốn thời gian.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện:

1. Code có lỗ hổng cho phép thực thi lệnh (vd. một thư viện parse input có
   RCE, hoặc mình lỡ `eval`/`subprocess` với dữ liệu người dùng).
2. Kẻ tấn công chạy được shell **bên trong container với UID 0 (root)**.
3. Là root trong container, họ ghi được mọi file trong image, cài công cụ,
   đọc biến môi trường chứa secret, và — quan trọng nhất — UID 0 trong
   container trùng UID 0 trên host (nếu không bật user namespace).
4. Chỉ cần một cấu hình lỏng (mount `/var/run/docker.sock`, mount thư mục
   host, `--privileged`, hoặc một lỗ hổng kernel/runc như CVE-2019-5736) là
   họ thoát ra host với quyền root → kiểm soát cả máy và các container khác.

`USER appuser` (UID 10001) cắt chuỗi ở **bước 2–3**: shell thu được chỉ là
user thường, không ghi được vào hệ thống file của image ngoài thư mục của nó,
không cài package, và nếu thoát được ra host thì cũng chỉ là UID 10001 không
có quyền gì — các kỹ thuật leo thang kiểu ghi đè binary `runc` cần quyền root
đều thất bại.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

**20 request trong 2 giây.** Cách làm: gửi 10 request lúc 10:00:59 — chúng
thuộc bộ đếm của phút 10:00 (chưa tới hạn mức 10). Đến 10:01:00 bộ đếm reset
về 0, gửi tiếp 10 request lúc 10:01:00–10:01:01 — thuộc phút 10:01, cũng
"hợp lệ". Tổng 20 request trong khoảng ~2 giây, gấp đôi hạn mức.

Với sliding window của mình, lúc 10:01:01 hàm `hit_count` đếm mọi request có
timestamp trong `(now − 60, now]`, tức vẫn thấy 10 request lúc 10:00:59 → request
thứ 11 bị 429. Mình kiểm chứng bằng test: limit=2, gọi ở t=1000 và t=1001, lần
t=1002 bị chặn, phải tới t=1065 (hai request cũ đã ra khỏi cửa sổ) mới qua.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

Khác nhau: rate limit giới hạn **tần suất** (số request trong 60 giây, trả
429, tự hồi sau 1 phút) — bảo vệ hạ tầng khỏi bị dội. Cost guard giới hạn
**tổng tiền** trong tháng (cộng dồn `cost_usd` theo `cost:<user>:<YYYY-MM>`,
trả 402, chỉ hồi khi sang tháng) — bảo vệ ví tiền.

- **Rate limit cho qua, cost guard chặn**: một user gửi đều đặn 5
  request/phút (dưới hạn mức 10), mỗi request kèm câu hỏi dài và lịch sử 20
  lượt nên tốn nhiều token. Chạy suốt vài ngày thì tổng chi tiêu vượt 10 USD →
  từ đó mọi request đều 402 dù tần suất vẫn thấp.
- **Cost guard cho qua, rate limit chặn**: một script lỗi gọi `/ask` 50 lần
  trong 5 giây với câu hỏi "hi" — mỗi lần chỉ tốn ~0.00002 USD, ngân sách còn
  gần nguyên, nhưng từ request thứ 11 trong phút đó đã bị 429 (mình thấy rõ khi
  chạy vòng lặp curl: 200 200 200 rồi 429 với limit=3).

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

1. t=0: Redis mất kết nối (restart, failover, mạng chập chờn).
2. Cả 3 container gọi `ping()` thất bại → endpoint gộp trả 503 ở cả 3.
3. Sau vài lần probe thất bại liên tiếp (vd. 3 × 10 giây), orchestrator kết
   luận cả 3 container **chết** → gửi SIGTERM/SIGKILL và **restart cả 3 cùng
   lúc**. Load balancer cũng rút cả 3 → không còn instance nào nhận traffic,
   user thấy 502/503 toàn bộ.
4. t≈30s: Redis sống lại, nhưng cả 3 container đang khởi động lại (cold start,
   import, kết nối) — downtime kéo dài thêm; nếu Redis còn chập chờn thì chúng
   rơi vào vòng crash-loop, có thể bị platform đánh dấu failed.
5. Request đang xử lý dở lúc bị restart bị cắt ngang.

Tách ra thì: `/health` (không chạm Redis) vẫn 200 → không container nào bị
restart; `/ready` 503 → LB tạm ngừng gửi traffic; Redis về là `/ready` 200 lại
ngay, không cold start. Sự cố 30 giây chỉ gây 30 giây gián đoạn, không bị
khuếch đại.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

Với Redis, `history_length` tăng đều **0 → 2 → 4 → 6 → 8** (mỗi lượt thêm 1
message user + 1 message assistant), bất kể request rơi vào container nào,
vì cả 3 container cùng đọc/ghi key `history:sv01` trong một Redis. Mình thấy
đúng dãy 0, 2, 4 khi chạy thử local, và test `test_state_khong_nam_trong_process`
mô phỏng 2 container dùng chung Redis đều thấy cùng dữ liệu.

Nếu lưu trong dict Python, mỗi container có dict riêng trong RAM, nên với
round-robin qua 3 container, con số sẽ **nhảy lung tung** kiểu 0, 0, 0, 2, 2,
2, 4, 4, 4 (mỗi container chỉ nhớ phần nó đã phục vụ) — agent "mất trí nhớ"
ngẫu nhiên giữa hai câu liên tiếp. Thêm nữa, container nào restart (deploy
mới, crash) thì lịch sử trong nó mất sạch về 0.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

**Lỗi:** sau khi nối repo GitHub vào Railway, service build xong và báo
Online, nhưng biến `AGENT_API_KEY` không vào được app. Mình đã tạo biến này ở
**Project Settings → Shared Variables** chứ không phải trong service. Trên
dashboard, cạnh tên biến có biểu tượng `!` màu vàng, nút **SHARE** chưa bấm, và
dòng environment `production` ghi **0 variables**. Lúc đó project cũng chưa có
Redis, nên `REDIS_URL` không có giá trị để `/ready` kết nối.

**Tìm nguyên nhân:** Shared Variables chỉ là biến dùng chung ở cấp project.
Railway chỉ đưa biến vào container khi biến được đặt trong service hoặc được
SHARE cho service. Biểu tượng `!` và con số "0 variables" cho thấy chưa service
nào nhận biến.

**Cách sửa:**
1. `+ Add → Database → Redis` để tạo Redis (kèm `redis-volume`).
2. Vào tab **Variables** của service agent, thêm `AGENT_API_KEY`,
   `REDIS_URL=${{Redis.REDIS_URL}}`, `RATE_LIMIT_PER_MINUTE`,
   `MONTHLY_BUDGET_USD`, `LOG_LEVEL`. Railway hiện "Apply 5 changes"; bấm
   **Deploy** thì biến mới có hiệu lực. Trên sơ đồ xuất hiện mũi tên agent →
   Redis, tức tham chiếu đã đúng.
3. **Settings → Networking → Generate Domain** vì service đang ở trạng thái
   "Unexposed service", chưa có URL công khai.

**Kết quả:** `/health` trả 200, `/ready` trả `{"status":"ready","redis":true}`,
`/ask` không có key trả 401, có key trả 200, gọi 15 lần liên tiếp thì bị 429.

Thêm một điểm dễ nhầm: mở URL gốc trên trình duyệt thấy
`{"detail":"Not Found"}`. Đó không phải lỗi deploy. App chỉ định nghĩa
`/health`, `/ready`, `/ask`, nên FastAPI trả 404 cho `/`.
