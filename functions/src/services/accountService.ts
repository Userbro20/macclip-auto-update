import admin from "firebase-admin";
import { createHash, randomUUID } from "crypto";
import { ACTIVATION_HMAC_PEPPER } from "../config";
import { getFirestore } from "../firestore";
import { ApiError } from "../middleware/errorHandler";

export const BOT_API_CAPABILITIES = [
  "users.lookup",
  "users.link-discord",
  "users.admin",
  "users.status",
  "users.subscription",
  "users.features.grant",
  "users.features.revoke"
] as const;

type AccountStatus = "active" | "banned" | "terminated";
type SubscriptionTier = "free" | "pro";
type AccountRole = "user" | "admin";

interface UserRecord {
  id: string;
  appUuid: string;
  displayName: string;
  email: string;
  passwordHash: string;
  createdAt: string;
  updatedAt: string;
  role: AccountRole;
  accountStatus: AccountStatus;
  subscriptionTier: SubscriptionTier;
  paidFeatures: string[];
  discordUserId: string;
  discordUsername: string;
}

interface AppInstallationRecord {
  id: string;
  appUuid: string;
  machineIdentifier: string;
  machineName: string;
  machineModel: string;
  systemVersion: string;
  appVersion: string;
  buildVersion: string;
  role: AccountRole;
  accountStatus: AccountStatus;
  subscriptionTier: SubscriptionTier;
  paidFeatures: string[];
  discordUserId: string;
  discordUsername: string;
  createdAt: string;
  updatedAt: string;
  lastSeenAt: string;
}

interface MachineReservationRecord {
  installationId: string;
  machineIdentifier: string;
  createdAt: string;
  updatedAt: string;
}

interface AppUuidReservationRecord {
  installationId: string;
  appUuid: string;
  machineIdentifier: string;
  createdAt: string;
  updatedAt: string;
}

interface AppInstallationResolveInput {
  appUuid?: string;
  machineIdentifier?: string;
  machineName?: string;
  machineModel?: string;
  systemVersion?: string;
  appVersion?: string;
  buildVersion?: string;
}

interface PublicUser {
  id: string;
  appUuid: string;
  displayName: string;
  email: string;
  createdAt: string;
  updatedAt: string;
  role: AccountRole;
  accountStatus: AccountStatus;
  subscriptionTier: SubscriptionTier;
  paidFeatures: string[];
  discordUserId: string;
  discordUsername: string;
  clipCount: number;
}

interface PublicStandaloneAppUser extends PublicUser {
  machineIdentifier: string;
  machineName: string;
  machineModel: string;
  systemVersion: string;
  appVersion: string;
  buildVersion: string;
  standaloneInstallation: true;
}

interface PublicAppInstallation {
  id: string;
  appUuid: string;
  machineIdentifier: string;
  machineName: string;
  machineModel: string;
  systemVersion: string;
  appVersion: string;
  buildVersion: string;
  role: AccountRole;
  accountStatus: AccountStatus;
  subscriptionTier: SubscriptionTier;
  paidFeatures: string[];
  discordUserId: string;
  discordUsername: string;
  websiteUserId: string;
  createdAt: string;
  updatedAt: string;
  lastSeenAt: string;
}

interface PublicEntitlementUser {
  id: string;
  accountStatus: AccountStatus;
  subscriptionTier: SubscriptionTier;
  paidFeatures: string[];
  updatedAt: string;
}

type PublicAccount = PublicUser | PublicStandaloneAppUser;

type AccountContext =
  | { kind: "user"; account: UserRecord }
  | { kind: "installation"; account: AppInstallationRecord };

type LookupKey = "email" | "userId" | "appUuid" | "discordUserId";

interface AccountLookup {
  key: LookupKey;
  value: string;
}

type FirestoreDocumentSnapshot = admin.firestore.DocumentSnapshot<admin.firestore.DocumentData>;
type FirestoreQueryDocumentSnapshot = admin.firestore.QueryDocumentSnapshot<admin.firestore.DocumentData>;
type FirestoreTransaction = admin.firestore.Transaction;

const USERS_COLLECTION = "users";
const APP_INSTALLATIONS_COLLECTION = "appInstallations";
const MACHINE_IDENTIFIER_RESERVATIONS_COLLECTION = "machineIdentifierReservations";
const APP_UUID_RESERVATIONS_COLLECTION = "appUuidReservations";
const ACTIVATION_URL_SCHEME = "macclipper://purchase-complete";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ACCOUNT_STATUS_VALUES = new Set<AccountStatus>(["active", "banned", "terminated"]);
const SUBSCRIPTION_TIERS = new Set<SubscriptionTier>(["free", "pro"]);

function nowIsoTimestamp(): string {
  return new Date().toISOString();
}

function sanitizeText(value: unknown, fallback = ""): string {
  const normalized = String(value ?? "").trim();
  return normalized || fallback;
}

function normalizeAccountStatus(value: unknown): AccountStatus {
  const normalized = sanitizeText(value, "active").toLowerCase() as AccountStatus;
  return ACCOUNT_STATUS_VALUES.has(normalized) ? normalized : "active";
}

function normalizeSubscriptionTier(value: unknown): SubscriptionTier {
  const normalized = sanitizeText(value, "free").toLowerCase() as SubscriptionTier;
  return SUBSCRIPTION_TIERS.has(normalized) ? normalized : "free";
}

function normalizeRole(value: unknown): AccountRole {
  return sanitizeText(value, "user").toLowerCase() === "admin" ? "admin" : "user";
}

function normalizeFeatureKey(value: unknown): string {
  return sanitizeText(value).toLowerCase();
}

function normalizeFeatureKeys(values: unknown): string[] {
  const source = Array.isArray(values) ? values : [];
  return Array.from(new Set(source.map(normalizeFeatureKey).filter(Boolean))).sort();
}

function defaultPaidFeaturesForTier(subscriptionTier: SubscriptionTier): string[] {
  return subscriptionTier === "pro" ? ["4k-pro"] : [];
}

function normalizeUuid(value: unknown, fallback?: string): string {
  const normalized = sanitizeText(value).toLowerCase();
  if (UUID_PATTERN.test(normalized)) {
    return normalized;
  }

  return sanitizeText(fallback, randomUUID()).toLowerCase();
}

function normalizeMachineIdentifier(value: unknown): string {
  return sanitizeText(value).toLowerCase();
}

function encodeReservationKey(value: string): string {
  return Buffer.from(value, "utf8").toString("base64url");
}

function usersCollection(): admin.firestore.CollectionReference<admin.firestore.DocumentData> {
  return getFirestore().collection(USERS_COLLECTION);
}

function installationsCollection(): admin.firestore.CollectionReference<admin.firestore.DocumentData> {
  return getFirestore().collection(APP_INSTALLATIONS_COLLECTION);
}

function machineIdentifierReservationsCollection(): admin.firestore.CollectionReference<admin.firestore.DocumentData> {
  return getFirestore().collection(MACHINE_IDENTIFIER_RESERVATIONS_COLLECTION);
}

function appUuidReservationsCollection(): admin.firestore.CollectionReference<admin.firestore.DocumentData> {
  return getFirestore().collection(APP_UUID_RESERVATIONS_COLLECTION);
}

function normalizeUserRecord(source: Partial<UserRecord>, fallbackId?: string): UserRecord {
  const id = sanitizeText(source.id, fallbackId || randomUUID()).toLowerCase();
  const subscriptionTier = normalizeSubscriptionTier(
    source.subscriptionTier || (Array.isArray(source.paidFeatures) && source.paidFeatures.length > 0 ? "pro" : "free")
  );
  const paidFeatures = normalizeFeatureKeys([
    ...defaultPaidFeaturesForTier(subscriptionTier),
    ...(Array.isArray(source.paidFeatures) ? source.paidFeatures : [])
  ]);
  const createdAt = sanitizeText(source.createdAt, nowIsoTimestamp());

  return {
    id,
    appUuid: normalizeUuid(source.appUuid, id),
    displayName: sanitizeText(source.displayName, "Creator"),
    email: sanitizeText(source.email).toLowerCase(),
    passwordHash: sanitizeText(source.passwordHash),
    createdAt,
    updatedAt: sanitizeText(source.updatedAt, createdAt),
    role: normalizeRole(source.role),
    accountStatus: normalizeAccountStatus(source.accountStatus),
    subscriptionTier,
    paidFeatures,
    discordUserId: sanitizeText(source.discordUserId),
    discordUsername: sanitizeText(source.discordUsername)
  };
}

function normalizeInstallationRecord(source: Partial<AppInstallationRecord>, fallbackId?: string): AppInstallationRecord {
  const id = sanitizeText(source.id, fallbackId || randomUUID()).toLowerCase();
  const createdAt = sanitizeText(source.createdAt, nowIsoTimestamp());
  const updatedAt = sanitizeText(source.updatedAt, createdAt);
  const lastSeenAt = sanitizeText(source.lastSeenAt, updatedAt);
  const subscriptionTier = normalizeSubscriptionTier(
    source.subscriptionTier || (Array.isArray(source.paidFeatures) && source.paidFeatures.length > 0 ? "pro" : "free")
  );
  const paidFeatures = normalizeFeatureKeys([
    ...defaultPaidFeaturesForTier(subscriptionTier),
    ...(Array.isArray(source.paidFeatures) ? source.paidFeatures : [])
  ]);

  return {
    id,
    appUuid: normalizeUuid(source.appUuid),
    machineIdentifier: normalizeMachineIdentifier(source.machineIdentifier),
    machineName: sanitizeText(source.machineName, "Mac"),
    machineModel: sanitizeText(source.machineModel),
    systemVersion: sanitizeText(source.systemVersion),
    appVersion: sanitizeText(source.appVersion),
    buildVersion: sanitizeText(source.buildVersion),
    role: normalizeRole(source.role),
    accountStatus: normalizeAccountStatus(source.accountStatus),
    subscriptionTier,
    paidFeatures,
    discordUserId: sanitizeText(source.discordUserId),
    discordUsername: sanitizeText(source.discordUsername),
    createdAt,
    updatedAt,
    lastSeenAt
  };
}

function snapshotToUser(snapshot: FirestoreDocumentSnapshot | FirestoreQueryDocumentSnapshot): UserRecord | null {
  const data = snapshot.data();
  if (!data) {
    return null;
  }

  return normalizeUserRecord(data as Partial<UserRecord>, snapshot.id);
}

function snapshotToInstallation(snapshot: FirestoreDocumentSnapshot | FirestoreQueryDocumentSnapshot): AppInstallationRecord | null {
  const data = snapshot.data();
  if (!data) {
    return null;
  }

  return normalizeInstallationRecord(data as Partial<AppInstallationRecord>, snapshot.id);
}

function publicUser(user: UserRecord): PublicUser {
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
    paidFeatures: [...user.paidFeatures],
    discordUserId: user.discordUserId || "",
    discordUsername: user.discordUsername || "",
    clipCount: 0
  };
}

function publicStandaloneAppUser(installation: AppInstallationRecord): PublicStandaloneAppUser {
  return {
    id: installation.id,
    appUuid: installation.appUuid,
    displayName: installation.machineName || "Mac",
    email: "Local app install",
    createdAt: installation.createdAt,
    updatedAt: installation.updatedAt,
    role: installation.role,
    accountStatus: installation.accountStatus,
    subscriptionTier: installation.subscriptionTier,
    paidFeatures: [...installation.paidFeatures],
    discordUserId: installation.discordUserId || "",
    discordUsername: installation.discordUsername || "",
    clipCount: 0,
    machineIdentifier: installation.machineIdentifier,
    machineName: installation.machineName,
    machineModel: installation.machineModel,
    systemVersion: installation.systemVersion,
    appVersion: installation.appVersion,
    buildVersion: installation.buildVersion,
    standaloneInstallation: true
  };
}

function publicEntitlementUser(user: UserRecord): PublicEntitlementUser {
  return {
    id: user.id,
    accountStatus: user.accountStatus,
    subscriptionTier: user.subscriptionTier,
    paidFeatures: [...user.paidFeatures],
    updatedAt: user.updatedAt
  };
}

function publicEntitlementInstallation(installation: AppInstallationRecord): PublicEntitlementUser {
  return {
    id: "",
    accountStatus: installation.accountStatus,
    subscriptionTier: installation.subscriptionTier,
    paidFeatures: [...installation.paidFeatures],
    updatedAt: installation.updatedAt
  };
}

async function publicAppInstallation(installation: AppInstallationRecord): Promise<PublicAppInstallation> {
  const linkedUser = await findUserByAppUuid(installation.appUuid);

  return {
    id: installation.id,
    appUuid: installation.appUuid,
    machineIdentifier: installation.machineIdentifier,
    machineName: installation.machineName,
    machineModel: installation.machineModel,
    systemVersion: installation.systemVersion,
    appVersion: installation.appVersion,
    buildVersion: installation.buildVersion,
    role: installation.role,
    accountStatus: installation.accountStatus,
    subscriptionTier: installation.subscriptionTier,
    paidFeatures: [...installation.paidFeatures],
    discordUserId: installation.discordUserId || "",
    discordUsername: installation.discordUsername || "",
    websiteUserId: linkedUser?.id || "",
    createdAt: installation.createdAt,
    updatedAt: installation.updatedAt,
    lastSeenAt: installation.lastSeenAt
  };
}

function publicAccount(context: AccountContext): PublicAccount {
  return context.kind === "user" ? publicUser(context.account) : publicStandaloneAppUser(context.account);
}

function normalizeLookupValue(key: LookupKey, value: string): string {
  if (key === "email") {
    return value.toLowerCase();
  }

  if (key === "appUuid") {
    return value.toLowerCase();
  }

  return value;
}

function parseAccountLookup(source: Record<string, unknown>): AccountLookup {
  const primaryCandidates: AccountLookup[] = [];
  const email = sanitizeText(source.email);
  const userId = sanitizeText(source.userId ?? source.websiteUserId);
  const appUuid = sanitizeText(source.appUuid);

  if (email) {
    primaryCandidates.push({ key: "email", value: normalizeLookupValue("email", email) });
  }

  if (userId) {
    primaryCandidates.push({ key: "userId", value: normalizeLookupValue("userId", userId) });
  }

  if (appUuid) {
    primaryCandidates.push({ key: "appUuid", value: normalizeLookupValue("appUuid", appUuid) });
  }

  if (primaryCandidates.length > 1) {
    throw new ApiError(400, "Provide exactly one lookup target: email, userId, appUuid, or discordUserId.");
  }

  if (primaryCandidates.length === 1) {
    return primaryCandidates[0];
  }

  const discordUserId = sanitizeText(source.discordUserId);
  if (discordUserId) {
    return { key: "discordUserId", value: discordUserId };
  }

  throw new ApiError(400, "Provide exactly one lookup target: email, userId, appUuid, or discordUserId.");
}

async function findUserById(userId: string): Promise<UserRecord | null> {
  const snapshot = await usersCollection().doc(userId).get();
  return snapshot.exists ? snapshotToUser(snapshot) : null;
}

async function findUserByEmail(email: string): Promise<UserRecord | null> {
  const snapshot = await usersCollection().where("email", "==", email).limit(1).get();
  return snapshot.empty ? null : snapshotToUser(snapshot.docs[0]);
}

async function findUserByAppUuid(appUuid: string): Promise<UserRecord | null> {
  const snapshot = await usersCollection().where("appUuid", "==", appUuid).limit(1).get();
  return snapshot.empty ? null : snapshotToUser(snapshot.docs[0]);
}

async function findUserByDiscordUserId(discordUserId: string): Promise<UserRecord | null> {
  const snapshot = await usersCollection().where("discordUserId", "==", discordUserId).limit(1).get();
  return snapshot.empty ? null : snapshotToUser(snapshot.docs[0]);
}

async function findInstallationByAppUuid(appUuid: string): Promise<AppInstallationRecord | null> {
  const snapshot = await installationsCollection().where("appUuid", "==", appUuid).limit(1).get();
  return snapshot.empty ? null : snapshotToInstallation(snapshot.docs[0]);
}

async function findInstallationByDiscordUserId(discordUserId: string): Promise<AppInstallationRecord | null> {
  const snapshot = await installationsCollection().where("discordUserId", "==", discordUserId).limit(1).get();
  return snapshot.empty ? null : snapshotToInstallation(snapshot.docs[0]);
}

async function findUserForLookup(lookup: AccountLookup): Promise<UserRecord | null> {
  switch (lookup.key) {
    case "email":
      return findUserByEmail(lookup.value);
    case "userId":
      return findUserById(lookup.value);
    case "appUuid":
      return findUserByAppUuid(lookup.value);
    case "discordUserId":
      return findUserByDiscordUserId(lookup.value);
    default:
      return null;
  }
}

async function findInstallationForLookup(lookup: AccountLookup): Promise<AppInstallationRecord | null> {
  switch (lookup.key) {
    case "appUuid":
      return findInstallationByAppUuid(lookup.value);
    case "discordUserId":
      return findInstallationByDiscordUserId(lookup.value);
    default:
      return null;
  }
}

async function requireExistingAccount(source: Record<string, unknown>): Promise<AccountContext> {
  const lookup = parseAccountLookup(source);
  const user = await findUserForLookup(lookup);
  if (user) {
    return { kind: "user", account: user };
  }

  const installation = await findInstallationForLookup(lookup);
  if (installation) {
    return { kind: "installation", account: installation };
  }

  throw new ApiError(404, "MacClipper user not found.");
}

function buildActivationToken(userId: string, feature: string): string {
  return createHash("sha256")
    .update(`${sanitizeText(userId)}|${normalizeFeatureKey(feature)}|${ACTIVATION_HMAC_PEPPER}`)
    .digest("hex");
}

function buildActivationURL(user: UserRecord, feature: string): string {
  const normalizedFeature = normalizeFeatureKey(feature);
  const token = buildActivationToken(user.id, normalizedFeature);
  const query = new URLSearchParams({
    userId: user.id,
    appUuid: user.appUuid || user.id,
    feature: normalizedFeature,
    token
  });
  return `${ACTIVATION_URL_SCHEME}?${query.toString()}`;
}

async function persistUser(user: UserRecord, updates: Partial<UserRecord>): Promise<UserRecord> {
  const nextUser = normalizeUserRecord(
    {
      ...user,
      ...updates,
      updatedAt: nowIsoTimestamp()
    },
    user.id
  );

  await usersCollection().doc(nextUser.id).set(nextUser);
  return nextUser;
}

async function persistInstallation(installation: AppInstallationRecord, updates: Partial<AppInstallationRecord>): Promise<AppInstallationRecord> {
  const timestamp = nowIsoTimestamp();
  const nextInstallation = normalizeInstallationRecord(
    {
      ...installation,
      ...updates,
      updatedAt: timestamp,
      lastSeenAt: timestamp
    },
    installation.id
  );

  await installationsCollection().doc(nextInstallation.id).set(nextInstallation);

  if (nextInstallation.machineIdentifier) {
    const machineReservation: MachineReservationRecord = {
      installationId: nextInstallation.id,
      machineIdentifier: nextInstallation.machineIdentifier,
      createdAt: nextInstallation.createdAt,
      updatedAt: timestamp
    };
    await machineIdentifierReservationsCollection().doc(encodeReservationKey(nextInstallation.machineIdentifier)).set(machineReservation);
  }

  const appUuidReservation: AppUuidReservationRecord = {
    installationId: nextInstallation.id,
    appUuid: nextInstallation.appUuid,
    machineIdentifier: nextInstallation.machineIdentifier,
    createdAt: nextInstallation.createdAt,
    updatedAt: timestamp
  };
  await appUuidReservationsCollection().doc(encodeReservationKey(nextInstallation.appUuid)).set(appUuidReservation);

  return nextInstallation;
}

async function persistAccount(context: AccountContext, updates: Partial<UserRecord> | Partial<AppInstallationRecord>): Promise<AccountContext> {
  if (context.kind === "user") {
    const nextUser = await persistUser(context.account, updates as Partial<UserRecord>);
    return { kind: "user", account: nextUser };
  }

  const nextInstallation = await persistInstallation(context.account, updates as Partial<AppInstallationRecord>);
  return { kind: "installation", account: nextInstallation };
}

async function findInstallationByMachineIdentifierInTransaction(
  transaction: FirestoreTransaction,
  machineIdentifier: string
): Promise<AppInstallationRecord | null> {
  const reservationRef = machineIdentifierReservationsCollection().doc(encodeReservationKey(machineIdentifier));
  const reservationSnapshot = await transaction.get(reservationRef);

  if (reservationSnapshot.exists) {
    const reservationData = reservationSnapshot.data() as Partial<MachineReservationRecord>;
    const installationId = sanitizeText(reservationData.installationId).toLowerCase();
    if (installationId) {
      const installationSnapshot = await transaction.get(installationsCollection().doc(installationId));
      if (installationSnapshot.exists) {
        const installation = snapshotToInstallation(installationSnapshot);
        if (installation) {
          return installation;
        }
      }
    }
  }

  const querySnapshot = await transaction.get(
    installationsCollection().where("machineIdentifier", "==", machineIdentifier).limit(1)
  );
  if (querySnapshot.empty) {
    return null;
  }

  return snapshotToInstallation(querySnapshot.docs[0]);
}

async function findInstallationByAppUuidInTransaction(
  transaction: FirestoreTransaction,
  appUuid: string
): Promise<AppInstallationRecord | null> {
  const reservationRef = appUuidReservationsCollection().doc(encodeReservationKey(appUuid));
  const reservationSnapshot = await transaction.get(reservationRef);

  if (reservationSnapshot.exists) {
    const reservationData = reservationSnapshot.data() as Partial<AppUuidReservationRecord>;
    const installationId = sanitizeText(reservationData.installationId).toLowerCase();
    if (installationId) {
      const installationSnapshot = await transaction.get(installationsCollection().doc(installationId));
      if (installationSnapshot.exists) {
        const installation = snapshotToInstallation(installationSnapshot);
        if (installation) {
          return installation;
        }
      }
    }
  }

  const querySnapshot = await transaction.get(
    installationsCollection().where("appUuid", "==", appUuid).limit(1)
  );
  if (querySnapshot.empty) {
    return null;
  }

  return snapshotToInstallation(querySnapshot.docs[0]);
}

async function appUuidIsAvailableInTransaction(
  transaction: FirestoreTransaction,
  appUuid: string,
  machineIdentifier: string
): Promise<boolean> {
  const reservationSnapshot = await transaction.get(appUuidReservationsCollection().doc(encodeReservationKey(appUuid)));
  if (reservationSnapshot.exists) {
    const reservationData = reservationSnapshot.data() as Partial<AppUuidReservationRecord>;
    const reservedMachineIdentifier = sanitizeText(reservationData.machineIdentifier).toLowerCase();
    return !reservedMachineIdentifier || reservedMachineIdentifier === machineIdentifier;
  }

  const querySnapshot = await transaction.get(installationsCollection().where("appUuid", "==", appUuid).limit(1));
  if (querySnapshot.empty) {
    return true;
  }

  const installation = snapshotToInstallation(querySnapshot.docs[0]);
  return !installation?.machineIdentifier || installation.machineIdentifier === machineIdentifier;
}

async function provisionPlaceholderInstallation(appUuid: string): Promise<AccountContext> {
  const normalizedAppUuid = normalizeUuid(appUuid, appUuid);
  if (!UUID_PATTERN.test(normalizedAppUuid)) {
    throw new ApiError(400, "appUuid is invalid.");
  }

  const existingUser = await findUserByAppUuid(normalizedAppUuid);
  if (existingUser) {
    return { kind: "user", account: existingUser };
  }

  const existingInstallation = await findInstallationByAppUuid(normalizedAppUuid);
  if (existingInstallation) {
    return { kind: "installation", account: existingInstallation };
  }

  const timestamp = nowIsoTimestamp();
  const installation = await getFirestore().runTransaction(async (transaction) => {
    const inTransactionInstallation = await findInstallationByAppUuidInTransaction(transaction, normalizedAppUuid);
    if (inTransactionInstallation) {
      return inTransactionInstallation;
    }

    const installationId = normalizeUuid(undefined);
    const nextInstallation = normalizeInstallationRecord(
      {
        id: installationId,
        appUuid: normalizedAppUuid,
        machineIdentifier: "",
        machineName: "Pending Mac",
        machineModel: "",
        systemVersion: "",
        appVersion: "",
        buildVersion: "",
        createdAt: timestamp,
        updatedAt: timestamp,
        lastSeenAt: timestamp
      },
      installationId
    );

    transaction.set(installationsCollection().doc(nextInstallation.id), nextInstallation);
    transaction.set(
      appUuidReservationsCollection().doc(encodeReservationKey(nextInstallation.appUuid)),
      {
        installationId: nextInstallation.id,
        appUuid: nextInstallation.appUuid,
        machineIdentifier: "",
        createdAt: timestamp,
        updatedAt: timestamp
      } satisfies AppUuidReservationRecord
    );

    return nextInstallation;
  });

  return { kind: "installation", account: installation };
}

export async function resolveAppInstallation(source: Record<string, unknown>): Promise<{ installation: PublicAppInstallation; created: boolean }> {
  const payload: AppInstallationResolveInput = {
    appUuid: sanitizeText(source.appUuid),
    machineIdentifier: sanitizeText(source.machineIdentifier),
    machineName: sanitizeText(source.machineName, "Mac"),
    machineModel: sanitizeText(source.machineModel),
    systemVersion: sanitizeText(source.systemVersion),
    appVersion: sanitizeText(source.appVersion),
    buildVersion: sanitizeText(source.buildVersion)
  };

  const machineIdentifier = normalizeMachineIdentifier(payload.machineIdentifier);
  if (!machineIdentifier) {
    throw new ApiError(400, "machineIdentifier is required.");
  }

  const timestamp = nowIsoTimestamp();
  const result = await getFirestore().runTransaction(async (transaction) => {
    const existingInstallation = await findInstallationByMachineIdentifierInTransaction(transaction, machineIdentifier);

    if (existingInstallation) {
      const nextInstallation = normalizeInstallationRecord(
        {
          ...existingInstallation,
          machineName: payload.machineName,
          machineModel: payload.machineModel,
          systemVersion: payload.systemVersion,
          appVersion: payload.appVersion,
          buildVersion: payload.buildVersion,
          updatedAt: timestamp,
          lastSeenAt: timestamp
        },
        existingInstallation.id
      );

      transaction.set(installationsCollection().doc(nextInstallation.id), nextInstallation);
      transaction.set(
        machineIdentifierReservationsCollection().doc(encodeReservationKey(machineIdentifier)),
        {
          installationId: nextInstallation.id,
          machineIdentifier,
          createdAt: nextInstallation.createdAt,
          updatedAt: timestamp
        } satisfies MachineReservationRecord
      );
      transaction.set(
        appUuidReservationsCollection().doc(encodeReservationKey(nextInstallation.appUuid)),
        {
          installationId: nextInstallation.id,
          appUuid: nextInstallation.appUuid,
          machineIdentifier,
          createdAt: nextInstallation.createdAt,
          updatedAt: timestamp
        } satisfies AppUuidReservationRecord
      );

      return { installation: nextInstallation, created: false };
    }

    const requestedAppUuid = sanitizeText(payload.appUuid).toLowerCase();
    if (requestedAppUuid) {
      const requestedInstallation = await findInstallationByAppUuidInTransaction(transaction, requestedAppUuid);
      if (requestedInstallation && (!requestedInstallation.machineIdentifier || requestedInstallation.machineIdentifier === machineIdentifier)) {
        const nextInstallation = normalizeInstallationRecord(
          {
            ...requestedInstallation,
            appUuid: requestedAppUuid,
            machineIdentifier,
            machineName: payload.machineName,
            machineModel: payload.machineModel,
            systemVersion: payload.systemVersion,
            appVersion: payload.appVersion,
            buildVersion: payload.buildVersion,
            updatedAt: timestamp,
            lastSeenAt: timestamp
          },
          requestedInstallation.id
        );

        transaction.set(installationsCollection().doc(nextInstallation.id), nextInstallation);
        transaction.set(
          machineIdentifierReservationsCollection().doc(encodeReservationKey(machineIdentifier)),
          {
            installationId: nextInstallation.id,
            machineIdentifier,
            createdAt: nextInstallation.createdAt,
            updatedAt: timestamp
          } satisfies MachineReservationRecord
        );
        transaction.set(
          appUuidReservationsCollection().doc(encodeReservationKey(nextInstallation.appUuid)),
          {
            installationId: nextInstallation.id,
            appUuid: nextInstallation.appUuid,
            machineIdentifier,
            createdAt: nextInstallation.createdAt,
            updatedAt: timestamp
          } satisfies AppUuidReservationRecord
        );

        return { installation: nextInstallation, created: false };
      }
    }

    let candidateAppUuid = normalizeUuid(payload.appUuid);
    while (!(await appUuidIsAvailableInTransaction(transaction, candidateAppUuid, machineIdentifier))) {
      candidateAppUuid = normalizeUuid(undefined);
    }

    const installationId = normalizeUuid(undefined);
    const installation = normalizeInstallationRecord(
      {
        id: installationId,
        appUuid: candidateAppUuid,
        machineIdentifier,
        machineName: payload.machineName,
        machineModel: payload.machineModel,
        systemVersion: payload.systemVersion,
        appVersion: payload.appVersion,
        buildVersion: payload.buildVersion,
        createdAt: timestamp,
        updatedAt: timestamp,
        lastSeenAt: timestamp
      },
      installationId
    );

    transaction.set(installationsCollection().doc(installation.id), installation);
    transaction.set(
      machineIdentifierReservationsCollection().doc(encodeReservationKey(machineIdentifier)),
      {
        installationId: installation.id,
        machineIdentifier,
        createdAt: timestamp,
        updatedAt: timestamp
      } satisfies MachineReservationRecord
    );
    transaction.set(
      appUuidReservationsCollection().doc(encodeReservationKey(installation.appUuid)),
      {
        installationId: installation.id,
        appUuid: installation.appUuid,
        machineIdentifier,
        createdAt: timestamp,
        updatedAt: timestamp
      } satisfies AppUuidReservationRecord
    );

    return { installation, created: true };
  });

  return {
    installation: await publicAppInstallation(result.installation),
    created: result.created
  };
}

export async function lookupEntitlements(source: Record<string, unknown>): Promise<{ user: PublicEntitlementUser }> {
  const userId = sanitizeText(source.userId);
  const appUuid = sanitizeText(source.appUuid).toLowerCase();
  const hasUserId = userId.length > 0;
  const hasAppUuid = appUuid.length > 0;

  if ((hasUserId ? 1 : 0) + (hasAppUuid ? 1 : 0) !== 1) {
    throw new ApiError(400, "Provide exactly one of userId or appUuid.");
  }

  if (hasUserId) {
    const user = await findUserById(userId);
    if (!user) {
      throw new ApiError(404, "MacClipper user not found.");
    }

    return { user: publicEntitlementUser(user) };
  }

  const user = await findUserByAppUuid(appUuid);
  if (user) {
    return { user: publicEntitlementUser(user) };
  }

  const installation = await findInstallationByAppUuid(appUuid);
  if (!installation) {
    throw new ApiError(404, "MacClipper user not found.");
  }

  return { user: publicEntitlementInstallation(installation) };
}

export async function lookupAccount(source: Record<string, unknown>): Promise<{ user: PublicAccount }> {
  const account = await requireExistingAccount(source);
  return { user: publicAccount(account) };
}

export async function linkDiscord(source: Record<string, unknown>): Promise<{ user: PublicAccount }> {
  const discordUserId = sanitizeText(source.discordUserId);
  const discordUsername = sanitizeText(source.discordUsername);
  if (!discordUserId || !discordUsername) {
    throw new ApiError(400, "discordUserId and discordUsername are required.");
  }

  const account = await requireExistingAccount(source);
  const nextAccount = await persistAccount(account, {
    discordUserId,
    discordUsername
  });

  return { user: publicAccount(nextAccount) };
}

export async function setAccountAdmin(source: Record<string, unknown>): Promise<{ user: PublicAccount }> {
  const account = await requireExistingAccount(source);
  const nextAccount = await persistAccount(account, {
    role: Boolean(source.enabled) ? "admin" : "user"
  });

  return { user: publicAccount(nextAccount) };
}

export async function setAccountStatus(source: Record<string, unknown>): Promise<{ user: PublicAccount }> {
  const nextStatus = normalizeAccountStatus(source.status);
  const account = await requireExistingAccount(source);
  const updates: Partial<UserRecord> & Partial<AppInstallationRecord> = {
    accountStatus: nextStatus
  };

  if (nextStatus === "terminated") {
    updates.role = "user";
    updates.subscriptionTier = "free";
    updates.paidFeatures = [];
  }

  const nextAccount = await persistAccount(account, updates);
  return { user: publicAccount(nextAccount) };
}

export async function setAccountSubscription(source: Record<string, unknown>): Promise<{ user: PublicAccount }> {
  const subscriptionTier = normalizeSubscriptionTier(source.subscriptionTier);
  const customFeatures = Array.isArray(source.paidFeatures) ? normalizeFeatureKeys(source.paidFeatures) : [];
  const paidFeatures = normalizeFeatureKeys([
    ...defaultPaidFeaturesForTier(subscriptionTier),
    ...customFeatures
  ]);

  const account = await requireExistingAccount(source);
  const nextAccount = await persistAccount(account, {
    subscriptionTier,
    paidFeatures
  });

  return { user: publicAccount(nextAccount) };
}

export async function grantAccountFeature(source: Record<string, unknown>): Promise<{ user: PublicAccount; activationURL?: string }> {
  const feature = normalizeFeatureKey(source.feature);
  if (!feature) {
    throw new ApiError(400, "feature is required.");
  }

  let account: AccountContext;
  try {
    account = await requireExistingAccount(source);
  } catch (error) {
    const requestedAppUuid = sanitizeText(source.appUuid);
    if (!(error instanceof ApiError) || error.statusCode !== 404 || !requestedAppUuid) {
      throw error;
    }

    account = await provisionPlaceholderInstallation(requestedAppUuid);
  }

  const currentPaidFeatures = account.account.paidFeatures;
  const nextAccount = await persistAccount(account, {
    subscriptionTier: feature === "4k-pro" ? "pro" : account.account.subscriptionTier,
    paidFeatures: normalizeFeatureKeys([feature, ...currentPaidFeatures])
  });

  return {
    user: publicAccount(nextAccount),
    ...(nextAccount.kind === "user" ? { activationURL: buildActivationURL(nextAccount.account, feature) } : {})
  };
}

export async function revokeAccountFeature(source: Record<string, unknown>): Promise<{ user: PublicAccount }> {
  const feature = normalizeFeatureKey(source.feature);
  if (!feature) {
    throw new ApiError(400, "feature is required.");
  }

  const account = await requireExistingAccount(source);
  const remainingFeatures = normalizeFeatureKeys(account.account.paidFeatures.filter((entry) => entry !== feature));
  const nextAccount = await persistAccount(account, {
    subscriptionTier: feature === "4k-pro" && remainingFeatures.length === 0 ? "free" : account.account.subscriptionTier,
    paidFeatures: remainingFeatures
  });

  return { user: publicAccount(nextAccount) };
}