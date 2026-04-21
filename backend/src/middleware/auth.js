import jwt from "jsonwebtoken";
import "../config/env.js";

const authMiddleware = (req, res, next) => {
  const token = req.cookies.access_token;
  if (!token) return res.sendStatus(401);

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded;
    next();
  } catch {
    res.sendStatus(403);
  }
};

const adminMiddleware = (req, res, next) => {
  authMiddleware(req, res, () => {
    if (req.user?.role !== "admin") {
      return res.status(403).json({ message: "Faqat admin uchun" });
    }
    next();
  });
};

export { authMiddleware, adminMiddleware };
