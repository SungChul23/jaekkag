# 재깍 - 4일차 부하·장애·정합성 검증 시나리오

## 테스트 순서
```
# 1. 재고소진 전용 상품 세팅
# SQL: UPDATE master_inventory SET stock = 15 WHERE product_id = '104';

# 2. 평상시
k6 run load-test/order-test.js

# 3. 스파이크 (터미널 B/C에 kubectl -w, Grafana 켜두고)
k6 run load-test/spike-test.js

# 4. 스파이크 도중 Worker 장애 발생
kubectl delete pod -n ecommerce <worker파드>

# 5. 재고소진
k6 run load-test/stockout-test.js

# 6. 중복 이벤트
.\load-test\duplicate-test.ps1

# 7. 최종 정합성 SQL 확인 + 재고 원복
# SQL: UPDATE master_inventory SET stock = 1000 WHERE product_id = '104';
```


## 사전 정보

```
BASE_URL = http://k8s-ecommerc-ecommerc-4a419899c8-564158823.us-east-1.elb.amazonaws.com
격리 상품 = product_id "104" (재고소진 전용, 다른 시나리오는 사용하지 않음)
인프라 = t3.medium x2 노드, Kinesis 3샤드, Publisher 배치 500개
```

폴더 구조:
```
load-test/
├── order-test.js       [1] 평상시 정상 주문
├── spike-test.js        [2] 타임세일 부하 급증
├── stockout-test.js     [5] 인기 상품 재고 소진
└── duplicate-test.ps1   [7] 중복 이벤트 발행
```

[3][4][6][8]은 스크립트 파일이 아니라 kubectl/CloudWatch/SQL 명령으로 진행.

---

## [1] 평상시 - 정상 주문

### `load-test/order-test.js`
```javascript
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://k8s-ecommerc-ecommerc-4a419899c8-564158823.us-east-1.elb.amazonaws.com';

// 104는 재고소진 전용이라 여기서 제외
const PRODUCT_IDS = ['101', '102', '103', '201', '202', '203', '204', '301', '302', '303', '304'];

export const options = {
  scenarios: {
    normal_order: {
      executor: 'constant-vus',
      vus: 5,
      duration: '20s',
    },
  },
};

export default function () {
  const payload = JSON.stringify({
    product_id: PRODUCT_IDS[Math.floor(Math.random() * PRODUCT_IDS.length)],
    quantity: Math.floor(Math.random() * 3) + 1,
  });

  const res = http.post(`${BASE_URL}/orders`, payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  check(res, {
    'status is 201': (r) => r.status === 201,
    'has order_id': (r) => JSON.parse(r.body).order_id !== undefined,
  });
}
```

### 실행
```powershell
k6 run load-test/order-test.js
```

### 확인
```sql
SELECT * FROM orders ORDER BY order_id DESC LIMIT 5;
SELECT * FROM outbox_events ORDER BY created_at DESC LIMIT 5;
```

---

## [2] 타임세일 시작 - k6 부하 급증

t3.medium x2, 샤드 3, Publisher 배치 500 기준으로 3,000이 아니라 **400 RPS 피크**로 설정.

### `load-test/spike-test.js`
```javascript
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://k8s-ecommerc-ecommerc-4a419899c8-564158823.us-east-1.elb.amazonaws.com';
const PRODUCT_IDS = ['101', '102', '103', '201', '202', '203', '204', '301', '302', '303', '304'];

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: 20,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 200,
      stages: [
        { target: 100, duration: '10s' },  // 서서히 증가
        { target: 400, duration: '20s' },  // 타임세일 피크
        { target: 400, duration: '20s' },  // 피크 유지 -> HPA 반응 관찰
        { target: 0, duration: '10s' },    // 종료
      ],
    },
  },
};

export default function () {
  const payload = JSON.stringify({
    product_id: PRODUCT_IDS[Math.floor(Math.random() * PRODUCT_IDS.length)],
    quantity: Math.floor(Math.random() * 3) + 1,
  });

  const res = http.post(`${BASE_URL}/orders`, payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  check(res, { 'status is 201': (r) => r.status === 201 });
}
```

### 실행 (터미널 A)
```powershell
k6 run load-test/spike-test.js
```

---

## [3] Order API 부하 증가, HPA 작동 (관찰만)

k6 스파이크가 도는 동안 별도 터미널에서 실행.

```powershell
kubectl get hpa -n ecommerce -w
kubectl get pods -n ecommerce -w
```

---

## [4] Kinesis 이벤트 급증, Worker lag 관측 (관찰만)

```powershell
aws cloudwatch get-metric-statistics `
  --namespace AWS/Kinesis `
  --metric-name GetRecords.IteratorAgeMilliseconds `
  --dimensions Name=StreamName,Value=ecommerce-order-events `
  --start-time (Get-Date).AddMinutes(-5).ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --period 60 --statistics Maximum
```

Grafana 대시보드가 켜져 있으면 그걸로 대체 가능 (`outbox_pending_events` 패널도 함께 확인).

### 임계 확인 (부하 종료 후)
```powershell
aws cloudwatch get-metric-statistics `
  --namespace AWS/Kinesis `
  --metric-name WriteProvisionedThroughputExceeded `
  --dimensions Name=StreamName,Value=ecommerce-order-events `
  --start-time (Get-Date).AddMinutes(-5).ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --period 60 --statistics Sum
```
0이면 여유 있음 -> 다음 리허설엔 600~800으로 올려도 됨.

---

## [5] 인기 상품 재고 소진 - SUCCESS/OUT_OF_STOCK

### 테스트 전: 격리 상품(104) 재고 낮게 세팅
```sql
UPDATE master_inventory SET stock = 15 WHERE product_id = '104';
```

### `load-test/stockout-test.js`
```javascript
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://k8s-ecommerc-ecommerc-4a419899c8-564158823.us-east-1.elb.amazonaws.com';

export const options = {
  scenarios: {
    stockout: {
      executor: 'constant-vus',
      vus: 10,
      duration: '10s',
    },
  },
};

export default function () {
  const payload = JSON.stringify({
    product_id: '104',
    quantity: 1,
  });

  const res = http.post(`${BASE_URL}/orders`, payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  check(res, { 'request sent': (r) => r.status === 201 || r.status === 200 });
}
```

### 실행
```powershell
k6 run load-test/stockout-test.js
```

### 확인
```sql
SELECT status, COUNT(*) FROM processed_events pe
JOIN orders o ON pe.order_id = o.order_id
WHERE o.product_id = '104'
GROUP BY status;
-- SUCCESS는 15건까지만, 나머지는 OUT_OF_STOCK이어야 함

SELECT stock FROM master_inventory WHERE product_id = '104';
-- 반드시 0 이상, 음수면 버그
```

### 테스트 후: 원복 (104는 이 케이스만 사용하므로 다른 케이스엔 영향 없음)
```sql
UPDATE master_inventory SET stock = 1000 WHERE product_id = '104';
```

---

## [6] Worker 강제 장애 - Pod 재생성, 과거 이벤트 재처리

k6 스파이크([2])가 도는 도중, 또는 [1]을 몇 건 더 쏘면서 실행.

```powershell
# Worker 파드 목록 확인
kubectl get pods -n ecommerce -l app=inventory-worker

# 하나 강제 삭제
kubectl delete pod <파드이름> -n ecommerce
```

### 확인
```powershell
# 자동 재생성 관찰
kubectl get pods -n ecommerce -l app=inventory-worker -w
```
```powershell
# 새 파드가 이전 체크포인트부터 이어받는지 로그 확인
kubectl logs -n ecommerce <새파드이름> --tail=50
```

---

## [7] DUPLICATE 감지 - 같은 event_id 두 번 발행

Order API로는 매번 새 event_id가 생겨서 재현 불가 -> Kinesis에 직접 같은 payload 두 번 발행.

### `load-test/duplicate-test.ps1`
```powershell
$eventId = [guid]::NewGuid().ToString()
$eventJson = @{
    event_id = $eventId
    event_type = "ORDER_CREATED"
    order_id = 999999
    product_id = "101"
    quantity = 1
    created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json -Compress

Write-Host "event_id: $eventId"

# 같은 이벤트 2번 발행
aws kinesis put-record --stream-name ecommerce-order-events --partition-key "999999" --data $eventJson
Start-Sleep -Seconds 2
aws kinesis put-record --stream-name ecommerce-order-events --partition-key "999999" --data $eventJson
```

### 실행
```powershell
.\load-test\duplicate-test.ps1
```

### 확인
```sql
SELECT * FROM processed_events WHERE order_id = 999999;
-- 1건만 (SUCCESS), Worker 로그에서 두 번째는 DUPLICATE로 스킵됐는지 확인

SELECT stock FROM master_inventory WHERE product_id = '101';
-- 재고가 한 번만 차감됐는지 (두 번 안 깎였는지) 이전 값과 비교
```

```powershell
kubectl logs -n ecommerce <worker파드이름> --tail=30 | Select-String "999999"
```

> 참고: Worker 로그 포맷이 실제로 event_id를 그대로 찍는지는 3번(차현지) 코드 기준으로 확인 필요.

---

## [8] 부하 종료 - 최종 정합성 확인

모든 테스트가 끝난 뒤 한 번에 확인.

```sql
-- Outbox 적체 없는지 (PENDING/FAILED가 0에 수렴해야 함)
SELECT publish_status, COUNT(*) FROM outbox_events GROUP BY publish_status;

-- 처리 결과 분포
SELECT status, COUNT(*) FROM processed_events GROUP BY status;

-- 재고 음수 절대 없어야 함
SELECT * FROM master_inventory WHERE stock < 0;
```

```powershell
# Pod 다시 정상 개수로 줄어드는지
kubectl get hpa -n ecommerce
kubectl get pods -n ecommerce
```

---

## 전체 리허설 순서

```powershell
# 1. 재고소진 전용 상품 세팅
# SQL: UPDATE master_inventory SET stock = 15 WHERE product_id = '104';

# 2. 평상시
k6 run load-test/order-test.js

# 3. 스파이크 (터미널 B/C에 kubectl -w, Grafana 켜두고)
k6 run load-test/spike-test.js

# 4. 스파이크 도중 Worker 장애 발생
kubectl delete pod -n ecommerce <worker파드>

# 5. 재고소진
k6 run load-test/stockout-test.js

# 6. 중복 이벤트
.\load-test\duplicate-test.ps1

# 7. 최종 정합성 SQL 확인 + 재고 원복
# SQL: UPDATE master_inventory SET stock = 1000 WHERE product_id = '104';
```

---

## DB 스키마 참고

**orders**
```
CREATE TABLE orders (
    order_id      BIGINT       AUTO_INCREMENT PRIMARY KEY,
    product_id    VARCHAR(10)  NOT NULL,
    quantity      INT          NOT NULL,
    order_status  ENUM('CREATED','CONFIRMED','CANCELLED')  NOT NULL DEFAULT 'CREATED',
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_product_id (product_id),
    INDEX idx_created_at (created_at)
);
```

**outbox_events**
```
CREATE TABLE outbox_events (
    id            BIGINT       AUTO_INCREMENT PRIMARY KEY,
    event_id      VARCHAR(36)  NOT NULL UNIQUE,
    event_type    VARCHAR(50)  NOT NULL,
    order_id      BIGINT       NOT NULL,
    product_id    VARCHAR(10)  NOT NULL,
    quantity      INT          NOT NULL,
    publish_status ENUM('PENDING','PUBLISHED','FAILED') NOT NULL DEFAULT 'PENDING',
    retry_count   INT          NOT NULL DEFAULT 0,
    last_error    TEXT         NULL,
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at  DATETIME     NULL,

    INDEX idx_status_created (publish_status, created_at)
);
```

**master_inventory**
```
CREATE TABLE IF NOT EXISTS master_inventory (
    product_id       VARCHAR(10)  NOT NULL,
    model_name       VARCHAR(30)  NOT NULL,
    color_name       VARCHAR(30)  NOT NULL,
    stock_quantity   INT          NOT NULL,
    updated_at       DATETIME(6)  NOT NULL
                                  DEFAULT CURRENT_TIMESTAMP(6)
                                  ON UPDATE CURRENT_TIMESTAMP(6),

    PRIMARY KEY (product_id),

    CONSTRAINT uq_master_inventory_model_color
        UNIQUE (model_name, color_name),

    CONSTRAINT chk_master_inventory_stock
        CHECK (stock_quantity >= 0),

    CONSTRAINT chk_master_inventory_model
        CHECK (
            model_name IN ('FOLD', 'FLIP', 'ULTRA')
        ),

    CONSTRAINT chk_master_inventory_color
        CHECK (
            color_name IN ('BLACK', 'WHITE', 'LAVENDER', 'GRAY')
        )
);
```

**processed_events**
```
CREATE TABLE IF NOT EXISTS processed_events (
    event_id         CHAR(36)      NOT NULL,
    order_id         BIGINT        NOT NULL,
    product_id       VARCHAR(10)   NOT NULL,
    model_name       VARCHAR(30)   NOT NULL,
    color_name       VARCHAR(30)   NOT NULL,
    quantity         INT           NOT NULL,
    process_status   VARCHAR(30)   NOT NULL,
    error_message    TEXT          NULL,
    processed_at     DATETIME(6)   NOT NULL
                                   DEFAULT CURRENT_TIMESTAMP(6),

    PRIMARY KEY (event_id),

    CONSTRAINT chk_processed_events_quantity
        CHECK (quantity > 0),

    CONSTRAINT chk_processed_events_status
        CHECK (
            process_status IN (
                'SUCCESS',
                'OUT_OF_STOCK',
                'FAILED'
            )
        ),

    CONSTRAINT chk_processed_events_model
        CHECK (
            model_name IN ('FOLD', 'FLIP', 'ULTRA')
        ),

    CONSTRAINT chk_processed_events_color
        CHECK (
            color_name IN ('BLACK', 'WHITE', 'LAVENDER', 'GRAY')
        ),

    INDEX idx_processed_events_order_id (order_id),
    INDEX idx_processed_events_product_id (product_id),
    INDEX idx_processed_events_status (process_status),
    INDEX idx_processed_events_processed_at (processed_at)
);
```