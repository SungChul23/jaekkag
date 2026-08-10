// [2] 타임세일 시작 - k6 부하 급증
// t3.medium x2, Kinesis 3샤드, Publisher 배치 500 기준 -> 3000이 아니라 400 RPS 피크로 설정
import http from 'k6/http';
import { check } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://k8s-ecommerc-ecommerc-4a419899c8-564158823.us-east-1.elb.amazonaws.com';
const PRODUCT_IDS = ['101', '102', '103', '201', '202', '203', '204', '301', '302', '303', '304'];

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: 20,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 200,
      stages: [
        { target: 100, duration: '10s' },  // 서서히 증가
        { target: 400, duration: '20s' },  // 타임세일 피크
        { target: 400, duration: '20s' },  // 피크 유지 -> HPA 반응 관찰 (03번 참고)
        { target: 0, duration: '10s' },    // 종료
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

/*
실행 (터미널 A):
  k6 run load-test/02-spike-test.js

이 스크립트가 도는 동안 03-hpa-watch.md, 04-kinesis-lag.md를 별도 터미널에서 같이 실행할 것.
*/