const { getEnv } = require('./helpers');

// Root mocha hooks shared across every spec file.
exports.mochaHooks = {
  async beforeEach() {
    const env = await getEnv();
    await env.clearFirestore();
  },
  async afterAll() {
    const env = await getEnv();
    await env.cleanup();
  },
};
