// [2] 타임세일 시작 - k6 부하 급증 (최대 안정성 버전)
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://k8s-ecommerc-ecommerc-4a419899c8-564158823.us-east-1.elb.amazonaws.com';
const PRODUCT_IDS = ['101', '102', '103', '201', '202', '203', '204', '301', '302', '303', '304'];

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: 5,
      timeUnit: '1s',
      preAllocatedVUs: 15,
      maxVUs: 70,
      stages: [
        { target: 40, duration: '10s' }, // 0~10s: 5 → 40 RPS로 상승
        { target: 70, duration: '10s' }, // 10~20s: 40 → 70 RPS로 상승
        { target: 90, duration: '10s' }, // 20~30s: 70 → 90 RPS로 상승 (피크 도달)
        { target: 90, duration: '15s' }, // 30~45s: 90 RPS 유지 (피크 지속)
        { target: 0, duration: '10s' },  // 45~55s: 90 → 0 RPS로 감소 (쿨다운)
      ],
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

  check(res, { 'status is 201': (r) => r.status === 201 });
}