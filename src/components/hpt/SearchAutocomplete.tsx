import React, { useEffect, useMemo, useRef, useState } from "react";
import {
  Archive,
  Box,
  Building2,
  FileText,
  Layers,
  Package,
  Search,
  Store,
  Tag,
  X,
} from "lucide-react";
import { Input } from "@/components/ui/input";
import type { LightComponentSuggestion } from "@/lib/hpt/data.server";

export type SuggestionType =
  | "name"
  | "part"
  | "subcategory"
  | "manufacturer"
  | "vendor"
  | "package"
  | "specification"
  | "cupboard";

export type SuggestionItem = {
  id: string;
  text: string;
  type: SuggestionType;
  label: string;
  subtext?: string;
};

type Props = {
  value: string;
  onChange: (value: string) => void;
  onSubmitSearch: (query: string) => void;
  onClear: () => void;
  componentNames?: string[];
  subCategories?: string[];
  allComponents?: LightComponentSuggestion[];
  placeholder?: string;
  className?: string;
  disabled?: boolean;
};

export function SearchAutocomplete({
  value,
  onChange,
  onSubmitSearch,
  onClear,
  componentNames = [],
  subCategories = [],
  allComponents = [],
  placeholder = "Search components by any field...",
  className = "",
  disabled = false,
}: Props) {
  const [isOpen, setIsOpen] = useState(false);
  const [selectedIndex, setSelectedIndex] = useState<number>(-1);
  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Close dropdown on click outside
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Instant, robust, case-insensitive suggestions calculation across EVERY SINGLE FIELD of ALL components
  const suggestions: SuggestionItem[] = useMemo(() => {
    const query = value.trim().toLowerCase();
    if (!query) return [];

    const items: SuggestionItem[] = [];
    const seenKeys = new Set<string>();

    const add = (
      val: string | null | undefined,
      type: SuggestionType,
      label: string,
      subtext?: string,
    ) => {
      if (!val) return;
      const clean = val.trim();
      if (!clean) return;
      if (!clean.toLowerCase().includes(query)) return;

      const key = `${type}:${clean.toUpperCase()}`;
      if (!seenKeys.has(key)) {
        seenKeys.add(key);
        items.push({
          id: `${type}-${clean}-${items.length}`,
          text: clean,
          type,
          label,
          subtext,
        });
      }
    };

    // 1. Search Component Names list
    for (let i = 0; i < componentNames.length; i++) {
      add(componentNames[i], "name", "Component Name");
    }

    // 2. Search Sub Categories list
    for (let i = 0; i < subCategories.length; i++) {
      add(subCategories[i], "subcategory", "Sub Category");
    }

    // 3. Search EVERY SINGLE ENTRY and FIELD across all components in DB dataset
    for (let i = 0; i < allComponents.length; i++) {
      const comp = allComponents[i];
      const ctx = comp.component_name || comp.part_number || undefined;

      add(comp.component_name, "name", "Component Name");
      add(comp.part_number, "part", "Part Number", ctx);
      add(comp.sub_category, "subcategory", "Sub Category", ctx);
      add(comp.manufacturer, "manufacturer", "Manufacturer", ctx);
      add(comp.vendor, "vendor", "Vendor", ctx);
      add(comp.package, "package", "Package", ctx);
      add(comp.specification, "specification", "Specification", ctx);
      add(comp.cupboard_number, "cupboard", "Cupboard", ctx);
    }

    // Sort matches: items starting with the typed query get priority
    items.sort((a, b) => {
      const aStarts = a.text.toLowerCase().startsWith(query);
      const bStarts = b.text.toLowerCase().startsWith(query);
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;
      return a.text.localeCompare(b.text);
    });

    return items.slice(0, 15);
  }, [value, componentNames, subCategories, allComponents]);

  const showDropdown = isOpen && value.trim().length > 0 && suggestions.length > 0;

  function handleInputChange(e: React.ChangeEvent<HTMLInputElement>) {
    const newValue = e.target.value;
    onChange(newValue);
    setSelectedIndex(-1);
    setIsOpen(true);
  }

  function handleSelectSuggestion(suggestionText: string) {
    onChange(suggestionText);
    onSubmitSearch(suggestionText);
    setIsOpen(false);
    setSelectedIndex(-1);
  }

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (!showDropdown) {
      if (e.key === "Enter") {
        e.preventDefault();
        onSubmitSearch(value);
      }
      return;
    }

    if (e.key === "ArrowDown") {
      e.preventDefault();
      setSelectedIndex((prev) => (prev < suggestions.length - 1 ? prev + 1 : 0));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setSelectedIndex((prev) => (prev > 0 ? prev - 1 : suggestions.length - 1));
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (selectedIndex >= 0 && selectedIndex < suggestions.length) {
        handleSelectSuggestion(suggestions[selectedIndex].text);
      } else {
        onSubmitSearch(value);
        setIsOpen(false);
      }
    } else if (e.key === "Escape") {
      setIsOpen(false);
      setSelectedIndex(-1);
    }
  }

  // Case-insensitive text highlighter matching lower, upper, and mixed case
  function renderHighlightedText(text: string, search: string) {
    const trimmedSearch = search.trim();
    if (!trimmedSearch) return text;

    try {
      const escaped = trimmedSearch.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const regex = new RegExp(`(${escaped})`, "gi");
      const parts = text.split(regex);

      return (
        <span>
          {parts.map((part, i) =>
            part.toLowerCase() === trimmedSearch.toLowerCase() ? (
              <span key={i} className="font-bold text-primary underline decoration-primary/40 decoration-2">
                {part}
              </span>
            ) : (
              part
            ),
          )}
        </span>
      );
    } catch {
      return text;
    }
  }

  function getSuggestionIcon(type: SuggestionType) {
    switch (type) {
      case "name":
        return <Package className="size-3.5 shrink-0 text-primary" aria-hidden />;
      case "part":
        return <Tag className="size-3.5 shrink-0 text-amber-500" aria-hidden />;
      case "subcategory":
        return <Layers className="size-3.5 shrink-0 text-blue-500" aria-hidden />;
      case "manufacturer":
        return <Building2 className="size-3.5 shrink-0 text-emerald-500" aria-hidden />;
      case "vendor":
        return <Store className="size-3.5 shrink-0 text-purple-500" aria-hidden />;
      case "package":
        return <Box className="size-3.5 shrink-0 text-indigo-500" aria-hidden />;
      case "specification":
        return <FileText className="size-3.5 shrink-0 text-slate-500" aria-hidden />;
      case "cupboard":
        return <Archive className="size-3.5 shrink-0 text-rose-500" aria-hidden />;
      default:
        return <Search className="size-3.5 shrink-0 text-muted-foreground" aria-hidden />;
    }
  }

  return (
    <div ref={containerRef} className={`relative flex-1 ${className}`}>
      <div className="relative">
        <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground pointer-events-none" aria-hidden />
        <Input
          ref={inputRef}
          value={value}
          onChange={handleInputChange}
          onFocus={() => setIsOpen(true)}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          className="pl-9 pr-9"
          disabled={disabled}
          aria-label="Search components"
          aria-autocomplete="list"
          aria-expanded={showDropdown}
        />
        {value && (
          <button
            type="button"
            onClick={() => {
              onClear();
              setIsOpen(false);
              setSelectedIndex(-1);
              inputRef.current?.focus();
            }}
            className="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 text-muted-foreground hover:text-foreground transition-colors"
            aria-label="Clear search"
          >
            <X className="size-4" aria-hidden />
          </button>
        )}
      </div>

      {/* Suggestions Overlay Dropdown */}
      {showDropdown && (
        <div className="absolute left-0 right-0 top-full z-50 mt-1.5 overflow-hidden rounded-xl border border-border/80 bg-card/98 p-1.5 shadow-xl backdrop-blur-md animate-in fade-in-50 slide-in-from-top-1">
          <div className="flex items-center justify-between px-2.5 py-1.5 border-b border-border/50 text-[11px] font-semibold text-muted-foreground uppercase tracking-wider">
            <span>Suggestions for "{value}"</span>
            <span className="text-[10px] font-normal text-muted-foreground/70">Press ↑↓ to navigate</span>
          </div>

          <ul role="listbox" className="mt-1 max-h-64 overflow-y-auto space-y-0.5">
            {suggestions.map((item, index) => {
              const isSelected = index === selectedIndex;

              return (
                <li
                  key={item.id}
                  role="option"
                  aria-selected={isSelected}
                  onMouseEnter={() => setSelectedIndex(index)}
                  onClick={() => handleSelectSuggestion(item.text)}
                  className={`flex items-center justify-between gap-2 rounded-lg px-3 py-2 text-xs cursor-pointer transition-all ${
                    isSelected
                      ? "bg-accent/20 text-accent-foreground font-medium pl-3.5"
                      : "text-foreground hover:bg-muted/70"
                  }`}
                >
                  <div className="flex items-center gap-2.5 min-w-0">
                    {getSuggestionIcon(item.type)}
                    
                    <span className="truncate">
                      {renderHighlightedText(item.text, value)}
                    </span>

                    {item.subtext && item.subtext.toLowerCase() !== item.text.toLowerCase() && (
                      <span className="text-[11px] text-muted-foreground truncate">
                        ({item.subtext})
                      </span>
                    )}
                  </div>

                  <span className="shrink-0 rounded bg-muted px-1.5 py-0.5 text-[10px] font-medium text-muted-foreground">
                    {item.label}
                  </span>
                </li>
              );
            })}
          </ul>
        </div>
      )}
    </div>
  );
}
