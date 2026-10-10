// How categories and severities look. Generic: they depend only on an event's category and
// severity, never on its producer.

export const CATEGORIES = [
  { value: "ACTION_REQUIRED", label: "Action required", glyph: "pan_tool" },
  { value: "BLOCKED", label: "Blocked", glyph: "block" },
  { value: "COMPLETED", label: "Completed", glyph: "check_circle" },
  { value: "INFO", label: "Info", glyph: "info" },
];

export const SEVERITIES = [
  { value: "LOW", label: "Low" },
  { value: "NORMAL", label: "Normal" },
  { value: "HIGH", label: "High" },
  { value: "CRITICAL", label: "Critical" },
];

export function categoryOf(value) {
  return CATEGORIES.find((category) => category.value === value) ?? { value, label: "Other", glyph: "label" };
}

export function severityLabel(value) {
  return SEVERITIES.find((severity) => severity.value === value)?.label ?? "Unknown";
}

/** The colour class of an event's icon: critical and high are errors, normal is primary. */
export function toneOf(severity) {
  if (severity === "CRITICAL" || severity === "HIGH") return "c-error";
  if (severity === "NORMAL") return "c-primary";
  return "c-var";
}
