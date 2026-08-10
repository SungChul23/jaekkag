// [1] 평상시 - 정상 주문
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://k8s-ecommerc-ecommerc-4a419899c8-564158823.us-east-1.elb.amazonaws.com';

// 104는 재고소진 전용 상품이라 여기서 제외
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

/*
실행:
  k6 run load-test/01-order-test.js

확인 (SQL):
  SELECT * FROM orders ORDER BY order_id DESC LIMIT 5;
  SELECT * FROM outbox_events ORDER BY created_at DESC LIMIT 5;
*/