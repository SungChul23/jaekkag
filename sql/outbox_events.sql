CREATE TABLE IF NOT EXISTS outbox_events (
    event_id        CHAR(36) PRIMARY KEY,
    order_id        BIGINT NOT NULL,
    product_id      INT NOT NULL,
    quantity        INT NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING', -- PENDING, PUBLISHED, FAILED
    retry_count     INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at    TIMESTAMP NULL,
    last_failed_at  TIMESTAMP NULL,
    INDEX idx_status_created (status, created_at)
);
