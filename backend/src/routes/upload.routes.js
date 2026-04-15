import express from "express";
import { upload } from "../config/upload.js";
import { authMiddleware } from "../middleware/auth.js";

const router = express.Router();

// POST /api/upload
router.post("/upload", authMiddleware, upload.single("image"), (req, res) => {
  console.log("Rasm yuklandi:", req.file);
  if (!req.file) {
    return res.status(400).json({ message: "Rasm yuklanmadi" });
  }
  const imagePath = `/uploads/${req.file.filename}`;
  res.json({ path: imagePath });
});

// POST /api/upload-audio
router.post(
  "/upload-audio",
  authMiddleware,
  upload.single("audio"),
  (req, res) => {
    console.log("Audio yuklandi:", req.file);
    if (!req.file) {
      return res.status(400).json({ message: "Audio yuklanmadi" });
    }
    const audioPath = `/uploads/${req.file.filename}`;
    res.json({ path: audioPath });
  },
);

// POST /api/upload-video
router.post(
  "/upload-video",
  authMiddleware,
  upload.single("video"),
  (req, res) => {
    console.log("Video yuklandi:", req.file);
    if (!req.file) {
      return res.status(400).json({ message: "Video yuklanmadi" });
    }
    const videoPath = `/uploads/${req.file.filename}`;
    res.json({ path: videoPath });
  },
);

export default router;
