import admin from "firebase-admin";

let initialized = false;

export function initializeFirebaseAdmin(): admin.app.App {
  if (!initialized) {
    if (admin.apps.length === 0) {
      admin.initializeApp();
    }
    initialized = true;
  }

  return admin.app();
}

export function getFirestore(): admin.firestore.Firestore {
  initializeFirebaseAdmin();
  return admin.firestore();
}

export const Timestamp = admin.firestore.Timestamp;
export const FieldValue = admin.firestore.FieldValue;