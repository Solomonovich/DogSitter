'use strict';

// Pure Cloudinary signed-upload signature helper (no Firebase dependency, so it
// unit-tests with `node --test` and zero installs). Implements Cloudinary's
// documented algorithm: sort the params to sign alphabetically, join as
// `key=value&key=value`, append the api_secret, and hash.
const crypto = require('crypto');

/** Build the canonical string that gets hashed (empty/undefined params dropped). */
function buildSignaturePayload(params) {
  return Object.keys(params)
    .filter((k) => params[k] !== undefined && params[k] !== null && params[k] !== '')
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join('&');
}

/** Return the hex signature for the given params + secret. */
function signParams(params, apiSecret, algorithm = 'sha1') {
  const payload = buildSignaturePayload(params);
  return crypto.createHash(algorithm).update(payload + apiSecret).digest('hex');
}

module.exports = { buildSignaturePayload, signParams };
