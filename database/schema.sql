-- =====================================================
-- Orders
-- =====================================================

CREATE TABLE IF NOT EXISTS orders (
    order_id BIGINT AUTO_INCREMENT PRIMARY KEY,

    product_id VARCHAR(10) NOT NULL,

    quantity INT NOT NULL,

    order_status ENUM(
        'CREATED',
        'CONFIRMED',
        'CANCELLED'
    ) NOT NULL DEFAULT 'CREATED',

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_product_id (product_id),
    INDEX idx_created_at (created_at)
);


-- =====================================================
-- Outbox Events
-- =====================================================

CREATE TABLE IF NOT EXISTS outbox_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,

    event_id VARCHAR(36) NOT NULL UNIQUE,

    event_type VARCHAR(50) NOT NULL,

    order_id BIGINT NOT NULL,

    product_id VARCHAR(10) NOT NULL,

    quantity INT NOT NULL,

    publish_status ENUM(
        'PENDING',
        'PUBLISHED',
        'FAILED'
    ) NOT NULL DEFAULT 'PENDING',

    retry_count INT NOT NULL DEFAULT 0,

    last_error TEXT NULL,

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    published_at DATETIME NULL,

    INDEX idx_status_created (
        publish_status,
        created_at
    )
);