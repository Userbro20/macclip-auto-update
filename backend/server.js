const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const express = require("express");
const multer = require("multer");
const bcrypt = require("bcryptjs");
const cookieParser = require("cookie-parser");

const ROOT_DIR = path.resolve(__dirname, "..");
const BACKEND_DIR = path.join(ROOT_DIR, "backend");
const RUNTIME_DIR = path.join(BACKEND_DIR, "runtime");
const DATA_DIR_DEFAULT = path.join(RUNTIME_DIR, "data");
const UPLOAD_DIR_DEFAULT = path.join(RUNTIME_DIR, "uploads");
const CONFIG_PATH = path.join(BACKEND_DIR, "config.env");
const RECOVERY_PATH = path.join(BACKEND_DIR, ".config.env.password");
const ACTIVATION_URL_SCHEME = "macclipper://purchase-complete";
const ACTIVATION_PEPPER = "macclipper-app-feature-grant-v1";
const ACCOUNT_STATUS_VALUES = new Set(["active", "banned", "terminated"]);
const SUBSCRIPTION_TIERS = new Set(["free", "pro"]);

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeText(filePath, contents) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, contents, "utf8");
}

function writeJson(filePath, value) {
  writeText(filePath, JSON.stringify(value, null, 2));
}

function readJson(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return fallback;
  }
}

function fileExists(filePath) {
  return fs.existsSync(filePath);
}

function randomSecret(length = 32) {
  return crypto.randomBytes(length).toString("base64url");
}

function buildDefaultConfig() {
  return {
    PORT: "4173",
    COOKIE_NAME: "macclipper.sid",
    SESSION_SECRET: randomSecret(32),
    MACCLIPPER_BOT_SHARED_SECRET: randomSecret(32),
    MAX_UPLOAD_MB: "512",
    DATA_DIR: DATA_DIR_DEFAULT,
    UPLOAD_DIR: UPLOAD_DIR_DEFAULT
  };
}

function toEnvString(values) {
  return Object.entries(values)
    .map(([key, value]) => `${key}=${String(value).replaceAll("\n", "")}`)
    .join("\n");
}

function parseEnvString(contents) {
  return contents
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"))
    .reduce((accumulator, line) => {
      const separatorIndex = line.indexOf("=");
      if (separatorIndex === -1) {
        return accumulator;
      }
      const key = line.slice(0, separatorIndex).trim();
      const value = line.slice(separatorIndex + 1).trim();
      accumulator[key] = value;
      return accumulator;
    }, {});
}

function encryptConfig(plainText, password) {
  const salt = crypto.randomBytes(16);
  const iv = crypto.randomBytes(12);
  const key = crypto.scryptSync(password, salt, 32);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const payload = Buffer.concat([cipher.update(plainText, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();

  return JSON.stringify(
    {
      version: 1,
      salt: salt.toString("hex"),
      iv: iv.toString("hex"),
      tag: tag.toString("hex"),
      payload: payload.toString("hex")
    },
    null,
    2
  );
}

function decryptConfig(encryptedText, password) {
  const parsed = JSON.parse(encryptedText);
  const salt = Buffer.from(parsed.salt, "hex");
  const iv = Buffer.from(parsed.iv, "hex");
  const tag = Buffer.from(parsed.tag, "hex");
  const payload = Buffer.from(parsed.payload, "hex");
  const key = crypto.scryptSync(password, salt, 32);
  const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
  decipher.setAuthTag(tag);

  return Buffer.concat([decipher.update(payload), decipher.final()]).toString("utf8");
}

function ensureLockedConfig() {
  ensureDir(BACKEND_DIR);

  if (!fileExists(RECOVERY_PATH)) {
    const password = randomSecret(18);
    writeText(
      RECOVERY_PATH,
      [
        "MacClipper locked config recovery file",
        "If you forget the config password, use the value below.",
        password
      ].join("\n")
    );
  }

  const recoveryPassword = fs.readFileSync(RECOVERY_PATH, "utf8").trim().split(/\r?\n/).pop();

  if (!fileExists(CONFIG_PATH)) {
    const defaultConfig = buildDefaultConfig();
    writeText(CONFIG_PATH, encryptConfig(toEnvString(defaultConfig), recoveryPassword));
  }

  const defaultConfig = buildDefaultConfig();
  const parsedConfig = parseEnvString(decryptConfig(fs.readFileSync(CONFIG_PATH, "utf8"), recoveryPassword));
  const mergedConfig = { ...defaultConfig, ...parsedConfig };

  const isMissingConfigKey = Object.keys(defaultConfig).some((key) => !(key in parsedConfig));
  if (isMissingConfigKey) {
    writeText(CONFIG_PATH, encryptConfig(toEnvString(mergedConfig), recoveryPassword));
  }

  return { recoveryPassword, config: mergedConfig };
}

const { config } = ensureLockedConfig();

const DATA_DIR = config.DATA_DIR || DATA_DIR_DEFAULT;
const UPLOAD_DIR = config.UPLOAD_DIR || UPLOAD_DIR_DEFAULT;
const USERS_FILE = path.join(DATA_DIR, "users.json");
const SESSIONS_FILE = path.join(DATA_DIR, "sessions.json");
const VIDEOS_FILE = path.join(DATA_DIR, "videos.json");
const COOKIE_NAME = config.COOKIE_NAME || "macclipper.sid";
const MAX_UPLOAD_MB = Number(config.MAX_UPLOAD_MB || 512);

ensureDir(DATA_DIR);
ensureDir(UPLOAD_DIR);
if (!fileExists(USERS_FILE)) writeJson(USERS_FILE, []);
if (!fileExists(SESSIONS_FILE)) writeJson(SESSIONS_FILE, []);
if (!fileExists(VIDEOS_FILE)) writeJson(VIDEOS_FILE, []);

if (process.argv.includes("--init-only")) {
  console.log(`Locked config ready at ${CONFIG_PATH}`);
  console.log(`Recovery password file ready at ${RECOVERY_PATH}`);
  process.exit(0);
}

if (process.argv.includes("--print-bot-secret")) {
  console.log(config.MACCLIPPER_BOT_SHARED_SECRET || "");
  process.exit(0);
}

function loadUsers() {
  return readJson(USERS_FILE, []).map(normalizeUserRecord);
}

function saveUsers(users) {
  writeJson(USERS_FILE, users.map(normalizeUserRecord));
}

function loadSessions() {
  return readJson(SESSIONS_FILE, []);
}

function saveSessions(sessions) {
  writeJson(SESSIONS_FILE, sessions);
}

function loadVideos() {
  return readJson(VIDEOS_FILE, []).sort((left, right) => new Date(right.uploadedAt) - new Date(left.uploadedAt));
}

function saveVideos(videos) {
  writeJson(VIDEOS_FILE, videos);
}

function sanitizeText(value, fallback = "") {
  return String(value || "").trim() || fallback;
}

function normalizeAccountStatus(value) {
  const normalized = sanitizeText(value, "active").toLowerCase();
  return ACCOUNT_STATUS_VALUES.has(normalized) ? normalized : "active";
}

function normalizeSubscriptionTier(value) {
  const normalized = sanitizeText(value, "free").toLowerCase();
  return SUBSCRIPTION_TIERS.has(normalized) ? normalized : "free";
}

function normalizeRole(value) {
  return sanitizeText(value, "user").toLowerCase() === "admin" ? "admin" : "user";
}

function normalizeFeatureKey(value) {
  return sanitizeText(value).toLowerCase();
}

function normalizeFeatureKeys(values) {
  const source = Array.isArray(values) ? values : [];
  return Array.from(new Set(source.map(normalizeFeatureKey).filter(Boolean))).sort();
}

function defaultPaidFeaturesForTier(tier) {
  return normalizeSubscriptionTier(tier) === "pro" ? ["4k-pro"] : [];
}

function normalizeUserRecord(user) {
  const id = sanitizeText(user.id, crypto.randomUUID());
  const subscriptionTier = normalizeSubscriptionTier(user.subscriptionTier || (Array.isArray(user.paidFeatures) && user.paidFeatures.length ? "pro" : "free"));
  const paidFeatures = normalizeFeatureKeys([
    ...defaultPaidFeaturesForTier(subscriptionTier),
    ...(Array.isArray(user.paidFeatures) ? user.paidFeatures : [])
  ]);

  return {
    id,
    appUuid: sanitizeText(user.appUuid) || id,
    displayName: sanitizeText(user.displayName, "Creator"),
    email: sanitizeText(user.email).toLowerCase(),
    passwordHash: sanitizeText(user.passwordHash),
    createdAt: sanitizeText(user.createdAt, new Date().toISOString()),
    updatedAt: sanitizeText(user.updatedAt, user.createdAt || new Date().toISOString()),
    role: normalizeRole(user.role || (user.isAdmin ? "admin" : "user")),
    accountStatus: normalizeAccountStatus(user.accountStatus),
    subscriptionTier,
    paidFeatures,
    discordUserId: sanitizeText(user.discordUserId),
    discordUsername: sanitizeText(user.discordUsername)
  };
}

function countUserClips(userId) {
  return loadVideos().filter((video) => video.uploaderId === userId).length;
}

function publicUser(user) {
  return {
    id: user.id,
    appUuid: user.appUuid || user.id,
    displayName: user.displayName,
    email: user.email,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
    role: user.role,
    accountStatus: user.accountStatus,
    subscriptionTier: user.subscriptionTier,
    paidFeatures: user.paidFeatures,
    discordUserId: user.discordUserId || "",
    discordUsername: user.discordUsername || "",
    clipCount: countUserClips(user.id)
  };
}

function publicEntitlementUser(user) {
  return {
    id: user.id,
    accountStatus: user.accountStatus,
    subscriptionTier: user.subscriptionTier,
    paidFeatures: user.paidFeatures,
    updatedAt: user.updatedAt
  };
}

function revokeSessionsForUser(userId) {
  saveSessions(loadSessions().filter((entry) => entry.userId !== userId));
}

function parseUserLookup(source) {
  const candidates = [
    ["email", sanitizeText(source.email).toLowerCase()],
    ["userId", sanitizeText(source.userId || source.websiteUserId)],
    ["appUuid", sanitizeText(source.appUuid)],
    ["discordUserId", sanitizeText(source.discordUserId)]
  ].filter(([, value]) => value);

  if (candidates.length !== 1) {
    throw new Error("Provide exactly one lookup target: email, userId, appUuid, or discordUserId.");
  }

  const [key, value] = candidates[0];
  return { key, value };
}

function findUserIndex(users, lookup) {
  switch (lookup.key) {
    case "email":
      return users.findIndex((user) => user.email === lookup.value);
    case "userId":
      return users.findIndex((user) => user.id === lookup.value);
    case "appUuid":
      return users.findIndex((user) => (user.appUuid || user.id) === lookup.value);
    case "discordUserId":
      return users.findIndex((user) => user.discordUserId === lookup.value);
    default:
      return -1;
  }
}

function requireExistingUser(source) {
  const users = loadUsers();
  const lookup = parseUserLookup(source);
  const index = findUserIndex(users, lookup);

  if (index === -1) {
    throw new Error("MacClipper user not found.");
  }

  return { users, index, user: users[index] };
}

function persistUser(users, index, updates) {
  const nextUser = normalizeUserRecord({
    ...users[index],
    ...updates,
    updatedAt: new Date().toISOString()
  });
  users[index] = nextUser;
  saveUsers(users);
  return nextUser;
}

function buildActivationToken(userId, feature) {
  const normalizedUserId = sanitizeText(userId);
  const normalizedFeature = normalizeFeatureKey(feature);

  if (!normalizedUserId || !normalizedFeature) {
    return "";
  }

  return crypto
    .createHash("sha256")
    .update(`${normalizedUserId}|${normalizedFeature}|${ACTIVATION_PEPPER}`)
    .digest("hex");
}

function buildActivationURL(userId, feature) {
  const normalizedUserId = sanitizeText(userId);
  const normalizedFeature = normalizeFeatureKey(feature);
  const token = buildActivationToken(normalizedUserId, normalizedFeature);
  const matchingUser = loadUsers().find((entry) => entry.id === normalizedUserId);
  const query = new URLSearchParams({
    userId: normalizedUserId,
    appUuid: matchingUser?.appUuid || normalizedUserId,
    feature: normalizedFeature,
    token
  });
  return `${ACTIVATION_URL_SCHEME}?${query.toString()}`;
}

function publicVideo(video) {
  return {
    id: video.id,
    title: video.title,
    game: video.game,
    description: video.description,
    visibility: video.visibility,
    uploadedAt: video.uploadedAt,
    uploaderId: video.uploaderId,
    uploaderName: video.uploaderName,
    fileName: video.fileName,
    fileType: video.fileType,
    fileSize: video.fileSize,
    videoUrl: video.videoUrl
  };
}

function getSessionUser(request) {
  const sessionToken = request.cookies[COOKIE_NAME];
  if (!sessionToken) {
    return null;
  }

  const sessions = loadSessions();
  const session = sessions.find((entry) => entry.token === sessionToken);
  if (!session) {
    return null;
  }

  const users = loadUsers();
  const user = users.find((entry) => entry.id === session.userId) || null;
  if (!user) {
    return null;
  }

  if (user.accountStatus !== "active") {
    saveSessions(sessions.filter((entry) => entry.token !== sessionToken));
    return null;
  }

  return user;
}

function requireAuth(request, response, next) {
  const user = getSessionUser(request);
  if (!user) {
    response.status(401).json({ error: "You need to sign in first." });
    return;
  }

  request.currentUser = user;
  next();
}

function requireBotAuth(request, response, next) {
  const configuredSecret = sanitizeText(config.MACCLIPPER_BOT_SHARED_SECRET);
  if (!configuredSecret) {
    response.status(503).json({ error: "The bot API secret is not configured yet." });
    return;
  }

  const header = String(request.headers.authorization || "");
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (token !== configuredSecret) {
    response.status(401).json({ error: "Bot API authorization failed." });
    return;
  }

  next();
}

const storage = multer.diskStorage({
  destination: (_request, _file, callback) => {
    callback(null, UPLOAD_DIR);
  },
  filename: (_request, file, callback) => {
    const extension = path.extname(file.originalname || "").toLowerCase() || ".mp4";
    callback(null, `${Date.now()}-${crypto.randomUUID()}${extension}`);
  }
});

const upload = multer({
  storage,
  limits: {
    fileSize: MAX_UPLOAD_MB * 1024 * 1024
  },
  fileFilter: (_request, file, callback) => {
    const extension = path.extname(file.originalname || "").toLowerCase();
    const isVideo = file.mimetype.startsWith("video/") || [".mp4", ".mov", ".m4v", ".webm"].includes(extension);

    if (!isVideo) {
      callback(new Error("Only video files can be uploaded."));
      return;
    }

    callback(null, true);
  }
});

const app = express();

app.use(express.json({ limit: "2mb" }));
app.use(cookieParser(config.SESSION_SECRET));
app.use("/media", express.static(UPLOAD_DIR));

app.get("/api/health", (_request, response) => {
  response.json({ ok: true });
});

app.get("/api/auth/me", (request, response) => {
  const user = getSessionUser(request);
  response.json({ user: user ? publicUser(user) : null });
});

app.post("/api/auth/signup", (request, response) => {
  const displayName = sanitizeText(request.body.displayName);
  const email = sanitizeText(request.body.email).toLowerCase();
  const password = sanitizeText(request.body.password);

  if (!displayName || !email || !password) {
    response.status(400).json({ error: "Display name, email, and password are required." });
    return;
  }

  const users = loadUsers();
  if (users.some((user) => user.email === email)) {
    response.status(409).json({ error: "That email already exists. Sign in instead." });
    return;
  }

  const user = {
    id: crypto.randomUUID(),
    displayName,
    email,
    passwordHash: bcrypt.hashSync(password, 10),
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    role: "user",
    accountStatus: "active",
    subscriptionTier: "free",
    paidFeatures: [],
    discordUserId: "",
    discordUsername: ""
  };

  users.push(user);
  saveUsers(users);

  const sessions = loadSessions();
  const token = randomSecret(24);
  sessions.push({ token, userId: user.id, createdAt: new Date().toISOString() });
  saveSessions(sessions);

  response.cookie(COOKIE_NAME, token, {
    httpOnly: true,
    sameSite: "lax",
    secure: false,
    maxAge: 1000 * 60 * 60 * 24 * 14
  });

  response.status(201).json({ user: publicUser(user) });
});

app.post("/api/auth/signin", (request, response) => {
  const email = sanitizeText(request.body.email).toLowerCase();
  const password = sanitizeText(request.body.password);
  const users = loadUsers();
  const user = users.find((entry) => entry.email === email);

  if (!user || !bcrypt.compareSync(password, user.passwordHash)) {
    response.status(401).json({ error: "Invalid email or password." });
    return;
  }

  if (user.accountStatus !== "active") {
    const message = user.accountStatus === "banned"
      ? "This account is banned from signing in."
      : "This account has been terminated. Contact support if you think this is wrong.";
    response.status(403).json({ error: message });
    return;
  }

  const sessions = loadSessions().filter((entry) => entry.userId !== user.id);
  const token = randomSecret(24);
  sessions.push({ token, userId: user.id, createdAt: new Date().toISOString() });
  saveSessions(sessions);

  response.cookie(COOKIE_NAME, token, {
    httpOnly: true,
    sameSite: "lax",
    secure: false,
    maxAge: 1000 * 60 * 60 * 24 * 14
  });

  response.json({ user: publicUser(user) });
});

app.post("/api/auth/signout", (request, response) => {
  const sessionToken = request.cookies[COOKIE_NAME];
  if (sessionToken) {
    saveSessions(loadSessions().filter((entry) => entry.token !== sessionToken));
  }

  response.clearCookie(COOKIE_NAME);
  response.json({ ok: true });
});

app.post("/api/auth/app-uuid", requireAuth, (request, response) => {
  const appUuid = sanitizeText(request.body.appUuid).toLowerCase();
  if (!appUuid) {
    response.status(400).json({ error: "appUuid is required." });
    return;
  }

  const users = loadUsers();
  const index = users.findIndex((entry) => entry.id === request.currentUser.id);
  if (index === -1) {
    response.status(404).json({ error: "MacClipper user not found." });
    return;
  }

  const duplicateUser = users.find((entry) => (entry.appUuid || entry.id) === appUuid && entry.id !== request.currentUser.id);
  if (duplicateUser) {
    response.status(409).json({ error: "That app UUID is already linked to another account." });
    return;
  }

  const nextUser = persistUser(users, index, { appUuid });
  response.json({ user: publicUser(nextUser) });
});

app.get("/api/entitlements/by-user-id", (request, response) => {
  const userId = sanitizeText(request.query.userId);
  const appUuid = sanitizeText(request.query.appUuid);
  const hasUserId = userId.length > 0;
  const hasAppUuid = appUuid.length > 0;

  if ((hasUserId ? 1 : 0) + (hasAppUuid ? 1 : 0) !== 1) {
    response.status(400).json({ error: "Provide exactly one of userId or appUuid." });
    return;
  }

  const user = loadUsers().find((entry) => hasUserId ? entry.id === userId : (entry.appUuid || entry.id) === appUuid);
  if (!user) {
    response.status(404).json({ error: "MacClipper user not found." });
    return;
  }

  response.json({ user: publicEntitlementUser(user) });
});

app.get("/api/entitlements/activation-link", requireAuth, (request, response) => {
  const feature = normalizeFeatureKey(request.query.feature || "4k-pro");
  if (!feature) {
    response.status(400).json({ error: "feature is required." });
    return;
  }

  if (!request.currentUser.paidFeatures.includes(feature)) {
    response.status(403).json({ error: "That feature is not active on this account yet." });
    return;
  }

  response.json({
    user: publicUser(request.currentUser),
    activationURL: buildActivationURL(request.currentUser.id, feature)
  });
});

app.post("/api/purchases/4k-pro/complete", requireAuth, (request, response) => {
  const users = loadUsers();
  const index = users.findIndex((entry) => entry.id === request.currentUser.id);
  if (index === -1) {
    response.status(404).json({ error: "MacClipper user not found." });
    return;
  }

  // Replace this simulated purchase grant with a Stripe Checkout/session verification flow when payments go live.
  const nextUser = persistUser(users, index, {
    subscriptionTier: "pro",
    paidFeatures: normalizeFeatureKeys(["4k-pro", ...users[index].paidFeatures])
  });

  response.json({
    user: publicUser(nextUser),
    activationURL: buildActivationURL(nextUser.id, "4k-pro")
  });
});

app.get("/api/bot/users/lookup", requireBotAuth, (request, response) => {
  try {
    const { user } = requireExistingUser(request.query);
    response.json({ user: publicUser(user) });
  } catch (error) {
    response.status(error.message === "MacClipper user not found." ? 404 : 400).json({ error: error.message });
  }
});

app.post("/api/bot/users/link-discord", requireBotAuth, (request, response) => {
  const discordUserId = sanitizeText(request.body.discordUserId);
  const discordUsername = sanitizeText(request.body.discordUsername);
  if (!discordUserId || !discordUsername) {
    response.status(400).json({ error: "discordUserId and discordUsername are required." });
    return;
  }

  try {
    const { users, index } = requireExistingUser(request.body);
    const nextUser = persistUser(users, index, {
      discordUserId,
      discordUsername
    });
    response.json({ user: publicUser(nextUser) });
  } catch (error) {
    response.status(error.message === "MacClipper user not found." ? 404 : 400).json({ error: error.message });
  }
});

app.post("/api/bot/users/admin", requireBotAuth, (request, response) => {
  const enabled = Boolean(request.body.enabled);

  try {
    const { users, index } = requireExistingUser(request.body);
    const nextUser = persistUser(users, index, {
      role: enabled ? "admin" : "user"
    });
    response.json({ user: publicUser(nextUser) });
  } catch (error) {
    response.status(error.message === "MacClipper user not found." ? 404 : 400).json({ error: error.message });
  }
});

app.post("/api/bot/users/status", requireBotAuth, (request, response) => {
  const accountStatus = normalizeAccountStatus(request.body.status);

  try {
    const { users, index } = requireExistingUser(request.body);
    const updates = { accountStatus };

    if (accountStatus === "terminated") {
      updates.role = "user";
      updates.subscriptionTier = "free";
      updates.paidFeatures = [];
    }

    const nextUser = persistUser(users, index, updates);
    if (accountStatus !== "active") {
      revokeSessionsForUser(nextUser.id);
    }

    response.json({ user: publicUser(nextUser) });
  } catch (error) {
    response.status(error.message === "MacClipper user not found." ? 404 : 400).json({ error: error.message });
  }
});

app.post("/api/bot/users/subscription", requireBotAuth, (request, response) => {
  const subscriptionTier = normalizeSubscriptionTier(request.body.subscriptionTier);
  const customFeatures = Array.isArray(request.body.paidFeatures)
    ? normalizeFeatureKeys(request.body.paidFeatures)
    : null;
  const paidFeatures = normalizeFeatureKeys([
    ...defaultPaidFeaturesForTier(subscriptionTier),
    ...(customFeatures || [])
  ]);

  try {
    const { users, index } = requireExistingUser(request.body);
    const nextUser = persistUser(users, index, {
      subscriptionTier,
      paidFeatures
    });
    response.json({ user: publicUser(nextUser) });
  } catch (error) {
    response.status(error.message === "MacClipper user not found." ? 404 : 400).json({ error: error.message });
  }
});

app.post("/api/bot/users/features/grant", requireBotAuth, (request, response) => {
  const feature = normalizeFeatureKey(request.body.feature);
  if (!feature) {
    response.status(400).json({ error: "feature is required." });
    return;
  }

  try {
    const { users, index } = requireExistingUser(request.body);
    const nextUser = persistUser(users, index, {
      subscriptionTier: feature === "4k-pro" ? "pro" : users[index].subscriptionTier,
      paidFeatures: normalizeFeatureKeys([feature, ...users[index].paidFeatures])
    });
    response.json({
      user: publicUser(nextUser),
      activationURL: buildActivationURL(nextUser.id, feature)
    });
  } catch (error) {
    response.status(error.message === "MacClipper user not found." ? 404 : 400).json({ error: error.message });
  }
});

app.get("/api/videos", (request, response) => {
  const currentUser = getSessionUser(request);
  const mineOnly = request.query.mine === "1";
  const videos = mineOnly && currentUser
    ? loadVideos().filter((video) => video.uploaderId === currentUser.id)
    : loadVideos();

  response.json({ videos: videos.map(publicVideo) });
});

app.get("/api/videos/:id", (request, response) => {
  const video = loadVideos().find((entry) => entry.id === request.params.id);
  if (!video) {
    response.status(404).json({ error: "Clip not found." });
    return;
  }

  response.json({ video: publicVideo(video) });
});

app.post("/api/videos", requireAuth, upload.single("video"), (request, response) => {
  if (!request.file) {
    response.status(400).json({ error: "Pick a video file first." });
    return;
  }

  const video = {
    id: crypto.randomUUID(),
    title: sanitizeText(request.body.title, path.parse(request.file.originalname).name || "Untitled clip"),
    game: sanitizeText(request.body.game, "Clip"),
    description: sanitizeText(request.body.description),
    visibility: sanitizeText(request.body.visibility, "Public"),
    uploadedAt: new Date().toISOString(),
    uploaderId: request.currentUser.id,
    uploaderName: request.currentUser.displayName,
    fileName: request.file.originalname,
    storedName: request.file.filename,
    fileType: request.file.mimetype,
    fileSize: request.file.size,
    videoUrl: `/media/${request.file.filename}`
  };

  const videos = loadVideos();
  videos.push(video);
  saveVideos(videos);

  response.status(201).json({ video: publicVideo(video) });
});

app.delete("/api/videos/:id", requireAuth, (request, response) => {
  const videos = loadVideos();
  const target = videos.find((entry) => entry.id === request.params.id);

  if (!target) {
    response.status(404).json({ error: "Clip not found." });
    return;
  }

  if (target.uploaderId !== request.currentUser.id) {
    response.status(403).json({ error: "You can only delete your own clips." });
    return;
  }

  const nextVideos = videos.filter((entry) => entry.id !== target.id);
  saveVideos(nextVideos);

  try {
    fs.unlinkSync(path.join(UPLOAD_DIR, target.storedName));
  } catch {
    // Ignore missing files so metadata deletion still succeeds.
  }

  response.json({ ok: true });
});

app.use((error, _request, response, _next) => {
  if (error instanceof multer.MulterError && error.code === "LIMIT_FILE_SIZE") {
    response.status(400).json({ error: `Video is too large. Max upload is ${MAX_UPLOAD_MB} MB.` });
    return;
  }

  if (error) {
    response.status(400).json({ error: error.message || "Request failed." });
    return;
  }

  response.status(500).json({ error: "Unexpected server error." });
});

const port = Number(config.PORT || 4173);
app.listen(port, () => {
  console.log(`MacClipper web server running at http://127.0.0.1:${port}`);
  console.log(`Locked config file: ${CONFIG_PATH}`);
  console.log(`Recovery password file: ${RECOVERY_PATH}`);
});