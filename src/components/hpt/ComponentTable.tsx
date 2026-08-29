import React, { useState } from "react";
import { Eye, Package } from "lucide-react";

import type { ComponentRecord } from "@/lib/hpt/types";
import { Badge } from "@/components/ui/badge";
import { ComponentViewModal } from "@/components/hpt/ComponentViewModal";

type Props = {
  items: ComponentRecord[];
  startIndex?: number;
  showMeta?: boolean;
  renderActions?: (item: ComponentRecord, onView: (item: ComponentRecord) => void) => React.ReactNode;
};

function QuantityBadge({ quantity }: { quantity: number }) {
  const tone =
    quantity === 0
      ? "bg-destructive/10 text-destructive"
      : quantity < 50
        ? "bg-warning/15 text-warning-foreground"
        : "bg-success/10 text-success";
  return <span className={`inline-flex rounded-md px-2 py-0.5 text-base font-bold ${tone}`}>{quantity}</span>;
}

/** Responsive component listing: table on desktop, cards on mobile. */
export function ComponentTable({ items, startIndex = 0, showMeta = false, renderActions }: Props) {
  const [viewingItem, setViewingItem] = useState<ComponentRecord | null>(null);

  const handleView = (item: ComponentRecord) => {
    setViewingItem(item);
  };

  return (
    <>
      {/* Desktop table - full screen width, no horizontal scroll */}
      <div className="hidden w-full overflow-hidden rounded-lg border border-border bg-card shadow-sm md:block">
        <table className="w-full table-fixed border-collapse text-left text-sm lg:text-base">
          <thead>
            <tr className="border-b border-border bg-secondary/80 text-xs font-semibold uppercase tracking-wider text-muted-foreground lg:text-sm">
              <th scope="col" className="w-[3.5%] px-1.5 py-3 text-center text-primary">Sr. No.</th>
              <th scope="col" className="w-[13%] px-2.5 py-3 text-primary">Component</th>
              <th scope="col" className="w-[9%] px-2 py-3 text-primary">Sub Category</th>
              <th scope="col" className="w-[9%] px-2 py-3 text-primary">Part No.</th>
              <th scope="col" className="w-[5%] px-1.5 py-3 text-center text-primary">Qty</th>
              <th scope="col" className="w-[6%] px-2 py-3 text-primary">Cupboard</th>
              <th scope="col" className="w-[8%] px-2 py-3 text-primary">Manufacturer</th>
              <th scope="col" className="w-[8%] px-2 py-3 text-primary">Vendor</th>
              <th scope="col" className="w-[7%] px-2 py-3 text-primary">Package</th>
              <th scope="col" className="w-[12%] px-2.5 py-3 text-primary">Specification</th>
              {showMeta && <th scope="col" className="w-[8%] px-2 py-3 text-primary">Added By</th>}
              {showMeta && <th scope="col" className="w-[4.5%] px-1.5 py-3 text-primary">Date</th>}
              <th scope="col" className="w-[12%] px-2 py-3 text-right text-primary">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {items.map((item, index) => (
              <tr key={item.id} className="transition-colors hover:bg-muted/50">
                <td className="px-1.5 py-2.5 text-center font-mono text-xs text-muted-foreground lg:text-sm">
                  {startIndex + index + 1}
                </td>
                <td className="px-2.5 py-2.5 font-medium text-foreground">
                  <div className="flex items-center gap-1 overflow-hidden" title={item.component_name?.toUpperCase()}>
                    <span className="truncate text-sm font-semibold lg:text-base">{item.component_name?.toUpperCase()}</span>
                    {item.is_demo && (
                      <Badge variant="outline" className="shrink-0 text-[9px] uppercase">
                        Demo
                      </Badge>
                    )}
                  </div>
                </td>
                <td className="px-2 py-2.5 text-muted-foreground" title={item.sub_category ? item.sub_category.toUpperCase() : ""}>
                  <span className="block truncate text-sm font-medium text-foreground/90 lg:text-base">
                    {item.sub_category && item.sub_category.trim() ? item.sub_category.toUpperCase() : "—"}
                  </span>
                </td>
                <td className="px-2 py-2.5" title={item.part_number?.toUpperCase()}>
                  <span className="block truncate rounded bg-muted/60 px-1.5 py-0.5 font-mono text-sm font-semibold text-foreground/90 lg:text-base">
                    {item.part_number?.toUpperCase()}
                  </span>
                </td>
                <td className="px-1.5 py-2.5 text-center">
                  <QuantityBadge quantity={item.quantity} />
                </td>
                <td className="px-2 py-2.5 font-bold text-accent" title={item.cupboard_number?.toUpperCase()}>
                  <span className="block truncate text-sm lg:text-base">{item.cupboard_number?.toUpperCase()}</span>
                </td>
                <td className="px-2 py-2.5 text-muted-foreground" title={item.manufacturer ? item.manufacturer.toUpperCase() : ""}>
                  <span className="block truncate text-sm lg:text-base">
                    {item.manufacturer && item.manufacturer.trim() ? item.manufacturer.toUpperCase() : "—"}
                  </span>
                </td>
                <td className="px-2 py-2.5 text-muted-foreground" title={item.vendor ? item.vendor.toUpperCase() : ""}>
                  <span className="block truncate text-sm lg:text-base">
                    {item.vendor && item.vendor.trim() ? item.vendor.toUpperCase() : "—"}
                  </span>
                </td>
                <td className="px-2 py-2.5 text-muted-foreground" title={item.package ? item.package.toUpperCase() : ""}>
                  <span className="block truncate text-sm lg:text-base">
                    {item.package && item.package.trim() ? item.package.toUpperCase() : "—"}
                  </span>
                </td>
                <td className="px-2.5 py-2.5 text-muted-foreground" title={item.specification ? item.specification.toUpperCase() : ""}>
                  <span className="block truncate text-sm lg:text-base">
                    {item.specification && item.specification.trim() ? item.specification.toUpperCase() : "—"}
                  </span>
                </td>
                {showMeta && (
                  <td className="px-2 py-2.5 font-medium text-foreground/80" title={item.created_by_name ?? "HPT Administrator"}>
                    <span className="block truncate text-xs lg:text-sm">
                      {item.created_by_name ?? "HPT Administrator"}
                    </span>
                  </td>
                )}
                {showMeta && (
                  <td className="whitespace-nowrap px-1.5 py-2.5 text-xs text-muted-foreground lg:text-sm">
                    {new Date(item.created_at).toLocaleDateString(undefined, { month: "numeric", day: "numeric", year: "2-digit" })}
                  </td>
                )}
                <td className="whitespace-nowrap px-2 py-2.5 text-right">
                  {renderActions ? (
                    renderActions(item, handleView)
                  ) : (
                    <button
                      type="button"
                      onClick={() => handleView(item)}
                      title="View component details"
                      className="inline-flex items-center gap-1 rounded-md border border-border bg-background px-2.5 py-1 text-xs font-medium text-foreground shadow-2xs hover:bg-accent hover:text-accent-foreground"
                    >
                      <Eye className="size-3.5" aria-hidden />
                      <span>View</span>
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Mobile cards */}
      <div className="grid gap-3 md:hidden">
        {items.map((item, index) => (
          <div key={item.id} className="card-elevated p-4">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-start gap-2">
                <span className="rounded bg-muted/80 px-1.5 py-0.5 font-mono text-xs font-semibold text-muted-foreground">
                  #{startIndex + index + 1}
                </span>
                <Package className="mt-0.5 size-4 shrink-0 text-accent" aria-hidden />
                <div>
                  <p className="text-base font-semibold text-foreground">
                    {item.component_name?.toUpperCase()}
                    {item.is_demo && (
                      <Badge variant="outline" className="ml-2 text-[10px] uppercase">
                        Demo
                      </Badge>
                    )}
                  </p>
                  {item.sub_category && item.sub_category.trim() && (
                    <p className="text-sm font-medium text-primary">Sub Category: {item.sub_category.toUpperCase()}</p>
                  )}
                  <p className="font-mono text-base font-semibold text-foreground/90">{item.part_number?.toUpperCase()}</p>
                </div>
              </div>
              <QuantityBadge quantity={item.quantity} />
            </div>
            <dl className="mt-3 grid grid-cols-2 gap-2 border-t border-border pt-3 text-base">
              <div>
                <dt className="text-sm text-muted-foreground">Cupboard No.</dt>
                <dd className="font-bold text-accent">{item.cupboard_number?.toUpperCase()}</dd>
              </div>
              <div>
                <dt className="text-sm text-muted-foreground">Manufacturer</dt>
                <dd className="font-medium text-foreground">{item.manufacturer?.trim() ? item.manufacturer.toUpperCase() : "—"}</dd>
              </div>
              <div>
                <dt className="text-sm text-muted-foreground">Vendor</dt>
                <dd className="font-medium text-foreground">{item.vendor?.trim() ? item.vendor.toUpperCase() : "—"}</dd>
              </div>
              <div>
                <dt className="text-sm text-muted-foreground">Package</dt>
                <dd className="font-medium text-foreground">{item.package?.trim() ? item.package.toUpperCase() : "—"}</dd>
              </div>
              {item.specification?.trim() && (
                <div className="col-span-2">
                  <dt className="text-sm text-muted-foreground">Specification</dt>
                  <dd className="font-medium text-foreground">{item.specification.toUpperCase()}</dd>
                </div>
              )}
              {showMeta && (
                <div className="col-span-2">
                  <dt className="text-sm text-muted-foreground">Added By</dt>
                  <dd className="font-medium text-foreground">
                    {item.created_by_name ?? "System"} ({new Date(item.created_at).toLocaleDateString()})
                  </dd>
                </div>
              )}
            </dl>
            <div className="mt-3 flex justify-end gap-2">
              {renderActions ? (
                renderActions(item, handleView)
              ) : (
                <button
                  type="button"
                  onClick={() => handleView(item)}
                  title="View component details"
                  className="inline-flex items-center gap-1 rounded-md border border-border bg-background px-2.5 py-1 text-xs font-medium text-foreground shadow-2xs hover:bg-accent hover:text-accent-foreground"
                >
                  <Eye className="size-3.5" aria-hidden />
                  <span>View</span>
                </button>
              )}
            </div>
          </div>
        ))}
      </div>

      {/* Component Details Popup Modal */}
      <ComponentViewModal
        item={viewingItem}
        open={viewingItem !== null}
        onOpenChange={(open) => !open && setViewingItem(null)}
      />
    </>
  );
}
