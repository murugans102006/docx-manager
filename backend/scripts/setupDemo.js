require('dotenv').config();

const crypto = require('node:crypto');
const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');
const config = require('../src/config');

const demoUsers = [
  { key: 'admin', name: 'Demo Administrator', email: 'demo-admin@college.local', role: 'admin' },
  { key: 'coordinator', name: 'Demo Document Coordinator', email: 'demo-coordinator@college.local', role: 'coordinator' },
  { key: 'authority', name: 'Demo Faculty Advisor', email: 'demo-authority@college.local', role: 'authority' }
];

async function main() {
  if (process.env.NODE_ENV === 'production') {
    throw new Error('Demo setup is disabled when NODE_ENV=production.');
  }
  if (!config.jwtSecret || config.jwtSecret.length < 32) {
    throw new Error('Set a JWT_SECRET of at least 32 characters in backend/.env first.');
  }

  await mongoose.connect(config.mongoUri);
  const models = require('../src/models');
  await Promise.all(Object.values(models).map((model) => model.init()));

  const collision = await models.User.findOne({
    email: { $in: demoUsers.map((user) => user.email) }
  }).select('email');
  const existingType = await models.DocumentType.findOne({ name: 'Bonafide Certificate (Demo)' }).select('_id');
  if (collision || existingType) {
    throw new Error(
      'Demo accounts or document type already exist. No changes were made; do not rerun setup because their passwords cannot be recovered.'
    );
  }

  const passwords = Object.fromEntries(
    demoUsers.map((user) => [user.key, crypto.randomBytes(24).toString('base64url')])
  );
  const session = await mongoose.startSession();
  let createdUsers;
  let documentType;
  let template;
  try {
    await session.withTransaction(async () => {
      createdUsers = await models.User.create(
        await Promise.all(demoUsers.map(async (user) => ({
          name: user.name,
          email: user.email,
          role: user.role,
          department: 'Demo Department',
          active: true,
          passwordHash: await bcrypt.hash(passwords[user.key], 12)
        }))),
        { session, ordered: true }
      );
      const authority = createdUsers.find((user) => user.role === 'authority');
      const admin = createdUsers.find((user) => user.role === 'admin');
      [documentType] = await models.DocumentType.create([{
        name: 'Bonafide Certificate (Demo)',
        description: 'Development-only sample document type for testing the request and signing workflow.',
        requiredFields: ['purpose'],
        active: true,
        workflow: [{ authority: authority._id, label: 'Faculty Advisor' }]
      }], { session });
      [template] = await models.Template.create([{
        name: 'Bonafide Certificate Demo Template',
        documentType: documentType._id,
        body: 'This is a development sample and is not an official college certificate.\n\nStudent: {{studentName}}\nStudent ID: {{studentId}}\nPurpose: {{purpose}}\n\nFor testing only.',
        active: true,
        createdBy: admin._id
      }], { session });
    });
  } finally {
    await session.endSession();
  }

  console.log('Created local demo users and Bonafide Certificate document type.');
  console.log('These generated passwords are for local development only; keep them private.');
  for (const user of demoUsers) {
    console.log(`${user.role}: ${user.email}  password: ${passwords[user.key]}`);
  }
  console.log(`Demo template: ${template.name}`);
  console.log('The document text clearly marks generated output as a non-official demo.');
}

main()
  .catch((error) => {
    console.error(`Demo setup failed: ${error.message}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await mongoose.disconnect();
  });
