// 0 → 10 个虚拟用户
// 10 → 50
// 50 → 100 最后降回 0

// 每个虚拟用户持续发送：
// { "product_id": 10、11 或 12,"quantity": 1～3}

import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "30s", target: 10 },
    { duration: "1m", target: 50 },
    { duration: "1m", target: 100 },
    { duration: "30s", target: 0 },
  ],

  thresholds: {
    http_req_failed: ["rate<0.05"],
    http_req_duration: ["p(95)<1000"],
  },
};

const productIds = [10, 11, 12];

export default function () {
  const productId =
    productIds[Math.floor(Math.random() * productIds.length)];

  const quantity = Math.floor(Math.random() * 3) + 1;

  const payload = JSON.stringify({
    product_id: productId,
    quantity: quantity,
  });

  const response = http.post(
    `${__ENV.BASE_URL}/orders`,
    payload,
    {
      headers: {
        "Content-Type": "application/json",
      },
      tags: {
        api: "create-order",
      },
    }
  );

  check(response, {
    "status is 201": (res) => res.status === 201,
    "response has order_id": (res) => {
      try {
        return res.json("order_id") !== undefined;
      } catch {
        return false;
      }
    },
    "status is RECEIVED": (res) => {
      try {
        return res.json("status") === "RECEIVED";
      } catch {
        return false;
      }
    },
  });

  sleep(0.1);
}