// [5] 인기 상품 재고 소진 - SUCCESS/OUT_OF_STOCK 분리
//
// 사전 준비 (SQL, 실행 전 필수):
//   UPDATE master_inventory SET stock = 15 WHERE product_id = '104';
//
// 104는 이 테스트 전용 격리 상품. 01/02번 스크립트는 104를 쓰지 않으므로
// 다른 시나리오에 영향 없음.
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

/*
실행:
  k6 run load-test/05-stockout-test.js

확인 (SQL):
  SELECT status, COUNT(*) FROM processed_events pe
  JOIN orders o ON pe.order_id = o.order_id
  WHERE o.product_id = '104'
  GROUP BY status;
  -- SUCCESS는 15건까지만, 나머지는 OUT_OF_STOCK이어야 함

  SELECT stock FROM master_inventory WHERE product_id = '104';
  -- 반드시 0 이상, 음수면 버그

테스트 후 원복 (SQL, 다음 리허설을 위해 필수):
  UPDATE master_inventory SET stock = 1000 WHERE product_id = '104';
*/