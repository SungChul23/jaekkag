CREATE TABLE IF NOT EXISTS master_inventory (
    product_id BIGINT PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    quantity INT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,
    CHECK (quantity >= 0)
);

CREATE TABLE IF NOT EXISTS processed_events (
    event_id CHAR(36) PRIMARY KEY,
    order_id BIGINT NOT NULL,
    result VARCHAR(30) NOT NULL,
    processed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO master_inventory (
    product_id,
    product_name,
    quantity
)
VALUES
    (10, 'Wireless Earbuds', 100),
    (20, 'Keyboard', 50),
    (30, 'Monitor', 0)
ON DUPLICATE KEY UPDATE
    product_name = VALUES(product_name);