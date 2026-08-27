import { createServerFn } from "@tanstack/react-start";

export const getCurrentSession = createServerFn({ method: "GET" }).handler(async () => {
  const { readSession } = await import("./session.server");
  return await readSession();
});

export const loginUser = createServerFn({ method: "POST" })
  .inputValidator((input: { loginId: string; password: string; admin?: boolean }) => input)
  .handler(async ({ data }) => {
    const { authenticate } = await import("./data.server");
    const { writeSession } = await import("./session.server");
    const session = await authenticate(data.loginId, data.password, data.admin === true);
    await writeSession(session);
    return session;
  });

export const logout = createServerFn({ method: "POST" }).handler(async () => {
  const { destroySession } = await import("./session.server");
  await destroySession();
  return { ok: true };
});
