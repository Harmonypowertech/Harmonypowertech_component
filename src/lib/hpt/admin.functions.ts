import { createServerFn } from "@tanstack/react-start";

export const adminStatsFn = createServerFn({ method: "GET" }).handler(async () => {
  const { requireAdmin } = await import("./session.server");
  const { dashboardStats } = await import("./data.server");
  await requireAdmin();
  return await dashboardStats();
});

export const listUsersFn = createServerFn({ method: "GET" }).handler(async () => {
  const { requireAdmin } = await import("./session.server");
  const { listUsers } = await import("./data.server");
  await requireAdmin();
  return await listUsers();
});

export const createUserFn = createServerFn({ method: "POST" })
  .inputValidator((input: { name: string; userId: string; password: string }) => input)
  .handler(async ({ data }) => {
    const { requireAdmin } = await import("./session.server");
    const { createUser } = await import("./data.server");
    await requireAdmin();
    return await createUser(data);
  });

export const setUserStatusFn = createServerFn({ method: "POST" })
  .inputValidator((input: { id: string; status: "active" | "inactive" }) => input)
  .handler(async ({ data }) => {
    const { requireAdmin } = await import("./session.server");
    const { setUserStatus } = await import("./data.server");
    await requireAdmin();
    return await setUserStatus(data.id, data.status);
  });

export const resetPasswordFn = createServerFn({ method: "POST" })
  .inputValidator((input: { id: string; password: string }) => input)
  .handler(async ({ data }) => {
    const { requireAdmin } = await import("./session.server");
    const { resetUserPassword } = await import("./data.server");
    await requireAdmin();
    return await resetUserPassword(data.id, data.password);
  });

export const deleteUserFn = createServerFn({ method: "POST" })
  .inputValidator((input: { id: string }) => input)
  .handler(async ({ data }) => {
    const { requireAdmin } = await import("./session.server");
    const { deleteUser } = await import("./data.server");
    await requireAdmin();
    return await deleteUser(data.id);
  });
