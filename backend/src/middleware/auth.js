const jwt = require('jsonwebtoken');
const { jwtSecret } = require('../config');
const { User } = require('../models');
const { AppError } = require('../utils/errors');

async function authenticate(req, res, next) {
  try {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) throw new AppError('Authentication required', 401, 'UNAUTHENTICATED');
    const payload = jwt.verify(token, jwtSecret);
    const user = await User.findById(payload.sub);
    if (!user || !user.active || payload.ver !== user.tokenVersion) throw new AppError('Invalid or expired token', 401, 'UNAUTHENTICATED');
    req.user = user;
    next();
  } catch (error) {
    next(error instanceof AppError ? error : new AppError('Invalid or expired token', 401, 'UNAUTHENTICATED'));
  }
}

const allow = (...roles) => (req, res, next) => {
  if (!req.user || !roles.includes(req.user.role)) return next(new AppError('Forbidden', 403, 'FORBIDDEN'));
  next();
};

module.exports = { authenticate, allow };
