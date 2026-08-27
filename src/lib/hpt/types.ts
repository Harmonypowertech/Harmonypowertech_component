export type ComponentRecord = {
  id: string;
  component_name: string;
  sub_category?: string | null;
  part_number: string;
  quantity: number;
  cupboard_number: string;
  manufacturer?: string | null;
  vendor?: string | null;
  specification?: string | null;
  package?: string | null;
  created_at: string;
  updated_at: string;
  created_by: string | null;
  created_by_name: string | null;
  is_demo: boolean;
};

export type UserRecord = {
  id: string;
  name: string;
  user_id: string;
  role: "user" | "admin";
  status: "active" | "inactive";
  created_at: string;
};

export type SessionUser = {
  uid: string;
  name: string;
  loginId: string;
  role: "user" | "admin";
};

export type PickLogRecord = {
  id: string;
  component_id: string | null;
  component_name: string;
  part_number: string;
  cupboard_number: string | null;
  quantity_taken: number;
  previous_quantity: number;
  remaining_quantity: number;
  reason: string;
  taken_by: string | null;
  taken_by_name: string;
  created_at: string;
};

export type PickComponentInput = {
  componentId: string;
  quantity: number;
  reason: string;
};

/** Friendly message extraction for server-function errors. */
export function errorMessage(error: unknown, fallback: string): string {
  if (!error) return fallback;
  if (typeof error === "string" && error.trim()) return error;
  if (typeof error === "object") {
    const obj = error as Record<string, any>;
    if (typeof obj.data === "string" && obj.data.trim()) return obj.data;
    if (obj.data && typeof obj.data.message === "string" && obj.data.message.trim()) return obj.data.message;
    if (typeof obj.message === "string" && obj.message.trim()) {
      // Remove generic wrapper prefixes if present
      const clean = obj.message.replace(/^Server error:\s*/i, "").trim();
      if (!/^Failed to (fetch|load|call server)/i.test(clean)) {
        return clean;
      }
    }
    if (obj.cause && typeof obj.cause === "object" && typeof (obj.cause as any).message === "string") {
      return (obj.cause as any).message;
    }
  }
  return fallback;
}
