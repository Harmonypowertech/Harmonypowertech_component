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
  return (
    <span className={`inline-flex rounded-md px-1.5 py-0.5 text-xs font-bold md:text-[13px] lg:text-sm xl:text-base ${tone}`}>
      {quantity}
    </span>
  );
}

/** Responsive component listing: table on desktop/laptop, cards on mobile. */
export function ComponentTable({ items, startIndex = 0, showMeta = false, renderActions }: Props) {
  const [viewingItem, setViewingItem] = useState<ComponentRecord | null>(null);

  const handleView = (item: ComponentRecord) => {
    setViewingItem(item);
  };

  return (
    <>
      {/* Desktop & Laptop table container */}
      <div className="hidden w-full overflow-x-auto rounded-lg border border-border bg-card shadow-sm md:block">
        <table className="w-full min-w-[980px] table-fixed border-collapse text-left text-xs md:text-[12px] lg:text-[13px] xl:text-sm 2xl:text-base">
          <thead>
            <tr className="border-b border-border bg-secondary/80 text-[8px] font-semibold uppercase tracking-wider text-muted-foreground md:text-[9px] lg:text-[10px] xl:text-[11px]">
              <th scope="col" className="w-[3.5%] min-w-[36px] px-1 py-2.5 text-center text-primary">Sr. No.</th>
              <th scope="col" className="w-[13%] min-w-[120px] px-2 py-2.5 text-primary">Component</th>
              <th scope="col" className="w-[9%] min-w-[85px] px-1.5 py-2.5 text-primary">Sub Category</th>
              <th scope="col" className="w-[10%] min-w-[95px] px-1.5 py-2.5 text-primary">Part No.</th>
              <th scope="col" className="w-[5%] min-w-[45px] px-1 py-2.5 text-center text-primary">Qty</th>
              <th scope="col" className="w-[6%] min-w-[60px] px-1.5 py-2.5 text-primary">Cupboard</th>
              <th scope="col" className="w-[8%] min-w-[80px] px-1.5 py-2.5 text-primary">Manufacturer</th>
              <th scope="col" className="w-[8%] min-w-[80px] px-1.5 py-2.5 text-primary">Vendor</th>
              <th scope="col" className="w-[7%] min-w-[70px] px-1.5 py-2.5 text-primary">Package</th>
              <th scope="col" className="w-[11%] min-w-[100px] px-2 py-2.5 text-primary">Specification</th>
              {showMeta && <th scope="col" className="w-[8%] min-w-[80px] px-1.5 py-2.5 text-primary">Added By</th>}
              {showMeta && <th scope="col" className="w-[4.5%] min-w-[50px] px-1 py-2.5 text-primary">Date</th>}
              <th scope="col" className="w-[11%] min-w-[110px] px-2 py-2.5 text-right text-primary">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {items.map((item, index) => (
              <tr key={item.id} className="transition-colors hover:bg-muted/50">
                <td className="px-1 py-2 text-center font-mono text-[10px] text-muted-foreground md:text-[11px] lg:text-xs xl:text-sm">
                  {startIndex + index + 1}
                </td>
                <td className="px-2 py-2 font-medium text-foreground">
                  <div className="flex items-center gap-1 overflow-hidden" title={item.component_name?.toUpperCase()}>
                    <span className="truncate text-xs font-semibold md:text-[13px] lg:text-sm xl:text-base">
                      {item.component_name?.toUpperCase()}
                    </span>
                    {item.is_demo && (
                      <Badge variant="outline" className="shrink-0 text-[8px] uppercase lg:text-[9px]">
                        Demo
                      </Badge>
                    )}
                  </div>
                </td>
                <td className="px-1.5 py-2 text-muted-foreground" title={item.sub_category ? item.sub_category.toUpperCase() : ""}>
                  <span className="block truncate text-[11px] font-medium text-foreground/90 md:text-xs lg:text-[13px] xl:text-sm">
                    {item.sub_category && item.sub_category.trim() ? item.sub_category.toUpperCase() : "—"}
                  </span>
                </td>
                <td className="px-1.5 py-2" title={item.part_number?.toUpperCase()}>
                  {/* Part Number font size decreased by 3 */}
                  <span className="block truncate rounded bg-muted/60 px-1 py-0.5 font-mono text-[9px] font-semibold text-foreground/90 md:text-[10px] lg:text-[11px] xl:text-xs">
                    {item.part_number?.toUpperCase()}
                  </span>
                </td>
                <td className="px-1 py-2 text-center">
                  <QuantityBadge quantity={item.quantity} />
                </td>
                <td className="px-1.5 py-2 font-bold text-accent" title={item.cupboard_number?.toUpperCase()}>
                  <span className="block truncate text-[11px] md:text-xs lg:text-[13px] xl:text-sm">{item.cupboard_number?.toUpperCase()}</span>
                </td>
                <td className="px-1.5 py-2 text-muted-foreground" title={item.manufacturer ? item.manufacturer.toUpperCase() : ""}>
                  {/* Manufacturer font size decreased by 3 */}
                  <span className="block truncate text-[9px] font-normal text-muted-foreground md:text-[9px] lg:text-[10px] xl:text-[11px]">
                    {item.manufacturer && item.manufacturer.trim() ? item.manufacturer.toUpperCase() : "—"}
                  </span>
                </td>
                <td className="px-1.5 py-2 text-muted-foreground" title={item.vendor ? item.vendor.toUpperCase() : ""}>
                  {/* Vendor font size decreased by 3 */}
                  <span className="block truncate text-[9px] font-normal text-muted-foreground md:text-[9px] lg:text-[10px] xl:text-[11px]">
                    {item.vendor && item.vendor.trim() ? item.vendor.toUpperCase() : "—"}
                  </span>
                </td>
                <td className="px-1.5 py-2 text-muted-foreground" title={item.package ? item.package.toUpperCase() : ""}>
                  {/* Package font size decreased by 3 */}
                  <span className="block truncate text-[9px] font-normal text-muted-foreground md:text-[9px] lg:text-[10px] xl:text-[11px]">
                    {item.package && item.package.trim() ? item.package.toUpperCase() : "—"}
                  </span>
                </td>
                <td className="px-2 py-2 text-muted-foreground" title={item.specification ? item.specification.toUpperCase() : ""}>
                  {/* Specification font size decreased by 3 */}
                  <span className="block truncate text-[9px] font-normal text-muted-foreground md:text-[9px] lg:text-[10px] xl:text-[11px]">
                    {item.specification && item.specification.trim() ? item.specification.toUpperCase() : "—"}
                  </span>
                </td>
                {showMeta && (
                  <td className="px-1.5 py-2 font-medium text-foreground/80" title={item.created_by_name ?? "HPT Administrator"}>
                    <span className="block truncate text-[10px] md:text-[11px] lg:text-xs xl:text-sm">
                      {item.created_by_name ?? "HPT Administrator"}
                    </span>
                  </td>
                )}
                {showMeta && (
                  <td className="whitespace-nowrap px-1 py-2 text-[10px] text-muted-foreground md:text-[11px] lg:text-xs">
                    {new Date(item.created_at).toLocaleDateString(undefined, { month: "numeric", day: "numeric", year: "2-digit" })}
                  </td>
                )}
                <td className="whitespace-nowrap px-2 py-2 text-right">
                  {renderActions ? (
                    renderActions(item, handleView)
                  ) : (
                    <button
                      type="button"
                      onClick={() => handleView(item)}
                      title="View component details"
                      className="inline-flex items-center gap-1 rounded-md border border-border bg-background px-2 py-1 text-[11px] font-medium text-foreground shadow-2xs hover:bg-accent hover:text-accent-foreground md:text-xs"
                    >
                      <Eye className="size-3 md:size-3.5" aria-hidden />
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
          <div key={item.id} className="card-elevated p-3.5 sm:p-4">
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-start gap-2">
                <span className="rounded bg-muted/80 px-1.5 py-0.5 font-mono text-xs font-semibold text-muted-foreground">
                  #{startIndex + index + 1}
                </span>
                <Package className="mt-0.5 size-4 shrink-0 text-accent" aria-hidden />
                <div>
                  <p className="text-sm font-semibold text-foreground sm:text-base">
                    {item.component_name?.toUpperCase()}
                    {item.is_demo && (
                      <Badge variant="outline" className="ml-2 text-[9px] uppercase">
                        Demo
                      </Badge>
                    )}
                  </p>
                  {item.sub_category && item.sub_category.trim() && (
                    <p className="text-xs font-medium text-primary sm:text-sm">Sub Category: {item.sub_category.toUpperCase()}</p>
                  )}
                  {/* Part number font size decreased by 3 */}
                  <p className="font-mono text-[11px] font-medium text-muted-foreground">{item.part_number?.toUpperCase()}</p>
                </div>
              </div>
              <QuantityBadge quantity={item.quantity} />
            </div>
            <dl className="mt-3 grid grid-cols-2 gap-2 border-t border-border pt-3 text-xs sm:text-sm">
              <div>
                <dt className="text-xs text-muted-foreground">Cupboard No.</dt>
                <dd className="font-bold text-accent">{item.cupboard_number?.toUpperCase()}</dd>
              </div>
              <div>
                <dt className="text-[10px] text-muted-foreground">Manufacturer</dt>
                <dd className="text-[11px] text-foreground">{item.manufacturer?.trim() ? item.manufacturer.toUpperCase() : "—"}</dd>
              </div>
              <div>
                <dt className="text-[10px] text-muted-foreground">Vendor</dt>
                <dd className="text-[11px] text-foreground">{item.vendor?.trim() ? item.vendor.toUpperCase() : "—"}</dd>
              </div>
              <div>
                <dt className="text-[10px] text-muted-foreground">Package</dt>
                <dd className="text-[11px] text-foreground">{item.package?.trim() ? item.package.toUpperCase() : "—"}</dd>
              </div>
              {item.specification?.trim() && (
                <div className="col-span-2">
                  <dt className="text-[10px] text-muted-foreground">Specification</dt>
                  <dd className="text-[11px] text-foreground">{item.specification.toUpperCase()}</dd>
                </div>
              )}
              {showMeta && (
                <div className="col-span-2">
                  <dt className="text-xs text-muted-foreground">Added By</dt>
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
                  className="inline-flex items-center gap-1 rounded-md border border-border bg-background px-2 py-1 text-xs font-medium text-foreground shadow-2xs hover:bg-accent hover:text-accent-foreground"
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
