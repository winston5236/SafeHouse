# Feng Shui（風水）

> 掃描房間，在瀏覽器裡重建 3D 模型，並用「模組（DLC）」檢查家裡的安全、節能與病蟲害風險，最後給出一個一眼就能看懂的 **Home quality** 分數。
> Scan a room with an iPhone, rebuild it in 3D in the browser, and run safety / energy / pest checks on it, summarised as one **Home quality** score.

- 專案名稱 Project name: **Feng Shui**（原名 Home Guardian；更早為 "le rat is in da house"）
- Repo 資料夾: `SafeHouse`
- 版本 Build: **2026-10-02**（概念原型 / concept prototype）
- 全部在本機執行，**沒有後端伺服器**。Everything runs locally; there is no backend.

---

## 1. 這個版本能做什麼

**掃描與模型**
- iOS App 用 LiDAR（Apple RoomPlan）掃描房間，存成 `.json`（牆、門、窗、家具的位置與尺寸）和 `.usdz`。
- 掃描時可以在畫面上點選標記 **冷氣、吊扇、立扇**（RoomPlan 不會自動辨識它們），標記會存進 JSON 的 `devices`。
- 網頁讀入 `.json` 後用 Three.js 重建房間；地板高度自動歸零，牆面自動對齊格線。
- 物件類型來自掃描結果，可以在 **Objects**（左上角按鈕）修改類型、尺寸、位置、旋轉，也可新增或刪除。
- 房間上方有一片只用來顯示的**平面天花板**（高度取最高的牆）。

**匯入後的冷氣設定**
- 匯入 JSON 後會跳出視窗：選**品牌**、選**位置**（程式建議的前三個位置、點選牆面，或沿用模型裡已有的冷氣）。
- 程式依房間自動判斷**尺寸與噸數**（見第 5 節）。

**七個模組（右側面板上的圖示分頁）**

| 分頁 | 內容 |
|---|---|
| Air 空氣 | 室內 PM2.5 與分級、曲線 |
| Energy 節能 | 即時功率、累計度數、電費估算 |
| Cooling 降溫 | 西曬窗日射得熱、遮陽方案、A/B/C/D 情境、冷氣與風扇位置建議、氣流動畫、設備清單、冷氣尺寸與噸數 |
| Infestation 病蟲害 | 家具旁隱蔽縫隙、廚房靠近出入口、潮濕、入侵路徑（風險條件，**不是偵測**） |
| Fire 失火 | 空氣盒放置位置建議、MQTT 連線、溫度／CO₂／濕度曲線、事件紀錄、手機推播設定 |
| Typhoon 颱風 | 逐扇窗的防護建議、材料尺寸、窗邊該移開的物品 |
| Power outage 停電準備 | 備品勾選清單、急難包位置、冰箱保冷、大功率設備 |

**Home quality（右上角視窗）**
- 三個面向：**安全、節能、害蟲/生物**，各有百分比與一隻寵物（心情隨分數變化）。
- 總分取**最低的面向**。沒有資料的項目標為「等待資料」，**不計分**。
- 點寵物可篩選該面向，點圖示會跳到對應分頁；可標記「已完成」讓分數回升。
- 顯示**已節省的電（kWh）、CO₂（kg）與金額（NT$）**，另有每月數字與「還可再省」。
- 有「颱風警報中」示範開關，打開後颱風與停電準備的扣分加重。

**其他**
- 英文／中文介面切換（標題列按鈕）。
- 警示：頁面警示條、警報聲、手機推播（ntfy）。
- 離線偵測：感測盒 20 秒沒資料視為離線。

---

## 2. 快速開始（只用網頁）

1. 用瀏覽器開啟 `index.html`。**第一次需要網路**，因為會從 CDN 載入 Three.js 與 mqtt.js。
2. 按 **Load demo living room**（範例客廳），或 **Import scan (.json)** 匯入掃描檔。
3. 匯入掃描檔後，先完成冷氣設定視窗，再到各分頁查看。
4. 沒有硬體時，在 Air／Energy／Fire 分頁用 **Simulate** 下拉選單示範：正常、悶（CO₂ 上升）、疑似火災、空污、用電過載。

---

## 3. iOS App（掃描）

檔案：`le_rat_is_in_da_houseApp.swift`、`collaborate file RoomScanCaptureView.swift`、`DeviceMarker.swift`

**需求**：iOS 16 以上、有 LiDAR 的實體機（iPhone 12 Pro 以上或 iPad Pro）。**模擬器不能掃描。**

**Xcode 設定**
1. 把三個 `.swift` 檔加入專案（勾選 target membership）。
2. 把 `index.html` 加入專案並確認在 **Build Phases → Copy Bundle Resources** 內（App 內嵌網頁從 bundle 載入它）。
3. Target → Info 加入：
   - `Privacy - Camera Usage Description`（例如「用來掃描房間」）
   - `Application supports iTunes file sharing` = YES
   - `Supports opening documents in place` = YES
4. Minimum Deployments 設為 iOS 16.0 以上（`isInspectable` 需 16.4 以上才有效）。
5. Signing & Capabilities 設定 Team，插上實體機執行。

**使用**
1. 按開始掃描，沿著牆走一圈，鏡頭要對到牆的頂端與天花板邊緣（牆高會影響天花板高度）。
2. 掃描中可用 *Mark AC / Ceiling fan / Floor fan* 點選設備：冷氣要點**對角的兩個角**，吊扇點吊扇正下方的天花板，立扇點它站的地板位置。
3. 結束後 App 把 `RoomScan-<時間>.json` 與 `.usdz` 存進 App 的 Documents，不會上傳。
4. 按 **View in Feng Shui** 會用內嵌網頁開啟，並自動把 JSON 交給網頁；也可以用 **Share** 傳到電腦，再用網頁的 Import 匯入。

---

## 4. 資料格式

**掃描 JSON**：RoomPlan 的 `CapturedRoom` 編碼，欄位 `walls / doors / windows / openings / objects`，每項有 `transform`、`dimensions`、`category`。匯入器同時接受 `transform` 的扁平或巢狀陣列，以及字串或 `{名稱:{}}` 形式的 `category`。

**冷氣與風扇標記**（頂層 `devices` 陣列）
```json
{ "type": "ac", "position": [x, y, z], "normal": [nx, ny, nz], "size": [寬, 高] }
{ "type": "ceilingFan", "position": [x, y, z], "normal": [nx, ny, nz] }
{ "type": "fan", "position": [x, y, z], "normal": [nx, ny, nz] }
```
冷氣會被自動吸附到最近的牆；如果離牆太遠，頁面頂端會出現警告。

**感測資料（MQTT，JSON）**
```json
{ "temp": 26.5, "co2": 650, "hum": 55, "pm25": 12, "power": 320, "kwh": 1.2 }
```
`pm25`、`power`、`kwh` 可省略；沒給 `kwh` 時由 `power` 積分。預設 broker `wss://broker.emqx.io:8084/mqtt`、預設主題 `home-guardian/demo/sensor`（沿用舊名稱，可在 Fire 分頁修改）。**公開測試 broker 僅供展示，請勿傳送敏感資料。**

**給 App 的接口（`window`）**
- `importScanJSONText(text)`、`importScanJSONBase64(b64)`：匯入掃描。
- `setDevice(id, {on, w, dir, set, swing, ...})`：控制設備狀態（`id` 為物件編號）。
- `notify(level, message)`：每次新警示都會呼叫（1 注意、2 警報、3 離線）；在 iOS 內嵌時會轉成 `nativeBridge` 訊息。
- `nativeBridge` 訊息：`scanImported`（牆與物件數，App 已處理）、`notify`（App 端目前尚未處理，可自行接上本機通知）。

---

## 5. 規則與假設（請當作示範值）

**警示門檻**
- CO₂：≥ 1000 ppm 注意、≥ 2000 ppm 警報（多半是通風不良，不是火災）。
- 溫度：≥ 40 °C 注意；≥ 57 °C、1 分鐘內升溫 ≥ 8 °C，或 ≥ 45 °C 且 CO₂ 快速上升 → 疑似火災。
- 濕度 ≥ 75% 注意；PM2.5 ≥ 35.5 µg/m³ 注意（分級參考臺灣空氣品質指標）；功率 ≥ 1500 W 注意（一般 110 V／15 A 插座迴路上限約 1650 W）。
- 紅色警報：響警報聲並推播；注意等級：靜音推播，同類型 10 分鐘最多一次。

**颱風**：玻璃面積 ≥ 1.5 m² 或高度 ≥ 1.8 m 視為高風險，建議防颱板（比窗大 0.2 m）；一般窗貼米字膠帶。膠帶只減少碎片飛散，不增加玻璃強度。

**降溫模型**：日射得熱＝西曬玻璃面積 × SHGC × 日射強度；耗電＝（日射＋每人 75 W＋內熱）÷ COP（預設 3），計算 08–22 時。日射曲線、遮陽方案的 SHGC／VLT 都是**示範值**，請換成氣象署資料與實際產品規格。窗戶方位無法從掃描得知，需自行勾選朝西的窗。

**冷氣尺寸與噸數**：尖峰負荷＝（每 m² 100 W × 天花板高 ÷ 2.5 ＋ 西曬日射（SHGC × 540 W/m² 峰值）＋ 每人 130 W ＋ 設備）× 1.1；從 2.2、2.8、3.6、4.5、5.6、7.1、8.0 kW 選最接近且不小於負荷的規格；1 噸約 3.5 kW。冷氣運轉功率預設為滿載輸入的一半左右（變頻平均）。**品牌目前只記錄，不影響數值。** 僅為規劃估算，請由安裝人員確認。

**評分**：每個模組產生檢查項目（有扣分上限）；安全含颱風、窗邊物品、熱源靠近家具、空氣盒連線、即時火災與空品、停電準備；節能含遮陽、風扇＋調高設定溫度、冷氣氣流與位置、設備；害蟲含狹縫、廚房靠近出入口、濕度。權重寫在 `checks()`，可調整。

**節省的電與 CO₂**：依已採取的做法（遮陽、風扇、冷氣設定溫度高於 24 °C）以模型估算，**不是實測**。CO₂ 係數 0.471 kg/度（2025 年度民生住宅電力排碳係數，經濟部能源署公告），每年可能更新，改程式裡的 `EF`。電價預設 3 元/度，可在 Energy 分頁修改。

---

## 6. 目前的限制（請誠實對待）

- 掃描 JSON 格式與裝置標記**尚未用真實裝置輸出完整驗證**（`DeviceMarker.swift` 內也註明未在實機測過）。
- **害蟲項目只看環境誘因，不是偵測**；目前沒有害蟲感測器。
- **沒有入侵偵測**。
- 判斷邏輯在網頁裡：**網頁關掉就不會判斷與推播**。正式使用需要常駐主機。
- 本系統為輔助提醒，**不能取代合格的火警偵測器與消防設備**；空氣盒沒有煙霧感測。
- 天花板只顯示平面；斜面、挑高與天花板上的物件不處理。
- 離線使用需把 Three.js 與 mqtt.js 從 CDN 改成隨 App 附帶的檔案。
- 空氣盒與智慧插座的硬體與韌體不在此 repo。

---

## 7. 隱私

- 掃描與模型只留在本機，不會上傳。
- 網路只用於：載入 CDN 函式庫、你設定的 MQTT broker、以及 ntfy 推播。
- 推播只送警示文字，不含模型或原始數據。ntfy 主題名稱等同密碼，請勿公開。
- 瀏覽器只儲存三項偏好：`hgTopic`（ntfy 主題）、`hgLang`（語言）、`hgPets`（寵物選擇）。

---

## 8. 檔案

| 檔案 | 用途 |
|---|---|
| `index.html` | 整個網頁（單一檔案；Three.js 與 mqtt.js 來自 CDN） |
| `collaborate file RoomScanCaptureView.swift` | 掃描畫面、儲存、內嵌網頁與 JS 橋接 |
| `DeviceMarker.swift` | 掃描時點選標記冷氣與風扇 |
| `le_rat_is_in_da_houseApp.swift` | App 進入點 |
