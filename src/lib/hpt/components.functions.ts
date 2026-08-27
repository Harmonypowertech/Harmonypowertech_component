import { createServerFn } from "@tanstack/react-start";

export const searchComponentsFn = createServerFn({ method: "GET" })
  .inputValidator(
    (input: {
      query?: string;
      nameFilter?: string;
      subCategoryFilter?: string;
      quantityFilter?: string;
      page?: number;
      pageSize?: number;
    }) => input,
  )
  .handler(async ({ data }) => {
    const { requireUser } = await import("./session.server");
    const { searchComponents } = await import("./data.server");
    await requireUser();
    return await searchComponents(
      data?.query ?? "",
      data?.nameFilter ?? "all",
      data?.quantityFilter ?? "all",
      data?.page ?? 1,
      data?.pageSize ?? 100,
      data?.subCategoryFilter ?? "all",
    );
  });

export const listComponentNamesFn = createServerFn({ method: "GET" }).handler(async () => {
  const { requireUser } = await import("./session.server");
  const { listComponentNames } = await import("./data.server");
  await requireUser();
  return await listComponentNames();
});

export const listSubCategoriesFn = createServerFn({ method: "GET" }).handler(async () => {
  const { requireUser } = await import("./session.server");
  const { listSubCategories } = await import("./data.server");
  await requireUser();
  return await listSubCategories();
});

export const getInventoryStatsFn = createServerFn({ method: "GET" }).handler(async () => {
  const { requireUser } = await import("./session.server");
  const { getInventoryStats } = await import("./data.server");
  await requireUser();
  return await getInventoryStats();
});

export const addComponentFn = createServerFn({ method: "POST" })
  .inputValidator(
    (input: {
      componentName: string;
      subCategory?: string;
      partNumber: string;
      quantity: number;
      cupboardNumber: string;
      manufacturer?: string;
      vendor?: string;
      specification?: string;
      package?: string;
    }) => input,
  )
  .handler(async ({ data }) => {
    const { requireUser } = await import("./session.server");
    const { createComponent } = await import("./data.server");
    const session = await requireUser();
    return await createComponent(data, session.uid);
  });

export const updateComponentFn = createServerFn({ method: "POST" })
  .inputValidator(
    (input: {
      id: string;
      componentName: string;
      subCategory?: string;
      partNumber: string;
      quantity: number;
      cupboardNumber: string;
      manufacturer?: string;
      vendor?: string;
      specification?: string;
      package?: string;
    }) => input,
  )
  .handler(async ({ data }) => {
    const { requireUser } = await import("./session.server");
    const { updateComponent } = await import("./data.server");
    await requireUser();
    const { id, ...rest } = data;
    return await updateComponent(id, rest);
  });

export const deleteComponentFn = createServerFn({ method: "POST" })
  .inputValidator((input: { id: string }) => input)
  .handler(async ({ data }) => {
    const { requireAdmin } = await import("./session.server");
    const { deleteComponent } = await import("./data.server");
    await requireAdmin();
    return await deleteComponent(data.id);
  });

export const pickComponentFn = createServerFn({ method: "POST" })
  .inputValidator(
    (input: {
      componentId: string;
      quantity: number;
      reason: string;
    }) => input,
  )
  .handler(async ({ data }) => {
    const { requireUser } = await import("./session.server");
    const { pickComponent } = await import("./data.server");
    const session = await requireUser();
    return await pickComponent(data, session.uid, session.name);
  });
