module.exports = (res, data, status = 200) => res.status(status).json({ success: true, data });
