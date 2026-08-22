export const provenanceClasses = [
  "USER_INTENT",
  "USER_ENTERED_SITE_DATA",
  "FIRST_PARTY_SITE_CONTENT",
  "THIRD_PARTY_EMBED",
  "EMAIL_FROM_EXTERNAL_SENDER",
  "ADVERTISEMENT",
  "TOOL_RESULT",
  "PASSWORD_OR_SECRET",
  "MODEL_GENERATED",
  "LOCAL_TRUSTED_POLICY",
] as const;

export type ProvenanceClass = (typeof provenanceClasses)[number];

export interface ProvenancedText {
  text: string;
  provenance: ProvenanceClass;
}

export interface AddressingCounters {
  address_resolution_failed: number;
  address_now_ambiguous: number;
  logical_target_changed: number;
  node_replaced_but_semantic_locator_recovered: number;
  coordinate_invalidated_by_layout_change: number;
}

export interface ObservedElement {
  element_id: string;
  tag: string;
  role: ProvenancedText;
  name: ProvenancedText;
  value?: ProvenancedText;
  disabled: boolean;
}

export interface Observation {
  observation_id: string;
  url: ProvenancedText;
  title: ProvenancedText;
  text: ProvenancedText;
  elements: ObservedElement[];
  complete: boolean;
  addressing: AddressingCounters;
  backend: "linux-playwright-chromium" | "linux-playwright-webkit";
}

export interface Receipt {
  receipt_id: string;
  session_id: string;
  action: "click" | "fill";
  status: "succeeded" | "failed" | "indeterminate";
  dispatched: "not_dispatched" | "dispatched" | "unknown";
  observation_id: string;
  element_id: string;
  postcondition: string;
  created_monotonic_ms: number;
  evidence?: string;
}

export interface ToolResult {
  content: Array<{ type: "text"; text: string }>;
  structuredContent?: unknown;
  isError?: boolean;
}

export function emptyCounters(): AddressingCounters {
  return {
    address_resolution_failed: 0,
    address_now_ambiguous: 0,
    logical_target_changed: 0,
    node_replaced_but_semantic_locator_recovered: 0,
    coordinate_invalidated_by_layout_change: 0,
  };
}
