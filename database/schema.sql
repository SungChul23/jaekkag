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
        ON UPDATE CURRENT_TIMESTAMP
);

-- =====================================================
-- Outbox Events
-- =====================================================

CREATE TABLE IF NOT EXISTS outbox_events (
    event_id CHAR(36) PRIMARY KEY,

    aggregate_id BIGINT NOT NULL,

    event_type VARCHAR(50) NOT NULL,

    payload JSON NOT NULL,

    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);