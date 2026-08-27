import { createFileRoute, redirect, useNavigate } from "@tanstack/react-router";
import { toast } from "sonner";

import { AuthLayout } from "@/components/hpt/AuthLayout";
import { LoginCard } from "@/components/hpt/LoginCard";
import { getCurrentSession, loginUser } from "@/lib/hpt/auth.functions";
import { errorMessage } from "@/lib/hpt/types";

export const Route = createFileRoute("/")({
  ssr: false,
  head: () => ({
    meta: [
      { title: "Employee Login | Harmony Powertech Component System" },
      {
        name: "description",
        content:
          "Secure employee sign-in for the Harmony Powertech electronic component management system. Search parts, stock levels and cupboard locations.",
      },
      { property: "og:title", content: "Employee Login | Harmony Powertech" },
      {
        property: "og:description",
        content: "Sign in to search Harmony Powertech electronic components, quantities and cupboard locations.",
      },
    ],
  }),
  beforeLoad: async () => {
    try {
      const session = await getCurrentSession();
      if (session) throw redirect({ to: "/dashboard" });
    } catch (err) {
      // Re-throw redirects, ignore session read errors to allow login
      if (err && typeof err === "object" && "to" in err) throw err;
    }
  },
  component: EmployeeLogin,
  errorComponent: () => (
    <div className="flex min-h-screen items-center justify-center p-6 text-center text-muted-foreground">
      Sign-in is temporarily unavailable. Please refresh and try again.
    </div>
  ),
});

function EmployeeLogin() {
  const navigate = useNavigate();

  async function handleLogin(loginId: string, password: string) {
    try {
      await loginUser({ data: { loginId, password } });
    } catch (error) {
      throw new Error(errorMessage(error, "Invalid User ID or Password."));
    }
    toast.success("Signed in successfully.");
    await navigate({ to: "/dashboard", replace: true });
  }

  return (
    <AuthLayout tagline="Electronic Component Management System — find any part, its stock level and its exact cupboard in seconds.">
      <LoginCard
        heading="Employee Sign In"
        subheading="Use the User ID issued by your administrator."
        onSubmit={handleLogin}
      />
    </AuthLayout>
  );
}
