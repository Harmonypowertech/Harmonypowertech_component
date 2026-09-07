import React, { useState, useMemo } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import {
  Clock,
  History,
  Laptop,
  Loader2,
  Moon,
  PackageMinus,
  RefreshCw,
  Search,
  Settings,
  ShieldCheck,
  Sun,
  X,
} from "lucide-react";
import { toast } from "sonner";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { getMyPickHistoryFn } from "@/lib/hpt/components.functions";
import type { PickLogRecord } from "@/lib/hpt/types";

type Props = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  userName: string;
  userId: string;
  role: "user" | "admin";
};

type ThemeMode = "light" | "dark" | "system";

export function UserSettingsModal({ open, onOpenChange, userName, userId, role }: Props) {
  const queryClient = useQueryClient();
  const getMyPicks = useServerFn(getMyPickHistoryFn);

  const [theme, setTheme] = useState<ThemeMode>(() => {
    if (typeof window !== "undefined") {
      const saved = localStorage.getItem("hpt_theme") as ThemeMode;
      if (saved === "light" || saved === "dark" || saved === "system") return saved;
      if (document.documentElement.classList.contains("dark")) return "dark";
    }
    return "light";
  });

  const [searchFilter, setSearchFilter] = useState("");

  const picksQuery = useQuery({
    queryKey: ["my-pick-history", userId],
    queryFn: () => getMyPicks(),
    enabled: open,
    refetchInterval: 5000,
  });

  const applyTheme = (newTheme: ThemeMode) => {
    setTheme(newTheme);
    try {
      localStorage.setItem("hpt_theme", newTheme);
      if (newTheme === "dark") {
        document.documentElement.classList.add("dark");
      } else if (newTheme === "light") {
        document.documentElement.classList.remove("dark");
      } else {
        if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
          document.documentElement.classList.add("dark");
        } else {
          document.documentElement.classList.remove("dark");
        }
      }
      toast.success(`Theme set to ${newTheme.toUpperCase()}`);
    } catch {
      // ignore
    }
  };

  const filteredPicks = useMemo(() => {
    const rawList = (picksQuery.data ?? []) as PickLogRecord[];
    if (!searchFilter.trim()) return rawList;
    const q = searchFilter.trim().toLowerCase();
    return rawList.filter(
      (p) =>
        (p.component_name && p.component_name.toLowerCase().includes(q)) ||
        (p.part_number && p.part_number.toLowerCase().includes(q)) ||
        (p.cupboard_number && p.cupboard_number.toLowerCase().includes(q)) ||
        (p.reason && p.reason.toLowerCase().includes(q)),
    );
  }, [picksQuery.data, searchFilter]);

  const totalUnitsTaken = useMemo(() => {
    return (picksQuery.data ?? []).reduce((acc: number, curr: PickLogRecord) => acc + (curr.quantity_taken || 0), 0);
  }, [picksQuery.data]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[92vh] max-w-4xl overflow-hidden p-0 sm:max-w-4xl">
        <DialogHeader className="border-b border-border bg-muted/30 px-5 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5">
              <div className="flex size-9 items-center justify-center rounded-lg bg-primary/10 text-primary">
                <Settings className="size-5" aria-hidden />
              </div>
              <div>
                <DialogTitle className="text-lg font-bold text-foreground">
                  Settings &amp; Preferences
                </DialogTitle>
                <DialogDescription className="text-xs text-muted-foreground">
                  Switch light/dark theme and view your personal component pick history.
                </DialogDescription>
              </div>
            </div>
          </div>
        </DialogHeader>

        <div className="overflow-y-auto px-5 py-4 max-h-[calc(92vh-130px)]">
          {/* User Information Banner */}
          <div className="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-border/80 bg-secondary/50 p-3.5">
            <div className="flex items-center gap-3">
              <div className="flex size-10 items-center justify-center rounded-full bg-accent/15 font-bold uppercase text-accent">
                {role === "admin" ? <ShieldCheck className="size-5" /> : userName.charAt(0) || "U"}
              </div>
              <div>
                <div className="flex items-center gap-2">
                  <p className="font-semibold text-foreground">{userName}</p>
                  <Badge variant="outline" className="text-[10px] uppercase font-bold text-primary">
                    {role}
                  </Badge>
                </div>
                <p className="text-xs font-mono text-muted-foreground">User ID: {userId}</p>
              </div>
            </div>

            <div className="flex items-center gap-2 text-xs text-muted-foreground">
              <Clock className="size-3.5 text-primary" />
              <span>Active Employee Account</span>
            </div>
          </div>

          <Tabs defaultValue="theme" className="w-full">
            <TabsList className="grid w-full grid-cols-2">
              <TabsTrigger value="theme" className="flex items-center gap-2">
                <Sun className="size-4" />
                <span>Theme &amp; Mode</span>
              </TabsTrigger>
              <TabsTrigger value="picks" className="flex items-center gap-2">
                <History className="size-4" />
                <span>My Pick History</span>
                {(picksQuery.data ?? []).length > 0 && (
                  <span className="ml-1 rounded-full bg-primary/15 px-1.5 py-0.2 text-[10px] font-bold text-primary">
                    {(picksQuery.data ?? []).length}
                  </span>
                )}
              </TabsTrigger>
            </TabsList>

            {/* Tab 1: Theme Settings */}
            <TabsContent value="theme" className="mt-4 space-y-4">
              <div className="rounded-xl border border-border bg-card p-5 shadow-2xs">
                <h3 className="text-sm font-semibold text-foreground">Color Theme Mode</h3>
                <p className="mt-1 text-xs text-muted-foreground">
                  Switch between Light and Dark mode. Your choice is saved automatically.
                </p>

                <div className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
                  {/* Light Option */}
                  <button
                    type="button"
                    onClick={() => applyTheme("light")}
                    className={`flex flex-col items-center justify-center gap-2 rounded-xl border p-4 transition-all hover:bg-muted/50 ${
                      theme === "light"
                        ? "border-primary bg-primary/5 text-primary ring-2 ring-primary/20"
                        : "border-border bg-card text-muted-foreground"
                    }`}
                  >
                    <div className="flex size-10 items-center justify-center rounded-full bg-amber-500/10 text-amber-500">
                      <Sun className="size-5" />
                    </div>
                    <div className="text-center">
                      <p className="text-xs font-bold text-foreground">Light Mode</p>
                      <p className="text-[10px] text-muted-foreground">Daytime bright interface</p>
                    </div>
                    {theme === "light" && (
                      <span className="rounded-full bg-primary px-2 py-0.5 text-[9px] font-semibold text-primary-foreground">
                        Active
                      </span>
                    )}
                  </button>

                  {/* Dark Option */}
                  <button
                    type="button"
                    onClick={() => applyTheme("dark")}
                    className={`flex flex-col items-center justify-center gap-2 rounded-xl border p-4 transition-all hover:bg-muted/50 ${
                      theme === "dark"
                        ? "border-primary bg-primary/5 text-primary ring-2 ring-primary/20"
                        : "border-border bg-card text-muted-foreground"
                    }`}
                  >
                    <div className="flex size-10 items-center justify-center rounded-full bg-indigo-500/10 text-indigo-400">
                      <Moon className="size-5" />
                    </div>
                    <div className="text-center">
                      <p className="text-xs font-bold text-foreground">Dark Mode</p>
                      <p className="text-[10px] text-muted-foreground">High-contrast dark interface</p>
                    </div>
                    {theme === "dark" && (
                      <span className="rounded-full bg-primary px-2 py-0.5 text-[9px] font-semibold text-primary-foreground">
                        Active
                      </span>
                    )}
                  </button>

                  {/* System Option */}
                  <button
                    type="button"
                    onClick={() => applyTheme("system")}
                    className={`flex flex-col items-center justify-center gap-2 rounded-xl border p-4 transition-all hover:bg-muted/50 ${
                      theme === "system"
                        ? "border-primary bg-primary/5 text-primary ring-2 ring-primary/20"
                        : "border-border bg-card text-muted-foreground"
                    }`}
                  >
                    <div className="flex size-10 items-center justify-center rounded-full bg-slate-500/10 text-slate-500 dark:text-slate-400">
                      <Laptop className="size-5" />
                    </div>
                    <div className="text-center">
                      <p className="text-xs font-bold text-foreground">System Theme</p>
                      <p className="text-[10px] text-muted-foreground">Follows OS system preference</p>
                    </div>
                    {theme === "system" && (
                      <span className="rounded-full bg-primary px-2 py-0.5 text-[9px] font-semibold text-primary-foreground">
                        Active
                      </span>
                    )}
                  </button>
                </div>
              </div>
            </TabsContent>

            {/* Tab 2: Personal Pick History */}
            <TabsContent value="picks" className="mt-4 space-y-4">
              {/* Stats Bar */}
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-2">
                <div className="rounded-lg border border-border bg-card p-3 shadow-2xs">
                  <p className="text-[11px] font-medium text-muted-foreground">Total Pick Transactions</p>
                  <p className="mt-0.5 text-xl font-bold text-foreground">
                    {picksQuery.isPending ? "…" : (picksQuery.data ?? []).length}
                  </p>
                </div>
                <div className="rounded-lg border border-border bg-card p-3 shadow-2xs">
                  <p className="text-[11px] font-medium text-muted-foreground">Total Quantity Taken</p>
                  <p className="mt-0.5 text-xl font-bold text-accent">
                    {picksQuery.isPending ? "…" : `${totalUnitsTaken} Units`}
                  </p>
                </div>
              </div>

              {/* Search & Refresh */}
              <div className="flex items-center justify-between gap-2">
                <div className="relative flex-1">
                  <Search className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
                  <Input
                    placeholder="Filter my picks by component name, part number, cupboard, reason..."
                    value={searchFilter}
                    onChange={(e) => setSearchFilter(e.target.value)}
                    className="h-9 pl-8 text-xs"
                  />
                  {searchFilter && (
                    <button
                      type="button"
                      onClick={() => setSearchFilter("")}
                      className="absolute right-2.5 top-2.5 text-muted-foreground hover:text-foreground"
                    >
                      <X className="size-3.5" />
                    </button>
                  )}
                </div>

                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => queryClient.invalidateQueries({ queryKey: ["my-pick-history"] })}
                  disabled={picksQuery.isFetching}
                  className="h-9 gap-1 text-xs"
                >
                  <RefreshCw className={`size-3.5 ${picksQuery.isFetching ? "animate-spin" : ""}`} />
                  Refresh
                </Button>
              </div>

              {/* Picks Table */}
              {picksQuery.isPending ? (
                <div className="py-12 text-center text-xs text-muted-foreground">
                  <Loader2 className="mx-auto mb-2 size-5 animate-spin text-primary" />
                  Loading your pick history…
                </div>
              ) : filteredPicks.length === 0 ? (
                <div className="rounded-lg border border-border/70 bg-muted/20 p-8 text-center">
                  <PackageMinus className="mx-auto size-8 text-muted-foreground/40" />
                  <p className="mt-2 text-sm font-semibold text-foreground">
                    {searchFilter ? "No matching picks found" : "No pick history recorded yet"}
                  </p>
                  <p className="mt-1 text-xs text-muted-foreground">
                    {searchFilter
                      ? "Try searching for a different component name or keyword."
                      : "When you take components from inventory using the 'Pick' button, your personal logs will be listed here."}
                  </p>
                </div>
              ) : (
                <div className="overflow-x-auto rounded-lg border border-border bg-card shadow-xs">
                  <table className="w-full min-w-[700px] table-fixed border-collapse text-left text-xs">
                    <thead>
                      <tr className="border-b border-border bg-secondary/80 text-[9px] font-semibold uppercase tracking-wider text-muted-foreground">
                        <th scope="col" className="w-[5%] px-2 py-2.5 text-center text-primary">#</th>
                        <th scope="col" className="w-[20%] px-2.5 py-2.5 text-primary">Component</th>
                        <th scope="col" className="w-[15%] px-2 py-2.5 text-primary">Part No.</th>
                        <th scope="col" className="w-[10%] px-2 py-2.5 text-primary">Cupboard</th>
                        <th scope="col" className="w-[10%] px-2 py-2.5 text-center text-primary">Qty Taken</th>
                        <th scope="col" className="w-[14%] px-2 py-2.5 text-center text-primary">Stock Before &rarr; After</th>
                        <th scope="col" className="w-[26%] px-2.5 py-2.5 text-primary">Reason for Taking</th>
                        <th scope="col" className="w-[15%] px-2.5 py-2.5 text-primary">Date &amp; Time</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border">
                      {filteredPicks.map((pick: PickLogRecord, idx: number) => (
                        <tr key={pick.id} className="transition-colors hover:bg-muted/40">
                          <td className="px-2 py-2 text-center font-mono text-[10px] text-muted-foreground">
                            {idx + 1}
                          </td>
                          <td className="px-2.5 py-2 font-medium text-foreground">
                            <span className="block truncate font-semibold" title={pick.component_name}>
                              {pick.component_name}
                            </span>
                          </td>
                          <td className="px-2 py-2 font-mono text-[11px] text-foreground/85">
                            <span className="block truncate rounded bg-muted/60 px-1 py-0.5" title={pick.part_number}>
                              {pick.part_number}
                            </span>
                          </td>
                          <td className="px-2 py-2 font-bold text-accent">
                            {pick.cupboard_number || "—"}
                          </td>
                          <td className="px-2 py-2 text-center">
                            <span className="inline-flex rounded bg-amber-500/15 px-1.5 py-0.5 font-bold text-amber-700 dark:text-amber-400">
                              -{pick.quantity_taken}
                            </span>
                          </td>
                          <td className="px-2 py-2 text-center font-mono text-[11px] text-muted-foreground">
                            {pick.previous_quantity} &rarr; <span className="font-semibold text-foreground">{pick.remaining_quantity}</span>
                          </td>
                          <td className="px-2.5 py-2" title={pick.reason}>
                            <div className="truncate rounded bg-muted/50 px-1.5 py-0.5 text-[11px] text-foreground">
                              {pick.reason}
                            </div>
                          </td>
                          <td className="whitespace-nowrap px-2.5 py-2 text-[11px] text-muted-foreground">
                            {new Date(pick.created_at).toLocaleString(undefined, {
                              month: "short",
                              day: "numeric",
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
            </TabsContent>
          </Tabs>
        </div>

        <div className="flex justify-end border-t border-border bg-muted/20 px-5 py-3">
          <Button variant="outline" size="sm" onClick={() => onOpenChange(false)}>
            Close Settings
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
