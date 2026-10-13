/** Financial identifiers shown in item details require an explicit reveal. */
export function isSensitiveFinancialField(label: string, kind?: string): boolean {
  const normalized = label.trim().toLowerCase().replace(/[\s_-]+/g, " ");
  if (kind === "credit-card" && normalized === "number") return true;
  return /^(?:card number|credit card number|account number|bank account number|routing number|iban|swift\s*\/?\s*bic)$/.test(normalized);
}
