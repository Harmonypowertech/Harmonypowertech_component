import { BrandLogo } from "./BrandLogo";

type Props = {
  tagline: string;
  children: React.ReactNode;
};

/** Split-screen authentication shell used by employee and admin sign-in. */
export function AuthLayout({ tagline, children }: Props) {
  return (
    <main className="grid min-h-screen lg:grid-cols-2">
      <section className="relative flex flex-col justify-between overflow-hidden bg-primary-deep px-6 py-10 text-primary-foreground sm:px-10 lg:py-14">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 opacity-[0.12]"
          style={{
            backgroundImage:
              "linear-gradient(to right, currentColor 1px, transparent 1px), linear-gradient(to bottom, currentColor 1px, transparent 1px)",
            backgroundSize: "44px 44px",
          }}
        />
        <div className="relative">
          <div className="inline-flex rounded-xl border border-white/20 bg-white/95 p-3 shadow-md backdrop-blur-sm dark:bg-card">
            <BrandLogo priority className="h-9 sm:h-11 w-auto object-contain" />
          </div>
          <h1 className="mt-8 text-2xl font-semibold sm:text-3xl">Harmony Powertech</h1>
          <p className="mt-2 max-w-md text-sm text-primary-foreground/80 sm:text-base">{tagline}</p>
        </div>
        <ul className="relative mt-10 grid gap-3 text-sm text-primary-foreground/80 sm:grid-cols-2">
          {[
            "Instant part number lookup",
            "Live stock quantities",
            "Cupboard location tracking",
            "Controlled employee access",
          ].map((item) => (
            <li key={item} className="flex items-center gap-2 rounded-md bg-white/5 px-3 py-2">
              <span className="size-1.5 rounded-full bg-accent" aria-hidden />
              {item}
            </li>
          ))}
        </ul>
      </section>

      <section className="flex items-center justify-center bg-background px-4 py-10 sm:px-8">
        <div className="w-full max-w-md">
          <div className="mb-6 flex justify-center lg:hidden">
            <div className="inline-flex rounded-xl border border-border/80 bg-white/95 p-2.5 shadow-sm dark:bg-card">
              <BrandLogo priority className="h-9 w-auto object-contain" />
            </div>
          </div>
          {children}
        </div>
      </section>
    </main>
  );
}
