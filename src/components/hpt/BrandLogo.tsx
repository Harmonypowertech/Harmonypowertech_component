import logoUrl from "@/assets/hpt-logo.png";
import { cn } from "@/lib/utils";

type Props = {
  className?: string;
  priority?: boolean;
};

/** Harmony Powertech corporate logo — high fidelity presentation. */
export function BrandLogo({ className, priority = false }: Props) {
  return (
    <img
      src={logoUrl}
      alt="Harmony Powertech"
      width={298}
      height={80}
      {...(priority ? {} : { loading: "lazy" as const })}
      className={cn("h-9 w-auto max-h-10 object-contain select-none transition-transform duration-200 hover:scale-[1.02]", className)}
      draggable={false}
    />
  );
}
