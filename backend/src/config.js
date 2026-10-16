const path = require('node:path');

module.exports = {
  port: Number(process.env.PORT || 3000),
  mongoUri: process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017/college_documents',
  jwtSecret: process.env.JWT_SECRET || '',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '8h',
  storageDir: path.resolve(__dirname, '..', process.env.STORAGE_DIR || 'storage'),
  maxUploadBytes: Number(process.env.MAX_UPLOAD_BYTES || 10 * 1024 * 1024),
  resetTtlMinutes: Number(process.env.PASSWORD_RESET_TTL_MINUTES || 30),
  smtpHost: process.env.SMTP_HOST || '',
  smtpPort: Number(process.env.SMTP_PORT || 587),
  smtpUser: process.env.SMTP_USER || '',
  smtpPassword: process.env.SMTP_PASSWORD || '',
  smtpFrom: process.env.SMTP_FROM || '',
  passwordResetUrl: process.env.PASSWORD_RESET_URL || '',
  frontendOrigin: process.env.FRONTEND_ORIGIN || '*'
};
