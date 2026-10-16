require('dotenv').config();
const mongoose = require('mongoose');
const config = require('./config');

if (!config.jwtSecret || config.jwtSecret.length < 32) {
  console.error('JWT_SECRET must be configured with at least 32 characters.');
  process.exit(1);
}

async function start() {
  await mongoose.connect(config.mongoUri);
  const hello = await mongoose.connection.db.admin().command({ hello: 1 });
  if (!hello.setName && hello.msg !== 'isdbgrid') throw new Error('MongoDB must run as a replica set or sharded cluster for atomic workflow transactions');
  const models = require('./models');
  await Promise.all(Object.values(models).map((model) => model.init()));
  const app = require('./app');
  const server = app.listen(config.port, () => console.log(`API listening on port ${config.port}`));
  const shutdown = async () => {
    server.close(async () => { await mongoose.disconnect(); process.exit(0); });
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

start().catch((error) => {
  console.error('Unable to start API:', error.message);
  process.exit(1);
});
