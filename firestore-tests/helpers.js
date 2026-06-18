const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

let testEnv = null;

async function getEnv() {
  if (!testEnv) {
    testEnv = await initializeTestEnvironment({
      projectId: 'demo-dogsitter',
      firestore: {
        rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'),
        host: '127.0.0.1',
        port: 8080,
      },
    });
  }
  return testEnv;
}

// Authenticated Firestore handle.
//   opts.verified === false  -> request.auth.token.email_verified == false
//   default                  -> verified (matches a Google/Apple login or a verified email)
function authed(env, uid, opts = {}) {
  const claims = Object.assign(
    { email_verified: opts.verified !== false },
    opts.claims || {}
  );
  return env.authenticatedContext(uid, claims).firestore();
}

function unauthed(env) {
  return env.unauthenticatedContext().firestore();
}

// Seed documents with rules bypassed (acts like an admin / trusted backend).
async function seed(env, fn) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await fn(ctx.firestore());
  });
}

module.exports = { getEnv, authed, unauthed, seed, assertSucceeds, assertFails };
