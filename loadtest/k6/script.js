import { sleep, check } from 'k6';
import http from 'k6/http';

export const options = {
  stages: [
    { duration: '30s', target: 10 },   // ramp up
    { duration: '2m', target: 20 },    // steady state
    { duration: '30s', target: 40 },   // burst
    { duration: '30s', target: 0 },    // ramp down
  ],
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<2000'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const PRODUCT_IDS = ['prod-1', 'prod-2', 'prod-3', 'prod-4', 'prod-5', 'prod-6', 'prod-7', 'prod-8'];

function randomUser() {
  return `user-${Math.floor(Math.random() * 50) + 1}`;
}

function randomProduct() {
  return PRODUCT_IDS[Math.floor(Math.random() * PRODUCT_IDS.length)];
}

function randomHex(bytes) {
  let result = '';
  for (let i = 0; i < bytes * 2; i++) {
    result += Math.floor(Math.random() * 16).toString(16);
  }
  return result;
}

function b3Headers() {
  const traceId = randomHex(16);
  const spanId  = randomHex(8);
  return {
    'X-B3-TraceId': traceId,
    'X-B3-SpanId': spanId,
    'X-B3-Sampled': '1',
  };
}

function thinkTime() {
  sleep(0.5 + Math.random() * 1.5);
}

// Flow 1 – Browse products (55%)
function browseFlow() {
  const headers = b3Headers();
  const listRes = http.get(`${BASE_URL}/products`, { headers });
  check(listRes, { 'products list ok': (r) => r.status === 200 });
  thinkTime();

  const id = randomProduct();
  const detailRes = http.get(`${BASE_URL}/products/${id}`, { headers });
  check(detailRes, { 'product detail ok': (r) => r.status === 200 });
  thinkTime();
}

// Flow 2 – Add to cart (25%)
function addToCartFlow() {
  const headers = b3Headers();
  const userID = randomUser();

  const listRes = http.get(`${BASE_URL}/products`, { headers });
  check(listRes, { 'products list ok': (r) => r.status === 200 });
  thinkTime();

  const productID = randomProduct();
  const quantity = Math.floor(Math.random() * 3) + 1;

  const addRes = http.post(
    `${BASE_URL}/cart/${userID}/items`,
    JSON.stringify({ product_id: productID, quantity }),
    { headers: { ...headers, 'Content-Type': 'application/json' } },
  );
  check(addRes, { 'add to cart ok': (r) => r.status === 200 });
  thinkTime();
}

// Flow 3 – Checkout (20%)
function checkoutFlow() {
  const headers = b3Headers();
  const userID = randomUser();

  // Browse and add a couple of items first.
  const listRes = http.get(`${BASE_URL}/products`, { headers });
  check(listRes, { 'products list ok': (r) => r.status === 200 });
  thinkTime();

  const itemCount = Math.floor(Math.random() * 2) + 1;
  for (let i = 0; i < itemCount; i++) {
    const productID = randomProduct();
    http.post(
      `${BASE_URL}/cart/${userID}/items`,
      JSON.stringify({ product_id: productID, quantity: 1 }),
      { headers: { ...headers, 'Content-Type': 'application/json' } },
    );
    thinkTime();
  }

  const checkoutRes = http.post(
    `${BASE_URL}/checkout`,
    JSON.stringify({ user_id: userID }),
    { headers: { ...headers, 'Content-Type': 'application/json' } },
  );
  // 402 is expected when payment is declined (injected failure).
  check(checkoutRes, { 'checkout responded': (r) => r.status === 200 || r.status === 402 || r.status === 409 });
  thinkTime();
}

export default function () {
  const roll = Math.random();
  if (roll < 0.55) {
    browseFlow();
  } else if (roll < 0.80) {
    addToCartFlow();
  } else {
    checkoutFlow();
  }
}
