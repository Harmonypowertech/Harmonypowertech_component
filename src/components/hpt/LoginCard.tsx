import { useState } from "react";
import { Eye, EyeOff, Loader2, LogIn } from "lucide-react";
import { AlertCircle } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type Props = {
  heading: string;
  subheading: string;
  idLabel?: string;
  submitLabel?: string;
  onSubmit: (loginId: string, password: string) => Promise<void>;
  footer?: React.ReactNode;
};

export function LoginCard({
  heading,
  subheading,
  idLabel = "User ID",
  submitLabel = "Login",
  onSubmit,
  footer,
}: Props) {
  const [loginId, setLoginId] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    if (!loginId.trim() || !password) {
      setError("Please enter your User ID and password.");
      return;
    }
    setLoading(true);
    try {
      await onSubmit(loginId.trim(), password);
    } catch (submitError) {
      setError(submitError instanceof Error ? submitError.message : "Invalid User ID or Password.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="card-elevated w-full max-w-md p-6 sm:p-8">
      <h2 className="text-xl font-semibold text-foreground">{heading}</h2>
      <p className="mt-1 text-sm text-muted-foreground">{subheading}</p>

      <form onSubmit={handleSubmit} className="mt-6 space-y-4" noValidate>
        <div className="space-y-1.5">
          <Label htmlFor="loginId">{idLabel}</Label>
          <Input
            id="loginId"
            autoComplete="username"
            value={loginId}
            onChange={(e) => setLoginId(e.target.value)}
            placeholder="Enter your ID"
            className="h-11"
          />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="password">Password</Label>
          <div className="relative">
            <Input
              id="password"
              type={showPassword ? "text" : "password"}
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter your password"
              className="h-11 pr-11"
            />
            <button
              type="button"
              suppressHydrationWarning
              onClick={() => setShowPassword((v) => !v)}
              aria-label={showPassword ? "Hide password" : "Show password"}
              className="absolute inset-y-0 right-0 flex w-11 items-center justify-center text-muted-foreground transition-colors hover:text-foreground"
            >
              {showPassword ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
            </button>
          </div>
        </div>

        {error && (
          <div
            role="alert"
            className="flex items-start gap-2 rounded-md border border-destructive/30 bg-destructive/5 px-3 py-2 text-sm text-destructive"
          >
            <AlertCircle className="mt-0.5 size-4 shrink-0" aria-hidden />
            <span>{error}</span>
          </div>
        )}

        <Button type="submit" className="h-11 w-full" disabled={loading}>
          {loading ? (
            <>
              <Loader2 className="size-4 animate-spin" aria-hidden /> Authenticating...
            </>
          ) : (
            <>
              <LogIn className="size-4" aria-hidden /> {submitLabel}
            </>
          )}
        </Button>
      </form>

      {footer && <div className="mt-6 border-t border-border pt-4 text-center text-sm">{footer}</div>}
    </div>
  );
}
