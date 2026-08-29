import { createFileRoute, redirect } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { AlertCircle, Boxes, ChevronLeft, ChevronRight, Layers, Loader2, PackageMinus, PackagePlus, Pencil, RotateCcw, Search, Tag, X } from "lucide-react";
import { toast } from "sonner";

import { AppHeader } from "@/components/hpt/AppHeader";
import { ComponentTable } from "@/components/hpt/ComponentTable";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { getCurrentSession } from "@/lib/hpt/auth.functions";
import {
  addComponentFn,
  getInventoryStatsFn,
  listComponentNamesFn,
  listSubCategoriesFn,
  pickComponentFn,
  searchComponentsFn,
  updateComponentFn,
} from "@/lib/hpt/components.functions";
import { errorMessage, type ComponentRecord } from "@/lib/hpt/types";

export const Route = createFileRoute("/dashboard")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Component Search Dashboard | Harmony Powertech" },
      {
        name: "description",
        content:
          "Search Harmony Powertech electronic components by name or part number to see live stock quantities and exact cupboard locations.",
      },
      { property: "og:title", content: "Component Search Dashboard | Harmony Powertech" },
      {
        property: "og:description",
        content: "Live component search: quantities, part numbers and cupboard locations for HPT employees.",
      },
    ],
  }),
  beforeLoad: async () => {
    try {
      const session = await getCurrentSession();
      if (!session) throw redirect({ to: "/" });
      return { session };
    } catch (err) {
      if (err && typeof err === "object" && "to" in err) throw err;
      throw redirect({ to: "/" });
    }
  },
  component: Dashboard,
  errorComponent: () => (
    <div className="flex min-h-screen items-center justify-center p-6 text-center text-muted-foreground">
      The dashboard could not be loaded. Please refresh and try again.
    </div>
  ),
});

const emptyForm = {
  componentName: "",
  subCategory: "",
  partNumber: "",
  quantity: "",
  cupboardNumber: "",
  manufacturer: "",
  vendor: "",
  specification: "",
  package: "",
};

function Dashboard() {
  const { session } = Route.useRouteContext();
  const queryClient = useQueryClient();
  const search = useServerFn(searchComponentsFn);
  const addComponent = useServerFn(addComponentFn);
  const updateComponent = useServerFn(updateComponentFn);
  const pickComponent = useServerFn(pickComponentFn);
  const getComponentNames = useServerFn(listComponentNamesFn);
  const getSubCategories = useServerFn(listSubCategoriesFn);
  const getInventoryStats = useServerFn(getInventoryStatsFn);

  const [term, setTerm] = useState("");
  const [query, setQuery] = useState("");
  const [nameFilter, setNameFilter] = useState("all");
  const [subCategoryFilter, setSubCategoryFilter] = useState("all");
  const [quantityFilter, setQuantityFilter] = useState("all");
  const [page, setPage] = useState(1);
  const [open, setOpen] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [addError, setAddError] = useState<string | null>(null);

  const [editing, setEditing] = useState<ComponentRecord | null>(null);
  const [editForm, setEditForm] = useState(emptyForm);
  const [editError, setEditError] = useState<string | null>(null);

  const [picking, setPicking] = useState<ComponentRecord | null>(null);
  const [pickQuantity, setPickQuantity] = useState("");
  const [pickReason, setPickReason] = useState("");

  const statsQuery = useQuery({
    queryKey: ["inventory-stats"],
    queryFn: () => getInventoryStats(),
  });

  const namesQuery = useQuery({
    queryKey: ["component-names"],
    queryFn: () => getComponentNames(),
  });

  const subCategoriesQuery = useQuery({
    queryKey: ["sub-categories"],
    queryFn: () => getSubCategories(),
  });

  const list = useQuery({
    queryKey: ["components", query, nameFilter, subCategoryFilter, quantityFilter, page],
    queryFn: () => search({ data: { query, nameFilter, subCategoryFilter, quantityFilter, page, pageSize: 100 } }),
  });

  function refreshComponents() {
    queryClient.invalidateQueries({ queryKey: ["components"] });
    queryClient.invalidateQueries({ queryKey: ["component-names"] });
    queryClient.invalidateQueries({ queryKey: ["sub-categories"] });
    queryClient.invalidateQueries({ queryKey: ["inventory-stats"] });
    queryClient.invalidateQueries({ queryKey: ["admin"] });
  }

  const create = useMutation({
    mutationFn: (input: {
      componentName: string;
      subCategory?: string;
      partNumber: string;
      quantity: number;
      cupboardNumber: string;
      manufacturer?: string;
      vendor?: string;
      specification?: string;
      package?: string;
    }) => addComponent({ data: input }),
    onSuccess: () => {
      toast.success("Component added successfully.");
      setForm(emptyForm);
      setAddError(null);
      setOpen(false);
      refreshComponents();
    },
    onError: (error) => {
      const msg = errorMessage(error, "Unable to save component. Please try again.");
      setAddError(msg);
      toast.error(msg, { duration: 6000 });
    },
  });

  const pick = useMutation({
    mutationFn: () => {
      if (!picking) throw new Error("No component selected.");
      const q = Number(pickQuantity);
      if (!Number.isInteger(q) || q <= 0) {
        throw new Error("Quantity must be a positive whole number.");
      }
      if (q > picking.quantity) {
        throw new Error(`Cannot pick more than available quantity (${picking.quantity}).`);
      }
      if (!pickReason.trim()) {
        throw new Error("Please enter a reason for taking the component.");
      }
      return pickComponent({
        data: {
          componentId: picking.id,
          quantity: q,
          reason: pickReason.trim(),
        },
      });
    },
    onSuccess: (res) => {
      toast.success(`Picked ${pickQuantity} unit(s) of ${picking?.component_name}. Remaining stock: ${res.remainingQuantity}`);
      setPicking(null);
      setPickQuantity("");
      setPickReason("");
      refreshComponents();
    },
    onError: (error) => toast.error(errorMessage(error, "Unable to pick component.")),
  });

  const update = useMutation({
    mutationFn: () => {
      const quantity = Number(editForm.quantity);
      if (!editForm.componentName.trim() || !editForm.partNumber.trim() || !editForm.cupboardNumber.trim()) {
        throw new Error("Component Name, Part Number, and Cupboard Number are required.");
      }
      if (!Number.isInteger(quantity) || quantity < 0) {
        throw new Error("Quantity must be a whole number of 0 or more.");
      }
      return updateComponent({
        data: {
          id: editing!.id,
          componentName: editForm.componentName.trim().toUpperCase(),
          subCategory: editForm.subCategory.trim().toUpperCase(),
          partNumber: editForm.partNumber.trim().toUpperCase(),
          quantity,
          cupboardNumber: editForm.cupboardNumber.trim().toUpperCase(),
          manufacturer: editForm.manufacturer.trim().toUpperCase(),
          vendor: editForm.vendor.trim().toUpperCase(),
          specification: editForm.specification.trim().toUpperCase(),
          package: editForm.package.trim().toUpperCase(),
        },
      });
    },
    onSuccess: () => {
      toast.success("Component updated successfully.");
      setEditing(null);
      setEditError(null);
      refreshComponents();
    },
    onError: (error) => {
      const msg = errorMessage(error, "Unable to update component.");
      setEditError(msg);
      toast.error(msg, { duration: 6000 });
    },
  });

  function submitSearch(event: React.FormEvent) {
    event.preventDefault();
    setQuery(term.trim());
    setPage(1);
  }

  function handleResetFilters() {
    setTerm("");
    setQuery("");
    setNameFilter("all");
    setSubCategoryFilter("all");
    setQuantityFilter("all");
    setPage(1);
  }

  function submitComponent(event: React.FormEvent) {
    event.preventDefault();
    setAddError(null);
    const quantity = Number(form.quantity);
    if (!form.componentName.trim() || !form.partNumber.trim() || !form.cupboardNumber.trim()) {
      toast.error("Please fill in Component Name, Part Number, and Cupboard Number.");
      return;
    }
    if (!Number.isInteger(quantity) || quantity < 0) {
      toast.error("Quantity must be a whole number of 0 or more.");
      return;
    }
    create.mutate({
      componentName: form.componentName.trim().toUpperCase(),
      subCategory: form.subCategory.trim().toUpperCase(),
      partNumber: form.partNumber.trim().toUpperCase(),
      quantity,
      cupboardNumber: form.cupboardNumber.trim().toUpperCase(),
      manufacturer: form.manufacturer.trim().toUpperCase(),
      vendor: form.vendor.trim().toUpperCase(),
      specification: form.specification.trim().toUpperCase(),
      package: form.package.trim().toUpperCase(),
    });
  }

  function openEdit(item: ComponentRecord) {
    setEditing(item);
    setEditError(null);
    setEditForm({
      componentName: item.component_name,
      subCategory: item.sub_category ?? "",
      partNumber: item.part_number,
      quantity: String(item.quantity),
      cupboardNumber: item.cupboard_number,
      manufacturer: item.manufacturer ?? "",
      vendor: item.vendor ?? "",
      specification: item.specification ?? "",
      package: item.package ?? "",
    });
  }

  const items = list.data?.items ?? [];
  const total = list.data?.total ?? items.length;
  const totalPages = list.data?.totalPages ?? 1;
  const hasActiveFilters = Boolean(term || query || nameFilter !== "all" || subCategoryFilter !== "all" || quantityFilter !== "all");

  return (
    <div className="min-h-screen bg-background">
      <AppHeader title="Component Search" userName={session.name} userId={session.loginId} role={session.role} />

      <main className="mx-auto w-full max-w-[98vw] px-3 py-5 sm:px-6 sm:py-7">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h1 className="text-xl font-semibold text-foreground sm:text-2xl">Electronic Component Inventory</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Search by component name, part number, manufacturer or vendor to find stock levels and cupboard locations.
            </p>
          </div>
          <Button onClick={() => setOpen(true)}>
            <PackagePlus className="size-4" aria-hidden />
            Add Component
          </Button>
        </div>

        {/* Inventory Overview Stats for Employees */}
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-2">
          <div className="card-elevated flex items-center gap-4 p-5">
            <div className="flex size-12 shrink-0 items-center justify-center rounded-xl bg-accent/10 text-accent">
              <Boxes className="size-6" aria-hidden />
            </div>
            <div>
              <p className="text-xs font-medium uppercase tracking-wider text-muted-foreground">Total Unique Components</p>
              <p className="mt-0.5 text-2xl font-bold text-foreground">
                {statsQuery.isPending ? "…" : statsQuery.data?.totalComponents?.toLocaleString() ?? 0}
              </p>
            </div>
          </div>

          <div className="card-elevated flex items-center gap-4 p-5">
            <div className="flex size-12 shrink-0 items-center justify-center rounded-xl bg-success/10 text-success">
              <Layers className="size-6" aria-hidden />
            </div>
            <div>
              <p className="text-xs font-medium uppercase tracking-wider text-muted-foreground">Total Stock Units</p>
              <p className="mt-0.5 text-2xl font-bold text-foreground">
                {statsQuery.isPending ? "…" : statsQuery.data?.totalStockUnits?.toLocaleString() ?? 0}
              </p>
            </div>
          </div>
        </div>

        <div className="card-elevated mt-6 p-4">
          <form onSubmit={submitSearch} className="flex flex-col gap-3 lg:flex-row lg:items-center">
            {/* Search Input */}
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
              <Input
                value={term}
                onChange={(event) => setTerm(event.target.value)}
                placeholder="Search by name, part number, manufacturer, vendor..."
                className="pl-9"
                aria-label="Search components"
              />
              {term && (
                <button
                  type="button"
                  onClick={() => {
                    setTerm("");
                    setQuery("");
                    setPage(1);
                  }}
                  className="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 text-muted-foreground hover:text-foreground"
                  aria-label="Clear search"
                >
                  <X className="size-4" aria-hidden />
                </button>
              )}
            </div>

            {/* Component Name Filter (Fetched directly from DB) */}
            <div className="w-full lg:w-48">
              <Select
                value={nameFilter}
                onValueChange={(val) => {
                  setNameFilter(val);
                  setPage(1);
                }}
              >
                <SelectTrigger aria-label="Filter by Component Name">
                  <SelectValue placeholder="All Component Names" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Component Names</SelectItem>
                  {(namesQuery.data ?? []).map((name) => (
                    <SelectItem key={name} value={name}>
                      {name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Sub Category Filter (Fetched directly from DB) */}
            <div className="w-full lg:w-48">
              <Select
                value={subCategoryFilter}
                onValueChange={(val) => {
                  setSubCategoryFilter(val);
                  setPage(1);
                }}
              >
                <SelectTrigger aria-label="Filter by Sub Category">
                  <SelectValue placeholder="All Sub Categories" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Sub Categories</SelectItem>
                  {(subCategoriesQuery.data ?? []).map((sub) => (
                    <SelectItem key={sub} value={sub}>
                      {sub}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Quantity Filter */}
            <div className="w-full lg:w-40">
              <Select
                value={quantityFilter}
                onValueChange={(val) => {
                  setQuantityFilter(val);
                  setPage(1);
                }}
              >
                <SelectTrigger aria-label="Filter by Quantity">
                  <SelectValue placeholder="All Quantities" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Quantities</SelectItem>
                  <SelectItem value="below_5000">Below 5000</SelectItem>
                  <SelectItem value="below_3000">Below 3000</SelectItem>
                  <SelectItem value="below_1000">Below 1000</SelectItem>
                  <SelectItem value="below_500">Below 500</SelectItem>
                  <SelectItem value="below_100">Below 100</SelectItem>
                  <SelectItem value="below_10">Below 10</SelectItem>
                  <SelectItem value="lowest">Lowest</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="flex gap-2">
              <Button type="submit" variant="secondary" disabled={list.isFetching} className="flex-1 lg:flex-none">
                {list.isFetching ? <Loader2 className="size-4 animate-spin" aria-hidden /> : <Search className="size-4" aria-hidden />}
                Search
              </Button>
              {hasActiveFilters && (
                <Button
                  type="button"
                  variant="outline"
                  onClick={handleResetFilters}
                  className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
                >
                  <RotateCcw className="size-3.5" aria-hidden />
                  Reset
                </Button>
              )}
            </div>
          </form>
        </div>

        <div className="mt-6">
          {list.isPending ? (
            <p className="py-12 text-center text-sm text-muted-foreground">Loading components…</p>
          ) : list.isError ? (
            <p className="py-12 text-center text-sm text-destructive">
              {errorMessage(list.error, "Unable to load components right now.")}
            </p>
          ) : items.length === 0 ? (
            <div className="card-elevated p-10 text-center">
              <p className="font-medium text-foreground">No components found</p>
              <p className="mt-1 text-sm text-muted-foreground">
                {hasActiveFilters ? "Nothing matches your search or filter criteria. Try resetting filters." : "Add your first component to get started."}
              </p>
            </div>
          ) : (
            <>
              <div className="mb-3 flex items-center justify-between">
                <p className="text-sm text-muted-foreground">
                  Showing <span className="font-semibold text-foreground">{(page - 1) * 100 + 1}–{Math.min(page * 100, total)}</span> of{" "}
                  <span className="font-semibold text-foreground">{total}</span> component{total === 1 ? "" : "s"}
                  {hasActiveFilters ? " (filtered)" : ""}
                </p>
                {totalPages > 1 && (
                  <p className="text-xs text-muted-foreground">
                    Page <span className="font-medium text-foreground">{page}</span> of {totalPages}
                  </p>
                )}
              </div>
              <ComponentTable
                items={items}
                startIndex={(page - 1) * 100}
                showMeta
                renderActions={(item) => (
                  <div className="flex items-center justify-end gap-1.5">
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => {
                        setPicking(item);
                        setPickQuantity("1");
                        setPickReason("");
                      }}
                      className="flex items-center gap-1 border-amber-500/30 bg-amber-500/10 text-amber-700 hover:bg-amber-500/20 dark:text-amber-400"
                    >
                      <PackageMinus className="size-3.5" aria-hidden />
                      <span>Pick</span>
                    </Button>
                    <Button size="sm" variant="outline" onClick={() => openEdit(item)} className="flex items-center gap-1">
                      <Pencil className="size-3.5" aria-hidden />
                      <span>Edit</span>
                    </Button>
                  </div>
                )}
              />

              {/* Pagination Controls at Bottom */}
              {totalPages > 1 && (
                <div className="mt-5 flex flex-col items-center justify-between gap-3 border-t border-border pt-4 sm:flex-row">
                  <p className="text-xs text-muted-foreground">
                    Showing entries <span className="font-medium text-foreground">{(page - 1) * 100 + 1}</span> to{" "}
                    <span className="font-medium text-foreground">{Math.min(page * 100, total)}</span> (out of{" "}
                    <span className="font-medium text-foreground">{total}</span>)
                  </p>
                  <div className="flex items-center gap-2">
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={page <= 1}
                      onClick={() => setPage((p) => Math.max(1, p - 1))}
                      className="flex items-center gap-1 text-xs"
                    >
                      <ChevronLeft className="size-4" aria-hidden />
                      Previous Page
                    </Button>
                    <span className="rounded-md border border-border bg-secondary px-3 py-1 text-xs font-semibold text-foreground">
                      {page} / {totalPages}
                    </span>
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={page >= totalPages}
                      onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                      className="flex items-center gap-1 text-xs"
                    >
                      Next Page
                      <ChevronRight className="size-4" aria-hidden />
                    </Button>
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      </main>

      {/* Add Component Dialog */}
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Add Component</DialogTitle>
            <DialogDescription>Record a new electronic component and its complete details.</DialogDescription>
          </DialogHeader>
          <form onSubmit={submitComponent} className="space-y-4">
            {addError && (
              <div
                role="alert"
                className="flex items-start gap-2.5 rounded-lg border border-destructive/40 bg-destructive/10 p-3 text-xs text-destructive"
              >
                <AlertCircle className="mt-0.5 size-4 shrink-0" aria-hidden />
                <div className="leading-snug">
                  <span className="block font-semibold">Cannot Add Component (Duplicate Entry)</span>
                  <span>{addError}</span>
                </div>
              </div>
            )}
            <div className="space-y-1.5">
              <Label htmlFor="componentName">Component Name *</Label>
              <Input
                id="componentName"
                placeholder="e.g. 10K RESISTOR"
                value={form.componentName}
                onChange={(event) => setForm({ ...form, componentName: event.target.value.toUpperCase() })}
                className="uppercase"
                required
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="subCategory">Sub Category</Label>
              <Input
                id="subCategory"
                placeholder="e.g. SMD, CERAMIC, POWER, ELECTROLYTIC, IC, ETC."
                value={form.subCategory}
                onChange={(event) => setForm({ ...form, subCategory: event.target.value.toUpperCase() })}
                className="uppercase"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="partNumber">Part Number *</Label>
              <Input
                id="partNumber"
                placeholder="e.g. R-10K-0805"
                value={form.partNumber}
                onChange={(event) => setForm({ ...form, partNumber: event.target.value.toUpperCase() })}
                className="uppercase"
                required
              />
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="quantity">Quantity *</Label>
                <Input
                  id="quantity"
                  type="number"
                  min={0}
                  step={1}
                  placeholder="0"
                  value={form.quantity}
                  onChange={(event) => setForm({ ...form, quantity: event.target.value })}
                  required
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="cupboardNumber">Cupboard Number *</Label>
                <Input
                  id="cupboardNumber"
                  placeholder="e.g. C-01"
                  value={form.cupboardNumber}
                  onChange={(event) => setForm({ ...form, cupboardNumber: event.target.value.toUpperCase() })}
                  className="uppercase"
                  required
                />
              </div>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="manufacturer">Manufacturer Name</Label>
                <Input
                  id="manufacturer"
                  placeholder="e.g. TEXAS INSTRUMENTS"
                  value={form.manufacturer}
                  onChange={(event) => setForm({ ...form, manufacturer: event.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="vendor">Vendor Name</Label>
                <Input
                  id="vendor"
                  placeholder="e.g. MOUSER / DIGIKEY"
                  value={form.vendor}
                  onChange={(event) => setForm({ ...form, vendor: event.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="package">Package</Label>
                <Input
                  id="package"
                  placeholder="e.g. SMD 0805 / DIP-8 / TO-220"
                  value={form.package}
                  onChange={(event) => setForm({ ...form, package: event.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="specification">Specification</Label>
                <Input
                  id="specification"
                  placeholder="e.g. 1/4W 1% TOL"
                  value={form.specification}
                  onChange={(event) => setForm({ ...form, specification: event.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={create.isPending}>
                {create.isPending && <Loader2 className="size-4 animate-spin" aria-hidden />}
                Save Component
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Edit Component Dialog */}
      <Dialog open={editing !== null} onOpenChange={(isOpen) => !isOpen && setEditing(null)}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Edit Component</DialogTitle>
            <DialogDescription>Modify details for {editing?.component_name}.</DialogDescription>
          </DialogHeader>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              update.mutate();
            }}
            className="space-y-4"
          >
            {editError && (
              <div
                role="alert"
                className="flex items-start gap-2.5 rounded-lg border border-destructive/40 bg-destructive/10 p-3 text-xs text-destructive"
              >
                <AlertCircle className="mt-0.5 size-4 shrink-0" aria-hidden />
                <div className="leading-snug">
                  <span className="block font-semibold">Cannot Update Component (Duplicate Entry)</span>
                  <span>{editError}</span>
                </div>
              </div>
            )}
            <div className="space-y-1.5">
              <Label htmlFor="editComponentName">Component Name *</Label>
              <Input
                id="editComponentName"
                value={editForm.componentName}
                onChange={(event) => setEditForm({ ...editForm, componentName: event.target.value.toUpperCase() })}
                className="uppercase"
                required
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="editSubCategory">Sub Category</Label>
              <Input
                id="editSubCategory"
                placeholder="e.g. SMD, CERAMIC, POWER, ELECTROLYTIC, IC, ETC."
                value={editForm.subCategory}
                onChange={(event) => setEditForm({ ...editForm, subCategory: event.target.value.toUpperCase() })}
                className="uppercase"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="editPartNumber">Part Number *</Label>
              <Input
                id="editPartNumber"
                value={editForm.partNumber}
                onChange={(event) => setEditForm({ ...editForm, partNumber: event.target.value.toUpperCase() })}
                className="uppercase"
                required
              />
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="editQuantity">Quantity *</Label>
                <Input
                  id="editQuantity"
                  type="number"
                  min={0}
                  step={1}
                  value={editForm.quantity}
                  onChange={(event) => setEditForm({ ...editForm, quantity: event.target.value })}
                  required
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="editCupboardNumber">Cupboard Number *</Label>
                <Input
                  id="editCupboardNumber"
                  value={editForm.cupboardNumber}
                  onChange={(event) => setEditForm({ ...editForm, cupboardNumber: event.target.value.toUpperCase() })}
                  className="uppercase"
                  required
                />
              </div>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="editManufacturer">Manufacturer Name</Label>
                <Input
                  id="editManufacturer"
                  placeholder="e.g. TEXAS INSTRUMENTS"
                  value={editForm.manufacturer}
                  onChange={(event) => setEditForm({ ...editForm, manufacturer: event.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="editVendor">Vendor Name</Label>
                <Input
                  id="editVendor"
                  placeholder="e.g. MOUSER / DIGIKEY"
                  value={editForm.vendor}
                  onChange={(event) => setEditForm({ ...editForm, vendor: event.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="editPackage">Package</Label>
                <Input
                  id="editPackage"
                  placeholder="e.g. SMD 0805 / DIP-8"
                  value={editForm.package}
                  onChange={(event) => setEditForm({ ...editForm, package: event.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="editSpecification">Specification</Label>
                <Input
                  id="editSpecification"
                  placeholder="e.g. 1/4W 1% TOL"
                  value={editForm.specification}
                  onChange={(event) => setEditForm({ ...editForm, specification: event.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
            </div>

            <DialogFooter>
              <Button type="button" variant="outline" onClick={() => setEditing(null)}>
                Cancel
              </Button>
              <Button type="submit" disabled={update.isPending}>
                {update.isPending && <Loader2 className="size-4 animate-spin" aria-hidden />}
                Save Changes
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {/* Pick / Take Component Dialog */}
      <Dialog open={picking !== null} onOpenChange={(isOpen) => !isOpen && setPicking(null)}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 text-primary">
              <PackageMinus className="size-5 text-amber-500" aria-hidden />
              Pick Component
            </DialogTitle>
            <DialogDescription>
              Record the quantity of <strong className="text-foreground">{picking?.component_name}</strong> being taken from inventory.
            </DialogDescription>
          </DialogHeader>

          {picking && (
            <div className="rounded-lg border border-border bg-secondary/50 p-3 text-xs">
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">Part Number:</span>
                <span className="font-mono font-medium text-foreground">{picking.part_number}</span>
              </div>
              <div className="mt-1.5 flex items-center justify-between">
                <span className="text-muted-foreground">Cupboard Location:</span>
                <span className="font-semibold text-accent">{picking.cupboard_number}</span>
              </div>
              <div className="mt-1.5 flex items-center justify-between">
                <span className="text-muted-foreground">Current Stock in Inventory:</span>
                <span className="font-bold text-foreground">{picking.quantity} unit(s)</span>
              </div>
            </div>
          )}

          <form
            onSubmit={(e) => {
              e.preventDefault();
              pick.mutate();
            }}
            className="space-y-4"
          >
            <div className="space-y-1.5">
              <Label htmlFor="pickQuantity">
                Enter the Quantity <span className="text-destructive">*</span>
              </Label>
              <Input
                id="pickQuantity"
                type="number"
                min={1}
                max={picking?.quantity ?? 1}
                step={1}
                placeholder="e.g. 5"
                value={pickQuantity}
                onChange={(event) => setPickQuantity(event.target.value)}
                required
                autoFocus
              />
              <p className="text-[11px] text-muted-foreground">
                Maximum available to take: <span className="font-semibold text-foreground">{picking?.quantity ?? 0}</span>
              </p>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="pickReason">
                Reason for Taking Component <span className="text-destructive">*</span>
              </Label>
              <Textarea
                id="pickReason"
                rows={3}
                placeholder="e.g. Prototype testing on PCB revision 2 / Assembly line batch #104"
                value={pickReason}
                onChange={(event) => setPickReason(event.target.value)}
                required
              />
            </div>

            <DialogFooter className="gap-2 sm:gap-0">
              <Button type="button" variant="outline" onClick={() => setPicking(null)}>
                Cancel
              </Button>
              <Button
                type="submit"
                disabled={pick.isPending || !picking || (picking.quantity <= 0)}
                className="bg-amber-600 text-white hover:bg-amber-700 dark:bg-amber-500 dark:hover:bg-amber-600"
              >
                {pick.isPending && <Loader2 className="size-4 animate-spin" aria-hidden />}
                Confirm &amp; Pick
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
