-- orders는 아직 1번(Order API) 코드가 없으므로, 검증용 최소 컬럼만 미리 만들어둠.
-- 실제 규격은 1번이 확정하는 대로 교체.
CREATE TABLE IF NOT EXISTS orders (
    order_id    BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id  INT NOT NULL,
    quantity    INT NOT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 담당(2번) 정식 규격 그대로 (sql/outbox_events.sql과 동일)
CREATE TABLE IF NOT EXISTS outbox_events (
    event_id        CHAR(36) PRIMARY KEY,
    order_id        BIGINT NOT NULL,
    product_id      INT NOT NULL,
    quantity        INT NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    retry_count     INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at    TIMESTAMP NULL,
    last_failed_at  TIMESTAMP NULL,
    INDEX idx_status_created (status, created_at)
);
