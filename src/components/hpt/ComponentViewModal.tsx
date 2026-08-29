import React from "react";
import {
  Building2,
  Calendar,
  Eye,
  FileText,
  Hash,
  Layers,
  MapPin,
  Package,
  Store,
  Tag,
  User,
  X,
} from "lucide-react";

import type { ComponentRecord } from "@/lib/hpt/types";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

type Props = {
  item: ComponentRecord | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
};

function QuantityStatus({ quantity }: { quantity: number }) {
  const tone =
    quantity === 0
      ? "bg-destructive/15 text-destructive border-destructive/30"
      : quantity < 50
        ? "bg-warning/15 text-warning-foreground border-warning/30"
        : "bg-success/15 text-success border-success/30";

  const label =
    quantity === 0 ? "Out of Stock" : quantity < 50 ? "Low Stock" : "In Stock";

  return (
    <div className="flex items-center gap-2">
      <span className={`inline-flex items-center rounded-md border px-2.5 py-1 text-base font-bold ${tone}`}>
        {quantity} Units
      </span>
      <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
        ({label})
      </span>
    </div>
  );
}

export function ComponentViewModal({ item, open, onOpenChange }: Props) {
  if (!item) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto sm:p-6">
        <DialogHeader className="border-b border-border pb-3">
          <DialogTitle className="flex items-center gap-2 text-lg font-bold text-foreground sm:text-xl">
            <div className="flex size-8 items-center justify-center rounded-lg bg-primary/10 text-primary">
              <Eye className="size-4" aria-hidden />
            </div>
            Component Details
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-5 pt-2">
          {/* Main Title & Part Number Card */}
          <div className="rounded-lg border border-border/80 bg-muted/40 p-4 shadow-sm">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div className="space-y-1">
                <div className="flex items-center gap-2">
                  <Package className="size-5 text-accent" aria-hidden />
                  <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                    Component Name
                  </span>
                  {item.is_demo && (
                    <Badge variant="outline" className="text-[10px] uppercase">
                      Demo
                    </Badge>
                  )}
                </div>
                <h3 className="text-lg font-bold text-foreground sm:text-xl">
                  {item.component_name?.toUpperCase() || "N/A"}
                </h3>
              </div>

              <div className="space-y-1 sm:text-right">
                <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  Part Number
                </span>
                <p className="font-mono text-lg font-bold text-primary sm:text-xl">
                  {item.part_number?.toUpperCase() || "N/A"}
                </p>
              </div>
            </div>
          </div>

          {/* Key Parameters Grid */}
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {/* Sub Category */}
            <div className="rounded-md border border-border/60 bg-card p-3 shadow-2xs">
              <div className="flex items-center gap-1.5 text-muted-foreground">
                <Layers className="size-4 text-primary" aria-hidden />
                <span className="text-xs font-semibold uppercase">Sub Category</span>
              </div>
              <p className="mt-1 text-base font-semibold text-foreground">
                {item.sub_category?.trim() ? item.sub_category.toUpperCase() : "—"}
              </p>
            </div>

            {/* Cupboard Location */}
            <div className="rounded-md border border-border/60 bg-card p-3 shadow-2xs">
              <div className="flex items-center gap-1.5 text-muted-foreground">
                <MapPin className="size-4 text-accent" aria-hidden />
                <span className="text-xs font-semibold uppercase">Cupboard Location</span>
              </div>
              <p className="mt-1 text-base font-bold text-accent">
                {item.cupboard_number?.toUpperCase() || "—"}
              </p>
            </div>

            {/* Quantity */}
            <div className="rounded-md border border-border/60 bg-card p-3 shadow-2xs">
              <div className="flex items-center gap-1.5 text-muted-foreground">
                <Hash className="size-4 text-primary" aria-hidden />
                <span className="text-xs font-semibold uppercase">Quantity</span>
              </div>
              <div className="mt-1">
                <QuantityStatus quantity={item.quantity} />
              </div>
            </div>

            {/* Manufacturer */}
            <div className="rounded-md border border-border/60 bg-card p-3 shadow-2xs">
              <div className="flex items-center gap-1.5 text-muted-foreground">
                <Building2 className="size-4 text-primary" aria-hidden />
                <span className="text-xs font-semibold uppercase">Manufacturer</span>
              </div>
              <p className="mt-1 text-base font-semibold text-foreground">
                {item.manufacturer?.trim() ? item.manufacturer.toUpperCase() : "—"}
              </p>
            </div>

            {/* Vendor */}
            <div className="rounded-md border border-border/60 bg-card p-3 shadow-2xs">
              <div className="flex items-center gap-1.5 text-muted-foreground">
                <Store className="size-4 text-primary" aria-hidden />
                <span className="text-xs font-semibold uppercase">Vendor</span>
              </div>
              <p className="mt-1 text-base font-semibold text-foreground">
                {item.vendor?.trim() ? item.vendor.toUpperCase() : "—"}
              </p>
            </div>

            {/* Package */}
            <div className="rounded-md border border-border/60 bg-card p-3 shadow-2xs">
              <div className="flex items-center gap-1.5 text-muted-foreground">
                <Tag className="size-4 text-primary" aria-hidden />
                <span className="text-xs font-semibold uppercase">Package / Footprint</span>
              </div>
              <p className="mt-1 text-base font-semibold text-foreground">
                {item.package?.trim() ? item.package.toUpperCase() : "—"}
              </p>
            </div>
          </div>

          {/* Specification Details */}
          <div className="rounded-md border border-border/60 bg-card p-3.5 shadow-2xs">
            <div className="flex items-center gap-1.5 text-muted-foreground">
              <FileText className="size-4 text-primary" aria-hidden />
              <span className="text-xs font-semibold uppercase">Specification</span>
            </div>
            <p className="mt-1.5 whitespace-pre-wrap text-base font-normal text-foreground">
              {item.specification?.trim() ? item.specification.toUpperCase() : "No specification provided."}
            </p>
          </div>

          {/* Metadata Section */}
          <div className="grid grid-cols-1 gap-3 rounded-md border border-border/40 bg-muted/20 p-3 text-xs text-muted-foreground sm:grid-cols-2">
            <div className="flex items-center gap-1.5">
              <User className="size-3.5" aria-hidden />
              <span>Added By: <strong className="text-foreground">{item.created_by_name ?? "HPT Administrator"}</strong></span>
            </div>
            <div className="flex items-center gap-1.5">
              <Calendar className="size-3.5" aria-hidden />
              <span>
                Created:{" "}
                <strong className="text-foreground">
                  {new Date(item.created_at).toLocaleString()}
                </strong>
              </span>
            </div>
          </div>
        </div>

        {/* Footer with Close Button */}
        <div className="mt-4 flex justify-end border-t border-border pt-3">
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            className="flex items-center gap-1.5"
          >
            <X className="size-4" aria-hidden />
            Close
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
