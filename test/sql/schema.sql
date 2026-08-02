CREATE TABLE IF NOT EXISTS orders (
    order_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id   INT NOT NULL,
    quantity     INT NOT NULL,
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS outbox_events (
    event_id     CHAR(36) PRIMARY KEY,
    order_id     BIGINT NOT NULL,
    product_id   INT NOT NULL,
    quantity     INT NOT NULL,
    status       VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMP NULL,
    INDEX idx_status_created (status, created_at)
);

CREATE TABLE IF NOT EXISTS master_inventory (
    product_id   INT PRIMARY KEY,
    stock        INT NOT NULL
);

CREATE TABLE IF NOT EXISTS processed_events (
    event_id     CHAR(36) PRIMARY KEY,
    result       VARCHAR(20) NOT NULL,
    processed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT IGNORE INTO master_inventory (product_id, stock) VALUES
    (10, 1000),
    (20, 500),
    (30, 200);
