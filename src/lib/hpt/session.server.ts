import { getCookie, useSession } from "@tanstack/react-start/server";

export type HptSession = {
  uid: string;
  name: string;
  loginId: string;
  role: "user" | "admin";
};

export type SessionInfo = HptSession | null;

async function sessionPassword(): Promise<string> {
  const configured =
    typeof process !== "undefined" && process.env ? process.env["HPT_SESSION_SECRET"] : undefined;
  if (configured && configured.length >= 32) return configured;

  // Use available Supabase keys to derive session password
  const serviceKey =
    (typeof process !== "undefined" && process.env
      ? process.env["SUPABASE_SERVICE_ROLE_KEY"] ||
        process.env["SUPABASE_PUBLISHABLE_KEY"] ||
        process.env["VITE_SUPABASE_PUBLISHABLE_KEY"]
      : undefined);

  if (serviceKey && serviceKey.length >= 32) {
    const material = new TextEncoder().encode(`hpt-session-v1:${serviceKey}`);
    const digest = await crypto.subtle.digest("SHA-256", material);
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  }

  // Built-in stable fallback secret (52 characters)
  const defaultSecret = "hpt-default-fallback-session-secret-key-2026-secure-32chars";
  const material = new TextEncoder().encode(`hpt-session-v1:${defaultSecret}`);
  const digest = await crypto.subtle.digest("SHA-256", material);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sessionConfig() {
  const password = await sessionPassword();
  if (!password) {
    throw new AppError(
      "Sign-in is not configured on this deployment. Please contact the administrator.",
    );
  }
  return {
    password,
    name: "hpt_session",
    maxAge: 60 * 60 * 12,
    cookie: {
      httpOnly: true,
      sameSite: "lax" as const,
      secure: true,
      path: "/",
    },
  };
}

export async function readSession(): Promise<SessionInfo> {
  // A signed-out visitor has nothing to decrypt. Avoid requiring deployment
  // secrets merely to render the public sign-in screen.
  if (!getCookie("hpt_session")) return null;
  try {
    const session = await useSession<HptSession>(await sessionConfig());
    const data = session.data as Partial<HptSession> | undefined;
    if (!data || !data.uid || !data.loginId || !data.role) return null;
    return {
      uid: data.uid,
      name: data.name ?? data.loginId,
      loginId: data.loginId,
      role: data.role,
    };
  } catch {
    return null;
  }
}

export async function writeSession(data: HptSession): Promise<void> {
  const session = await useSession<HptSession>(await sessionConfig());
  await session.update(data);
}

export async function destroySession(): Promise<void> {
  if (!getCookie("hpt_session")) return;
  const session = await useSession<HptSession>(await sessionConfig());
  await session.clear();
}

export class AppError extends Error {}

export async function requireUser(): Promise<HptSession> {
  const data = await readSession();
  if (!data) throw new AppError("Your session has expired. Please sign in again.");
  return data;
}

export async function requireAdmin(): Promise<HptSession> {
  const data = await requireUser();
  if (data.role !== "admin") throw new AppError("You are not authorized to perform this action.");
  return data;
}
