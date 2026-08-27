import { Link, useNavigate } from "@tanstack/react-router";
import { useQueryClient } from "@tanstack/react-query";
import { LogOut, ShieldCheck } from "lucide-react";
import { toast } from "sonner";
import { useState } from "react";

import { BrandLogo } from "./BrandLogo";
import { Button } from "@/components/ui/button";
import { logout } from "@/lib/hpt/auth.functions";

type Props = {
  title: string;
  userName: string;
  userId: string;
  role: "user" | "admin";
};

export function AppHeader({ title, userName, userId, role }: Props) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [busy, setBusy] = useState(false);

  async function handleLogout() {
    setBusy(true);
    try {
      await queryClient.cancelQueries();
      queryClient.clear();
      await logout();
      toast.success("You have been signed out.");
      navigate({ to: role === "admin" ? "/admin-login" : "/", replace: true });
    } catch {
      toast.error("Unable to sign out. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <header className="sticky top-0 z-30 border-b border-border bg-card/95 backdrop-blur-md shadow-xs">
      <div className="mx-auto flex w-full max-w-[98vw] flex-col gap-3 px-3 py-2.5 sm:px-6 md:flex-row md:items-center md:justify-between">
        {/* Brand & Page Identity */}
        <div className="flex items-center gap-3 sm:gap-4">
          <Link
            to="/dashboard"
            className="flex shrink-0 items-center rounded-lg border border-border/60 bg-white/95 p-1.5 shadow-2xs transition-all hover:scale-[1.02] hover:shadow-xs dark:bg-card"
            title="Harmony Powertech - Dashboard"
          >
            <BrandLogo priority className="h-8 sm:h-9 w-auto object-contain" />
          </Link>

          <div className="hidden h-9 w-px bg-border/80 sm:block" aria-hidden />

          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-sm font-semibold tracking-tight text-foreground sm:text-base">{title}</h1>
              {role === "admin" && (
                <span className="rounded bg-accent/15 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-accent">
                  Admin
                </span>
              )}
            </div>
            <p className="text-[11px] font-medium text-muted-foreground">
              Harmony Powertech &bull; Component Inventory Hub
            </p>
          </div>
        </div>

        {/* User Profile & Navigation */}
        <div className="flex items-center justify-between gap-2.5 md:justify-end">
          <div className="flex items-center gap-2.5 rounded-lg border border-border/80 bg-secondary/60 px-3 py-1.5 shadow-2xs">
            <div className="flex size-7 shrink-0 items-center justify-center rounded-md bg-accent/15 text-accent">
              {role === "admin" ? (
                <ShieldCheck className="size-4" aria-hidden />
              ) : (
                <span className="text-xs font-bold uppercase">
                  {userName.charAt(0) || "U"}
                </span>
              )}
            </div>
            <div className="leading-tight">
              <p className="text-xs font-semibold text-foreground">{userName}</p>
              <p className="text-[11px] font-mono text-muted-foreground">ID: {userId}</p>
            </div>
          </div>

          {role === "admin" && (
            <Button variant="secondary" size="sm" asChild className="gap-1.5 text-xs font-medium">
              <Link to="/admin">
                <ShieldCheck className="size-3.5" aria-hidden />
                <span className="hidden sm:inline">Admin Panel</span>
              </Link>
            </Button>
          )}

          <Button
            variant="outline"
            size="sm"
            onClick={handleLogout}
            disabled={busy}
            className="gap-1.5 text-xs text-muted-foreground hover:text-foreground"
          >
            <LogOut className="size-3.5" aria-hidden />
            <span className="hidden sm:inline">Logout</span>
          </Button>
        </div>
      </div>
    </header>
  );
}
