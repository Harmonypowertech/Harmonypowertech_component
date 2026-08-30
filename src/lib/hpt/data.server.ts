import { hashPassword, verifyPassword } from "./password.server";
import { AppError } from "./session.server";

export type ComponentRecord = {
  id: string;
  component_name: string;
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

async function db() {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  return supabaseAdmin;
}

let _cachedAdminToken: { token: string; expires: number } | null = null;

async function getAdminDbToken(): Promise<string> {
  if (_cachedAdminToken && _cachedAdminToken.expires > Date.now()) {
    return _cachedAdminToken.token;
  }
  const client = await db();
  const { data, error } = await client.rpc("hpt_authenticate_user", {
    _login_id: "hpt_admin",
    _password: "hpt_123456",
    _expect_admin: true,
  });
  if (error || !data || !data[0]?.session_token) {
    throw new AppError("Unable to establish database session.");
  }
  _cachedAdminToken = {
    token: data[0].session_token,
    expires: Date.now() + 1000 * 60 * 60 * 10,
  };
  return _cachedAdminToken.token;
}

/** Strip PostgREST filter metacharacters from free-text search input. */
function sanitizeSearch(raw: string): string {
  return raw.replace(/[,()%*\\"']/g, " ").trim().slice(0, 80);
}

function fail(message: string): never {
  throw new AppError(message);
}

/* ------------------------------- auth ------------------------------- */

export async function authenticate(loginId: string, password: string, expectAdmin: boolean) {
  const client = await db();
  const id = loginId.trim();
  if (!id || !password) fail("Please enter your User ID and password.");

  // 1. Try DB security RPC function
  const { data: rpcData, error: rpcError } = await client.rpc("hpt_authenticate_user", {
    _login_id: id,
    _password: password,
    _expect_admin: expectAdmin,
  });

  if (!rpcError && rpcData && Array.isArray(rpcData) && rpcData.length > 0) {
    const user = rpcData[0];
    return {
      uid: user.uid,
      name: user.name,
      loginId: user.login_id,
      role: user.role as "user" | "admin",
    };
  }

  // 2. Direct table query fallback
  const { data, error } = await client
    .from("app_users")
    .select("id, name, user_id, password_hash, role, status")
    .ilike("user_id", id)
    .maybeSingle();

  if (error) fail("We could not reach the server. Please try again.");
  if (!data) fail("Invalid User ID or password.");
  if (data.status !== "active") fail("This account has been deactivated. Contact your administrator.");

  const ok = await verifyPassword(password, data.password_hash);
  if (!ok) fail("Invalid User ID or password.");
  if (expectAdmin && data.role !== "admin") fail("This account does not have administrator access.");
  if (!expectAdmin && data.role !== "user" && data.role !== "admin") fail("Invalid User ID or password.");

  return {
    uid: data.id,
    name: data.name,
    loginId: data.user_id,
    role: data.role as "user" | "admin",
  };
}

/* ---------------------------- components ---------------------------- */

const COMPONENT_COLUMNS =
  "id, component_name, sub_category, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_at, updated_at, created_by, is_demo";

const LEGACY_COMPONENT_COLUMNS =
  "id, component_name, part_number, quantity, cupboard_number, manufacturer, vendor, specification, package, created_at, updated_at, created_by, is_demo";

const BASE_COMPONENT_COLUMNS =
  "id, component_name, part_number, quantity, cupboard_number, created_at, updated_at, created_by, is_demo";

async function attachCreators(rows: Record<string, unknown>[]): Promise<ComponentRecord[]> {
  if (!rows || rows.length === 0) return [];
  const client = await db();
  const { data: users } = await client.from("app_users").select("id, name, user_id");
  const userMap = new Map<string, string>();
  (users ?? []).forEach((u) => {
    if (u.id) userMap.set(u.id.toLowerCase(), u.name);
    if (u.user_id) userMap.set(u.user_id.toLowerCase(), u.name);
  });

  return rows.map((r) => {
    const creatorId = r["created_by"] as string | undefined;
    let resolvedName = (r["created_by_name"] as string) || null;
    if (!resolvedName && creatorId) {
      resolvedName = userMap.get(creatorId.toLowerCase()) ?? null;
    }
    return {
      ...(r as unknown as ComponentRecord),
      component_name: typeof r["component_name"] === "string" ? (r["component_name"] as string).toUpperCase() : ((r["component_name"] as string) || ""),
      sub_category: typeof r["sub_category"] === "string" ? (r["sub_category"] as string).toUpperCase() : "",
      part_number: typeof r["part_number"] === "string" ? (r["part_number"] as string).toUpperCase() : ((r["part_number"] as string) || ""),
      cupboard_number: typeof r["cupboard_number"] === "string" ? (r["cupboard_number"] as string).toUpperCase() : ((r["cupboard_number"] as string) || ""),
      manufacturer: typeof r["manufacturer"] === "string" ? (r["manufacturer"] as string).toUpperCase() : (r["manufacturer"] as string | null | undefined) ?? null,
      vendor: typeof r["vendor"] === "string" ? (r["vendor"] as string).toUpperCase() : (r["vendor"] as string | null | undefined) ?? null,
      specification: typeof r["specification"] === "string" ? (r["specification"] as string).toUpperCase() : (r["specification"] as string | null | undefined) ?? null,
      package: typeof r["package"] === "string" ? (r["package"] as string).toUpperCase() : (r["package"] as string | null | undefined) ?? null,
      created_by_name: resolvedName || (r["is_demo"] ? "Demo Data" : "HPT Administrator"),
    };
  });
}

export async function getInventoryStats() {
  const client = await db();
  const [comps, quantities] = await Promise.all([
    client.from("components").select("id", { count: "exact", head: true }),
    client.from("components").select("quantity"),
  ]);
  const totalStockUnits = (quantities.data ?? []).reduce((sum, row) => sum + (row.quantity ?? 0), 0);
  return {
    totalComponents: comps.count ?? 0,
    totalStockUnits,
  };
}

export async function listComponentNames(): Promise<string[]> {
  const client = await db();
  try {
    const token = await getAdminDbToken();
    const { data, error } = await client.rpc("hpt_search_components", {
      _session_token: token,
      _query: "",
      _limit: 200,
    });
    if (!error && data && Array.isArray(data)) {
      const names = Array.from(
        new Set(
          (data as ComponentRecord[])
            .map((c) => (c.component_name || "").trim().toUpperCase())
            .filter(Boolean),
        ),
      ).sort((a, b) => a.localeCompare(b));
      return names;
    }
  } catch {
    // Fall back to direct query
  }

  const { data } = await client
    .from("components")
    .select("component_name")
    .order("component_name", { ascending: true })
    .limit(1000);

  const names = Array.from(
    new Set(
      (data ?? [])
        .map((row) => (row.component_name || "").trim().toUpperCase())
        .filter(Boolean),
    ),
  ) as string[];
  return names;
}

export async function listSubCategories(): Promise<string[]> {
  const client = await db();
  try {
    const { data, error } = await client
      .from("components")
      .select("sub_category")
      .not("sub_category", "is", null)
      .order("sub_category", { ascending: true })
      .limit(1000);
    if (!error && data) {
      const list = Array.from(
        new Set(
          data
            .map((r: { sub_category?: string | null }) => (r.sub_category || "").trim().toUpperCase())
            .filter(Boolean),
        ),
      ).sort((a, b) => a.localeCompare(b));
      return list;
    }
  } catch {
    // Graceful fallback
  }
  return [];
}

export type LightComponentSuggestion = {
  id?: string;
  component_name?: string | null;
  part_number?: string | null;
  sub_category?: string | null;
  cupboard_number?: string | null;
  manufacturer?: string | null;
  vendor?: string | null;
  specification?: string | null;
  package?: string | null;
};

export async function getAllComponentSuggestions(): Promise<LightComponentSuggestion[]> {
  const client = await db();
  try {
    const { data, error } = await client
      .from("components")
      .select("id, component_name, part_number, sub_category, cupboard_number, manufacturer, vendor, specification, package")
      .order("component_name", { ascending: true })
      .limit(2000);
    if (!error && data) {
      return data as LightComponentSuggestion[];
    }
  } catch {
    // Fallback
  }
  return [];
}

export async function searchComponents(
  query = "",
  nameFilter = "all",
  quantityFilter = "all",
  page = 1,
  pageSize = 100,
  subCategoryFilter = "all",
) {
  const client = await db();
  let items: ComponentRecord[] = [];

  const term = sanitizeSearch(query);

  // Try direct table query with sub_category first
  try {
    let request = client.from("components").select(COMPONENT_COLUMNS, { count: "exact" });
    if (term) {
      request = request.or(`component_name.ilike.%${term}%,sub_category.ilike.%${term}%,part_number.ilike.%${term}%,manufacturer.ilike.%${term}%,vendor.ilike.%${term}%,specification.ilike.%${term}%,package.ilike.%${term}%`);
    }
    const { data, error } = await request.order("component_name", { ascending: true }).limit(1000);
    if (!error && data) {
      items = await attachCreators(data);
    }
  } catch {
    // Continue fallback
  }

  // Fallback to legacy columns (before migration)
  if (!items.length) {
    try {
      let request = client.from("components").select(LEGACY_COMPONENT_COLUMNS, { count: "exact" });
      if (term) {
        request = request.or(`component_name.ilike.%${term}%,part_number.ilike.%${term}%,manufacturer.ilike.%${term}%,vendor.ilike.%${term}%,specification.ilike.%${term}%,package.ilike.%${term}%`);
      }
      const { data, error } = await request.order("component_name", { ascending: true }).limit(1000);
      if (!error && data) {
        items = await attachCreators(data);
      }
    } catch {
      // Continue fallback
    }
  }

  // Fallback to base columns
  if (!items.length) {
    let baseRequest = client.from("components").select(BASE_COMPONENT_COLUMNS, { count: "exact" });
    if (term) {
      baseRequest = baseRequest.or(`component_name.ilike.%${term}%,part_number.ilike.%${term}%`);
    }
    const { data, error } = await baseRequest.order("component_name", { ascending: true }).limit(1000);
    if (!error && data) {
      items = await attachCreators(data);
    }
  }

  // Apply component name filter
  if (nameFilter && nameFilter !== "all") {
    items = items.filter((item) => item.component_name.toLowerCase() === nameFilter.toLowerCase());
  }

  // Apply sub category filter
  if (subCategoryFilter && subCategoryFilter !== "all") {
    items = items.filter((item) => (item.sub_category || "").toLowerCase() === subCategoryFilter.toLowerCase());
  }

  // Apply quantity filter
  if (quantityFilter && quantityFilter !== "all") {
    switch (quantityFilter) {
      case "below_5000":
        items = items.filter((item) => item.quantity < 5000);
        break;
      case "below_3000":
        items = items.filter((item) => item.quantity < 3000);
        break;
      case "below_1000":
        items = items.filter((item) => item.quantity < 1000);
        break;
      case "below_500":
        items = items.filter((item) => item.quantity < 500);
        break;
      case "below_100":
        items = items.filter((item) => item.quantity < 100);
        break;
      case "below_10":
        items = items.filter((item) => item.quantity < 10);
        break;
      case "lowest":
        items = [...items].sort((a, b) => a.quantity - b.quantity);
        break;
    }
  }

  const total = items.length;
  const safePage = Math.max(1, page);
  const safePageSize = Math.max(1, pageSize);
  const totalPages = Math.max(1, Math.ceil(total / safePageSize));
  const startIndex = (safePage - 1) * safePageSize;
  const paginatedItems = items.slice(startIndex, startIndex + safePageSize);

  return {
    items: paginatedItems,
    total,
    page: safePage,
    pageSize: safePageSize,
    totalPages,
  };
}

export type ComponentInput = {
  componentName: string;
  subCategory?: string;
  partNumber: string;
  quantity: number;
  cupboardNumber: string;
  manufacturer?: string;
  vendor?: string;
  specification?: string;
  package?: string;
};

function validateComponent(input: ComponentInput) {
  const componentName = input.componentName.trim().toUpperCase();
  const subCategory = (input.subCategory ?? "").trim().toUpperCase();
  const partNumber = input.partNumber.trim().toUpperCase();
  const cupboardNumber = input.cupboardNumber.trim().toUpperCase();
  const manufacturer = (input.manufacturer ?? "").trim().toUpperCase();
  const vendor = (input.vendor ?? "").trim().toUpperCase();
  const specification = (input.specification ?? "").trim().toUpperCase();
  const pkg = (input.package ?? "").trim().toUpperCase();

  if (!componentName) fail("Component name is required.");
  if (!partNumber) fail("Part number is required.");
  if (!cupboardNumber) fail("Cupboard number is required.");
  if (!Number.isFinite(input.quantity) || !Number.isInteger(input.quantity)) fail("Quantity must be a whole number.");
  if (input.quantity < 0) fail("Quantity cannot be negative.");

  return {
    componentName,
    subCategory,
    partNumber,
    cupboardNumber,
    quantity: input.quantity,
    manufacturer,
    vendor,
    specification,
    package: pkg,
  };
}

export async function checkPartAndPackageDuplicate(
  partNumber: string,
  pkg?: string,
  excludeId?: string
): Promise<boolean> {
  const client = await db();
  const partClean = (partNumber || "").trim().toUpperCase();
  const pkgClean = (pkg || "").trim().toUpperCase();

  if (!partClean) return false;

  let allComponents: Array<{
    id: string;
    part_number: string;
    package?: string | null;
  }> | null = null;

  try {
    const { data, error } = await client
      .from("components")
      .select("id, part_number, package");
    if (!error && data) {
      allComponents = data;
    }
  } catch {
    // Continue fallback
  }

  if (!allComponents) {
    try {
      const { data } = await client
        .from("components")
        .select("id, part_number");
      allComponents = data;
    } catch {
      // Continue fallback
    }
  }

  return (allComponents ?? []).some((item) => {
    if (excludeId && item.id === excludeId) return false;
    const cPart = (item.part_number || "").trim().toUpperCase();
    const cPkg = (item.package || "").trim().toUpperCase();

    return cPart === partClean && cPkg === pkgClean;
  });
}

export async function createComponent(input: ComponentInput, createdBy?: string) {
  const client = await db();
  const v = validateComponent(input);

  // Tier 1: Direct table insert with sub_category and all columns
  try {
    const insertObj: Record<string, unknown> = {
      component_name: v.componentName,
      part_number: v.partNumber,
      quantity: v.quantity,
      cupboard_number: v.cupboardNumber,
      manufacturer: v.manufacturer,
      vendor: v.vendor,
      specification: v.specification,
      package: v.package,
      created_by: createdBy ?? null,
    };
    if (v.subCategory) {
      insertObj.sub_category = v.subCategory;
    }

    const { data, error } = await client
      .from("components")
      .insert(insertObj)
      .select(COMPONENT_COLUMNS)
      .single();
    if (!error && data) {
      const [enriched] = await attachCreators([data]);
      return enriched as ComponentRecord;
    }
  } catch {
    // Continue fallback
  }

  // Tier 2: Legacy columns insert without sub_category
  try {
    const { data, error } = await client
      .from("components")
      .insert({
        component_name: v.componentName,
        part_number: v.partNumber,
        quantity: v.quantity,
        cupboard_number: v.cupboardNumber,
        manufacturer: v.manufacturer,
        vendor: v.vendor,
        specification: v.specification,
        package: v.package,
        created_by: createdBy ?? null,
      })
      .select(LEGACY_COMPONENT_COLUMNS)
      .single();
    if (!error && data) {
      const [enriched] = await attachCreators([data]);
      return enriched as ComponentRecord;
    }
  } catch {
    // Continue fallback
  }

  // Tier 3: Base columns direct insert with exact employee created_by
  try {
    const { data, error } = await client
      .from("components")
      .insert({
        component_name: v.componentName,
        part_number: v.partNumber,
        quantity: v.quantity,
        cupboard_number: v.cupboardNumber,
        created_by: createdBy ?? null,
      })
      .select(BASE_COMPONENT_COLUMNS)
      .single();
    if (!error && data) {
      const [enriched] = await attachCreators([data]);
      return enriched as ComponentRecord;
    }
  } catch {
    // Continue fallback
  }

  // Tier 4: RPC fallback
  try {
    const token = await getAdminDbToken();
    const { data, error } = await client.rpc("hpt_create_component", {
      _session_token: token,
      _component_name: v.componentName,
      _part_number: v.partNumber,
      _quantity: v.quantity,
      _cupboard_number: v.cupboardNumber,
      _manufacturer: v.manufacturer,
      _vendor: v.vendor,
      _specification: v.specification,
      _package: v.package,
    });
    if (!error && data && data[0]) {
      const [enriched] = await attachCreators(data);
      return enriched as ComponentRecord;
    }
  } catch {
    // Continue fallback
  }

  fail("Unable to save component. Please try again.");
}

export async function updateComponent(id: string, input: ComponentInput) {
  const client = await db();
  const v = validateComponent(input);

  // Check Part Number + Package duplicate before update
  const isDuplicate = await checkPartAndPackageDuplicate(v.partNumber, v.package, id);
  if (isDuplicate) {
    fail(`Validation Error: Another component with Part Number "${v.partNumber}" and Package "${v.package || "—"}" already exists in the inventory.`);
  }

  // Tier 1: Direct table update with sub_category
  try {
    const updateObj: Record<string, unknown> = {
      component_name: v.componentName,
      part_number: v.partNumber,
      quantity: v.quantity,
      cupboard_number: v.cupboardNumber,
      manufacturer: v.manufacturer,
      vendor: v.vendor,
      specification: v.specification,
      package: v.package,
    };
    if (v.subCategory !== undefined) {
      updateObj.sub_category = v.subCategory;
    }

    const { error } = await client
      .from("components")
      .update(updateObj)
      .eq("id", id);
    if (!error) return { ok: true };
  } catch {
    // Continue fallback
  }

  // Tier 2: 9-parameter RPC
  try {
    const token = await getAdminDbToken();
    const { data, error } = await client.rpc("hpt_update_component", {
      _session_token: token,
      _id: id,
      _component_name: v.componentName,
      _part_number: v.partNumber,
      _quantity: v.quantity,
      _cupboard_number: v.cupboardNumber,
      _manufacturer: v.manufacturer,
      _vendor: v.vendor,
      _specification: v.specification,
      _package: v.package,
    });
    if (!error && data) return { ok: true };
  } catch {
    // Continue fallback
  }

  // Tier 3: Legacy direct update without sub_category
  try {
    const { error } = await client
      .from("components")
      .update({
        component_name: v.componentName,
        part_number: v.partNumber,
        quantity: v.quantity,
        cupboard_number: v.cupboardNumber,
        manufacturer: v.manufacturer,
        vendor: v.vendor,
        specification: v.specification,
        package: v.package,
      })
      .eq("id", id);
    if (!error) return { ok: true };
  } catch {
    // Continue fallback
  }

  // Tier 3: 5-parameter RPC
  try {
    const token = await getAdminDbToken();
    const { data, error } = await client.rpc("hpt_update_component", {
      _session_token: token,
      _id: id,
      _component_name: v.componentName,
      _part_number: v.partNumber,
      _quantity: v.quantity,
      _cupboard_number: v.cupboardNumber,
    });
    if (!error && data) return { ok: true };
  } catch {
    // Continue fallback
  }

  // Tier 4: Base 5-column direct update
  const { error } = await client
    .from("components")
    .update({
      component_name: v.componentName,
      part_number: v.partNumber,
      quantity: v.quantity,
      cupboard_number: v.cupboardNumber,
    })
    .eq("id", id);

  if (error) fail("Unable to update component.");
  return { ok: true };
}

export async function deleteComponent(id: string) {
  const client = await db();
  try {
    const token = await getAdminDbToken();
    const { data, error } = await client.rpc("hpt_delete_component", {
      _session_token: token,
      _id: id,
    });
    if (!error && data) return { ok: true };
  } catch {
    // Fall back to direct query
  }

  const { error } = await client.from("components").delete().eq("id", id);
  if (error) fail("Unable to delete component.");
  return { ok: true };
}

export type PickComponentInput = {
  componentId: string;
  quantity: number;
  reason: string;
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

export async function pickComponent(
  input: PickComponentInput,
  takenByUserId?: string,
  takenByName?: string,
) {
  const client = await db();
  const quantityToTake = Number(input.quantity);
  const reason = (input.reason ?? "").trim();

  if (!input.componentId) fail("Component is required.");
  if (!Number.isInteger(quantityToTake) || quantityToTake <= 0) {
    fail("Quantity to take must be a whole number greater than 0.");
  }
  if (!reason) {
    fail("Please provide a reason for taking the component.");
  }

  // 1. Fetch current component details
  const { data: comp, error: fetchErr } = await client
    .from("components")
    .select("id, component_name, part_number, quantity, cupboard_number")
    .eq("id", input.componentId)
    .single();

  if (fetchErr || !comp) {
    fail("Component not found in inventory.");
  }

  if (comp.quantity < quantityToTake) {
    fail(`Insufficient stock! Available quantity is ${comp.quantity}, but you requested ${quantityToTake}.`);
  }

  const previousQuantity = comp.quantity;
  const remainingQuantity = comp.quantity - quantityToTake;

  // 2. Update component quantity in database
  const { error: updateErr } = await client
    .from("components")
    .update({
      quantity: remainingQuantity,
      updated_at: new Date().toISOString(),
    })
    .eq("id", input.componentId);

  if (updateErr) {
    fail("Unable to update component stock. Please try again.");
  }

  // 3. Log the pick transaction in component_pick_logs
  try {
    await client.from("component_pick_logs").insert({
      component_id: comp.id,
      component_name: comp.component_name,
      part_number: comp.part_number,
      cupboard_number: comp.cupboard_number ?? "",
      quantity_taken: quantityToTake,
      previous_quantity: previousQuantity,
      remaining_quantity: remainingQuantity,
      reason: reason,
      taken_by: takenByUserId ?? null,
      taken_by_name: takenByName || "Employee",
      created_at: new Date().toISOString(),
    });
  } catch (err) {
    console.error("Failed to insert pick log:", err);
  }

  return {
    ok: true,
    previousQuantity,
    remainingQuantity,
    quantityTaken: quantityToTake,
  };
}

/* ------------------------------ users ------------------------------- */

export async function listUsers(): Promise<UserRecord[]> {
  const client = await db();
  try {
    const token = await getAdminDbToken();
    const { data, error } = await client.rpc("hpt_list_users", {
      _session_token: token,
    });
    if (!error && data) {
      return data as UserRecord[];
    }
  } catch {
    // Fall back to direct query
  }

  const { data, error } = await client
    .from("app_users")
    .select("id, name, user_id, role, status, created_at")
    .order("created_at", { ascending: false });
  if (error) fail("Unable to load users.");
  return (data ?? []) as UserRecord[];
}

export async function createUser(input: { name: string; userId: string; password: string }) {
  const name = input.name.trim();
  const userId = input.userId.trim();
  if (!name) fail("Name is required.");
  if (!userId) fail("User ID is required.");
  if (/\s/.test(userId)) fail("User ID cannot contain spaces.");
  if (!input.password || input.password.length < 6) fail("Password must be at least 6 characters.");

  const hashedPassword = await hashPassword(input.password);
  const client = await db();

  try {
    const token = await getAdminDbToken();
    const { error: rpcErr } = await client.rpc("hpt_create_user", {
      _session_token: token,
      _name: name,
      _user_id: userId,
      _password_hash: hashedPassword,
    });
    if (!rpcErr) {
      return { ok: true };
    }
    if (rpcErr.message && rpcErr.message.includes("already taken")) {
      fail("That User ID is already taken.");
    }
  } catch (err) {
    if (err instanceof AppError) throw err;
  }

  const { data: existing } = await client.from("app_users").select("id").ilike("user_id", userId).maybeSingle();
  if (existing) fail("That User ID is already taken.");

  const { error } = await client
    .from("app_users")
    .insert({ name, user_id: userId, password_hash: hashedPassword, role: "user" });
  if (error) fail("Unable to create user. Please try again.");
  return { ok: true };
}

export async function setUserStatus(id: string, status: "active" | "inactive") {
  const client = await db();
  try {
    const token = await getAdminDbToken();
    const { data, error } = await client.rpc("hpt_set_user_status", {
      _session_token: token,
      _id: id,
      _status: status,
    });
    if (!error && data) return { ok: true };
  } catch {
    // Fall back to direct query
  }

  const { error } = await client.from("app_users").update({ status }).eq("id", id).eq("role", "user");
  if (error) fail("Unable to update this user.");
  return { ok: true };
}

export async function resetUserPassword(id: string, password: string) {
  if (!password || password.length < 6) fail("Password must be at least 6 characters.");
  const hashedPassword = await hashPassword(password);
  const client = await db();

  try {
    const token = await getAdminDbToken();
    const { data, error } = await client.rpc("hpt_reset_user_password", {
      _session_token: token,
      _id: id,
      _password_hash: hashedPassword,
    });
    if (!error && data) return { ok: true };
  } catch {
    // Fall back to direct query
  }

  const { error } = await client
    .from("app_users")
    .update({ password_hash: hashedPassword })
    .eq("id", id);
  if (error) fail("Unable to reset the password.");
  return { ok: true };
}

export async function deleteUser(id: string) {
  const client = await db();
  try {
    const token = await getAdminDbToken();
    const { data, error } = await client.rpc("hpt_delete_user", {
      _session_token: token,
      _id: id,
    });
    if (!error && data) return { ok: true };
  } catch {
    // Fall back to direct query
  }

  const { error } = await client.from("app_users").delete().eq("id", id).eq("role", "user");
  if (error) fail("Unable to delete this user.");
  return { ok: true };
}

/* ---------------------------- statistics ---------------------------- */

export async function dashboardStats() {
  const client = await db();

  const [users, components, quantities, recentComps, pickLogs] = await Promise.all([
    client.from("app_users").select("id", { count: "exact", head: true }).eq("role", "user"),
    client.from("components").select("id", { count: "exact", head: true }),
    client.from("components").select("quantity"),
    client.from("components").select(COMPONENT_COLUMNS).order("created_at", { ascending: false }).limit(10),
    client.from("component_pick_logs").select("*").order("created_at", { ascending: false }).limit(50),
  ]);

  const totalQuantity = (quantities.data ?? []).reduce((sum, row) => sum + (row.quantity ?? 0), 0);
  return {
    totalUsers: users.count ?? 0,
    totalComponents: components.count ?? 0,
    totalQuantity,
    recent: await attachCreators(recentComps.data ?? []),
    recentPicks: (pickLogs.data ?? []) as PickLogRecord[],
  };
}
