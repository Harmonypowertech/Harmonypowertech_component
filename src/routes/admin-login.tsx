import { createFileRoute, Link, redirect, useNavigate } from "@tanstack/react-router";
import { toast } from "sonner";

import { AuthLayout } from "@/components/hpt/AuthLayout";
import { LoginCard } from "@/components/hpt/LoginCard";
import { getCurrentSession, loginUser } from "@/lib/hpt/auth.functions";
import { errorMessage } from "@/lib/hpt/types";

export const Route = createFileRoute("/admin-login")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Administrator Login | Harmony Powertech" },
      {
        name: "description",
        content:
          "Administrator access to the Harmony Powertech component management system: manage employees, components and stock records.",
      },
      { property: "og:title", content: "Administrator Login | Harmony Powertech" },
      {
        property: "og:description",
        content: "Restricted administrator sign-in for the Harmony Powertech component management system.",
      },
    ],
  }),
  beforeLoad: async () => {
    try {
      const session = await getCurrentSession();
      if (session?.role === "admin") throw redirect({ to: "/dashboard" });
    } catch (err) {
      if (err && typeof err === "object" && "to" in err) throw err;
    }
  },
  component: AdminLogin,
  errorComponent: () => (
    <div className="flex min-h-screen items-center justify-center p-6 text-center text-muted-foreground">
      Administrator sign-in is temporarily unavailable. Please refresh and try again.
    </div>
  ),
});

function AdminLogin() {
  const navigate = useNavigate();

  async function handleLogin(loginId: string, password: string) {
    try {
      await loginUser({ data: { loginId, password, admin: true } });
    } catch (error) {
      throw new Error(errorMessage(error, "Invalid Admin ID or Password."));
    }
    toast.success("Administrator signed in.");
    await navigate({ to: "/dashboard", replace: true });
  }

  return (
    <AuthLayout tagline="Administration Console — manage employee accounts, component records and inventory statistics.">
      <LoginCard
        heading="Administrator Sign In"
        subheading="Restricted access. Administrator credentials required."
        idLabel="Admin ID"
        submitLabel="Login as Administrator"
        onSubmit={handleLogin}
        footer={
          <Link to="/" className="font-medium text-muted-foreground underline-offset-4 hover:underline">
            Back to employee login
          </Link>
        }
      />
    </AuthLayout>
  );
}
