'use strict';

const test = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');
const { buildSignaturePayload, signParams } = require('../src/cloudinarySignature.js');

test('builds a sorted key=value payload and drops empty params', () => {
  const payload = buildSignaturePayload({ public_id: 'x', folder: 'a/b', timestamp: 100, empty: '' });
  assert.strictEqual(payload, 'folder=a/b&public_id=x&timestamp=100');
});

test('signature matches the documented sha1(payload + secret) algorithm', () => {
  const params = { folder: 'dogsitter/pets/u1/p1', public_id: 'p1_abc', timestamp: 1700000000 };
  const secret = 'test_secret';
  const expected = crypto
    .createHash('sha1')
    .update('folder=dogsitter/pets/u1/p1&public_id=p1_abc&timestamp=1700000000' + secret)
    .digest('hex');
  assert.strictEqual(signParams(params, secret), expected);
});

test('signature is deterministic, hex, and changes with params', () => {
  const secret = 'secret';
  const a = signParams({ timestamp: 1, public_id: 'x' }, secret);
  const b = signParams({ timestamp: 1, public_id: 'x' }, secret);
  const c = signParams({ timestamp: 2, public_id: 'x' }, secret);
  assert.strictEqual(a, b);
  assert.notStrictEqual(a, c);
  assert.match(a, /^[0-9a-f]{40}$/);
});
