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


-- =====================================================
-- Master Inventory
-- =====================================================

CREATE TABLE IF NOT EXISTS master_inventory (
    product_id      VARCHAR(10)  PRIMARY KEY,
    model_name      VARCHAR(30)  NOT NULL,
    color_name      VARCHAR(30)  NOT NULL,
    stock_quantity  INT          NOT NULL,
    updated_at      DATETIME(6)  NOT NULL
        DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),

    CONSTRAINT uq_inventory_model_color
        UNIQUE (model_name, color_name),

    CONSTRAINT chk_inventory_stock
        CHECK (stock_quantity >= 0),

    CONSTRAINT chk_inventory_model
        CHECK (model_name IN ('FOLD', 'FLIP', 'ULTRA')),

    CONSTRAINT chk_inventory_color
        CHECK (
            color_name IN (
                'BLACK',
                'WHITE',
                'LAVENDER',
                'GRAY'
            )
        )
);


-- =====================================================
-- Processed Events
-- =====================================================

CREATE TABLE IF NOT EXISTS processed_events (
    event_id        CHAR(36)     PRIMARY KEY,
    order_id        BIGINT       NOT NULL,
    product_id      VARCHAR(10)  NOT NULL,
    model_name      VARCHAR(30)  NOT NULL,
    color_name      VARCHAR(30)  NOT NULL,
    quantity        INT          NOT NULL,
    process_status  VARCHAR(30)  NOT NULL,
    error_message   TEXT         NULL,
    processed_at    DATETIME(6)  NOT NULL
        DEFAULT CURRENT_TIMESTAMP(6),

    CONSTRAINT chk_processed_quantity
        CHECK (quantity > 0),

    CONSTRAINT chk_processed_model
        CHECK (model_name IN ('FOLD', 'FLIP', 'ULTRA')),

    CONSTRAINT chk_processed_color
        CHECK (
            color_name IN (
                'BLACK',
                'WHITE',
                'LAVENDER',
                'GRAY'
            )
        ),

    CONSTRAINT chk_processed_status
        CHECK (
            process_status IN (
                'SUCCESS',
                'OUT_OF_STOCK',
                'FAILED'
            )
        ),

    INDEX idx_processed_order_id (order_id),
    INDEX idx_processed_product_id (product_id),
    INDEX idx_processed_status_time (
        process_status,
        processed_at
    )
);