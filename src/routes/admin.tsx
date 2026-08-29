import { createFileRoute, redirect } from "@tanstack/react-router";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { AlertCircle, Boxes, ChevronLeft, ChevronRight, History, KeyRound, Layers, Loader2, PackageMinus, Pencil, RotateCcw, Search, Trash2, UserPlus, Users, X } from "lucide-react";
import { toast } from "sonner";

import { AppHeader } from "@/components/hpt/AppHeader";
import { ComponentTable } from "@/components/hpt/ComponentTable";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { getCurrentSession } from "@/lib/hpt/auth.functions";
import {
  adminStatsFn,
  createUserFn,
  deleteUserFn,
  listUsersFn,
  resetPasswordFn,
  setUserStatusFn,
} from "@/lib/hpt/admin.functions";
import { deleteComponentFn, listComponentNamesFn, listSubCategoriesFn, pickComponentFn, searchComponentsFn, updateComponentFn } from "@/lib/hpt/components.functions";
import { errorMessage, type ComponentRecord, type PickLogRecord } from "@/lib/hpt/types";

export const Route = createFileRoute("/admin")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Admin Console | Harmony Powertech" },
      {
        name: "description",
        content:
          "Harmony Powertech system administration: user management, inventory auditing and component editing.",
      },
      { property: "og:title", content: "Admin Console | Harmony Powertech" },
      {
        property: "og:description",
        content: "HPT admin console — manage users, view stock statistics and edit component records.",
      },
    ],
  }),
  beforeLoad: async () => {
    try {
      const session = await getCurrentSession();
      if (!session) throw redirect({ to: "/admin-login" });
      if (session.role !== "admin") throw redirect({ to: "/dashboard" });
      return { session };
    } catch (err) {
      if (err && typeof err === "object" && "to" in err) throw err;
      throw redirect({ to: "/admin-login" });
    }
  },
  component: AdminConsole,
  errorComponent: ({ error }) => (
    <div className="flex min-h-screen flex-col items-center justify-center gap-3 p-6 text-center">
      <p className="text-sm font-semibold text-destructive">The administration console could not be loaded.</p>
      <p className="max-w-md text-xs text-muted-foreground">{(error as Error)?.message || "Please refresh or sign in again."}</p>
      <Button size="sm" variant="outline" onClick={() => window.location.reload()}>
        Refresh Page
      </Button>
    </div>
  ),
});

function StatCard({ icon, label, value }: { icon: React.ReactNode; label: string; value: number | string }) {
  return (
    <div className="card-elevated flex items-center gap-4 p-5">
      <div className="rounded-md bg-secondary p-3 text-accent">{icon}</div>
      <div>
        <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
        <p className="text-2xl font-semibold text-foreground">{value}</p>
      </div>
    </div>
  );
}

const emptyUser = { name: "", userId: "", password: "", role: "user" as const };

function AdminConsole() {
  const { session } = Route.useRouteContext();
  const queryClient = useQueryClient();

  const stats = useServerFn(adminStatsFn);
  const listUsers = useServerFn(listUsersFn);
  const createUser = useServerFn(createUserFn);
  const setStatus = useServerFn(setUserStatusFn);
  const resetPassword = useServerFn(resetPasswordFn);
  const deleteUser = useServerFn(deleteUserFn);
  const searchComponents = useServerFn(searchComponentsFn);
  const updateComponent = useServerFn(updateComponentFn);
  const removeComponent = useServerFn(deleteComponentFn);
  const getComponentNames = useServerFn(listComponentNamesFn);
  const getSubCategories = useServerFn(listSubCategoriesFn);
  const pickComponent = useServerFn(pickComponentFn);

  const [userForm, setUserForm] = useState(emptyUser);
  const [resetTarget, setResetTarget] = useState<{ id: string; name: string } | null>(null);
  const [newPassword, setNewPassword] = useState("");
  const [deleteUserTarget, setDeleteUserTarget] = useState<{ id: string; name: string } | null>(null);
  const [editing, setEditing] = useState<ComponentRecord | null>(null);
  const [editError, setEditError] = useState<string | null>(null);
  const [editForm, setEditForm] = useState({
    componentName: "",
    subCategory: "",
    partNumber: "",
    quantity: "",
    cupboardNumber: "",
    manufacturer: "",
    vendor: "",
    specification: "",
    package: "",
  });
  const [deleteComponentTarget, setDeleteComponentTarget] = useState<ComponentRecord | null>(null);
  const [picking, setPicking] = useState<ComponentRecord | null>(null);
  const [pickQuantity, setPickQuantity] = useState("");
  const [pickReason, setPickReason] = useState("");
  const [term, setTerm] = useState("");
  const [query, setQuery] = useState("");
  const [nameFilter, setNameFilter] = useState("all");
  const [subCategoryFilter, setSubCategoryFilter] = useState("all");
  const [quantityFilter, setQuantityFilter] = useState("all");
  const [page, setPage] = useState(1);

  const statsQuery = useQuery({ queryKey: ["admin", "stats"], queryFn: () => stats() });
  const usersQuery = useQuery({ queryKey: ["admin", "users"], queryFn: () => listUsers() });
  const namesQuery = useQuery({
    queryKey: ["component-names"],
    queryFn: () => getComponentNames(),
  });
  const subCategoriesQuery = useQuery({
    queryKey: ["sub-categories"],
    queryFn: () => getSubCategories(),
  });
  const componentsQuery = useQuery({
    queryKey: ["admin", "components", query, nameFilter, subCategoryFilter, quantityFilter, page],
    queryFn: () => searchComponents({ data: { query, nameFilter, subCategoryFilter, quantityFilter, page, pageSize: 100 } }),
  });

  function refreshAll() {
    queryClient.invalidateQueries({ queryKey: ["admin"] });
    queryClient.invalidateQueries({ queryKey: ["components"] });
    queryClient.invalidateQueries({ queryKey: ["component-names"] });
    queryClient.invalidateQueries({ queryKey: ["sub-categories"] });
  }

  const addUser = useMutation({
    mutationFn: () => createUser({ data: { ...userForm, name: userForm.name.trim(), userId: userForm.userId.trim() } }),
    onSuccess: () => {
      toast.success("Employee account created.");
      setUserForm(emptyUser);
      refreshAll();
    },
    onError: (error) => toast.error(errorMessage(error, "Unable to create user.")),
  });

  const toggleStatus = useMutation({
    mutationFn: (input: { id: string; status: "active" | "inactive" }) => setStatus({ data: input }),
    onSuccess: () => {
      toast.success("Account status updated.");
      refreshAll();
    },
    onError: (error) => toast.error(errorMessage(error, "Unable to update this user.")),
  });

  const doReset = useMutation({
    mutationFn: () => resetPassword({ data: { id: resetTarget!.id, password: newPassword } }),
    onSuccess: () => {
      toast.success("Password reset.");
      setResetTarget(null);
      setNewPassword("");
    },
    onError: (error) => toast.error(errorMessage(error, "Unable to reset the password.")),
  });

  const doDeleteUser = useMutation({
    mutationFn: () => deleteUser({ data: { id: deleteUserTarget!.id } }),
    onSuccess: () => {
      toast.success("Employee removed.");
      setDeleteUserTarget(null);
      refreshAll();
    },
    onError: (error) => toast.error(errorMessage(error, "Unable to delete this user.")),
  });

  const doUpdateComponent = useMutation({
    mutationFn: () => {
      const quantity = Number(editForm.quantity);
      if (!editForm.componentName.trim() || !editForm.partNumber.trim() || !editForm.cupboardNumber.trim()) {
        throw new Error("Component Name, Part Number, and Cupboard Number are required.");
      }
      if (!Number.isInteger(quantity) || quantity < 0) throw new Error("Quantity must be a whole number of 0 or more.");
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
      toast.success("Component updated.");
      setEditing(null);
      setEditError(null);
      refreshAll();
    },
    onError: (error) => {
      const msg = errorMessage(error, "Unable to update component.");
      setEditError(msg);
      toast.error(msg, { duration: 6000 });
    },
  });

  const doDeleteComponent = useMutation({
    mutationFn: () => removeComponent({ data: { id: deleteComponentTarget!.id } }),
    onSuccess: () => {
      toast.success("Component deleted.");
      setDeleteComponentTarget(null);
      refreshAll();
    },
    onError: (error) => toast.error(errorMessage(error, "Unable to delete component.")),
  });

  const doPickComponent = useMutation({
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
      refreshAll();
    },
    onError: (error) => toast.error(errorMessage(error, "Unable to pick component.")),
  });

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

  const users = usersQuery.data ?? [];
  const components = componentsQuery.data?.items ?? [];
  const total = componentsQuery.data?.total ?? components.length;
  const totalPages = componentsQuery.data?.totalPages ?? 1;

  return (
    <div className="min-h-screen bg-background">
      <AppHeader title="Admin Console" userName={session.name} userId={session.loginId} role={session.role} />

      <main className="mx-auto w-full max-w-[98vw] px-3 py-5 sm:px-6 sm:py-7">
        <h1 className="text-xl font-semibold text-foreground sm:text-2xl">Administration Overview</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Manage employee accounts and maintain the electronic component inventory.
        </p>

        <div className="mt-6 grid gap-4 sm:grid-cols-3">
          <StatCard icon={<Users className="size-5" aria-hidden />} label="Employees" value={statsQuery.data?.totalUsers ?? "—"} />
          <StatCard icon={<Boxes className="size-5" aria-hidden />} label="Components" value={statsQuery.data?.totalComponents ?? "—"} />
          <StatCard icon={<Layers className="size-5" aria-hidden />} label="Total Stock Units" value={statsQuery.data?.totalQuantity ?? "—"} />
        </div>

        <Tabs defaultValue="users" className="mt-8">
          <TabsList>
            <TabsTrigger value="users">Employees</TabsTrigger>
            <TabsTrigger value="components">Components</TabsTrigger>
            <TabsTrigger value="recent">Recent Activity</TabsTrigger>
          </TabsList>

          <TabsContent value="users" className="mt-4 space-y-6">
            <form
              onSubmit={(event) => {
                event.preventDefault();
                if (!userForm.name.trim() || !userForm.userId.trim() || userForm.password.length < 6) {
                  toast.error("Enter a name, User ID and a password of at least 6 characters.");
                  return;
                }
                addUser.mutate();
              }}
              className="card-elevated grid gap-4 p-4 sm:grid-cols-4 sm:items-end"
            >
              <div className="space-y-1.5">
                <Label htmlFor="name">Full Name</Label>
                <Input id="name" value={userForm.name} onChange={(e) => setUserForm({ ...userForm, name: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="userId">User ID</Label>
                <Input id="userId" value={userForm.userId} onChange={(e) => setUserForm({ ...userForm, userId: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="password">Temporary Password</Label>
                <Input
                  id="password"
                  type="password"
                  value={userForm.password}
                  onChange={(e) => setUserForm({ ...userForm, password: e.target.value })}
                />
              </div>
              <Button type="submit" disabled={addUser.isPending}>
                {addUser.isPending ? <Loader2 className="size-4 animate-spin" aria-hidden /> : <UserPlus className="size-4" aria-hidden />}
                Add Employee
              </Button>
            </form>

            <div className="overflow-hidden rounded-lg border border-border">
              <table className="w-full border-collapse text-sm">
                <thead>
                  <tr className="bg-secondary/70 text-left">
                    <th className="px-4 py-3 font-semibold text-primary">Name</th>
                    <th className="px-4 py-3 font-semibold text-primary">User ID</th>
                    <th className="px-4 py-3 font-semibold text-primary">Role</th>
                    <th className="px-4 py-3 font-semibold text-primary">Active</th>
                    <th className="px-4 py-3 text-right font-semibold text-primary">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {users.map((user) => (
                    <tr key={user.id} className="border-t border-border bg-card">
                      <td className="px-4 py-3 font-medium text-foreground">{user.name}</td>
                      <td className="px-4 py-3 font-mono text-[13px] text-muted-foreground">{user.user_id}</td>
                      <td className="px-4 py-3">
                        <Badge variant={user.role === "admin" ? "default" : "outline"}>{user.role}</Badge>
                      </td>
                      <td className="px-4 py-3">
                        {user.role === "admin" ? (
                          <span className="text-xs text-muted-foreground">—</span>
                        ) : (
                          <Switch
                            checked={user.status === "active"}
                            onCheckedChange={(checked) =>
                              toggleStatus.mutate({ id: user.id, status: checked ? "active" : "inactive" })
                            }
                            aria-label={`Toggle ${user.name}`}
                          />
                        )}
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex justify-end gap-2">
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => {
                              setResetTarget({ id: user.id, name: user.name });
                              setNewPassword("");
                            }}
                          >
                            <KeyRound className="size-4" aria-hidden />
                            <span className="hidden sm:inline">Reset</span>
                          </Button>
                          {user.role !== "admin" && (
                            <Button
                              size="sm"
                              variant="outline"
                              onClick={() => setDeleteUserTarget({ id: user.id, name: user.name })}
                            >
                              <Trash2 className="size-4 text-destructive" aria-hidden />
                            </Button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                  {users.length === 0 && (
                    <tr>
                      <td colSpan={5} className="px-4 py-8 text-center text-muted-foreground">
                        {usersQuery.isPending ? "Loading employees…" : "No employees yet."}
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </TabsContent>

          <TabsContent value="components" className="mt-4 space-y-4">
            <form
              onSubmit={(event) => {
                event.preventDefault();
                setQuery(term.trim());
              }}
              className="flex flex-col gap-3 lg:flex-row lg:items-center"
            >
              <div className="relative flex-1">
                <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
                <Input
                  value={term}
                  onChange={(event) => setTerm(event.target.value)}
                  placeholder="Search components by name or part number..."
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

              {/* Component Name Filter */}
              <div className="w-full lg:w-52">
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

              {/* Sub Category Filter */}
              <div className="w-full lg:w-44">
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
                <Button
                  type="submit"
                  variant="secondary"
                  disabled={componentsQuery.isFetching}
                  onClick={() => setPage(1)}
                >
                  {componentsQuery.isFetching ? <Loader2 className="size-4 animate-spin" aria-hidden /> : <Search className="size-4" aria-hidden />}
                  Search
                </Button>
                {(term || query || nameFilter !== "all" || subCategoryFilter !== "all" || quantityFilter !== "all") && (
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() => {
                      setTerm("");
                      setQuery("");
                      setNameFilter("all");
                      setSubCategoryFilter("all");
                      setQuantityFilter("all");
                      setPage(1);
                    }}
                    className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
                  >
                    <RotateCcw className="size-3.5" aria-hidden />
                    Reset
                  </Button>
                )}
              </div>
            </form>

            {components.length === 0 ? (
              <p className="py-10 text-center text-sm text-muted-foreground">
                {componentsQuery.isPending ? "Loading components…" : "No components found."}
              </p>
            ) : (
              <>
                <div className="mb-3 flex items-center justify-between">
                  <p className="text-sm text-muted-foreground">
                    Showing <span className="font-semibold text-foreground">{(page - 1) * 100 + 1}–{Math.min(page * 100, total)}</span> of{" "}
                    <span className="font-semibold text-foreground">{total}</span> component{total === 1 ? "" : "s"}
                  </p>
                  {totalPages > 1 && (
                    <p className="text-xs text-muted-foreground">
                      Page <span className="font-medium text-foreground">{page}</span> of {totalPages}
                    </p>
                  )}
                </div>
                <ComponentTable
                  items={components}
                  startIndex={(page - 1) * 100}
                  showMeta
                  renderActions={(item) => (
                    <div className="flex justify-end gap-1.5">
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => {
                          setPicking(item);
                          setPickQuantity("1");
                          setPickReason("");
                        }}
                        title="Pick component"
                        className="flex items-center gap-1 border-amber-500/30 bg-amber-500/10 text-amber-700 hover:bg-amber-500/20 dark:text-amber-400"
                      >
                        <PackageMinus className="size-3.5" aria-hidden />
                        <span className="hidden sm:inline">Pick</span>
                      </Button>
                      <Button size="sm" variant="outline" onClick={() => openEdit(item)} title="Edit component">
                        <Pencil className="size-3.5" aria-hidden />
                      </Button>
                      <Button size="sm" variant="outline" onClick={() => setDeleteComponentTarget(item)} title="Delete component">
                        <Trash2 className="size-3.5 text-destructive" aria-hidden />
                      </Button>
                    </div>
                  )}
                />

                {/* Pagination Controls */}
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
          </TabsContent>

          <TabsContent value="recent" className="mt-4 space-y-8">
            {/* Component Pick Activity Logs */}
            <div>
              <div className="mb-3 flex items-center justify-between">
                <div>
                  <h2 className="flex items-center gap-2 text-base font-semibold text-foreground">
                    <PackageMinus className="size-4 text-amber-500" aria-hidden />
                    Component Pick / Issue Activity Log
                  </h2>
                  <p className="text-xs text-muted-foreground">
                    Real-time record of all components taken by employees along with reason and quantity.
                  </p>
                </div>
                <Badge variant="outline" className="text-xs">
                  {(statsQuery.data?.recentPicks ?? []).length} Records
                </Badge>
              </div>

              {(statsQuery.data?.recentPicks ?? []).length === 0 ? (
                <div className="card-elevated p-8 text-center">
                  <PackageMinus className="mx-auto size-8 text-muted-foreground/50" aria-hidden />
                  <p className="mt-2 text-sm font-medium text-foreground">No pick activity recorded yet</p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    When employees take components using the &quot;Pick&quot; button, their reason and quantity will appear here.
                  </p>
                </div>
              ) : (
                <div className="overflow-hidden rounded-lg border border-border bg-card shadow-sm">
                  <table className="w-full table-fixed border-collapse text-left text-xs">
                    <thead>
                      <tr className="border-b border-border bg-secondary/80 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                        <th scope="col" className="w-[4%] px-2 py-3 text-center text-primary">#</th>
                        <th scope="col" className="w-[14%] px-2.5 py-3 text-primary">Component</th>
                        <th scope="col" className="w-[10%] px-2 py-3 text-primary">Part No.</th>
                        <th scope="col" className="w-[6%] px-2 py-3 text-primary">Cupboard</th>
                        <th scope="col" className="w-[8%] px-2 py-3 text-center text-primary">Qty Taken</th>
                        <th scope="col" className="w-[8%] px-2 py-3 text-center text-primary">Stock (Before &rarr; After)</th>
                        <th scope="col" className="w-[28%] px-3 py-3 text-primary">Reason for Taking</th>
                        <th scope="col" className="w-[11%] px-2 py-3 text-primary">Taken By (Employee)</th>
                        <th scope="col" className="w-[11%] px-2 py-3 text-primary">Date &amp; Time</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border">
                      {(statsQuery.data?.recentPicks ?? []).map((pickLog: PickLogRecord, idx: number) => (
                        <tr key={pickLog.id} className="transition-colors hover:bg-muted/50">
                          <td className="px-2 py-2.5 text-center font-mono text-[11px] text-muted-foreground">{idx + 1}</td>
                          <td className="px-2.5 py-2.5 font-medium text-foreground">
                            <span className="block truncate" title={pickLog.component_name}>
                              {pickLog.component_name}
                            </span>
                          </td>
                          <td className="px-2 py-2.5 font-mono text-[11px] text-foreground/80">
                            <span className="block truncate rounded bg-muted/60 px-1.5 py-0.5" title={pickLog.part_number}>
                              {pickLog.part_number}
                            </span>
                          </td>
                          <td className="px-2 py-2.5 font-semibold text-accent">{pickLog.cupboard_number || "—"}</td>
                          <td className="px-2 py-2.5 text-center">
                            <span className="inline-flex rounded-md bg-amber-500/15 px-2 py-0.5 font-semibold text-amber-700 dark:text-amber-400">
                              -{pickLog.quantity_taken}
                            </span>
                          </td>
                          <td className="px-2 py-2.5 text-center font-mono text-[11px] text-muted-foreground">
                            {pickLog.previous_quantity} &rarr; <span className="font-semibold text-foreground">{pickLog.remaining_quantity}</span>
                          </td>
                          <td className="px-3 py-2.5" title={pickLog.reason}>
                            <div className="rounded-md bg-muted/50 px-2 py-1 text-xs text-foreground">
                              {pickLog.reason}
                            </div>
                          </td>
                          <td className="px-2 py-2.5 font-medium text-foreground">
                            <span className="block truncate" title={pickLog.taken_by_name}>
                              {pickLog.taken_by_name}
                            </span>
                          </td>
                          <td className="whitespace-nowrap px-2 py-2.5 text-[11px] text-muted-foreground">
                            {new Date(pickLog.created_at).toLocaleString(undefined, {
                              month: "short",
                              day: "numeric",
                              year: "numeric",
                              hour: "2-digit",
                              minute: "2-digit",
                            })}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>

            {/* Recently Added Components */}
            <div>
              <div className="mb-3">
                <h2 className="text-base font-semibold text-foreground">Recently Added Components</h2>
                <p className="text-xs text-muted-foreground">Components recently created in the inventory.</p>
              </div>
              {(statsQuery.data?.recent ?? []).length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">No recent additions.</p>
              ) : (
                <ComponentTable items={(statsQuery.data?.recent ?? []) as ComponentRecord[]} showMeta />
              )}
            </div>
          </TabsContent>
        </Tabs>
      </main>

      {/* Reset password */}
      <Dialog open={resetTarget !== null} onOpenChange={(open) => !open && setResetTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reset password</DialogTitle>
            <DialogDescription>Set a new password for {resetTarget?.name}.</DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label htmlFor="newPassword">New password</Label>
            <Input id="newPassword" type="password" value={newPassword} onChange={(e) => setNewPassword(e.target.value)} />
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setResetTarget(null)}>
              Cancel
            </Button>
            <Button
              onClick={() => {
                if (newPassword.length < 6) {
                  toast.error("Password must be at least 6 characters.");
                  return;
                }
                doReset.mutate();
              }}
              disabled={doReset.isPending}
            >
              {doReset.isPending && <Loader2 className="size-4 animate-spin" aria-hidden />}
              Reset password
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Edit component */}
      <Dialog open={editing !== null} onOpenChange={(open) => !open && setEditing(null)}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Edit component</DialogTitle>
            <DialogDescription>Update the stored details for this component.</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
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
              <Label htmlFor="editName">Component Name *</Label>
              <Input
                id="editName"
                value={editForm.componentName}
                onChange={(e) => setEditForm({ ...editForm, componentName: e.target.value.toUpperCase() })}
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
                onChange={(e) => setEditForm({ ...editForm, subCategory: e.target.value.toUpperCase() })}
                className="uppercase"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="editPart">Part Number *</Label>
              <Input
                id="editPart"
                value={editForm.partNumber}
                onChange={(e) => setEditForm({ ...editForm, partNumber: e.target.value.toUpperCase() })}
                className="uppercase"
                required
              />
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="editQty">Quantity *</Label>
                <Input
                  id="editQty"
                  type="number"
                  min={0}
                  step={1}
                  value={editForm.quantity}
                  onChange={(e) => setEditForm({ ...editForm, quantity: e.target.value })}
                  required
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="editCupboard">Cupboard Number *</Label>
                <Input
                  id="editCupboard"
                  value={editForm.cupboardNumber}
                  onChange={(e) => setEditForm({ ...editForm, cupboardNumber: e.target.value.toUpperCase() })}
                  className="uppercase"
                  required
                />
              </div>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="editAdminManufacturer">Manufacturer Name</Label>
                <Input
                  id="editAdminManufacturer"
                  placeholder="e.g. TEXAS INSTRUMENTS"
                  value={editForm.manufacturer}
                  onChange={(e) => setEditForm({ ...editForm, manufacturer: e.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="editAdminVendor">Vendor Name</Label>
                <Input
                  id="editAdminVendor"
                  placeholder="e.g. MOUSER / DIGIKEY"
                  value={editForm.vendor}
                  onChange={(e) => setEditForm({ ...editForm, vendor: e.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="editAdminPackage">Package</Label>
                <Input
                  id="editAdminPackage"
                  placeholder="e.g. SMD 0805 / DIP-8"
                  value={editForm.package}
                  onChange={(e) => setEditForm({ ...editForm, package: e.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="editAdminSpecification">Specification</Label>
                <Input
                  id="editAdminSpecification"
                  placeholder="e.g. 1/4W 1% TOL"
                  value={editForm.specification}
                  onChange={(e) => setEditForm({ ...editForm, specification: e.target.value.toUpperCase() })}
                  className="uppercase"
                />
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditing(null)}>
              Cancel
            </Button>
            <Button onClick={() => doUpdateComponent.mutate()} disabled={doUpdateComponent.isPending}>
              {doUpdateComponent.isPending && <Loader2 className="size-4 animate-spin" aria-hidden />}
              Save changes
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Delete user */}
      <AlertDialog open={deleteUserTarget !== null} onOpenChange={(open) => !open && setDeleteUserTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Remove employee?</AlertDialogTitle>
            <AlertDialogDescription>
              {deleteUserTarget?.name} will lose access immediately. This cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => doDeleteUser.mutate()}>Remove</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Delete component */}
      <AlertDialog
        open={deleteComponentTarget !== null}
        onOpenChange={(open) => !open && setDeleteComponentTarget(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete component?</AlertDialogTitle>
            <AlertDialogDescription>
              {deleteComponentTarget?.component_name} will be permanently removed from the inventory.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={() => doDeleteComponent.mutate()}>Delete</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* Pick Component Dialog in Admin */}
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
              doPickComponent.mutate();
            }}
            className="space-y-4"
          >
            <div className="space-y-1.5">
              <Label htmlFor="adminPickQuantity">
                Enter the Quantity <span className="text-destructive">*</span>
              </Label>
              <Input
                id="adminPickQuantity"
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
              <Label htmlFor="adminPickReason">
                Reason for Taking Component <span className="text-destructive">*</span>
              </Label>
              <Textarea
                id="adminPickReason"
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
                disabled={doPickComponent.isPending || !picking || (picking.quantity <= 0)}
                className="bg-amber-600 text-white hover:bg-amber-700 dark:bg-amber-500 dark:hover:bg-amber-600"
              >
                {doPickComponent.isPending && <Loader2 className="size-4 animate-spin" aria-hidden />}
                Confirm &amp; Pick
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
