import multer from "multer";
import path from "path";
import crypto from "node:crypto";

// Anything the browser will execute in our own origin. Uploads are served from
// /uploads on the same domain, so an .html or .svg upload is stored XSS.
const BLOCKED_EXTENSIONS = new Set([
  ".html", ".htm", ".xhtml", ".shtml", ".svg", ".xml",
  ".js", ".mjs", ".php", ".phtml", ".jsp", ".asp", ".aspx",
]);
const BLOCKED_MIMETYPES = new Set([
  "text/html", "application/xhtml+xml", "image/svg+xml",
  "text/xml", "application/xml",
  "text/javascript", "application/javascript", "application/x-httpd-php",
]);

const MAX_UPLOAD_BYTES = Number(
  process.env.MAX_UPLOAD_BYTES || 200 * 1024 * 1024
);

const storage = multer.diskStorage({
  destination: "uploads/",
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    // Date.now() collided whenever two uploads landed in the same millisecond,
    // silently overwriting one user's file with another's.
    cb(null, `${Date.now()}-${crypto.randomBytes(8).toString("hex")}${ext}`);
  },
});

function fileFilter(req, file, cb) {
  const ext = path.extname(file.originalname).toLowerCase();
  const mime = (file.mimetype || "").toLowerCase();

  if (BLOCKED_EXTENSIONS.has(ext) || BLOCKED_MIMETYPES.has(mime)) {
    return cb(new Error("Bu fayl turi qabul qilinmaydi"));
  }
  cb(null, true);
}

const upload = multer({
  storage,
  fileFilter,
  limits: { fileSize: MAX_UPLOAD_BYTES },
});

export { upload };
