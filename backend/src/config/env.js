import dotenv from "dotenv";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const candidateEnvPaths = [
  path.resolve(__dirname, "../../.env"),
  path.resolve(__dirname, "../.env"),
];

const envPath =
  candidateEnvPaths.find((candidate) => fs.existsSync(candidate)) ??
  candidateEnvPaths[0];

dotenv.config({ path: envPath });

// Without this every jwt.verify() throws and the whole app answers 403 with no
// hint why. Fail at boot instead.
if (!process.env.JWT_SECRET) {
  throw new Error(`JWT_SECRET topilmadi (.env: ${envPath})`);
}

export { envPath };
