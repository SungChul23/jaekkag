-- =========================================================
-- 재깍오픈 Inventory Worker 스키마
-- 1. master_inventory : 현재 상품별 재고 관리
-- 2. processed_events : 이벤트 중복 처리 방지 및 처리 결과 기록
-- =========================================================


-- ---------------------------------------------------------
-- 1. 상품별 현재 재고 테이블
-- ---------------------------------------------------------
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


-- ---------------------------------------------------------
-- 2. 처리 완료 이벤트 테이블
-- ---------------------------------------------------------
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
