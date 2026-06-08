/**
 * LumenPass Content Script
 * Detects login forms, injects autofill icons, and handles domain-matched suggestions.
 */

import browser from "webextension-polyfill";
import type { CategoryItem, EntryItem, EntryDetail, PasskeyMatchItem, DisabledAutofillDomain } from "../lib/api";
import {
  seedColour,
  initials,
  extractDomain,
  googleFaviconUrlForDisplay,
  pastelAvatar,
  computeTotp,
  totpCountdown,
} from "../lib/utils";
import {
  buildFeaturedTotps,
} from "../lib/totp-display";
import { generatePassword } from "../lib/password-generator";
import { generatePasswordFromConfig, getGeneratorConfig } from "../lib/password-generator";
import type { GeneratorType } from "../lib/storage";
import {
  getCredentialIdentifierKind,
  isCredentialIdentifierPurpose,
  isOneTimeCodeAutocomplete,
  isOneTimeCodeDescriptor,
  type CredentialIdentifierKind,
} from "./field-purpose";
import { parseCardExpiry } from "./credit-card-fields";
import {
  decideLoginSurface,
  isLikelyLoginSurfaceFromSignals,
  type LoginSurfaceSignals,
} from "./login-surface";
import { findBestSelectOptionIndex } from "./select-option-match";

// ─── Constants ────────────────────────────────────────────────────────────────

const POPUP_ID = "lumenpass-inline-popup";
const ICON_SIZE = 22;
const POPUP_GAP = 4;
const POPUP_VIEWPORT_MARGIN = 12;
const POPUP_LIST_MAX_HEIGHT = 320;
const ALL_ITEMS_SEARCH_DEBOUNCE_MS = 500;
const PROACTIVE_LOGIN_RETRY_DEBOUNCE_MS = 450;
const PROACTIVE_LOGIN_RETRY_MIN_INTERVAL_MS = 2500;
const EMAIL_LIKE_IDENTIFIER_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
/**
 * Last password value injected by LumenPass autofill for each field.
 * We only suppress the post-login save capture when the submitted password is
 * still exactly that value — if the user overwrites the field after autofill,
 * we must capture so the service worker can offer "update password".
 */
const lastExtensionAutofillPasswordByField = new WeakMap<HTMLInputElement, string>();
const TEXTUAL_INPUT_TYPES = new Set(["", "text", "email", "search", "tel", "url"]);
type FillableField = HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;

// ─── Card / Identity autofill constants ───────────────────────────────────────

const ALL_CARD_AUTOCOMPLETE = new Set(["cc-number", "cc-exp", "cc-exp-month", "cc-exp-year", "cc-csc", "cc-name", "cc-type"]);
const CARD_NUMBER_AUTOCOMPLETE = new Set(["cc-number"]);
const CARD_FIELD_DESCRIPTOR_PATTERN =
  /cc-number|card.?number|cardnumber|card.?num|cc.?num|card.?pan|^number$|^pan$|cc.?type|card.?type|credit.?card.?type|cc.?exp|card.?exp|ccexp|expir|expiry|exp.?date|date.?exp|valid.?thru|valid.?through|mm\s*[/.-]?\s*yy|yy\s*[/.-]?\s*mm|cvc|cvv|cvn|cid|cc.?csc|security.?code|verification.?number|verification.?code|cardholder|card.?holder|card.?user.?name|card.?owner|billing.?name|cc.?uname|cc.?name|card.?name|name.?on.?card/;
const CARD_NUMBER_DESCRIPTOR_PATTERN =
  /cc-number|card.?number|cardnumber|card.?num|cc.?num|card.?pan|^number$|^pan$/;
const CARD_EXPIRY_DESCRIPTOR_PATTERN =
  /cc.?exp(?![^a-z0-9]*(month|year))|card.?exp(?![^a-z0-9]*(month|year))|\bexpir(?:y|ation)?\b(?![^a-z0-9]*(month|year))|\bexp\b(?![^a-z0-9]*(month|year))|exp.?date|date.?exp|valid.?thru|valid.?through|mm\s*[/.-]?\s*yy|yy\s*[/.-]?\s*mm/;

const IDENTITY_AUTOCOMPLETE_VALUES = new Set([
  "name", "given-name", "additional-name", "family-name", "honorific-prefix",
  "email", "street-address", "address-line1", "address-line2",
  "address-level1", "address-level2", "postal-code", "country", "country-name",
  "tel", "organization",
]);

// ─── State ────────────────────────────────────────────────────────────────────

let activeAutofillField: FillableField | null = null;
/** The last input field the user right-clicked, used to target Password Generator fill. */
let lastContextMenuField: HTMLInputElement | null = null;
/** One persistent icon element per detected auth surface, shown only when the field is focused. */
const fieldIcons = new Map<FillableField, HTMLDivElement>();
/** Tracks which fields currently have focus so icons are only visible on focus. */
const focusedFields = new Set<FillableField>();
let popupEl: HTMLDivElement | null = null;
let itemDetailModalEl: HTMLDivElement | null = null;
let fillValuePromptEl: HTMLDivElement | null = null;
let itemDetailCopiedTimer: number | null = null;
let itemDetailTotpTimer: number | null = null;
let itemDetailLoadToken = 0;
let entries: EntryItem[] = [];
let socialEntries: EntryItem[] = [];
let socialFloatEl: HTMLDivElement | null = null;
let selectedIndex = 0;
let fetchController: AbortController | null = null;
let popupSearchQuery = "";
type PopupTab = "suggestions" | "all";
let popupTab: PopupTab = "suggestions";
let popupAllQuery = "";
let allItemsResults: EntryItem[] = [];
let allItemsLoading = false;
let allItemsHasSearched = false;
let allItemsSearchToken = 0;
let allItemsDebounceTimer: number | null = null;
let entriesSearchToken = 0;
let identifierHintDebounceTimer: number | null = null;
let identifierHintAllowsEmptyQuery = false;
let suppressPopupOpen = false;
let hasUserInteracted = false;
type FieldKind = "login" | "card" | "identity" | "identifier";
type EntrySearchType = "login" | "credit-card" | "identity";
let activeFieldKind: FieldKind = "login";
let desktopConnected = true;
let desktopVaultOpen = true;
let tooltipEl: HTMLDivElement | null = null;
let autofillIconsEnabled = true;
let autoSubmitEnabled = false;
let disabledAutofillDomains: DisabledAutofillDomain[] = [];
const dismissedFields = new Set<FillableField>();
const autofilledFields = new Set<FillableField>();

const DISABLE_AUTOFILL_OPTIONS: Array<{ label: string; durationMs: number | null }> = [
  { label: "1 hour", durationMs: 60 * 60 * 1000 },
  { label: "3 hours", durationMs: 3 * 60 * 60 * 1000 },
  { label: "8 hours", durationMs: 8 * 60 * 60 * 1000 },
  { label: "24 hours", durationMs: 24 * 60 * 60 * 1000 },
  { label: "Permanently", durationMs: null },
];

// ─── Helpers ──────────────────────────────────────────────────────────────────

// ─── Shadow DOM isolation ─────────────────────────────────────────────────────
// Every piece of LumenPass UI we inject is rendered inside a Shadow DOM so the
// host page's CSS cannot leak in. Without this, aggressive global rules on
// sites like warp.dev (e.g. `body * { font-family: ... }` or `* { padding: 0
// !important }`) reflowed our save-sign-in modal. The host element is a 0×0
// fixed-positioned <div> appended to <html>; descendants keep their own
// `position: fixed` so positioning against the viewport works exactly as
// before.

let lpShadowHost: HTMLDivElement | null = null;
let lpShadowRoot: ShadowRoot | null = null;

function bringLpShadowHostToFront(): void {
  if (!lpShadowHost?.isConnected) return;
  const parent = document.documentElement || document.body;
  if (lpShadowHost.parentNode !== parent || parent.lastElementChild !== lpShadowHost) {
    parent.appendChild(lpShadowHost);
  }
}

function getLpShadowRoot(): ShadowRoot {
  if (lpShadowRoot && lpShadowHost && lpShadowHost.isConnected) {
    bringLpShadowHostToFront();
    return lpShadowRoot;
  }

  const host = document.createElement("div");
  host.id = "lumenpass-shadow-host";
  host.style.cssText = [
    "all: initial !important",
    "position: fixed !important",
    "top: 0 !important",
    "left: 0 !important",
    "width: 0 !important",
    "height: 0 !important",
    "z-index: 2147483647 !important",
    "pointer-events: none !important",
  ].join(";");

  const parent = document.documentElement || document.body || document;
  parent.appendChild(host);

  const root = host.attachShadow({ mode: "open" });
  const baseStyle = document.createElement("style");
  baseStyle.id = "lp-shadow-base";
  baseStyle.textContent = `
    :host { all: initial; }
    * { box-sizing: border-box; }
  `;
  root.appendChild(baseStyle);

  lpShadowHost = host;
  lpShadowRoot = root;
  return root;
}

function lpAppend(node: Node): void {
  const root = getLpShadowRoot();
  if (node instanceof HTMLElement && !node.style.pointerEvents) {
    node.style.pointerEvents = "auto";
  }
  root.appendChild(node);
  bringLpShadowHostToFront();
}

function lpAppendStyle(style: HTMLStyleElement): void {
  const root = getLpShadowRoot();
  if (style.id && root.getElementById(style.id)) return;
  root.appendChild(style);
}

function lpGetElementById(id: string): HTMLElement | null {
  return lpShadowRoot?.getElementById(id) ?? null;
}

function lpEscapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function showItemAvatarFallback(img: HTMLImageElement): void {
  img.style.display = "none";
  const fallback = img.nextElementSibling as HTMLElement | null;
  if (fallback) fallback.style.display = "flex";
}

function bindItemAvatarFallbacks(root: ParentNode): void {
  root.querySelectorAll<HTMLImageElement>("[data-lp-favicon]").forEach((img) => {
    const validate = () => {
      if (img.naturalWidth > 0 && img.naturalHeight > 0 && (img.naturalWidth < 48 || img.naturalHeight < 48)) {
        showItemAvatarFallback(img);
      }
    };

    img.addEventListener("error", () => showItemAvatarFallback(img));
    img.addEventListener("load", validate);
    if (img.complete) validate();
  });
}

function itemAvatarHtml({
  title,
  favicon,
  size = 30,
  radius = 8,
  fontSize = 11,
}: {
  title: string;
  favicon?: string;
  size?: number;
  radius?: number;
  fontSize?: number;
}): string {
  const safeTitle = title.trim() || "Item";
  const abbr = lpEscapeHtml(initials(safeTitle));
  const avatar = pastelAvatar(safeTitle);
  const faviconSrc = favicon ? googleFaviconUrlForDisplay(favicon, 128) : "";
  const fallbackDisplay = faviconSrc ? "none" : "flex";
  const faviconHtml = faviconSrc
    ? `<img data-lp-favicon src="${lpEscapeHtml(faviconSrc)}" width="${size}" height="${size}" style="width:${size}px;height:${size}px;border-radius:${radius}px;display:block;object-fit:contain;background:#ffffff;padding:3px;box-shadow:inset 0 0 0 1px rgba(15,23,42,0.08);" />`
    : "";

  return `<div style="width:${size}px;height:${size}px;position:relative;flex-shrink:0;border-radius:${radius}px;overflow:hidden;background:${avatar.bg};box-shadow:0 1px 2px rgba(15,23,42,0.08), inset 0 0 0 1px rgba(15,23,42,0.06);">
    ${faviconHtml}
    <div data-lp-fallback style="display:${fallbackDisplay};position:absolute;inset:0;border-radius:${radius}px;background:${avatar.bg};color:${avatar.fg};font-size:${fontSize}px;font-weight:700;align-items:center;justify-content:center;letter-spacing:0;">${abbr}</div>
  </div>`;
}

function ensurePkAnimStyle(): void {
  if (lpGetElementById("lp-pk-anim")) return;
  const s = document.createElement("style");
  s.id = "lp-pk-anim";
  s.textContent = "@keyframes lp-slide-up{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}";
  lpAppendStyle(s);
}

async function copyTextToClipboard(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // Fall through to execCommand for pages/browsers where the Clipboard API is
    // unavailable to content scripts.
  }

  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "true");
  textarea.style.cssText = "position:fixed;top:0;left:0;width:1px;height:1px;padding:0;border:0;opacity:0;pointer-events:none;";

  const selection = document.getSelection();
  const ranges = selection
    ? Array.from({ length: selection.rangeCount }, (_, index) => selection.getRangeAt(index).cloneRange())
    : [];

  try {
    (document.body || document.documentElement).appendChild(textarea);
    textarea.focus();
    textarea.select();
    textarea.setSelectionRange(0, textarea.value.length);
    return document.execCommand("copy");
  } catch {
    return false;
  } finally {
    textarea.remove();
    if (selection && ranges.length > 0) {
      selection.removeAllRanges();
      ranges.forEach((range) => selection.addRange(range));
    }
  }
}

function normalizeAutofillDomain(domain: string): string {
  const trimmed = domain.trim().toLowerCase();
  if (!trimmed) return "";
  try {
    return new URL(trimmed.includes("://") ? trimmed : `https://${trimmed}`).hostname
      .replace(/^www\./, "");
  } catch {
    return trimmed.replace(/^www\./, "");
  }
}

function getCurrentAutofillDomain(): string {
  return normalizeAutofillDomain(window.location.hostname || window.location.href);
}

function disabledAutofillDomainsActive(
  domains: DisabledAutofillDomain[],
): DisabledAutofillDomain[] {
  const now = Date.now();
  return domains.filter((item) => {
    const domain = normalizeAutofillDomain(item.domain);
    return domain && (item.expiresAt === null || item.expiresAt > now);
  });
}

function isAutofillDisabledForCurrentDomain(): boolean {
  const current = getCurrentAutofillDomain();
  if (!current) return false;
  return disabledAutofillDomainsActive(disabledAutofillDomains).some((item) => {
    const domain = normalizeAutofillDomain(item.domain);
    return current === domain || current.endsWith(`.${domain}`);
  });
}

function applyDisabledAutofillDomains(domains: DisabledAutofillDomain[]): void {
  disabledAutofillDomains = disabledAutofillDomainsActive(domains);
  if (isAutofillDisabledForCurrentDomain()) {
    dismissLoginAutofillPrompt();
    hidePopup();
    fieldIcons.forEach((_, field) => hideIconForField(field));
  }
  reconcileAutofillFieldIcons();
}

function isVisible(el: HTMLElement): boolean {
  const rect = el.getBoundingClientRect();
  if (rect.width < 2 || rect.height < 2) return false;
  // Element must overlap with the visible viewport (allow 100px buffer for scroll)
  const vw = document.documentElement.clientWidth;
  const vh = document.documentElement.clientHeight;
  if (rect.bottom < -100 || rect.right < -100 || rect.top > vh + 100 || rect.left > vw + 100) return false;
  const style = window.getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return false;
  if (parseFloat(style.opacity) < 0.05) return false;
  // Check for clip/clip-path that collapses the element to nothing
  if (style.clip && style.clip !== "auto" && style.clip === "rect(0px, 0px, 0px, 0px)") return false;
  return true;
}

function isInsideLumenPassPromptModal(el: Element): boolean {
  return !!el.closest("[data-lp-prompt-modal='true']");
}

function isEditableInput(field: HTMLInputElement): boolean {
  return isVisible(field) && !field.disabled && !field.readOnly && field.type !== "hidden" && !isInsideLumenPassPromptModal(field);
}

function getVisibleInputs(root: ParentNode = document): HTMLInputElement[] {
  return Array.from(root.querySelectorAll<HTMLInputElement>("input")).filter(isEditableInput);
}

function isEditableFillField(field: FillableField): boolean {
  if (!isVisible(field) || field.disabled) return false;
  if (isInsideLumenPassPromptModal(field)) return false;
  if (field instanceof HTMLInputElement) {
    return !field.readOnly && field.type !== "hidden";
  }
  if (field instanceof HTMLTextAreaElement) {
    return !field.readOnly;
  }
  return true;
}

function getVisibleFillFields(root: ParentNode = document): FillableField[] {
  return Array.from(root.querySelectorAll<FillableField>("input, textarea, select")).filter(isEditableFillField);
}

function isPasswordField(field: HTMLInputElement): boolean {
  return field.type.toLowerCase() === "password";
}

function isTextualField(field: HTMLInputElement): boolean {
  return TEXTUAL_INPUT_TYPES.has((field.getAttribute("type") ?? "text").toLowerCase());
}

function getFieldDescriptor(field: FillableField): string {
  const fieldName = field.name ?? "";
  const strippedName = fieldName
    .replace(/^\d+[_-]*/, "")
    .replace(/^\d+/, "");
  const labels = "labels" in field && field.labels
    ? Array.from(field.labels).map((label) => label.textContent ?? "")
    : [];
  const explicitLabel = field.id
    ? Array.from(document.querySelectorAll<HTMLLabelElement>(`label[for="${CSS.escape(field.id)}"]`)).map((label) => label.textContent ?? "")
    : [];
  const wrappingLabel = field.closest("label")?.textContent ?? "";
  const nearbyLabels = getNearbyFieldLabels(field);

  return [
    fieldName,
    strippedName,
    strippedName.replace(/[_-]+/g, " "),
    field.id,
    "autocomplete" in field ? field.autocomplete : "",
    "placeholder" in field ? field.placeholder : "",
    field.getAttribute("aria-label"),
    field.getAttribute("title"),
    ...labels,
    ...explicitLabel,
    ...nearbyLabels,
    wrappingLabel,
  ]
    .filter(Boolean)
    .join(" ")
    .trim()
    .toLowerCase();
}

function normalizeValue(value: string): string {
  return value
    .toLowerCase()
    .replace(/[_./,-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeLookupKey(value: string): string {
  return normalizeValue(value).replace(/[^a-z0-9 ]+/g, "");
}

function getFieldAutocomplete(field: FillableField): string {
  return ("autocomplete" in field ? field.autocomplete : "").toLowerCase();
}

function isCredentialIdentifierField(field: HTMLInputElement): boolean {
  return isCredentialIdentifierPurpose(field.type, getFieldAutocomplete(field));
}

function isSingleCharacterCodeSegment(field: HTMLInputElement): boolean {
  if (field.maxLength !== 1) return false;

  const descriptor = getFieldDescriptor(field);
  const inputMode = (field.inputMode ?? "").toLowerCase();
  const pattern = field.getAttribute("pattern") ?? "";
  const hasCodeCopy = /\b(digit|code|verification|otp|totp|pin)\b/.test(descriptor);
  const hasNumericIntent = /numeric|decimal|tel/.test(inputMode) || /\\d|\[0-9\]/.test(pattern);
  if (!hasCodeCopy && !hasNumericIntent) return false;

  const peerSegments = getFieldScopeInputs(field).filter((candidate) => (
    candidate !== field
    && isTextualField(candidate)
    && !isPasswordField(candidate)
    && candidate.maxLength === 1
    && areFieldsVisuallyNear(field, candidate)
  ));

  return peerSegments.length >= 3;
}

function isOneTimeCodeField(field: FillableField): boolean {
  if (!(field instanceof HTMLInputElement)) return false;
  if (!isEditableInput(field) || isPasswordField(field)) return false;

  const autocomplete = getFieldAutocomplete(field);
  if (isOneTimeCodeAutocomplete(autocomplete)) return true;
  if (isCredentialIdentifierField(field)) return false;

  const descriptor = getFieldDescriptor(field);
  if (isOneTimeCodeDescriptor(descriptor)) return true;

  return isSingleCharacterCodeSegment(field);
}

function getLabelCandidateText(element: Element | null | undefined): string {
  if (!element) return "";
  if (element.matches("input, textarea, select, button")) return "";
  if (element.querySelector("input, textarea, select, button")) return "";

  const text = (element.textContent ?? "").replace(/\s+/g, " ").trim();
  if (!text || text.length > 80) return "";
  return text;
}

function getNearbyFieldLabels(field: FillableField): string[] {
  const parent = field.parentElement;
  const row = parent?.closest("[role='row'], tr, .row");
  const rowChildren = row ? Array.from(row.children) : [];
  const parentIndex = parent ? rowChildren.findIndex((child) => child === parent || child.contains(field)) : -1;

  const candidates = [
    field.previousElementSibling,
    parent?.previousElementSibling,
    parentIndex > 0 ? rowChildren[parentIndex - 1] : null,
  ];

  return Array.from(new Set(candidates.map(getLabelCandidateText).filter(Boolean)));
}

function areFieldsVisuallyNear(a: FillableField, b: FillableField): boolean {
  const aRect = a.getBoundingClientRect();
  const bRect = b.getBoundingClientRect();
  const aCenterX = aRect.left + aRect.width / 2;
  const bCenterX = bRect.left + bRect.width / 2;
  const aCenterY = aRect.top + aRect.height / 2;
  const bCenterY = bRect.top + bRect.height / 2;

  return Math.abs(aCenterX - bCenterX) <= 280 && Math.abs(aCenterY - bCenterY) <= 180;
}

function areFieldsInLoginCluster(a: FillableField, b: FillableField): boolean {
  const aRect = a.getBoundingClientRect();
  const bRect = b.getBoundingClientRect();
  const aCenterX = aRect.left + aRect.width / 2;
  const bCenterX = bRect.left + bRect.width / 2;
  const aCenterY = aRect.top + aRect.height / 2;
  const bCenterY = bRect.top + bRect.height / 2;

  return Math.abs(aCenterX - bCenterX) <= 320 && Math.abs(aCenterY - bCenterY) <= 100;
}

// ─── Card / Identity field detection ─────────────────────────────────────────

function isCardField(field: FillableField): boolean {
  if (!isEditableFillField(field)) return false;
  if (field instanceof HTMLInputElement && isPasswordField(field)) return false;
  if (isOneTimeCodeField(field)) return false;
  const autocomplete = getFieldAutocomplete(field);
  if (ALL_CARD_AUTOCOMPLETE.has(autocomplete)) return true;
  const d = getFieldDescriptor(field);
  return CARD_FIELD_DESCRIPTOR_PATTERN.test(d);
}

function isCardNumberField(field: FillableField): boolean {
  if (!isEditableFillField(field)) return false;
  if (field instanceof HTMLInputElement && isPasswordField(field)) return false;
  if (isOneTimeCodeField(field)) return false;
  const autocomplete = getFieldAutocomplete(field);
  if (CARD_NUMBER_AUTOCOMPLETE.has(autocomplete)) return true;
  const d = getFieldDescriptor(field);
  return CARD_NUMBER_DESCRIPTOR_PATTERN.test(d);
}

function getFillableFieldValue(field: FillableField): string {
  if (field instanceof HTMLSelectElement) {
    const selectedText = field.selectedOptions[0]?.textContent?.trim() ?? "";
    return selectedText || field.value.trim();
  }
  return field.value.trim();
}

function getCardDigits(value: string): string {
  return value.replace(/\D+/g, "");
}

function getCardScopeFields(anchor: FillableField): FillableField[] {
  return getFieldScopeFillFields(anchor).filter(isCardField);
}

function findScopeFieldValue(
  scopeFields: FillableField[],
  options: { autocompletes?: string[]; matcher?: RegExp },
): string {
  const autocompletes = new Set(options.autocompletes ?? []);

  if (autocompletes.size > 0) {
    for (const field of scopeFields) {
      if (!autocompletes.has(getFieldAutocomplete(field))) continue;
      const value = getFillableFieldValue(field);
      if (value) return value;
    }
  }

  if (options.matcher) {
    for (const field of scopeFields) {
      if (!options.matcher.test(getFieldDescriptor(field))) continue;
      const value = getFillableFieldValue(field);
      if (value) return value;
    }
  }

  return "";
}

function getEnteredCardNumberForField(anchor: FillableField): string {
  const scopeFields = getCardScopeFields(anchor);
  const cardNumber = findScopeFieldValue(scopeFields, {
    autocompletes: ["cc-number"],
    matcher: CARD_NUMBER_DESCRIPTOR_PATTERN,
  });
  return getCardDigits(cardNumber);
}

function hasAutofilledCardNumberForField(anchor: FillableField): boolean {
  return getCardScopeFields(anchor).some((field) => (
    autofilledFields.has(field) && getCardDigits(getFillableFieldValue(field)).length > 0
  ));
}

function shouldSuppressCardAutofillPopup(anchor: FillableField): boolean {
  if (detectFieldKind(anchor) !== "card") return false;

  if (hasAutofilledCardNumberForField(anchor)) return true;

  // Keep suggestions available while the user is still starting to type.
  // Once the page already holds a near-complete card number, suppress the popup.
  return getEnteredCardNumberForField(anchor).length >= 12;
}

function isIdentityField(field: FillableField): boolean {
  if (!isEditableFillField(field)) return false;
  if (field instanceof HTMLInputElement && isPasswordField(field)) return false;
  if (isOneTimeCodeField(field)) return false;
  const autocomplete = getFieldAutocomplete(field);
  if (IDENTITY_AUTOCOMPLETE_VALUES.has(autocomplete)) return true;
  const d = getFieldDescriptor(field);
  return /full.?name|first.?name|frst.?name|middle.?name|middle.?initial|last.?name|given.?name|family.?name|surname|^name$|e.?mail|email.?adr|^address|addr?ess|street|adr.?city|^city$|^town$|postal.?code|zip|^postcode$|adr.?state|^state$|province|^country$|home.?phone|work.?phone|cell.?phone|telephone|^phone$|^tel$|^mobile$|web.?site|^company$|^organization$/.test(d);
}

function hasCreditCardSurface(): boolean {
  return getVisibleFillFields().some(isCardNumberField);
}

function hasIdentitySurface(): boolean {
  return getVisibleFillFields().filter(isIdentityField).length >= 2;
}

function hasIdentitySurfaceForField(field: FillableField): boolean {
  if (!isIdentityField(field)) return false;
  return getFieldScopeFillFields(field).filter(isIdentityField).length >= 2;
}

function isCurrentPasswordField(field: HTMLInputElement): boolean {
  if (!isPasswordField(field)) return false;
  const autocomplete = (field.autocomplete ?? "").toLowerCase();
  if (autocomplete === "current-password") return true;
  return /current.?pass|old.?pass|existing.?pass/.test(getFieldDescriptor(field));
}

function isRegistrationSurface(): boolean {
  const passwordFields = getPasswordFields();
  if (passwordFields.length === 0) return false;

  const hasCurrentPassword = passwordFields.some(isCurrentPasswordField);
  if (hasCurrentPassword) return false;

  const hasConfirmPassword = passwordFields.some((field) => (
    /confirm.?pass|repeat.?pass|retype.?pass|verify.?pass/.test(getFieldDescriptor(field))
  ));
  if (hasConfirmPassword) return true;
  if (passwordFields.length >= 2) return true;

  const pathTitle = `${window.location.pathname} ${document.title}`.toLowerCase();
  if (/(sign.?up|register|registration|create.?account|join|signup)/.test(pathTitle)) return true;

  const pageText = (document.body?.innerText ?? "").toLowerCase().slice(0, 2000);
  return /(sign.?up|create.?account|register|registration|join now|get started)/.test(pageText)
    && /confirm.?pass|repeat.?pass|retype.?pass|verify.?pass/.test(pageText);
}

function isRegistrationPasswordField(field: HTMLInputElement): boolean {
  if (!isPasswordField(field)) return false;
  if (isCurrentPasswordField(field)) return false;
  const autocomplete = (field.autocomplete ?? "").toLowerCase();
  if (autocomplete === "new-password") return true;
  const descriptor = getFieldDescriptor(field);
  if (/confirm.?pass|repeat.?pass|retype.?pass|verify.?pass/.test(descriptor)) return true;
  if (/new.?pass|create.?pass|choose.?pass|set.?pass/.test(descriptor)) return true;
  return isRegistrationSurface();
}

function getLoginPasswordFields(): HTMLInputElement[] {
  return getPasswordFields().filter((field) => !isRegistrationPasswordField(field));
}

function isCredentialHintField(field: FillableField): field is HTMLInputElement {
  return field instanceof HTMLInputElement
    && isRegistrationSurface()
    && isLikelyUsernameField(field);
}

function getCredentialHintFields(): HTMLInputElement[] {
  return getVisibleInputs().filter(isCredentialHintField);
}

function detectFieldKind(field: FillableField): FieldKind {
  if (isCardField(field)) return "card";
  if (isCredentialHintField(field)) return "identifier";
  if (hasIdentitySurfaceForField(field)) return "identity";
  // Username/email/phone fields on login surfaces take priority over identity matching
  if (field instanceof HTMLInputElement && isLikelyUsernameField(field)) return "login";
  if (isIdentityField(field)) return "identity";
  return "login";
}

function getEntrySearchType(kind: FieldKind = activeFieldKind): EntrySearchType {
  if (kind === "card") return "credit-card";
  if (kind === "identifier") return "login";
  return kind;
}

function entryMatchesFieldKind(entry: EntryItem, kind: FieldKind = activeFieldKind): boolean {
  if (kind === "card") return entry.kind === "credit-card";
  if (kind === "identity") return entry.kind === "identity";
  if (kind === "identifier") {
    const hintKind = activeAutofillField instanceof HTMLInputElement
      ? getCredentialHintKind(activeAutofillField)
      : "any";
    return entry.kind !== "credit-card"
      && entry.kind !== "identity"
      && entry.kind !== "passkey"
      && matchesCredentialHintKind(entry, hintKind);
  }
  return entry.kind !== "credit-card" && entry.kind !== "identity";
}

function getSpecialPurposeTitle(kind: FieldKind = activeFieldKind): string {
  if (kind === "card") return "Credit Cards";
  if (kind === "identity") return "Identities";
  if (kind === "identifier") return "Pick suggestion";
  return "";
}

function getPurposeSearchLabel(kind: FieldKind = activeFieldKind): string {
  if (kind === "card") return "credit cards";
  if (kind === "identity") return "identities";
  if (kind === "identifier") return "usernames and emails";
  return "items";
}

function getCredentialHintKind(field: HTMLInputElement): CredentialIdentifierKind {
  return getCredentialIdentifierKind(
    field.type,
    getFieldAutocomplete(field),
    getFieldDescriptor(field),
  );
}

function isEmailLikeIdentifier(value: string): boolean {
  return EMAIL_LIKE_IDENTIFIER_RE.test(value.trim());
}

function matchesCredentialHintKind(
  entry: EntryItem,
  kind: CredentialIdentifierKind,
): boolean {
  const username = entry.username.trim();
  if (!username) return false;
  if (kind === "email") return isEmailLikeIdentifier(username);
  if (kind === "username") return !isEmailLikeIdentifier(username);
  return true;
}

function isLikelyUsernameField(field: HTMLInputElement): boolean {
  if (!isEditableInput(field) || isPasswordField(field) || !isTextualField(field)) return false;
  if (isOneTimeCodeField(field)) return false;

  const descriptor = getFieldDescriptor(field);
  if (/search/.test(descriptor)) return false;
  if (field.type.toLowerCase() === "email") return true;

  return /(user(name)?|email|e-mail|login|sign[\s_-]?in|identifier|account|member|phone|mobile)/.test(descriptor);
}

function getPasswordFields(): HTMLInputElement[] {
  return getVisibleInputs().filter(isPasswordField);
}

function dedupeFields<T>(fields: Array<T | null | undefined>): T[] {
  const seen = new Set<T>();
  return fields.filter((field): field is T => {
    if (!field || seen.has(field)) return false;
    seen.add(field);
    return true;
  });
}

function getFieldScopeInputs(anchor: HTMLInputElement): HTMLInputElement[] {
  const form = anchor.form ?? anchor.closest("form");
  if (form) return getVisibleInputs(form);

  const rect = anchor.getBoundingClientRect();
  const anchorCenterX = rect.left + rect.width / 2;
  const nearby = getVisibleInputs().filter((field) => {
    const fieldRect = field.getBoundingClientRect();
    const fieldCenterX = fieldRect.left + fieldRect.width / 2;
    return (
      Math.abs(fieldRect.top - rect.top) <= 260
      && Math.abs(fieldCenterX - anchorCenterX) <= 420
    );
  });

  return nearby.length > 0 ? nearby : getVisibleInputs();
}

function getFieldScopeFillFields(anchor: FillableField): FillableField[] {
  const form = anchor.closest("form");
  if (form) return getVisibleFillFields(form);

  const rect = anchor.getBoundingClientRect();
  const anchorCenterX = rect.left + rect.width / 2;
  const nearby = getVisibleFillFields().filter((field) => {
    const fieldRect = field.getBoundingClientRect();
    const fieldCenterX = fieldRect.left + fieldRect.width / 2;
    return (
      Math.abs(fieldRect.top - rect.top) <= 260
      && Math.abs(fieldCenterX - anchorCenterX) <= 420
    );
  });

  return nearby.length > 0 ? nearby : getVisibleFillFields();
}

function findFallbackUsernameField(passwordField: HTMLInputElement): HTMLInputElement | null {
  const scopeInputs = getFieldScopeInputs(passwordField);
  const passwordIndex = scopeInputs.indexOf(passwordField);
  if (passwordIndex === -1) return null;

  return scopeInputs
    .slice(0, passwordIndex)
    .reverse()
    .find((field) => isTextualField(field) && !isOneTimeCodeField(field) && !/search/.test(getFieldDescriptor(field)))
    ?? null;
}

function getAutofillFields(): HTMLInputElement[] {
  const passwordFields = getLoginPasswordFields();
  const usernameFields = passwordFields.length > 0
    ? getVisibleInputs().filter((field) => (
      isLikelyUsernameField(field)
      && passwordFields.some((passwordField) => areFieldsInLoginCluster(field, passwordField))
    ))
    : (isLikelyLoginSurface() ? getVisibleInputs().filter(isLikelyUsernameField) : []);
  const fallbackUsernameFields = passwordFields.map(findFallbackUsernameField);
  return dedupeFields([...usernameFields, ...fallbackUsernameFields, ...passwordFields]);
}

function getAutofillFieldGroups(): HTMLInputElement[][] {
  const pending = [...getAutofillFields()];
  const groups: HTMLInputElement[][] = [];

  while (pending.length > 0) {
    const seed = pending.shift();
    if (!seed) break;

    const group = new Set<HTMLInputElement>([seed]);
    let expanded = true;

    while (expanded) {
      expanded = false;

      for (let index = pending.length - 1; index >= 0; index -= 1) {
        const candidate = pending[index];
        const related = Array.from(group).some((field) => {
          const fieldScope = getFieldScopeInputs(field);
          const candidateScope = getFieldScopeInputs(candidate);
          return fieldScope.includes(candidate) || candidateScope.includes(field);
        });

        if (!related) continue;

        group.add(candidate);
        pending.splice(index, 1);
        expanded = true;
      }
    }

    groups.push([...group]);
  }

  return groups;
}

function getAutofillIconFields(): FillableField[] {
  if (isAutofillDisabledForCurrentDomain()) return [];
  const loginFields = dedupeFields(getAutofillFieldGroups().flatMap((group) => group))
    .filter((field) => !hasIdentitySurfaceForField(field));
  const identifierFields = getCredentialHintFields();

  const cardFields = getVisibleFillFields().filter(isCardField);
  const identityFields = getVisibleFillFields().filter((field) => {
    if (!hasIdentitySurfaceForField(field)) return false;
    if (field instanceof HTMLInputElement && isLikelyUsernameField(field)) {
      return !loginFields.some((loginField) => areFieldsVisuallyNear(field, loginField));
    }
    return true;
  });
  return dedupeFields([...loginFields, ...identifierFields, ...cardFields, ...identityFields]);
}

function getPrimaryAutofillField(): FillableField | null {
  return getAutofillIconFields()[0] ?? getAutofillFields()[0] ?? null;
}

function getPreferredUsernameField(anchor: HTMLInputElement): HTMLInputElement | null {
  if (isLikelyUsernameField(anchor)) return anchor;

  const scopeInputs = getFieldScopeInputs(anchor);
  const explicitCandidates = scopeInputs.filter((field) => field !== anchor && isLikelyUsernameField(field));
  const fallbackCandidates = scopeInputs.filter((field) => (
    field !== anchor
    && isTextualField(field)
    && !isOneTimeCodeField(field)
    && !/search/.test(getFieldDescriptor(field))
  ));
  const candidates = explicitCandidates.length > 0 ? explicitCandidates : fallbackCandidates;
  if (candidates.length === 0) return null;

  const anchorIndex = scopeInputs.indexOf(anchor);
  if (anchorIndex !== -1) {
    const beforeAnchor = candidates.filter((field) => scopeInputs.indexOf(field) < anchorIndex);
    if (beforeAnchor.length > 0) return beforeAnchor[beforeAnchor.length - 1];
  }

  return candidates[0] ?? null;
}

function getPreferredPasswordField(anchor: HTMLInputElement): HTMLInputElement | null {
  if (isPasswordField(anchor)) return anchor;

  const scopeInputs = getFieldScopeInputs(anchor);
  const passwordFields = scopeInputs.filter(isPasswordField);
  if (passwordFields.length === 0) return null;

  const anchorIndex = scopeInputs.indexOf(anchor);
  if (anchorIndex !== -1) {
    const nextPassword = passwordFields.find((field) => scopeInputs.indexOf(field) > anchorIndex);
    if (nextPassword) return nextPassword;
  }

  return passwordFields[0] ?? null;
}

function getCurrentAutofillAnchor(): HTMLInputElement | null {
  if (
    activeAutofillField instanceof HTMLInputElement
    && activeAutofillField.isConnected
    && isEditableInput(activeAutofillField)
  ) {
    return activeAutofillField;
  }

  const activeElement = document.activeElement;
  if (
    activeElement instanceof HTMLInputElement
    && activeElement.isConnected
    && isEditableInput(activeElement)
  ) {
    return activeElement;
  }

  const primaryField = getPrimaryAutofillField();
  if (
    primaryField instanceof HTMLInputElement
    && primaryField.isConnected
    && isEditableInput(primaryField)
  ) {
    return primaryField;
  }

  return getAutofillFields()[0] ?? null;
}

function getActionableAuthElements(): HTMLElement[] {
  const selectors = [
    "button",
    "a[role='button']",
    "input[type='submit']",
    "input[type='button']",
    "[role='button']",
  ].join(",");

  return Array.from(document.querySelectorAll<HTMLElement>(selectors)).filter((el) => {
    if (!isVisible(el)) return false;
    const text = [
      el.innerText,
      el.textContent,
      el.getAttribute("aria-label"),
      el.getAttribute("title"),
      el instanceof HTMLInputElement ? el.value : "",
    ]
      .filter(Boolean)
      .join(" ")
      .trim()
      .toLowerCase();

    return /(sign in|sign-in|log in|log-in|login|continue with passkey|sign in with passkey|log in with passkey|use passkey|use a passkey|submit|continue|next|access|enter|proceed|authenticate|verify|confirm)/.test(text);
  });
}

function getPasskeyActionElements(): HTMLElement[] {
  return getActionableAuthElements().filter((el) => {
    const text = [
      el.innerText,
      el.textContent,
      el.getAttribute("aria-label"),
      el.getAttribute("title"),
      el instanceof HTMLInputElement ? el.value : "",
    ]
      .filter(Boolean)
      .join(" ")
      .trim()
      .toLowerCase();

    return /(passkey|security key|webauthn)/.test(text);
  });
}

/**
 * Build the {@link LoginSurfaceSignals} payload from the current DOM.
 *
 * The actual decision logic lives in `./login-surface.ts` so that it can be
 * unit-tested without a browser. Keeping this collector tiny also makes the
 * cost of running the heuristic on every navigation negligible.
 */
function collectLoginSurfaceSignals(): LoginSurfaceSignals {
  const passwordFields = getLoginPasswordFields();
  const usernameFields = passwordFields.length > 0
    ? getVisibleInputs().filter((field) => (
      isLikelyUsernameField(field)
      && passwordFields.some((passwordField) => areFieldsInLoginCluster(field, passwordField))
    ))
    : getVisibleInputs().filter(isLikelyUsernameField);
  const pageText = document.body?.innerText?.toLowerCase() ?? "";

  return {
    pathname: window.location.pathname.toLowerCase(),
    hostname: window.location.hostname.toLowerCase(),
    pageTitle: document.title.toLowerCase(),
    passwordFieldCount: passwordFields.length,
    usernameFieldCount: usernameFields.length,
    otpFieldCount: getVisibleInputs().filter(isOneTimeCodeField).length,
    hasLoginActionButton: getActionableAuthElements().length > 0,
    hasPasskeyActionButton: getPasskeyActionElements().length > 0,
    pageTextSample: pageText.slice(0, 3000),
    detectedLoggedInEmail: detectLoggedInEmail(),
    isRegistrationSurface: isRegistrationSurface(),
    isPasskeyManagementPage: false,
  };
}

function isLikelyLoginSurface(): boolean {
  return isLikelyLoginSurfaceFromSignals(collectLoginSurfaceSignals());
}

/**
 * Returns the structured decision (with `reason`) so callers can log why a
 * passkey/login prompt was suppressed. This is invaluable when triaging
 * reports of prompts appearing on authenticated pages.
 */
function describeLoginSurface() {
  return decideLoginSurface(collectLoginSurfaceSignals());
}

// ─── Social login detection ─────────────────────────────────────────────────────

type SocialProvider = "google" | "apple" | "facebook" | "github" | "microsoft" | "twitter" | "linkedin" | "other";

interface SocialProviderDef {
  id: SocialProvider;
  label: string;
  /** regex against lower-cased button text / aria-label */
  pattern: RegExp;
  /** SVG path data to render a small logo */
  svg: string;
  /** brand hex for the button accent */
  color: string;
}

const SOCIAL_PROVIDERS: SocialProviderDef[] = [
  {
    id: "google",
    label: "Google",
    pattern: /google/,
    color: "#DB4437",
    svg: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.18 1.48-4.97 2.31-8.16 2.31-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>`,
  },
  {
    id: "apple",
    label: "Apple",
    pattern: /apple/,
    color: "#000000",
    svg: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 814 1000"><path fill="currentColor" d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76 0-103.7 40.8-165.9 40.8s-105-42.4-148.6-105.1c-50.2-73.5-91.9-198.3-91.9-311.6 0-183.4 119.1-280.4 236.4-280.4 66.7 0 122.1 43.8 162.4 43.8 38.4 0 101-46.4 174.1-46.4zm-234-180.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z"/></svg>`,
  },
  {
    id: "facebook",
    label: "Facebook",
    pattern: /facebook|continue with fb/,
    color: "#1877F2",
    svg: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"><path fill="#1877F2" d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/></svg>`,
  },
  {
    id: "github",
    label: "GitHub",
    pattern: /github/,
    color: "#24292e",
    svg: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"><path fill="currentColor" d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/></svg>`,
  },
  {
    id: "microsoft",
    label: "Microsoft",
    pattern: /microsoft/,
    color: "#2F2F2F",
    svg: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 21 21"><rect x="1" y="1" width="9" height="9" fill="#F25022"/><rect x="11" y="1" width="9" height="9" fill="#7FBA00"/><rect x="1" y="11" width="9" height="9" fill="#00A4EF"/><rect x="11" y="11" width="9" height="9" fill="#FFB900"/></svg>`,
  },
  {
    id: "twitter",
    label: "X / Twitter",
    pattern: /twitter|\bx\.com\b|sign in with x\b/,
    color: "#000000",
    svg: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"><path fill="currentColor" d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.389 6.231H2.756l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>`,
  },
  {
    id: "linkedin",
    label: "LinkedIn",
    pattern: /linkedin/,
    color: "#0A66C2",
    svg: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24"><path fill="#0A66C2" d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 0 1-2.063-2.065 2.064 2.064 0 1 1 2.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z"/></svg>`,
  },
];

function detectSocialProvider(el: HTMLElement): SocialProviderDef | null {
  const text = [
    el.innerText,
    el.textContent,
    el.getAttribute("aria-label"),
    el.getAttribute("title"),
    el.getAttribute("data-provider"),
    el.className,
  ].filter(Boolean).join(" ").toLowerCase();

  for (const provider of SOCIAL_PROVIDERS) {
    if (provider.pattern.test(text)) return provider;
  }
  return null;
}

function isSocialLoginButton(el: HTMLElement): boolean {
  if (!isVisible(el)) return false;
  // Must be a button-like element
  const tag = el.tagName.toLowerCase();
  const role = (el.getAttribute("role") ?? "").toLowerCase();
  if (tag !== "button" && tag !== "a" && role !== "button") return false;
  return detectSocialProvider(el) !== null;
}

function getSocialLoginButtons(): Array<{ el: HTMLElement; provider: SocialProviderDef }> {
  const selectors = ["button", "a[role='button']", "[role='button']", "a"].join(",");
  const results: Array<{ el: HTMLElement; provider: SocialProviderDef }> = [];
  document.querySelectorAll<HTMLElement>(selectors).forEach((el) => {
    if (!isVisible(el)) return;
    const provider = detectSocialProvider(el);
    if (provider) results.push({ el, provider });
  });
  return results;
}

/** Attempt to pull a visible email address off the post-login page. */
function detectLoggedInEmail(): string {
  // Look for email-like text in common logged-in UI areas
  const candidates: string[] = [];
  const emailRe = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/;

  const attrSelectors = [
    "[data-email]", "[data-user-email]", "[data-hint_email]",
    ".user-email", ".account-email", ".member-email",
    "[data-testid*='email']", "[data-testid*='user']",
    "[aria-label*='email']", "[aria-label*='account']",
    "[title*='@']", "[alt*='@']",
  ];
  for (const sel of attrSelectors) {
    document.querySelectorAll<HTMLElement>(sel).forEach((el) => {
      const val = el.getAttribute("data-email") || el.getAttribute("data-user-email")
        || el.getAttribute("data-hint_email") || el.getAttribute("title")
        || el.getAttribute("alt") || el.getAttribute("aria-label") || el.textContent || "";
      const match = val.match(emailRe);
      if (match) candidates.push(match[0]);
    });
  }

  // Check <meta> tags (some apps expose user email in meta)
  document.querySelectorAll<HTMLMetaElement>("meta").forEach((m) => {
    const content = m.getAttribute("content") ?? "";
    const match = content.match(emailRe);
    if (match) candidates.push(match[0]);
  });

  // Also scan visible text nodes for an email pattern
  if (candidates.length === 0) {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let node: Text | null;
    let scanned = 0;
    while ((node = walker.nextNode() as Text | null) && scanned < 500) {
      scanned++;
      const match = (node.textContent ?? "").match(emailRe);
      if (match) { candidates.push(match[0]); break; }
    }
  }

  return candidates[0] ?? "";
}

function normalizeSearchQuery(value: string): string {
  return value.trim().toLowerCase();
}

function matchesSearchQuery(query: string, ...values: Array<string | null | undefined>): boolean {
  const normalized = normalizeSearchQuery(query);
  if (!normalized) return true;
  return values.some((value) => (value ?? "").toLowerCase().includes(normalized));
}

function filterEntryItems(items: EntryItem[], query: string): EntryItem[] {
  return items.filter((entry) => matchesSearchQuery(query, entry.title, entry.username, entry.url));
}

function filterPasskeyEntries<T extends { title: string; username: string; rpId: string }>(
  items: T[],
  query: string,
): T[] {
  return items.filter((entry) => matchesSearchQuery(query, entry.title, entry.username, entry.rpId));
}

function ensureOverlayStyles(): void {
  if (lpGetElementById("lp-overlay-styles")) return;

  const style = document.createElement("style");
  style.id = "lp-overlay-styles";
  style.textContent = `
    @keyframes lp-slide-up {
      from { opacity: 0; transform: translateY(8px); }
      to { opacity: 1; transform: translateY(0); }
    }

    @keyframes lp-spin {
      from { transform: rotate(0deg); }
      to { transform: rotate(360deg); }
    }

    .lp-scroll {
      overflow-y: auto;
      scrollbar-width: thin;
      scrollbar-color: rgba(148, 163, 184, 0.8) transparent;
    }

    .lp-scroll::-webkit-scrollbar {
      width: 8px;
    }

    .lp-scroll::-webkit-scrollbar-track {
      background: transparent;
    }

    .lp-scroll::-webkit-scrollbar-thumb {
      background: rgba(148, 163, 184, 0.8);
      border-radius: 999px;
    }

    .lp-scroll::-webkit-scrollbar-thumb:hover {
      background: rgba(100, 116, 139, 0.95);
    }
  `;
  lpAppendStyle(style);
}

// ─── Vault-locked tooltip + popup ─────────────────────────────────────────────

function showVaultLockedTooltip(anchorEl: HTMLDivElement): void {
  if (!tooltipEl) {
    tooltipEl = document.createElement("div");
    tooltipEl.style.cssText = `
      position: fixed;
      z-index: 2147483647;
      background: #1f2937;
      color: #fff;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      font-size: 12px;
      font-weight: 500;
      padding: 5px 10px;
      border-radius: 6px;
      white-space: nowrap;
      pointer-events: none;
      box-shadow: 0 2px 8px rgba(0,0,0,0.3);
    `;
    tooltipEl.textContent = "Unlock LumenPass";
    lpAppend(tooltipEl);
  }
  tooltipEl.style.display = "block";
  const rect = anchorEl.getBoundingClientRect();
  const tw = tooltipEl.getBoundingClientRect().width || 120;
  tooltipEl.style.left = `${Math.max(4, rect.left + rect.width / 2 - tw / 2)}px`;
  tooltipEl.style.top = `${Math.max(4, rect.top - 34)}px`;
}

function hideVaultLockedTooltip(): void {
  if (tooltipEl) tooltipEl.style.display = "none";
}

function renderLockedPopup(): void {
  if (!popupEl) return;
  // Start (or refresh) the active poll so the locked UI flips to the entry
  // list as soon as the desktop is unlocked, instead of waiting up to 30s+
  // for the next chrome.alarms tick.
  ensureVaultStatusFresh();
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const t = isDark ? "#f3f4f6" : "#111827";
  const sub = isDark ? "#9ca3af" : "#6b7280";
  const bg = isDark ? "#1f2937" : "#ffffff";
  const label = desktopConnected ? "Vault Locked" : "Desktop Not Running";

  popupEl.style.background = bg;
  popupEl.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;padding:10px 12px;">
      <div style="width:28px;height:28px;border-radius:8px;background:linear-gradient(135deg,#6370f5 0%,#3d4cdc 100%);display:flex;align-items:center;justify-content:center;flex-shrink:0;box-shadow:0 2px 8px rgba(68,76,231,0.3);">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
          <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
        </svg>
      </div>
      <span style="flex:1;font-size:12px;font-weight:600;color:${t};white-space:nowrap;">${label}</span>
      <button id="lp-open-app-btn" type="button"
        style="padding:5px 11px;background:#444ce7;color:#fff;border:none;border-radius:6px;font-size:12px;font-weight:500;cursor:pointer;white-space:nowrap;font-family:inherit;"
      >Unlock</button>
      <button id="lp-inline-close" type="button" aria-label="Close"
        style="width:22px;height:22px;flex-shrink:0;background:none;border:none;cursor:pointer;color:${sub};font-size:16px;line-height:1;display:flex;align-items:center;justify-content:center;border-radius:4px;padding:0;"
      >&times;</button>
    </div>
  `;

  popupEl.querySelector<HTMLButtonElement>("#lp-inline-close")?.addEventListener("click", (e) => {
    e.stopPropagation();
    hidePopup(true);
  });
  popupEl.querySelector<HTMLButtonElement>("#lp-open-app-btn")?.addEventListener("click", (e) => {
    e.stopPropagation();
    void browser.runtime.sendMessage({ type: "FOCUS_DESKTOP" });
    hidePopup();
  });
}

// ─── Icon rendering ───────────────────────────────────────────────────────────

type FieldIconAction = "autofill" | "identifier" | "save-card";

function getFieldIconAction(field: FillableField): FieldIconAction {
  const kind = detectFieldKind(field);
  if (kind === "identifier") return "identifier";
  if (kind === "card" && shouldSuppressCardAutofillPopup(field)) return "save-card";
  return "autofill";
}

function refreshIconForField(field: FillableField, iconOverride?: HTMLDivElement): void {
  const icon = iconOverride ?? fieldIcons.get(field);
  if (!icon) return;

  const action = getFieldIconAction(field);
  if (action === "identifier") {
    icon.setAttribute("aria-label", "LumenPass username/email suggestions");
    icon.title = "Username and email suggestions";
    icon.style.background = "#444ce7";
    icon.style.boxShadow = "0 2px 8px rgba(68,76,231,0.4)";
    icon.innerHTML = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21a8 8 0 0 0-16 0"/><circle cx="12" cy="7" r="4"/></svg>`;
    return;
  }

  if (action === "save-card") {
    icon.setAttribute("aria-label", "Save card to LumenPass");
    icon.title = "Save card to LumenPass";
    icon.style.background = "#0f766e";
    icon.style.boxShadow = "0 2px 8px rgba(15,118,110,0.35)";
    icon.innerHTML = `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M2.5 10h19"/><path d="M12 14v5"/><path d="M9.5 16.5H14.5"/></svg>`;
    return;
  }

  icon.setAttribute("aria-label", "LumenPass autofill");
  icon.title = "Autofill from LumenPass";
  icon.style.background = "#444ce7";
  icon.style.boxShadow = "0 2px 8px rgba(68,76,231,0.4)";
  icon.innerHTML = `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`;
}

function createIconForField(field: FillableField): HTMLDivElement {
  const div = document.createElement("div");
  div.setAttribute("role", "button");
  div.style.cssText = `
    position: fixed;
    z-index: 2147483647;
    width: ${ICON_SIZE}px;
    height: ${ICON_SIZE}px;
    border-radius: 5px;
    background: #444ce7;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    box-shadow: 0 2px 8px rgba(68,76,231,0.4);
    transition: transform 0.1s, opacity 0.15s;
    pointer-events: none;
    opacity: 0;
  `;
  refreshIconForField(field, div);

  div.addEventListener("mouseenter", () => {
    div.style.transform = "scale(1.1)";
    div.style.opacity = "1";
    if (!desktopConnected || !desktopVaultOpen) showVaultLockedTooltip(div);
  });
  div.addEventListener("mouseleave", () => {
    div.style.transform = "scale(1)";
    // Restore to the focused-visible opacity, not 0 (blur handler will hide it if needed)
    div.style.opacity = "0.85";
    hideVaultLockedTooltip();
  });
  div.addEventListener("mousedown", (e) => {
    e.stopPropagation();
    e.preventDefault();
    const popupVisible = popupEl?.style.display === "block" && activeAutofillField === field;
    if (popupVisible) {
      hidePopup();
      return;
    }

    const action = getFieldIconAction(field);
    dismissedFields.delete(field);
    autofilledFields.delete(field);
    field.focus({ preventScroll: true });
    if (action === "save-card") {
      if (desktopConnected && desktopVaultOpen) {
        void openCreditCardSavePrompt(field);
      } else {
        activeAutofillField = field;
        activeFieldKind = detectFieldKind(field);
        showPopup(field);
      }
      return;
    }
    void openSuggestionsForField(field, true, detectFieldKind(field) === "identifier");
  });

  positionIconEl(field, div);
  return div;
}

function positionIconEl(field: FillableField, icon: HTMLDivElement): void {
  const rect = field.getBoundingClientRect();

  if (rect.width === 0 && rect.height === 0) {
    requestAnimationFrame(() => positionIconEl(field, icon));
    return;
  }

  icon.style.top = `${rect.top + (rect.height - ICON_SIZE) / 2}px`;
  icon.style.left = `${rect.right - ICON_SIZE - 6}px`;
  const inView = rect.bottom > 0 && rect.top < window.innerHeight;
  if (!inView) {
    icon.style.opacity = "0";
    icon.style.pointerEvents = "none";
  }
}

function updateAllIconPositions(): void {
  reconcileAutofillFieldIcons();
  fieldIcons.forEach((icon, field) => positionIconEl(field, icon));
}

function removeIconForField(field: FillableField): void {
  const icon = fieldIcons.get(field);
  if (icon) {
    icon.remove();
    fieldIcons.delete(field);
  }
  focusedFields.delete(field);

  if (activeAutofillField === field) {
    activeAutofillField = null;
    hidePopup();
  }
}

function attachIconToField(field: FillableField): void {
  if (fieldIcons.has(field)) return;
  const icon = createIconForField(field);
  // Start hidden via opacity — only show when the field is focused.
  // We intentionally use opacity/pointer-events instead of display:none so
  // that positionIconEl can always update coordinates without fighting display.
  icon.style.opacity = "0";
  icon.style.pointerEvents = "none";
  if (!autofillIconsEnabled || isAutofillDisabledForCurrentDomain()) {
    icon.style.display = "none";
  }
  lpAppend(icon);
  fieldIcons.set(field, icon);
}

/** Show the autofill icon for a field (called on focus). */
function showIconForField(field: FillableField): void {
  if (!autofillIconsEnabled) return;
  if (isAutofillDisabledForCurrentDomain()) return;
  const icon = fieldIcons.get(field);
  if (!icon) return;
  refreshIconForField(field);
  // Ensure the element is in the flow before positioning
  icon.style.display = "flex";
  positionIconEl(field, icon);
  // Only make it visible if it is in the viewport (positionIconEl may have
  // hidden it if it had scrolled out of view)
  const rect = field.getBoundingClientRect();
  const inView = rect.bottom > 0 && rect.top < window.innerHeight;
  if (inView) {
    icon.style.opacity = "0.85";
    icon.style.pointerEvents = "all";
  }
}

/** Hide the autofill icon for a field (called on blur). */
function hideIconForField(field: FillableField): void {
  const icon = fieldIcons.get(field);
  if (!icon) return;
  icon.style.opacity = "0";
  icon.style.pointerEvents = "none";
}

function reconcileAutofillFieldIcons(): void {
  const validFields = new Set(getAutofillIconFields());

  fieldIcons.forEach((_icon, field) => {
    if (!document.contains(field) || !validFields.has(field)) {
      removeIconForField(field);
    }
  });

  validFields.forEach((field) => {
    if (!(field as FillableField & { _lumenpassAttached?: boolean })._lumenpassAttached) {
      (field as FillableField & { _lumenpassAttached?: boolean })._lumenpassAttached = true;
      attachToAutofillField(field);
    } else if (fieldIcons.has(field)) {
      const icon = fieldIcons.get(field);
      if (icon) {
        refreshIconForField(field);
        if (!autofillIconsEnabled || isAutofillDisabledForCurrentDomain()) {
          icon.style.display = "none";
          icon.style.opacity = "0";
          icon.style.pointerEvents = "none";
        } else if (focusedFields.has(field)) {
          // Field is focused: restore display and show
          icon.style.display = "flex";
          showIconForField(field);
        } else {
          // Not focused: restore display but keep invisible
          icon.style.display = "flex";
          icon.style.opacity = "0";
          icon.style.pointerEvents = "none";
          positionIconEl(field, icon);
        }
      }
    }
  });

  if (fieldIcons.size === 0) {
    dismissLoginAutofillPrompt();
    hidePopup();
  }
}

// ─── Inline popup ─────────────────────────────────────────────────────────────

function createPopup(): HTMLDivElement {
  ensureOverlayStyles();
  const div = document.createElement("div");
  div.id = POPUP_ID;
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  div.style.cssText = `
    position: fixed;
    z-index: 2147483646;
    width: 296px;
    background: ${isDark ? "#1f2937" : "#ffffff"};
    border: 1px solid ${isDark ? "#374151" : "#e5e7eb"};
    border-radius: 12px;
    box-shadow: 0 8px 32px rgba(0,0,0,0.18);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    font-size: 13px;
    color: ${isDark ? "#f3f4f6" : "#111827"};
    overflow: hidden;
  `;
  return div;
}

function positionPopup(field: FillableField): void {
  if (!popupEl) return;
  const rect = field.getBoundingClientRect();

  if (rect.width === 0 && rect.height === 0) {
    requestAnimationFrame(() => positionPopup(field));
    return;
  }

  popupEl.style.maxHeight = "";
  popupEl.style.overflowY = "hidden";
  popupEl.style.setProperty("--lp-popup-list-max-height", `${POPUP_LIST_MAX_HEIGHT}px`);

  const visualViewport = window.visualViewport;
  const viewportLeft = visualViewport?.offsetLeft ?? 0;
  const viewportTop = visualViewport?.offsetTop ?? 0;
  const viewportRight = viewportLeft + (visualViewport?.width ?? window.innerWidth);
  const viewportBottom = viewportTop + (visualViewport?.height ?? window.innerHeight);
  const viewportHeight = Math.max(0, viewportBottom - viewportTop);
  const viewportMaxHeight = Math.max(0, viewportHeight - POPUP_VIEWPORT_MARGIN * 2);

  let popupRect = popupEl.getBoundingClientRect();
  const popupWidth = popupRect.width || 296;
  const measuredPopupHeight = popupRect.height || popupEl.scrollHeight || 320;
  const targetPopupHeight = Math.min(measuredPopupHeight, viewportMaxHeight || measuredPopupHeight);
  const availableBelow = Math.max(0, viewportBottom - rect.bottom - POPUP_GAP - POPUP_VIEWPORT_MARGIN);
  const availableAbove = Math.max(0, rect.top - viewportTop - POPUP_GAP - POPUP_VIEWPORT_MARGIN);
  const fitsBelow = targetPopupHeight <= availableBelow;
  const fitsAbove = targetPopupHeight <= availableAbove;
  const placeAbove = !fitsBelow && (fitsAbove || availableAbove > availableBelow);
  const sideMaxHeight = placeAbove ? availableAbove : availableBelow;
  const maxPopupHeight = sideMaxHeight > 0 ? Math.min(sideMaxHeight, viewportMaxHeight) : viewportMaxHeight;
  const scrollEl = popupEl.querySelector<HTMLElement>(".lp-scroll");

  if (scrollEl && maxPopupHeight > 0 && measuredPopupHeight > maxPopupHeight) {
    const scrollHeight = scrollEl.getBoundingClientRect().height;
    const fixedHeight = measuredPopupHeight - scrollHeight;
    const listHeight = Math.max(0, Math.min(POPUP_LIST_MAX_HEIGHT, Math.floor(maxPopupHeight - fixedHeight)));
    popupEl.style.setProperty("--lp-popup-list-max-height", `${listHeight}px`);
    popupRect = popupEl.getBoundingClientRect();
  }

  const fittedPopupHeight = Math.min(popupRect.height || popupEl.scrollHeight || targetPopupHeight, maxPopupHeight);
  const minTop = viewportTop + POPUP_VIEWPORT_MARGIN;
  const maxTop = Math.max(minTop, viewportBottom - fittedPopupHeight - POPUP_VIEWPORT_MARGIN);
  let top = placeAbove ? rect.top - fittedPopupHeight - POPUP_GAP : rect.bottom + POPUP_GAP;
  let left = rect.left;

  if (maxPopupHeight > 0) {
    popupEl.style.maxHeight = `${Math.floor(maxPopupHeight)}px`;
  }
  if (maxPopupHeight > 0 && popupEl.scrollHeight > maxPopupHeight) {
    popupEl.style.overflowY = "auto";
  }

  top = Math.min(Math.max(minTop, top), maxTop);

  if (left + popupWidth > viewportRight - POPUP_VIEWPORT_MARGIN) {
    left = Math.max(POPUP_VIEWPORT_MARGIN, viewportRight - popupWidth - POPUP_VIEWPORT_MARGIN);
  }

  left = Math.max(viewportLeft + POPUP_VIEWPORT_MARGIN, left);

  popupEl.style.top = `${top}px`;
  popupEl.style.left = `${left}px`;
  popupEl.style.minWidth = `${Math.min(rect.width, popupWidth)}px`;
}

function getFilteredPopupEntries(): EntryItem[] {
  return filterEntryItems(entries, popupSearchQuery);
}

function getVisiblePopupEntries(): EntryItem[] {
  if (activeFieldKind === "identifier") return entries;
  return getFilteredPopupEntries();
}

function dedupeIdentifierEntries(items: EntryItem[], query = ""): EntryItem[] {
  const seen = new Set<string>();
  const normalizedQuery = normalizeLookupKey(query);
  return items.filter((entry) => {
    const key = normalizeLookupKey(entry.username);
    if (normalizedQuery && !key.includes(normalizedQuery)) return false;
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function fillIdentifierHint(entry: EntryItem): void {
  if (!(activeAutofillField instanceof HTMLInputElement)) return;
  if (!entry.username.trim()) return;
  suppressPopupOpen = true;
  if (simulateFill(activeAutofillField, entry.username)) {
    autofilledFields.add(activeAutofillField);
  }
  hidePopup();
  window.setTimeout(() => {
    suppressPopupOpen = false;
  }, 250);
}

function selectPopupEntry(entry: EntryItem): void {
  if (activeFieldKind === "identifier") {
    fillIdentifierHint(entry);
    return;
  }
  void fillEntry(entry);
}

function renderIdentifierPopupEntries(): void {
  if (!popupEl) return;
  const activeInput = activeAutofillField instanceof HTMLInputElement ? activeAutofillField : null;
  const query = activeInput?.value.trim() ?? "";
  if (!query && !identifierHintAllowsEmptyQuery) {
    hidePopup();
    return;
  }

  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  selectedIndex = entries.length === 0 ? 0 : Math.min(selectedIndex, entries.length - 1);
  const headerBorder = isDark ? "#374151" : "#eef2f7";
  const text = isDark ? "#f3f4f6" : "#111827";
  const subText = isDark ? "#9ca3af" : "#6b7280";
  const rowsHtml = entries.length === 0
    ? `<div style="padding:14px;color:${subText};text-align:center;font-size:12px;">No suggestions found</div>`
    : entries.map((entry, idx) => {
      const bg = idx === selectedIndex ? (isDark ? "#374151" : "#f3f4ff") : "transparent";
      const colour = seedColour(entry.username || entry.title);
      const abbr = initials(entry.username || entry.title);
      return `<button
        type="button"
        data-identifier-index="${idx}"
        style="all:unset;box-sizing:border-box;display:flex;align-items:center;gap:10px;width:100%;padding:10px 12px;cursor:pointer;background:${bg};transition:background 0.1s;"
        onmouseenter="this.style.background='${isDark ? "#374151" : "#f3f4ff"}'"
        onmouseleave="this.style.background='${idx === selectedIndex ? (isDark ? "#374151" : "#f3f4ff") : "transparent"}'"
      >
        <span style="width:24px;height:24px;border-radius:999px;background:${colour};display:flex;align-items:center;justify-content:center;color:white;font-size:9px;font-weight:700;flex-shrink:0;">${lpEscapeHtml(abbr)}</span>
        <span style="flex:1;min-width:0;font-weight:600;font-size:13px;color:${text};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${lpEscapeHtml(entry.username)}</span>
      </button>`;
    }).join("");

  popupEl.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;padding:11px 12px 10px;border-bottom:1px solid ${headerBorder};">
      <div style="width:28px;height:28px;border-radius:8px;background:#444ce7;display:flex;align-items:center;justify-content:center;flex-shrink:0;color:white;">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21a8 8 0 0 0-16 0"/><circle cx="12" cy="7" r="4"/></svg>
      </div>
      <div style="flex:1;min-width:0;font-size:13px;font-weight:700;color:${text};">Pick suggestion</div>
      <button id="lp-footer-close" type="button" aria-label="Close" title="Close" style="width:30px;height:30px;flex-shrink:0;border:1px solid ${isDark ? "#374151" : "#e5e7eb"};border-radius:9px;background:${isDark ? "#111827" : "#f8fafc"};color:${isDark ? "#cbd5e1" : "#64748b"};cursor:pointer;font-size:18px;line-height:1;display:flex;align-items:center;justify-content:center;">&times;</button>
    </div>
    <div class="lp-scroll" style="max-height:var(--lp-popup-list-max-height, min(260px, calc(100vh - 180px)));padding:4px 0;">
      ${rowsHtml}
    </div>
  `;

  popupEl.querySelector<HTMLButtonElement>("#lp-footer-close")?.addEventListener("click", (e) => {
    e.stopPropagation();
    hidePopup(true);
  });
  popupEl.querySelectorAll("[data-identifier-index]").forEach((el) => {
    el.addEventListener("click", (e) => {
      e.stopPropagation();
      e.preventDefault();
      const idx = parseInt((el as HTMLElement).dataset.identifierIndex ?? "0", 10);
      const entry = entries[idx];
      if (entry) fillIdentifierHint(entry);
    });
  });
}

async function searchAllItems(query: string): Promise<void> {
  if (!query.trim()) {
    allItemsResults = [];
    allItemsHasSearched = false;
    allItemsLoading = false;
    return;
  }

  const currentToken = ++allItemsSearchToken;
  allItemsLoading = true;
  allItemsHasSearched = true;
  renderPopupEntries(getAllItemsSearchFocusOptions());

  try {
    const searchType = getEntrySearchType();
    const res = await browser.runtime.sendMessage({
      type: "SEARCH_ENTRIES",
      payload: { query, type: searchType },
    });

    if (currentToken !== allItemsSearchToken) return;

    if (res?.ok && Array.isArray(res.data)) {
      allItemsResults = (res.data as EntryItem[]).filter((entry) => entryMatchesFieldKind(entry));
    } else {
      allItemsResults = [];
    }
  } catch {
    if (currentToken !== allItemsSearchToken) return;
    allItemsResults = [];
  } finally {
    if (currentToken === allItemsSearchToken) {
      allItemsLoading = false;
      renderPopupEntries(getAllItemsSearchFocusOptions());
      if (activeAutofillField) {
        positionPopup(activeAutofillField);
      }
    }
  }
}

function getAllItemsSearchFocusOptions():
  | { focusSearch: true; selectionStart: number | null }
  | undefined {
  const allSearchInput = popupEl?.querySelector<HTMLInputElement>("#lp-all-search");
  if (!allSearchInput) return undefined;

  const root = allSearchInput.getRootNode();
  const activeElement = root instanceof ShadowRoot ? root.activeElement : document.activeElement;
  if (activeElement !== allSearchInput) return undefined;

  return {
    focusSearch: true,
    selectionStart: allSearchInput.selectionStart,
  };
}

function handleAllItemsSearchInput(value: string): void {
  popupAllQuery = value;
  selectedIndex = 0;

  if (allItemsDebounceTimer !== null) {
    window.clearTimeout(allItemsDebounceTimer);
  }

  allItemsDebounceTimer = window.setTimeout(() => {
    allItemsDebounceTimer = null;
    void searchAllItems(value);
  }, ALL_ITEMS_SEARCH_DEBOUNCE_MS);
}

function renderPopupEntries(options?: { focusSearch?: boolean; selectionStart?: number | null }): void {
  if (!popupEl) return;
  if (activeFieldKind === "identifier") {
    renderIdentifierPopupEntries();
    return;
  }
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const specialPurposeTitle = getSpecialPurposeTitle();
  const purposeSearchLabel = getPurposeSearchLabel();
  const showTabs = activeFieldKind === "login";
  if (!showTabs && popupTab !== "suggestions") {
    popupTab = "suggestions";
  }

  const activeTabBg = isDark ? "#374151" : "#e0e7ff";
  const inactiveTabBg = "transparent";
  const activeTabColor = isDark ? "#f3f4f6" : "#111827";
  const inactiveTabColor = isDark ? "#9ca3af" : "#6b7280";
  const purposeHeaderHtml = specialPurposeTitle
    ? `<div style="display:flex;align-items:center;gap:8px;padding:12px 12px 10px;border-bottom:1px solid ${isDark ? "#374151" : "#eef2f7"};">
        <div style="width:28px;height:28px;border-radius:8px;background:${activeFieldKind === "card" ? "#0f766e" : "#059669"};display:flex;align-items:center;justify-content:center;flex-shrink:0;color:white;">
          ${activeFieldKind === "card"
            ? `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="5" width="20" height="14" rx="2"/><line x1="2" y1="10" x2="22" y2="10"/></svg>`
            : `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="M15 8h3M15 12h3M7 16h10"/></svg>`}
        </div>
        <div style="flex:1;min-width:0;">
          <div style="font-size:13px;font-weight:700;color:${isDark ? "#f3f4f6" : "#111827"};">${specialPurposeTitle}</div>
          <div style="font-size:11px;color:${isDark ? "#9ca3af" : "#64748b"};">Autofill ${purposeSearchLabel}</div>
        </div>
      </div>`
    : "";

  const tabsHtml = showTabs ? `
    <div style="display:flex;gap:4px;padding:8px 12px 0;border-bottom:1px solid ${isDark ? "#374151" : "#eef2f7"};">
      <button
        id="lp-tab-suggestions"
        type="button"
        style="flex:1;padding:8px 12px;border:none;border-radius:8px 8px 0 0;background:${popupTab === "suggestions" ? activeTabBg : inactiveTabBg};color:${popupTab === "suggestions" ? activeTabColor : inactiveTabColor};font-size:12px;font-weight:500;cursor:pointer;transition:all 0.15s;"
      >Suggestions</button>
      <button
        id="lp-tab-all"
        type="button"
        style="flex:1;padding:8px 12px;border:none;border-radius:8px 8px 0 0;background:${popupTab === "all" ? activeTabBg : inactiveTabBg};color:${popupTab === "all" ? activeTabColor : inactiveTabColor};font-size:12px;font-weight:500;cursor:pointer;transition:all 0.15s;"
      >All Items</button>
    </div>` : "";
  const disableAutofillFooterHtml = `
    <div style="border-top:1px solid ${isDark ? "#374151" : "#eef2f7"};padding:10px 12px;">
      <div style="display:flex;align-items:center;gap:8px;">
        <button
          id="lp-disable-autofill-domain"
          type="button"
          style="all:unset;box-sizing:border-box;flex:1;min-width:0;padding:8px 12px;border:1px solid ${isDark ? "#7f1d1d" : "#fecaca"};border-radius:9px;background:${isDark ? "#3f1d1d" : "#fef2f2"};cursor:pointer;color:${isDark ? "#fca5a5" : "#b42318"};font-size:12px;font-weight:600;text-align:center;transition:background 0.15s, border-color 0.15s;"
        >Disable Autofill for this domain</button>
        <button
          id="lp-footer-close"
          type="button"
          aria-label="Close"
          title="Close"
          style="width:34px;height:34px;flex-shrink:0;border:1px solid ${isDark ? "#374151" : "#e5e7eb"};border-radius:9px;background:${isDark ? "#111827" : "#f8fafc"};color:${isDark ? "#cbd5e1" : "#64748b"};cursor:pointer;font-size:18px;line-height:1;display:flex;align-items:center;justify-content:center;"
        >&times;</button>
      </div>
      <div
        data-disable-autofill-options
        data-open="false"
        style="display:none;gap:2px;margin-top:6px;padding:4px;border:1px solid ${isDark ? "#374151" : "#e5e7eb"};border-radius:10px;background:${isDark ? "#111827" : "#ffffff"};"
      ></div>
    </div>`;

  if (popupTab === "suggestions") {
    const filteredEntries = getFilteredPopupEntries();
    selectedIndex = filteredEntries.length === 0 ? 0 : Math.min(selectedIndex, filteredEntries.length - 1);
    const searchValue = popupSearchQuery.replace(/"/g, "&quot;");

    const emptyText = activeFieldKind === "card"
      ? "No credit cards saved"
      : activeFieldKind === "identity"
      ? "No identity profiles saved"
      : "No logins found for this site";

    if (entries.length === 0) {
      popupEl.innerHTML = `
        ${purposeHeaderHtml}
        ${tabsHtml}
        <div style="display:flex;align-items:center;gap:8px;padding:12px;">
          <div style="position:relative;flex:1;min-width:0;">
            <input
              id="lp-inline-search"
              type="text"
              value="${searchValue}"
              placeholder="Search ${purposeSearchLabel}"
              style="width:100%;padding:8px 32px 8px 10px;border:1px solid ${isDark ? "#374151" : "#dbe3f0"};border-radius:9px;background:${isDark ? "#111827" : "#f8fafc"};color:${isDark ? "#f3f4f6" : "#111827"};font-size:12px;outline:none;box-sizing:border-box;"
            />
            ${searchValue ? `<button
              id="lp-inline-clear"
              type="button"
              aria-label="Clear search"
              style="position:absolute;top:50%;right:6px;transform:translateY(-50%);width:22px;height:22px;border:none;border-radius:6px;background:transparent;color:${isDark ? "#cbd5e1" : "#64748b"};cursor:pointer;font-size:16px;line-height:1;display:flex;align-items:center;justify-content:center;"
            >&times;</button>` : ""}
          </div>
        </div>
        <div style="padding:0 14px 12px; color:${isDark ? "#9ca3af" : "#6b7280"}; text-align:center;">
          ${emptyText}
        </div>
        ${disableAutofillFooterHtml}`;
    } else {
      const rowsHtml = filteredEntries
        .map((entry, idx) => {
          const bg = idx === selectedIndex ? (isDark ? "#374151" : "#f3f4ff") : "transparent";
          const colour = seedColour(entry.title);
          const abbr = initials(entry.title);
          const faviconSrc = entry.favicon ? googleFaviconUrlForDisplay(entry.favicon, 128) : "";
          const avatarHtml = faviconSrc
            ? `<div style="width:24px;height:24px;border-radius:5px;overflow:hidden;display:flex;align-items:center;justify-content:center;position:relative;">
                 <img src="${faviconSrc}" style="width:24px;height:24px;border-radius:5px;object-fit:contain;background:white;" onerror="this.style.display='none';this.nextElementSibling.style.display='flex'" onload="if(this.naturalWidth<48||this.naturalHeight<48){this.style.display='none';this.nextElementSibling.style.display='flex'}" />
                 <div style="display:none;position:absolute;inset:0;border-radius:5px;background:${colour};align-items:center;justify-content:center;color:white;font-size:9px;font-weight:700;">${abbr}</div>
               </div>`
            : `<div style="width:24px;height:24px;border-radius:5px;background:${colour};display:flex;align-items:center;justify-content:center;color:white;font-size:9px;font-weight:700;">${abbr}</div>`;

          const subtitleText = entry.subtitle ?? entry.username;
          return `<div
            data-index="${idx}"
            style="display:flex;align-items:center;gap:10px;padding:8px 12px;cursor:pointer;background:${bg};transition:background 0.1s;"
            onmouseenter="this.style.background='${isDark ? "#374151" : "#f3f4ff"}'"
            onmouseleave="this.style.background='${idx === selectedIndex ? (isDark ? "#374151" : "#f3f4ff") : "transparent"}'"
          >
            ${avatarHtml}
            <div style="flex:1;min-width:0;">
              <div style="font-weight:500;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${entry.title}</div>
              <div style="font-size:11px;color:${isDark ? "#9ca3af" : "#6b7280"};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${subtitleText}</div>
            </div>
            <button
              type="button"
              data-view-index="${idx}"
              aria-label="View ${lpEscapeHtml(entry.title)} details"
              title="View details"
              style="width:32px;height:28px;flex-shrink:0;border:none;border-radius:8px;background:#444ce7;color:white;display:flex;align-items:center;justify-content:center;cursor:pointer;padding:0;box-shadow:0 1px 4px rgba(68,76,231,0.22);"
            >${itemDetailEyeSvg()}</button>
          </div>`;
        })
        .join("");

      popupEl.innerHTML = `
        ${purposeHeaderHtml}
        ${tabsHtml}
        <div style="display:flex;align-items:center;gap:8px;padding:12px 12px 8px;border-bottom:1px solid ${isDark ? "#374151" : "#eef2f7"};">
          <div style="position:relative;flex:1;min-width:0;">
            <input
              id="lp-inline-search"
              type="text"
              value="${searchValue}"
              placeholder="Search ${purposeSearchLabel}"
              style="width:100%;padding:8px 32px 8px 10px;border:1px solid ${isDark ? "#374151" : "#dbe3f0"};border-radius:9px;background:${isDark ? "#111827" : "#f8fafc"};color:${isDark ? "#f3f4f6" : "#111827"};font-size:12px;outline:none;box-sizing:border-box;"
            />
            ${searchValue ? `<button
              id="lp-inline-clear"
              type="button"
              aria-label="Clear search"
              style="position:absolute;top:50%;right:6px;transform:translateY(-50%);width:22px;height:22px;border:none;border-radius:6px;background:transparent;color:${isDark ? "#cbd5e1" : "#64748b"};cursor:pointer;font-size:16px;line-height:1;display:flex;align-items:center;justify-content:center;"
            >&times;</button>` : ""}
          </div>
        </div>
        <div class="lp-scroll" style="max-height:var(--lp-popup-list-max-height, min(320px, calc(100vh - 180px)));padding:4px 0;">
          ${rowsHtml}
        </div>
        ${disableAutofillFooterHtml}
      `;
    }

    const searchInput = popupEl.querySelector<HTMLInputElement>("#lp-inline-search");
    popupEl.querySelector<HTMLButtonElement>("#lp-inline-clear")?.addEventListener("click", (e) => {
      e.stopPropagation();
      e.preventDefault();
      popupSearchQuery = "";
      selectedIndex = 0;
      renderPopupEntries({ focusSearch: true, selectionStart: 0 });
      if (activeAutofillField) {
        positionPopup(activeAutofillField);
      }
    });
    searchInput?.addEventListener("input", () => {
      popupSearchQuery = searchInput.value;
      selectedIndex = 0;
      renderPopupEntries({
        focusSearch: true,
        selectionStart: searchInput.selectionStart,
      });
      if (activeAutofillField) {
        positionPopup(activeAutofillField);
      }
    });

    searchInput?.addEventListener("keydown", (e) => {
      const visibleEntries = getFilteredPopupEntries();
      if (e.key === "ArrowDown") {
        e.preventDefault();
        if (visibleEntries.length > 0) {
          selectedIndex = Math.min(selectedIndex + 1, visibleEntries.length - 1);
        }
        renderPopupEntries({ focusSearch: true, selectionStart: searchInput.selectionStart });
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        selectedIndex = visibleEntries.length > 0 ? Math.max(selectedIndex - 1, 0) : 0;
        renderPopupEntries({ focusSearch: true, selectionStart: searchInput.selectionStart });
      } else if (e.key === "Enter") {
        if (visibleEntries[selectedIndex]) {
          e.preventDefault();
          selectPopupEntry(visibleEntries[selectedIndex]);
        }
      } else if (e.key === "Escape") {
        e.preventDefault();
        hidePopup(true);
      }
    });

    if (options?.focusSearch && searchInput) {
      const caret = options.selectionStart ?? searchInput.value.length;
      searchInput.focus();
      searchInput.setSelectionRange(caret, caret);
    }

    if (filteredEntries.length > 0) {
      popupEl.querySelectorAll("[data-view-index]").forEach((el) => {
        el.addEventListener("click", (e) => {
          e.stopPropagation();
          e.preventDefault();
          const idx = parseInt((el as HTMLElement).dataset.viewIndex ?? "0", 10);
          void showItemDetailModal(filteredEntries[idx]);
        });
      });
      popupEl.querySelectorAll("[data-index]").forEach((el) => {
        el.addEventListener("click", (e) => {
          e.stopPropagation();
          const idx = parseInt((el as HTMLElement).dataset.index ?? "0", 10);
          const entry = filteredEntries[idx];
          if (entry) selectPopupEntry(entry);
        });
      });
    }
  } else {
    const allSearchValue = popupAllQuery.replace(/"/g, "&quot;");
    selectedIndex = allItemsResults.length === 0 ? 0 : Math.min(selectedIndex, allItemsResults.length - 1);

    let contentHtml = "";
    if (!allItemsHasSearched) {
      contentHtml = `<div style="padding:24px 14px; color:${isDark ? "#9ca3af" : "#6b7280"}; text-align:center;font-size:12px;">
        Enter a search term to find ${purposeSearchLabel}
      </div>`;
    } else if (allItemsLoading) {
      contentHtml = `<div style="padding:24px 14px; color:${isDark ? "#9ca3af" : "#6b7280"}; text-align:center;font-size:12px;">
        Searching...
      </div>`;
    } else if (allItemsResults.length === 0) {
      contentHtml = `<div style="padding:24px 14px; color:${isDark ? "#9ca3af" : "#6b7280"}; text-align:center;font-size:12px;">
        No items found
      </div>`;
    } else {
      const rowsHtml = allItemsResults
        .map((entry, idx) => {
          const bg = idx === selectedIndex ? (isDark ? "#374151" : "#f3f4ff") : "transparent";
          const colour = seedColour(entry.title);
          const abbr = initials(entry.title);
          const faviconSrc = entry.favicon ? googleFaviconUrlForDisplay(entry.favicon, 128) : "";
          const avatarHtml = faviconSrc
            ? `<div style="width:24px;height:24px;border-radius:5px;overflow:hidden;display:flex;align-items:center;justify-content:center;position:relative;">
                 <img src="${faviconSrc}" style="width:24px;height:24px;border-radius:5px;object-fit:contain;background:white;" onerror="this.style.display='none';this.nextElementSibling.style.display='flex'" onload="if(this.naturalWidth<48||this.naturalHeight<48){this.style.display='none';this.nextElementSibling.style.display='flex'}" />
                 <div style="display:none;position:absolute;inset:0;border-radius:5px;background:${colour};align-items:center;justify-content:center;color:white;font-size:9px;font-weight:700;">${abbr}</div>
               </div>`
            : `<div style="width:24px;height:24px;border-radius:5px;background:${colour};display:flex;align-items:center;justify-content:center;color:white;font-size:9px;font-weight:700;">${abbr}</div>`;

          const subtitleText = entry.subtitle ?? entry.username;
          return `<div
            data-all-index="${idx}"
            style="display:flex;align-items:center;gap:10px;padding:8px 12px;cursor:pointer;background:${bg};transition:background 0.1s;"
            onmouseenter="this.style.background='${isDark ? "#374151" : "#f3f4ff"}'"
            onmouseleave="this.style.background='${idx === selectedIndex ? (isDark ? "#374151" : "#f3f4ff") : "transparent"}'"
          >
            ${avatarHtml}
            <div style="flex:1;min-width:0;">
              <div style="font-weight:500;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${entry.title}</div>
              <div style="font-size:11px;color:${isDark ? "#9ca3af" : "#6b7280"};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${subtitleText}</div>
            </div>
            <button
              type="button"
              data-all-view-index="${idx}"
              aria-label="View ${lpEscapeHtml(entry.title)} details"
              title="View details"
              style="width:32px;height:28px;flex-shrink:0;border:none;border-radius:8px;background:#444ce7;color:white;display:flex;align-items:center;justify-content:center;cursor:pointer;padding:0;box-shadow:0 1px 4px rgba(68,76,231,0.22);"
            >${itemDetailEyeSvg()}</button>
          </div>`;
        })
        .join("");
      contentHtml = `<div class="lp-scroll" style="max-height:var(--lp-popup-list-max-height, min(320px, calc(100vh - 180px)));padding:4px 0;">
        ${rowsHtml}
      </div>`;
    }

    popupEl.innerHTML = `
      ${purposeHeaderHtml}
      ${tabsHtml}
      <div style="display:flex;align-items:center;gap:8px;padding:12px 12px 8px;border-bottom:1px solid ${isDark ? "#374151" : "#eef2f7"};">
        <div style="position:relative;flex:1;min-width:0;">
          <input
            id="lp-all-search"
            type="text"
            value="${allSearchValue}"
            placeholder="Search all ${purposeSearchLabel}"
            style="width:100%;padding:8px 32px 8px 10px;border:1px solid ${isDark ? "#374151" : "#dbe3f0"};border-radius:9px;background:${isDark ? "#111827" : "#f8fafc"};color:${isDark ? "#f3f4f6" : "#111827"};font-size:12px;outline:none;box-sizing:border-box;"
          />
          ${allSearchValue ? `<button
            id="lp-all-clear"
            type="button"
            aria-label="Clear search"
            style="position:absolute;top:50%;right:6px;transform:translateY(-50%);width:22px;height:22px;border:none;border-radius:6px;background:transparent;color:${isDark ? "#cbd5e1" : "#64748b"};cursor:pointer;font-size:16px;line-height:1;display:flex;align-items:center;justify-content:center;"
          >&times;</button>` : ""}
        </div>
      </div>
      ${contentHtml}
      ${disableAutofillFooterHtml}
    `;

    const allSearchInput = popupEl.querySelector<HTMLInputElement>("#lp-all-search");
    popupEl.querySelector<HTMLButtonElement>("#lp-all-clear")?.addEventListener("click", (e) => {
      e.stopPropagation();
      e.preventDefault();
      handleAllItemsSearchInput("");
      renderPopupEntries({ focusSearch: true, selectionStart: 0 });
      if (activeAutofillField) {
        positionPopup(activeAutofillField);
      }
    });

    allSearchInput?.addEventListener("input", () => {
      handleAllItemsSearchInput(allSearchInput.value);
      renderPopupEntries({
        focusSearch: true,
        selectionStart: allSearchInput.selectionStart,
      });
      if (activeAutofillField) {
        positionPopup(activeAutofillField);
      }
    });

    allSearchInput?.addEventListener("keydown", (e) => {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        if (allItemsResults.length > 0) {
          selectedIndex = Math.min(selectedIndex + 1, allItemsResults.length - 1);
        }
        renderPopupEntries({ focusSearch: true, selectionStart: allSearchInput.selectionStart });
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        selectedIndex = allItemsResults.length > 0 ? Math.max(selectedIndex - 1, 0) : 0;
        renderPopupEntries({ focusSearch: true, selectionStart: allSearchInput.selectionStart });
      } else if (e.key === "Enter") {
        if (allItemsResults[selectedIndex]) {
          e.preventDefault();
          selectPopupEntry(allItemsResults[selectedIndex]);
        }
      } else if (e.key === "Escape") {
        e.preventDefault();
        hidePopup(true);
      }
    });

    if (options?.focusSearch && allSearchInput) {
      const caret = options.selectionStart ?? allSearchInput.value.length;
      allSearchInput.focus();
      allSearchInput.setSelectionRange(caret, caret);
    }

    if (allItemsResults.length > 0) {
      popupEl.querySelectorAll("[data-all-view-index]").forEach((el) => {
        el.addEventListener("click", (e) => {
          e.stopPropagation();
          e.preventDefault();
          const idx = parseInt((el as HTMLElement).dataset.allViewIndex ?? "0", 10);
          void showItemDetailModal(allItemsResults[idx]);
        });
      });
      popupEl.querySelectorAll("[data-all-index]").forEach((el) => {
        el.addEventListener("click", (e) => {
          e.stopPropagation();
          const idx = parseInt((el as HTMLElement).dataset.allIndex ?? "0", 10);
          const entry = allItemsResults[idx];
          if (entry) selectPopupEntry(entry);
        });
      });
    }
  }

  popupEl.querySelector<HTMLButtonElement>("#lp-tab-suggestions")?.addEventListener("click", (e) => {
    e.stopPropagation();
    popupTab = "suggestions";
    selectedIndex = 0;
    renderPopupEntries();
    if (activeAutofillField) {
      positionPopup(activeAutofillField);
    }
  });

  popupEl.querySelector<HTMLButtonElement>("#lp-tab-all")?.addEventListener("click", (e) => {
    e.stopPropagation();
    popupTab = "all";
    selectedIndex = 0;
    renderPopupEntries({ focusSearch: true });
    if (activeAutofillField) {
      positionPopup(activeAutofillField);
    }
  });

  popupEl.querySelector<HTMLButtonElement>("#lp-disable-autofill-domain")?.addEventListener("click", (e) => {
    e.stopPropagation();
    renderDisableAutofillOptions(popupEl!, isDark, () => hidePopup(true));
    if (activeAutofillField) {
      positionPopup(activeAutofillField);
    }
  });

  popupEl.querySelector<HTMLButtonElement>("#lp-footer-close")?.addEventListener("click", (e) => {
    e.stopPropagation();
    hidePopup(true);
  });
}

function showPopup(field: FillableField): void {
  if (!popupEl) {
    popupEl = createPopup();
    lpAppend(popupEl);
  }
  if (
    activeFieldKind === "identifier"
    && (!(field instanceof HTMLInputElement) || !field.value.trim())
    && !identifierHintAllowsEmptyQuery
  ) {
    hidePopup();
    return;
  }
  popupTab = "suggestions";
  popupSearchQuery = "";
  popupAllQuery = "";
  allItemsResults = [];
  allItemsHasSearched = false;
  allItemsLoading = false;
  selectedIndex = 0;
  if (allItemsDebounceTimer !== null) {
    window.clearTimeout(allItemsDebounceTimer);
    allItemsDebounceTimer = null;
  }
  const shouldRenderLocked = !desktopConnected || !desktopVaultOpen;
  popupEl.style.display = "block";
  if (shouldRenderLocked) {
    renderLockedPopup();
  } else {
    renderPopupEntries();
  }
  requestAnimationFrame(() => positionPopup(field));
}

function hidePopup(dismissed = false): void {
  identifierHintAllowsEmptyQuery = false;
  if (dismissed && activeAutofillField) {
    dismissedFields.add(activeAutofillField);
  }
  if (popupEl) {
    popupEl.style.display = "none";
  }
  if (allItemsDebounceTimer !== null) {
    window.clearTimeout(allItemsDebounceTimer);
    allItemsDebounceTimer = null;
  }
  if (identifierHintDebounceTimer !== null) {
    window.clearTimeout(identifierHintDebounceTimer);
    identifierHintDebounceTimer = null;
  }
  if (activeAutofillField && !focusedFields.has(activeAutofillField)) {
    hideIconForField(activeAutofillField);
  }
}

async function disableAutofillForCurrentDomain(durationMs: number | null): Promise<void> {
  const domain = getCurrentAutofillDomain();
  if (!domain) return;
  try {
    const response = await browser.runtime.sendMessage({
      type: "DISABLE_AUTOFILL_DOMAIN",
      payload: { domain, durationMs },
    });
    if (response?.ok) {
      const next = response.data?.disabledAutofillDomains as DisabledAutofillDomain[] | undefined;
      applyDisabledAutofillDomains(next ?? [
        {
          domain,
          disabledAt: Date.now(),
          expiresAt: durationMs === null ? null : Date.now() + durationMs,
        },
      ]);
      showSaveResultToast(true, `Autofill disabled for ${domain}`);
    } else {
      showSaveResultToast(false, "Could not disable autofill for this domain");
    }
  } catch {
    showSaveResultToast(false, "Could not disable autofill for this domain");
  }
}

function renderDisableAutofillOptions(
  container: HTMLElement,
  isDark: boolean,
  close: () => void,
): void {
  const panel = container.querySelector<HTMLElement>("[data-disable-autofill-options]");
  if (!panel) return;
  const visible = panel.dataset.open === "true";
  if (visible) {
    panel.dataset.open = "false";
    panel.style.display = "none";
    return;
  }

  panel.dataset.open = "true";
  panel.style.display = "grid";
  panel.innerHTML = DISABLE_AUTOFILL_OPTIONS.map((option, index) => `
    <button
      type="button"
      data-disable-autofill-option="${index}"
      style="all:unset;box-sizing:border-box;padding:8px 10px;border-radius:8px;cursor:pointer;color:${isDark ? "#e5e7eb" : "#111827"};font-size:12px;font-weight:600;"
    >${option.label}</button>
  `).join("");

  panel.querySelectorAll<HTMLButtonElement>("[data-disable-autofill-option]").forEach((button) => {
    button.addEventListener("mouseenter", () => {
      button.style.background = isDark ? "#374151" : "#f3f4ff";
    });
    button.addEventListener("mouseleave", () => {
      button.style.background = "transparent";
    });
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      const index = parseInt(button.dataset.disableAutofillOption ?? "0", 10);
      const option = DISABLE_AUTOFILL_OPTIONS[index];
      close();
      void disableAutofillForCurrentDomain(option.durationMs);
    });
  });
}

// ─── Inline item detail modal ────────────────────────────────────────────────

type ItemDetailField = {
  key: string;
  label: string;
  value: string;
  secret?: boolean;
  multiline?: boolean;
  monospace?: boolean;
  openUrl?: boolean;
  isTotp?: boolean;
};

function itemDetailHasValue(value: string | undefined | null): value is string {
  return !!value && value.trim() !== "" && value.trim() !== "—" && value.trim() !== "-";
}

function mergeEntryDetail(entry: EntryItem, detail?: EntryDetail): EntryDetail {
  return {
    ...entry,
    ...(detail ?? {}),
    id: detail?.id ?? entry.id,
    title: detail?.title ?? entry.title,
    username: detail?.username ?? entry.username,
    url: detail?.url ?? entry.url,
    favicon: detail?.favicon ?? entry.favicon,
    subtitle: detail?.subtitle ?? entry.subtitle,
    socialProvider: detail?.socialProvider ?? entry.socialProvider,
    kind: detail?.kind ?? entry.kind,
  };
}

function formatItemKind(kind?: EntryItem["kind"]): string {
  switch (kind) {
    case "credit-card": return "Credit card";
    case "identity": return "Identity";
    case "secure-note": return "Secure note";
    case "software-license": return "Software license";
    case "ssh-key": return "SSH key";
    case "passkey": return "Passkey";
    case "totp": return "One-time password";
    case "login": return "Login";
    default: return "Item";
  }
}

function formatDetailDate(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatDetailCardDate(value: string): string {
  const trimmed = value.trim();
  const ymd = trimmed.match(/^(\d{4})[/-](\d{1,2})$/);
  if (ymd) return `${ymd[2].padStart(2, "0")} / ${ymd[1]}`;
  const mdy = trimmed.match(/^(\d{1,2})[/-](\d{4})$/);
  if (mdy) return `${mdy[1].padStart(2, "0")} / ${mdy[2]}`;
  return value;
}

function displayLabelForDetailField(label: string): string {
  const cleaned = label
    .replace(/[_-]+/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/\s+/g, " ")
    .trim();
  if (!cleaned) return "Field";

  const keepUpper = new Set(["ID", "PIN", "CVC", "CVV", "URL", "API", "SSH", "OTP", "TOTP"]);
  return cleaned
    .split(" ")
    .map((part) => {
      const upper = part.toUpperCase();
      if (keepUpper.has(upper)) return upper;
      return part.charAt(0).toUpperCase() + part.slice(1);
    })
    .join(" ");
}

function shouldHideDetailField(label: string, sourceKey = label): boolean {
  const normalizedLabel = label.toLowerCase().trim();
  const normalizedSource = sourceKey.toLowerCase().trim();
  const combined = `${normalizedSource} ${normalizedLabel}`;
  const isPasskeyInternalField =
    normalizedSource.includes("kpex_passkey_")
    || combined.includes("kpex passkey")
    || (combined.includes("passkey")
      && (
        combined.includes("credential id")
        || combined.includes("relying party")
        || combined.includes("user handle")
        || combined.includes("private key")
        || combined.includes("username")
      ));

  return normalizedSource === "lp_social_provider"
    || normalizedSource === "lp_social_label"
    || normalizedLabel === "otp"
    || normalizedLabel === "totp"
    || normalizedSource === "otp"
    || normalizedSource === "totp"
    || combined.includes("otp auth")
    || combined.includes("otpauth")
    || combined.includes("time otp")
    || combined.includes("totp secret")
    || combined.includes("base32")
    || combined.includes("attachment")
    || isPasskeyInternalField;
}

function isVisibleTotpDetailField(label: string, value: string): boolean {
  if (!itemDetailHasValue(value)) return false;
  const normalized = normalizeValue(label);
  return /(^otp$|^totp$|one time|one-time|authenticator)/i.test(normalized)
    && !/secret|seed|base32|time otp|timeotp|otpauth/i.test(label);
}

function isLikelySecretDetailField(label: string): boolean {
  return /password|passphrase|sensitive|secret|token|api key|private key|cvc|cvv|cvn|security code|pin/i.test(label);
}

function isLikelyMonospaceDetailField(label: string, value: string): boolean {
  return isLikelySecretDetailField(label)
    || /key|token|code|number|fingerprint|license|uuid|id/i.test(label)
    || /^[A-Z0-9+/=_:-]{12,}$/i.test(value.trim());
}

async function resolveTotpDisplayValue(value: string): Promise<string> {
  const trimmed = value.trim();
  if (!trimmed) return "";
  const shouldCompute = trimmed.startsWith("otpauth://") || /^[A-Z2-7=\s]{16,}$/i.test(trimmed);
  if (!shouldCompute) return trimmed;
  return (await computeTotp(trimmed)) ?? trimmed;
}

function buildItemDetailFields(entry: EntryDetail): {
  fields: ItemDetailField[];
  totpFields: ItemDetailField[];
} {
  const fields: ItemDetailField[] = [];
  const totpFields: ItemDetailField[] = [];
  const customFields = (entry.customFields ?? [])
    .map((field, index) => ({ ...field, index }))
    .filter((field) => itemDetailHasValue(field.value));
  const consumed = new Set<number>();
  let nextIndex = 0;

  const nextKey = (label: string) => `${normalizeLookupKey(label) || "field"}-${nextIndex++}`;
  const hasLabel = (label: string) => fields.some(
    (field) => normalizeLookupKey(field.label) === normalizeLookupKey(label),
  );

  const addField = (
    label: string,
    value: string | undefined | null,
    options: Partial<Omit<ItemDetailField, "key" | "label" | "value">> = {},
  ) => {
    if (!itemDetailHasValue(value)) return;
    fields.push({
      key: nextKey(label),
      label,
      value: value.trim(),
      multiline: value.includes("\n") || value.length > 72,
      monospace: isLikelyMonospaceDetailField(label, value),
      ...options,
    });
  };

  const addTotpField = (label: string, value: string | undefined | null) => {
    if (!itemDetailHasValue(value)) return;
    totpFields.push({
      key: nextKey(label),
      label,
      value: value.trim(),
      isTotp: true,
      monospace: true,
    });
  };

  const addMappedField = (
    label: string,
    matches: string[],
    options: Partial<Omit<ItemDetailField, "key" | "label" | "value">> & {
      valueTransformer?: (value: string) => string;
    } = {},
  ) => {
    for (const field of customFields) {
      if (consumed.has(field.index)) continue;
      if (shouldHideDetailField(field.label)) continue;
      const haystack = normalizeLookupKey(`${field.label} ${field.value}`);
      const matched = matches.some((match) => haystack.includes(normalizeLookupKey(match)));
      if (!matched) continue;

      consumed.add(field.index);
      const { valueTransformer, ...rowOptions } = options;
      addField(label, valueTransformer ? valueTransformer(field.value) : field.value, {
        secret: rowOptions.secret || field.secret || isLikelySecretDetailField(field.label),
        ...rowOptions,
      });
      return;
    }
  };

  const addStandardWebsite = () => addField("Website", entry.url, { openUrl: true });
  const addStandardUsername = (label = "Username") => addField(label, entry.username);
  const addStandardPassword = (label = "Password") => addField(label, entry.password, {
    secret: true,
    monospace: true,
  });

  const visibleTotpCustomFields = customFields.filter((field) => {
    const visible = isVisibleTotpDetailField(field.label, field.value);
    if (visible) consumed.add(field.index);
    return visible;
  });
  const featuredTotps = buildFeaturedTotps({
    standardTotp: entry.totp,
    standardLabel: "One-time password",
    customFields: visibleTotpCustomFields,
    isCustomTotpField: () => true,
    customLabel: (field) => displayLabelForDetailField(field.label),
  });

  for (const field of featuredTotps) {
    addTotpField(field.label, field.totp);
  }

  switch (entry.kind) {
    case "credit-card":
      addMappedField("Cardholder", ["cardholder", "name on card", "cardholder name", "card holder"]);
      if (!hasLabel("Cardholder")) addStandardUsername("Cardholder");
      addMappedField("Card Number", ["card number", "card no", "credit card number", "cc number", "pan"], {
        monospace: true,
      });
      addMappedField("Expiry Date", ["expiry", "expiration", "exp date", "valid thru", "valid through"], {
        valueTransformer: formatDetailCardDate,
      });
      addMappedField("Valid From", ["valid from"], { valueTransformer: formatDetailCardDate });
      addMappedField("CVC", ["cvc", "cvv", "cvn", "security code"], {
        secret: true,
        monospace: true,
      });
      addMappedField("PIN", ["pin"], { secret: true, monospace: true });
      addStandardWebsite();
      break;
    case "identity":
      addMappedField("Full Name", ["full name", "name"]);
      if (!hasLabel("Full Name")) addStandardUsername("Full Name");
      addMappedField("Email", ["email", "e-mail"]);
      addMappedField("Phone", ["phone", "mobile", "telephone"]);
      addMappedField("Address", ["address", "street", "city", "postal"]);
      addMappedField("ID Number", ["id number", "identity number", "driver license", "driver licence"], {
        monospace: true,
      });
      addStandardWebsite();
      break;
    case "ssh-key":
      addMappedField("Private Key", ["private key", "ssh key", "pem", "openssh"], {
        secret: true,
        multiline: true,
        monospace: true,
      });
      addMappedField("Public Key", ["public key", "authorized key"], {
        multiline: true,
        monospace: true,
      });
      addMappedField("Passphrase", ["passphrase"], { secret: true, monospace: true });
      addMappedField("Fingerprint", ["fingerprint"], { monospace: true });
      addStandardWebsite();
      addStandardUsername();
      break;
    case "secure-note":
      addStandardWebsite();
      break;
    default:
      addStandardWebsite();
      addStandardUsername();
      addStandardPassword();
      break;
  }

  for (const field of customFields) {
    if (consumed.has(field.index)) continue;
    if (shouldHideDetailField(field.label)) continue;
    addField(displayLabelForDetailField(field.label), field.value, {
      secret: field.secret || isLikelySecretDetailField(field.label),
      multiline: field.value.includes("\n") || field.value.length > 72,
      monospace: isLikelyMonospaceDetailField(field.label, field.value),
    });
  }

  if (itemDetailHasValue(entry.notes)) {
    addField("Notes", entry.notes, { multiline: true });
  }
  if ((entry.tags ?? []).length > 0) {
    addField("Tags", entry.tags!.join(", "));
  }
  if (itemDetailHasValue(entry.createdAt)) {
    addField("Created", formatDetailDate(entry.createdAt));
  }
  if (itemDetailHasValue(entry.updatedAt)) {
    addField("Updated", formatDetailDate(entry.updatedAt));
  }

  return { fields, totpFields };
}

function itemDetailCopySvg(): string {
  return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>`;
}

function itemDetailCheckSvg(): string {
  return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`;
}

function itemDetailEyeSvg(hidden = false): string {
  return hidden
    ? `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M17.94 17.94A10.94 10.94 0 0 1 12 20C7 20 2.73 16.89 1 12a20.27 20.27 0 0 1 5.06-6.06"/><path d="M9.9 4.24A10.76 10.76 0 0 1 12 4c5 0 9.27 3.11 11 8a20.27 20.27 0 0 1-2.16 3.19"/><path d="M14.12 14.12a3 3 0 0 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>`
    : `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8Z"/><circle cx="12" cy="12" r="3"/></svg>`;
}

function itemDetailExternalSvg(): string {
  return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/></svg>`;
}

function itemDetailEditSvg(): string {
  return `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>`;
}

function itemDetailAvatarHtml(entry: EntryItem): string {
  const colour = seedColour(entry.title);
  const abbr = lpEscapeHtml(initials(entry.title));
  const faviconSrc = entry.favicon ? googleFaviconUrlForDisplay(entry.favicon, 128) : "";
  if (faviconSrc) {
    return `<div style="width:44px;height:44px;border-radius:12px;overflow:hidden;display:flex;align-items:center;justify-content:center;position:relative;flex-shrink:0;background:white;border:1px solid rgba(148,163,184,0.18);">
      <img src="${lpEscapeHtml(faviconSrc)}" alt="" style="width:44px;height:44px;object-fit:contain;background:white;" onerror="this.style.display='none';this.nextElementSibling.style.display='flex'" onload="if(this.naturalWidth<48||this.naturalHeight<48){this.style.display='none';this.nextElementSibling.style.display='flex'}" />
      <div style="display:none;position:absolute;inset:0;background:${colour};align-items:center;justify-content:center;color:white;font-size:14px;font-weight:800;">${abbr}</div>
    </div>`;
  }

  return `<div style="width:44px;height:44px;border-radius:12px;background:${colour};display:flex;align-items:center;justify-content:center;color:white;font-size:14px;font-weight:800;flex-shrink:0;">${abbr}</div>`;
}

function renderItemDetailRows(
  rows: ItemDetailField[],
  isDark: boolean,
  copyValues: Map<string, string>,
): string {
  const text = isDark ? "#f3f4f6" : "#111827";
  const subText = isDark ? "#9ca3af" : "#64748b";
  const brand = isDark ? "#a5b4fc" : "#444ce7";
  const hoverBg = isDark ? "#273244" : "#f8fafc";
  const rowBorder = isDark ? "#2f3a4a" : "#e2e8f0";

  return rows.map((field, index) => {
    copyValues.set(field.key, field.value);
    const valueHtml = field.secret
      ? "&bull;&bull;&bull;&bull;&bull;&bull;&bull;&bull;"
      : lpEscapeHtml(field.value);
    const valueStyle = field.multiline
      ? "white-space:pre-wrap;word-break:break-word;line-height:1.45;"
      : "white-space:nowrap;overflow:hidden;text-overflow:ellipsis;";
    const fontStyle = field.monospace
      ? "font-family:'SF Mono',SFMono-Regular,Consolas,monospace;letter-spacing:0.01em;"
      : "";
    const copyTitle = `Copy ${field.label}`;

    return `<div
      data-lp-copy-row="true"
      data-lp-copy-key="${lpEscapeHtml(field.key)}"
      role="button"
      tabindex="0"
      title="${lpEscapeHtml(copyTitle)}"
      style="display:flex;align-items:flex-start;gap:10px;padding:12px 14px;cursor:pointer;transition:background 0.12s;${index > 0 ? `border-top:1px solid ${rowBorder};` : ""}"
      onmouseenter="this.style.background='${hoverBg}'"
      onmouseleave="this.style.background='transparent'"
    >
      <div style="flex:1;min-width:0;">
        <div style="font-size:11px;font-weight:650;color:${brand};margin-bottom:4px;">${lpEscapeHtml(field.label)}</div>
        <div
          data-lp-value-key="${lpEscapeHtml(field.key)}"
          style="font-size:13px;color:${text};${valueStyle}${fontStyle}"
        >${valueHtml}</div>
      </div>
      <div style="display:flex;align-items:center;gap:2px;flex-shrink:0;margin-top:1px;color:${subText};">
        ${field.secret ? `<button
          type="button"
          data-lp-reveal-key="${lpEscapeHtml(field.key)}"
          aria-label="Reveal ${lpEscapeHtml(field.label)}"
          title="Reveal"
          style="width:28px;height:28px;border:none;border-radius:8px;background:transparent;color:inherit;display:flex;align-items:center;justify-content:center;cursor:pointer;padding:0;"
        >${itemDetailEyeSvg()}</button>` : ""}
        ${field.openUrl ? `<button
          type="button"
          data-lp-open-key="${lpEscapeHtml(field.key)}"
          aria-label="Open ${lpEscapeHtml(field.label)}"
          title="Open"
          style="width:28px;height:28px;border:none;border-radius:8px;background:transparent;color:inherit;display:flex;align-items:center;justify-content:center;cursor:pointer;padding:0;"
        >${itemDetailExternalSvg()}</button>` : ""}
        <button
          type="button"
          data-lp-copy-button="true"
          data-lp-copy-key="${lpEscapeHtml(field.key)}"
          aria-label="${lpEscapeHtml(copyTitle)}"
          title="${lpEscapeHtml(copyTitle)}"
          style="width:28px;height:28px;border:none;border-radius:8px;background:transparent;color:inherit;display:flex;align-items:center;justify-content:center;cursor:pointer;padding:0;"
        >${itemDetailCopySvg()}</button>
      </div>
    </div>`;
  }).join("");
}

function renderTotpDetailRows(
  rows: ItemDetailField[],
  isDark: boolean,
  copyValues: Map<string, string>,
): string {
  if (rows.length === 0) return "";

  const cardBg = isDark ? "linear-gradient(135deg,#064e3b,#111827)" : "linear-gradient(135deg,#ecfdf5,#ffffff)";
  const border = isDark ? "#065f46" : "#bbf7d0";
  const labelColor = isDark ? "#6ee7b7" : "#059669";
  const text = isDark ? "#f0fdf4" : "#064e3b";
  const subText = isDark ? "#a7f3d0" : "#047857";

  return `<div style="display:grid;gap:10px;">
    ${rows.map((row) => {
      copyValues.set(row.key, row.value);
      const initialValue = row.value.startsWith("otpauth://") ? "......" : row.value;
      return `<div style="border:1px solid ${border};border-radius:13px;background:${cardBg};padding:13px 14px;box-shadow:0 1px 2px rgba(15,23,42,0.04);">
        <div style="display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:9px;">
          <div style="font-size:10px;font-weight:800;text-transform:uppercase;letter-spacing:0.12em;color:${labelColor};">${lpEscapeHtml(row.label)}</div>
          <button
            type="button"
            data-lp-copy-button="true"
            data-lp-copy-key="${lpEscapeHtml(row.key)}"
            style="display:inline-flex;align-items:center;gap:5px;border:1px solid ${border};border-radius:8px;background:${isDark ? "#0f172a" : "#ffffff"};color:${subText};padding:5px 8px;font-size:11px;font-weight:700;cursor:pointer;"
          >${itemDetailCopySvg()} Copy</button>
        </div>
        <div style="display:flex;align-items:center;gap:12px;">
          <div
            data-lp-totp-value="true"
            data-lp-totp-key="${lpEscapeHtml(row.key)}"
            style="flex:1;min-width:0;font-family:'SF Mono',SFMono-Regular,Consolas,monospace;font-size:26px;line-height:1;font-weight:800;letter-spacing:0.16em;color:${text};"
          >${lpEscapeHtml(initialValue)}</div>
          <div
            data-lp-totp-countdown="true"
            style="width:34px;height:34px;border-radius:999px;border:2px solid ${border};display:flex;align-items:center;justify-content:center;color:${subText};font-size:11px;font-weight:800;flex-shrink:0;"
          >${totpCountdown()}</div>
        </div>
      </div>`;
    }).join("")}
  </div>`;
}

function renderItemDetailModalShell(
  entry: EntryDetail,
  options: {
    loading?: boolean;
    error?: string;
  } = {},
): { html: string; copyValues: Map<string, string> } {
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#111827" : "#ffffff";
  const panelBg = isDark ? "#1f2937" : "#ffffff";
  const border = isDark ? "#374151" : "#e5e7eb";
  const rowBorder = isDark ? "#2f3a4a" : "#eef2f7";
  const text = isDark ? "#f3f4f6" : "#111827";
  const subText = isDark ? "#9ca3af" : "#64748b";
  const mutedBg = isDark ? "#0f172a" : "#f8fafc";
  const copyValues = new Map<string, string>();
  const domain = entry.url ? extractDomain(entry.url) : "";
  const subtitle = domain || entry.subtitle || formatItemKind(entry.kind);
  const { fields, totpFields } = buildItemDetailFields(entry);
  const rowsHtml = renderItemDetailRows(fields, isDark, copyValues);
  const totpHtml = renderTotpDetailRows(totpFields, isDark, copyValues);

  let bodyHtml = "";
  if (options.loading) {
    bodyHtml = `<div style="padding:24px 16px;color:${subText};font-size:13px;text-align:center;">
      <span style="display:inline-block;width:16px;height:16px;border:2px solid ${border};border-top-color:#444ce7;border-radius:999px;animation:lp-spin 0.8s linear infinite;margin-right:8px;vertical-align:-3px;"></span>
      Loading item details...
    </div>`;
  } else if (options.error) {
    bodyHtml = `<div style="padding:22px 16px;color:${subText};font-size:13px;text-align:center;">
      ${lpEscapeHtml(options.error)}
    </div>`;
  } else {
    bodyHtml = `
      ${totpHtml}
      ${fields.length > 0
        ? `<div style="border:1px solid ${rowBorder};border-radius:13px;overflow:hidden;background:${panelBg};">
            ${rowsHtml}
          </div>`
        : totpFields.length === 0
          ? `<div style="padding:22px 16px;color:${subText};font-size:13px;text-align:center;">No item fields to show.</div>`
          : ""}
    `;
  }

  const html = `
    <div
      id="lp-detail-overlay"
      data-lp-prompt-modal="true"
      tabindex="-1"
      style="position:fixed;inset:0;z-index:2147483647;background:${isDark ? "rgba(2,6,23,0.42)" : "rgba(15,23,42,0.16)"};font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;pointer-events:auto;"
    >
      <div
        id="lp-detail-card"
        role="dialog"
        aria-modal="true"
        aria-label="LumenPass item details"
        style="position:fixed;top:20px;right:12px;width:min(390px,calc(100vw - 24px));max-height:min(760px,calc(100vh - 40px));display:flex;flex-direction:column;overflow:hidden;border:1px solid ${border};border-radius:16px;background:${bg};box-shadow:0 18px 60px rgba(15,23,42,0.30);animation:lp-slide-up 0.16s ease-out;"
      >
        <div style="display:flex;align-items:center;gap:12px;padding:14px 14px 13px;border-bottom:1px solid ${rowBorder};background:${panelBg};">
          ${itemDetailAvatarHtml(entry)}
          <div style="flex:1;min-width:0;">
            <div style="font-size:15px;font-weight:800;color:${text};line-height:1.25;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${lpEscapeHtml(entry.title)}</div>
            <div style="font-size:12px;color:${subText};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:2px;">${lpEscapeHtml(subtitle)}</div>
          </div>
          <button
            id="lp-detail-close"
            type="button"
            aria-label="Close"
            title="Close"
            style="width:32px;height:32px;border:1px solid ${border};border-radius:10px;background:${mutedBg};color:${subText};font-size:20px;line-height:1;display:flex;align-items:center;justify-content:center;cursor:pointer;padding:0;flex-shrink:0;"
          >&times;</button>
        </div>
        <div class="lp-scroll" style="flex:1 1 auto;overflow-y:auto;overflow-x:hidden;min-height:0;padding:14px;display:grid;gap:12px;overscroll-behavior:contain;">
          ${bodyHtml}
        </div>
        <div style="display:flex;flex-direction:column;gap:10px;padding:10px 14px 14px;border-top:1px solid ${rowBorder};background:${panelBg};">
          <div id="lp-detail-toast" style="min-height:18px;color:${subText};font-size:12px;font-weight:650;text-align:center;"></div>
          <div style="display:flex;align-items:center;justify-content:flex-end;gap:10px;">
            <button
              id="lp-detail-bottom-close"
              type="button"
              style="min-width:84px;height:36px;border:1px solid ${border};border-radius:10px;background:${mutedBg};color:${text};font-size:13px;font-weight:750;cursor:pointer;padding:0 14px;"
            >Close</button>
            <button
              id="lp-detail-edit"
              type="button"
              style="min-width:92px;height:36px;border:none;border-radius:10px;background:#444ce7;color:white;font-size:13px;font-weight:800;cursor:pointer;padding:0 14px;display:inline-flex;align-items:center;justify-content:center;gap:7px;"
            >${itemDetailEditSvg()} Edit</button>
          </div>
        </div>
      </div>
    </div>`;

  return { html, copyValues };
}

function hideItemDetailModal(): void {
  itemDetailLoadToken++;
  if (itemDetailCopiedTimer !== null) {
    window.clearTimeout(itemDetailCopiedTimer);
    itemDetailCopiedTimer = null;
  }
  if (itemDetailTotpTimer !== null) {
    window.clearInterval(itemDetailTotpTimer);
    itemDetailTotpTimer = null;
  }
  itemDetailModalEl?.remove();
  itemDetailModalEl = null;
}

function showItemDetailToast(message: string, success = true): void {
  const toast = itemDetailModalEl?.querySelector<HTMLDivElement>("#lp-detail-toast");
  if (!toast) return;
  toast.textContent = message;
  toast.style.color = success ? "#10b981" : "#ef4444";

  if (itemDetailCopiedTimer !== null) {
    window.clearTimeout(itemDetailCopiedTimer);
  }
  itemDetailCopiedTimer = window.setTimeout(() => {
    toast.textContent = "";
    itemDetailCopiedTimer = null;
  }, 1600);
}

function attachItemDetailModalEvents(
  entry: EntryDetail,
  copyValues: Map<string, string>,
): void {
  if (!itemDetailModalEl) return;

  const overlay = itemDetailModalEl.querySelector<HTMLDivElement>("#lp-detail-overlay");
  const closeButton = itemDetailModalEl.querySelector<HTMLButtonElement>("#lp-detail-close");
  const bottomCloseButton = itemDetailModalEl.querySelector<HTMLButtonElement>("#lp-detail-bottom-close");
  const editButton = itemDetailModalEl.querySelector<HTMLButtonElement>("#lp-detail-edit");

  overlay?.focus({ preventScroll: true });
  overlay?.addEventListener("click", (event) => {
    if (event.target === overlay) hideItemDetailModal();
  });
  overlay?.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      event.preventDefault();
      hideItemDetailModal();
    }
  });
  closeButton?.addEventListener("click", () => hideItemDetailModal());
  bottomCloseButton?.addEventListener("click", () => hideItemDetailModal());
  editButton?.addEventListener("click", async () => {
    const id = entry.id?.trim();
    if (!id) {
      showItemDetailToast("Could not open editor", false);
      return;
    }

    const previous = editButton.innerHTML;
    editButton.disabled = true;
    editButton.style.opacity = "0.72";
    editButton.style.cursor = "default";
    editButton.textContent = "Opening...";

    try {
      const response = await browser.runtime.sendMessage({
        type: "OPEN_EDIT_ITEM",
        payload: { id },
      }) as { ok?: boolean; error?: string } | undefined;
      if (response?.ok) {
        hideItemDetailModal();
        return;
      }
      showItemDetailToast(response?.error ?? "Could not open editor", false);
    } catch {
      showItemDetailToast("Could not open editor", false);
    }

    editButton.disabled = false;
    editButton.style.opacity = "1";
    editButton.style.cursor = "pointer";
    editButton.innerHTML = previous;
  });

  const copyByKey = async (key: string, button?: HTMLElement): Promise<void> => {
    const rawValue = copyValues.get(key) ?? "";
    const isTotp = !!itemDetailModalEl?.querySelector(`[data-lp-totp-key="${CSS.escape(key)}"]`);
    const value = isTotp
      ? await resolveTotpDisplayValue(rawValue)
      : rawValue;
    if (!value) return;

    const ok = await copyTextToClipboard(value);
    if (button) {
      const previous = button.innerHTML;
      button.innerHTML = ok ? itemDetailCheckSvg() : itemDetailCopySvg();
      window.setTimeout(() => { button.innerHTML = previous; }, 1200);
    }
    showItemDetailToast(ok ? "Copied" : "Copy failed", ok);
  };

  itemDetailModalEl.querySelectorAll<HTMLElement>("[data-lp-copy-button]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      const key = button.dataset.lpCopyKey;
      if (key) void copyByKey(key, button);
    });
  });

  itemDetailModalEl.querySelectorAll<HTMLElement>("[data-lp-copy-row]").forEach((row) => {
    row.addEventListener("click", (event) => {
      const target = event.target instanceof Element ? event.target : null;
      if (target?.closest("button,a")) return;
      const key = row.dataset.lpCopyKey;
      if (key) void copyByKey(key);
    });
    row.addEventListener("keydown", (event) => {
      if (event.key !== "Enter" && event.key !== " ") return;
      const target = event.target instanceof Element ? event.target : null;
      if (target?.closest("button,a")) return;
      event.preventDefault();
      const key = row.dataset.lpCopyKey;
      if (key) void copyByKey(key);
    });
  });

  itemDetailModalEl.querySelectorAll<HTMLButtonElement>("[data-lp-reveal-key]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      const key = button.dataset.lpRevealKey;
      if (!key) return;
      const valueEl = itemDetailModalEl?.querySelector<HTMLElement>(`[data-lp-value-key="${CSS.escape(key)}"]`);
      if (!valueEl) return;
      const revealed = button.dataset.revealed === "true";
      button.dataset.revealed = revealed ? "false" : "true";
      button.title = revealed ? "Reveal" : "Hide";
      button.setAttribute("aria-label", revealed ? "Reveal value" : "Hide value");
      button.innerHTML = itemDetailEyeSvg(!revealed);
      valueEl.textContent = revealed ? "••••••••" : (copyValues.get(key) ?? "");
      valueEl.style.whiteSpace = revealed ? "nowrap" : "pre-wrap";
      valueEl.style.wordBreak = revealed ? "" : "break-word";
    });
  });

  itemDetailModalEl.querySelectorAll<HTMLButtonElement>("[data-lp-open-key]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      const key = button.dataset.lpOpenKey;
      const url = key ? copyValues.get(key) : "";
      if (url) window.open(url, "_blank", "noopener,noreferrer");
    });
  });
}

function startItemDetailTotpTimer(copyValues: Map<string, string>): void {
  if (itemDetailTotpTimer !== null) {
    window.clearInterval(itemDetailTotpTimer);
    itemDetailTotpTimer = null;
  }

  const tick = async () => {
    if (!itemDetailModalEl) return;
    const countdown = String(totpCountdown());
    itemDetailModalEl.querySelectorAll<HTMLElement>("[data-lp-totp-countdown]").forEach((el) => {
      el.textContent = countdown;
    });
    const valueEls = Array.from(itemDetailModalEl.querySelectorAll<HTMLElement>("[data-lp-totp-value]"));
    await Promise.all(valueEls.map(async (el) => {
      const key = el.dataset.lpTotpKey;
      const raw = key ? copyValues.get(key) : "";
      if (!raw) return;
      const display = await resolveTotpDisplayValue(raw);
      el.textContent = display.length === 6 ? `${display.slice(0, 3)} ${display.slice(3)}` : display;
    }));
  };

  void tick();
  itemDetailTotpTimer = window.setInterval(() => { void tick(); }, 1000);
}

function renderItemDetailModal(entry: EntryDetail, options?: { loading?: boolean; error?: string }): void {
  ensureOverlayStyles();
  const { html, copyValues } = renderItemDetailModalShell(entry, options);
  if (!itemDetailModalEl) {
    itemDetailModalEl = document.createElement("div");
    lpAppend(itemDetailModalEl);
  }
  itemDetailModalEl.innerHTML = html;
  attachItemDetailModalEvents(entry, copyValues);
  startItemDetailTotpTimer(copyValues);
}

async function showItemDetailModal(entry: EntryItem): Promise<void> {
  hidePopup();
  dismissLoginAutofillPrompt();
  hideItemDetailModal();

  const token = ++itemDetailLoadToken;
  const initialEntry = mergeEntryDetail(entry);
  renderItemDetailModal(initialEntry, { loading: true });

  try {
    const detail = await loadEntryDetail(entry);
    if (token !== itemDetailLoadToken) return;
    renderItemDetailModal(mergeEntryDetail(entry, detail));
  } catch {
    if (token !== itemDetailLoadToken) return;
    renderItemDetailModal(initialEntry, { error: "Could not load item details." });
  }
}

// ─── Entry fill ───────────────────────────────────────────────────────────────

async function loadEntryDetail(entry: EntryItem): Promise<EntryDetail> {
  if (!entry.password || entry.kind === "credit-card" || entry.kind === "identity") {
    try {
      const res = await browser.runtime.sendMessage({ type: "GET_ENTRY", payload: { id: entry.id } });
      if (res?.ok && res.data) return res.data as EntryDetail;
    } catch {
      // proceed with the entry payload we already have
    }
  }

  return entry as EntryDetail;
}

function getCustomFieldMap(entry: EntryDetail): Map<string, string> {
  const map = new Map<string, string>();

  for (const field of entry.customFields ?? []) {
    const normalizedKey = normalizeLookupKey(field.label);
    if (!normalizedKey || map.has(normalizedKey)) continue;
    map.set(normalizedKey, field.value);
  }

  if (entry.username) {
    map.set(normalizeLookupKey("username"), entry.username);
    map.set(normalizeLookupKey("full name"), entry.username);
  }

  if (entry.url) {
    map.set(normalizeLookupKey("url"), entry.url);
  }

  return map;
}

function getEntryValue(fieldMap: Map<string, string>, ...labels: string[]): string {
  for (const label of labels) {
    const value = fieldMap.get(normalizeLookupKey(label));
    if (value) return value;
  }
  return "";
}

function compactLookupValue(value: string): string {
  return normalizeValue(value).replace(/[^a-z0-9]+/g, "");
}

function inferCardTypeFromNumber(rawNumber: string): string {
  const digits = rawNumber.replace(/\D+/g, "");
  if (!digits) return "";
  if (/^4/.test(digits)) return "Visa";
  if (/^(5[1-5]|2(?:2[2-9]|[3-6]\d|7[01]|720))/.test(digits)) return "Mastercard";
  if (/^3[47]/.test(digits)) return "American Express";
  if (/^(6011|65|64[4-9]|622(?:12[6-9]|1[3-9]\d|[2-8]\d\d|9[01]\d|92[0-5]))/.test(digits)) return "Discover";
  if (/^3(?:0[0-5]|[68])/.test(digits)) return "Diners Club";
  if (/^35/.test(digits)) return "JCB";
  if (/^62/.test(digits)) return "UnionPay";
  if (/^(50|5[6-9]|6\d)/.test(digits)) return "Maestro";
  return "";
}

function getCardTypeCandidates(storedType: string, cardNumber: string): string[] {
  const rawType = storedType.trim() || inferCardTypeFromNumber(cardNumber);
  if (!rawType) return [];

  const normalizedType = compactLookupValue(rawType);
  const candidates = [rawType];
  const addAliases = (...aliases: string[]) => candidates.push(...aliases);

  if (/visa/.test(normalizedType)) addAliases("Visa");
  if (/master/.test(normalizedType)) addAliases("Mastercard", "Master Card", "Master");
  if (/americanexpress|amex/.test(normalizedType)) addAliases("American Express", "Amex", "AMEX");
  if (/discover/.test(normalizedType)) addAliases("Discover");
  if (/diners/.test(normalizedType)) addAliases("Diners Club", "Diners");
  if (/jcb/.test(normalizedType)) addAliases("JCB");
  if (/unionpay/.test(normalizedType)) addAliases("UnionPay", "Union Pay");
  if (/maestro/.test(normalizedType)) addAliases("Maestro");

  return Array.from(new Set(candidates.filter((candidate) => candidate.trim().length > 0)));
}

function findFillTarget(
  fields: FillableField[],
  {
    autocomplete,
    matcher,
    exclude = new Set<FillableField>(),
  }: {
    autocomplete?: string[];
    matcher?: RegExp;
    exclude?: Set<FillableField>;
  },
): FillableField | null {
  if (autocomplete && autocomplete.length > 0) {
    for (const field of fields) {
      if (exclude.has(field)) continue;
      if (autocomplete.includes(getFieldAutocomplete(field))) return field;
    }
  }

  if (matcher) {
    for (const field of fields) {
      if (exclude.has(field)) continue;
      if (field instanceof HTMLInputElement && isPasswordField(field)) continue;
      if (matcher.test(getFieldDescriptor(field))) return field;
    }
  }

  return null;
}

function fillMatchingField(
  fields: FillableField[],
  usedFields: Set<FillableField>,
  value: string | string[],
  {
    autocomplete,
    matcher,
  }: {
    autocomplete?: string[];
    matcher?: RegExp;
  },
): boolean {
  const candidates = Array.isArray(value) ? value : [value];
  const normalizedCandidates = candidates.filter((candidate) => candidate.trim().length > 0);
  if (normalizedCandidates.length === 0) return false;

  const field = findFillTarget(fields, { autocomplete, matcher, exclude: usedFields });
  if (!field) return false;

  for (const candidate of normalizedCandidates) {
    if (simulateFill(field, candidate)) {
      usedFields.add(field);
      autofilledFields.add(field);
      return true;
    }
  }

  return false;
}

type PostalAddressValues = {
  address1?: string;
  address2?: string;
  city?: string;
  state?: string;
  postalCode?: string;
  country?: string;
};

async function fillPostalAddressFields(
  getFields: () => FillableField[],
  usedFields: Set<FillableField>,
  {
    address1,
    address2,
    city,
    state,
    postalCode,
    country,
  }: PostalAddressValues,
  options: {
    allowAddressLine1CityFallback?: boolean;
  } = {},
): Promise<void> {
  const fillWithCurrentFields = (
    value: string | string[],
    config: {
      autocomplete?: string[];
      matcher?: RegExp;
    },
  ): boolean => fillMatchingField(getFields(), usedFields, value, config);

  const countryFilled = !!country && fillWithCurrentFields(country, {
    autocomplete: ["country", "country-name"],
    matcher: /^country$|country.?name|country.?or.?region|region.?country|country.?region/,
  });

  // Stripe and similar checkouts often re-render locality/state options after country changes.
  if (countryFilled) {
    await new Promise<void>((resolve) => window.setTimeout(resolve, 80));
  }

  if (address1) {
    fillWithCurrentFields(address1, {
      autocomplete: ["street-address", "address-line1"],
      matcher: /^address$|billing.?address|street.?address|address.?line.?1|^street$|street(?!.*2)/,
    });
  }
  if (address2) {
    fillWithCurrentFields(address2, {
      autocomplete: ["address-line2"],
      matcher: /address.?line.?2|address.?2|billing.?address.?2|apartment|suite|unit|building/,
    });
  }
  if (city) {
    const filledCity = fillWithCurrentFields(city, {
      autocomplete: ["address-level2"],
      matcher: /^city$|^town$|town.?city|municipality|suburb|locality/,
    });
    if (!filledCity && options.allowAddressLine1CityFallback) {
      fillWithCurrentFields(city, {
        autocomplete: ["address-line1"],
        matcher: /^city$|^town$|town.?city|municipality|suburb|locality/,
      });
    }
  }
  if (state) {
    fillWithCurrentFields(state, {
      autocomplete: ["address-level1"],
      matcher: /^state$|province|state.?or.?province|state.?or.?territory|region|county|district|prefecture|territory/,
    });
  }
  if (postalCode) {
    fillWithCurrentFields(postalCode, {
      autocomplete: ["postal-code"],
      matcher: /^zip$|zip.?code|postal.?code|postcode|pin.?code/,
    });
  }
}

async function fillCreditCardEntry(entry: EntryItem): Promise<void> {
  hidePopup();
  suppressPopupOpen = true;

  const fullEntry = await loadEntryDetail(entry);
  const fieldMap = getCustomFieldMap(fullEntry);
  const cardNumber = getEntryValue(fieldMap, "Card Number", "Number", "PAN");
  const cvc = getEntryValue(
    fieldMap,
    "CVC",
    "CVV",
    "CVN",
    "CSC",
    "CID",
    "Security Code",
    "Security Number",
    "Verification Number",
    "Verification Code",
    "Card Verification Code",
  );
  const expiryRaw = getEntryValue(
    fieldMap,
    "Expiry Date",
    "Expiration Date",
    "Expiration",
    "Exp Date",
    "Date Exp",
    "Valid Thru",
    "Valid Through",
  );
  const cardholder = getEntryValue(
    fieldMap,
    "Cardholder Name",
    "Cardholder",
    "Card Holder",
    "Name on Card",
    "Card Name",
    "Card User Name",
    "CC Name",
    "CC UName",
    "Full Name",
    "Username",
  );
  const cardType = getEntryValue(
    fieldMap,
    "Card Type",
    "Credit Card Type",
    "Type",
    "Brand",
    "Card Brand",
    "Network",
    "Payment Network",
  );
  const address1 = getEntryValue(
    fieldMap,
    "Billing Address",
    "Billing Street Address",
    "Street Address",
    "Address Line 1",
    "Address",
    "Street",
  );
  const address2 = getEntryValue(
    fieldMap,
    "Billing Address Line 2",
    "Address Line 2",
    "Apartment",
    "Suite",
    "Unit",
  );
  const city = getEntryValue(fieldMap, "Billing City", "City", "Town");
  const state = getEntryValue(fieldMap, "Billing State", "Billing Province", "State", "Province", "Region");
  const postalCode = getEntryValue(
    fieldMap,
    "Billing Postal Code",
    "Billing Zip",
    "Postal Code",
    "Zip",
    "Zip Code",
    "Postcode",
  );
  const country = getEntryValue(
    fieldMap,
    "Billing Country",
    "Billing Country or Region",
    "Country",
    "Country Name",
  );
  const cardTypeCandidates = getCardTypeCandidates(cardType, cardNumber);

  const getScopeFields = () => activeAutofillField
    ? getFieldScopeFillFields(activeAutofillField)
    : getVisibleFillFields();
  const scopeFields = getScopeFields();
  const usedFields = new Set<FillableField>();

  if (cardTypeCandidates.length > 0) {
    fillMatchingField(scopeFields, usedFields, cardTypeCandidates, {
      autocomplete: ["cc-type"],
      matcher: /cc.?type|card.?type|credit.?card.?type|payment.?type|card.?brand|card.?network|\btype\b/,
    });
  }
  if (cardNumber) {
    fillMatchingField(scopeFields, usedFields, cardNumber, {
      autocomplete: ["cc-number"],
      matcher: CARD_NUMBER_DESCRIPTOR_PATTERN,
    });
  }
  if (cvc) {
    fillMatchingField(scopeFields, usedFields, cvc, {
      autocomplete: ["cc-csc"],
      matcher: /^cvv$|^cvc$|^cvn$|^csc$|^cid$|cvv2|cc.?csc|card.?cvv|card.?cvc|card.?verification|security.?code|security.?number|verification.?number|verification.?code|^ccv$/,
    });
  }
  if (cardholder) {
    fillMatchingField(scopeFields, usedFields, cardholder, {
      autocomplete: ["cc-name"],
      matcher: /cardholder|card.?holder|card.?user.?name|card.?owner|billing.?name|cc.?uname|cc.?name|name.?on.?card|card.?name/,
    });
  }
  if (expiryRaw) {
    const expiry = parseCardExpiry(expiryRaw);
    if (expiry) {
      const shortYear = expiry.year.substring(2);
      if (!fillMatchingField(scopeFields, usedFields, [
        `${expiry.month}/${shortYear}`,
        `${expiry.month} / ${shortYear}`,
        `${expiry.month}${shortYear}`,
      ], {
        autocomplete: ["cc-exp"],
        matcher: CARD_EXPIRY_DESCRIPTOR_PATTERN,
      })) {
        fillMatchingField(scopeFields, usedFields, [expiry.month, String(parseInt(expiry.month, 10))], {
          autocomplete: ["cc-exp-month"],
          matcher: /exp.?month|cc.?exp.?month|cc.?exp.?(mm|mo)|card.?month|card.?exp.?(mm|mo)|expiry.?month|expiry.?(mm|mo)|\bexp.?mm\b|\bccexp.?mm\b/,
        });
        fillMatchingField(scopeFields, usedFields, [expiry.year, expiry.year.substring(2)], {
          autocomplete: ["cc-exp-year"],
          matcher: /exp.?year|cc.?exp.?year|cc.?exp.?(yy|yyyy)|card.?year|card.?exp.?(yy|yyyy)|expiry.?year|expiry.?(yy|yyyy)|\bexp.?yy\b|\bccexp.?yy\b/,
        });
      }
    }
  }

  await fillPostalAddressFields(getScopeFields, usedFields, {
    address1,
    address2,
    city,
    state,
    postalCode,
    country,
  });

  window.setTimeout(() => { suppressPopupOpen = false; }, 250);
}

async function fillIdentityEntry(entry: EntryItem): Promise<void> {
  hidePopup();
  suppressPopupOpen = true;

  const fullEntry = await loadEntryDetail(entry);
  const fieldMap = getCustomFieldMap(fullEntry);

  const firstName = getEntryValue(fieldMap, "First Name", "Given Name");
  const middleName = getEntryValue(fieldMap, "Middle Name", "Additional Name", "Initial", "Middle Initial");
  const lastName = getEntryValue(fieldMap, "Last Name", "Family Name", "Surname");
  const fullName = getEntryValue(fieldMap, "Full Name", "Name", "Username")
    || [firstName, middleName, lastName].filter(Boolean).join(" ");
  const prefix = getEntryValue(fieldMap, "Honorific Prefix", "Prefix", "Title");
  const company = getEntryValue(fieldMap, "Company", "Organization");
  const email = getEntryValue(fieldMap, "Email", "E-mail");
  const phone = getEntryValue(
    fieldMap,
    "Default Phone",
    "Phone",
    "Phone Number",
    "Telephone",
    "Tel",
    "Mobile",
    "Home",
    "Cell",
    "Business",
  );
  const address1 = getEntryValue(fieldMap, "Street Address", "Address Line 1", "Address", "Street");
  const address2 = getEntryValue(fieldMap, "Address Line 2", "Apartment", "Suite", "Unit");
  const city = getEntryValue(fieldMap, "City", "Town");
  const state = getEntryValue(fieldMap, "State", "Province", "Region");
  const postalCode = getEntryValue(fieldMap, "Postal Code", "Zip", "Zip Code", "Postcode");
  const country = getEntryValue(fieldMap, "Country", "Country Name");

  const getScopeFields = () => activeAutofillField
    ? getFieldScopeFillFields(activeAutofillField)
    : getVisibleFillFields();
  const scopeFields = getScopeFields();
  const usedFields = new Set<FillableField>();

  if (prefix) {
    fillMatchingField(scopeFields, usedFields, prefix, {
      autocomplete: ["honorific-prefix"],
      matcher: /honorific.?prefix|prefix|title/,
    });
  }
  if (fullName) {
    fillMatchingField(scopeFields, usedFields, fullName, {
      autocomplete: ["name", "cc-name"],
      matcher: /^name$|full.?name|your.?name|cardholder|cc.?name|name.?on.?card/,
    });
  }
  if (firstName) {
    fillMatchingField(scopeFields, usedFields, firstName, {
      autocomplete: ["given-name"],
      matcher: /first.?name|given.?name|forename|^f.?name$|^firstname$/,
    });
  }
  if (middleName) {
    fillMatchingField(scopeFields, usedFields, middleName, {
      autocomplete: ["additional-name"],
      matcher: /middle.?name|middle.?initial|additional.?name|^initial$/,
    });
  }
  if (lastName) {
    fillMatchingField(scopeFields, usedFields, lastName, {
      autocomplete: ["family-name"],
      matcher: /last.?name|family.?name|surname|^l.?name$|^lastname$/,
    });
  }
  if (company) {
    fillMatchingField(scopeFields, usedFields, company, {
      autocomplete: ["organization"],
      matcher: /^company$|^organization$|^organisation$|org.?name/,
    });
  }
  if (email) {
    fillMatchingField(scopeFields, usedFields, email, {
      autocomplete: ["email"],
      matcher: /^email$|e.?mail/,
    });
  }
  if (phone) {
    fillMatchingField(scopeFields, usedFields, phone, {
      autocomplete: ["tel"],
      matcher: /^phone$|phone.?number|telephone|^tel$|mobile|cell/,
    });
  }
  await fillPostalAddressFields(getScopeFields, usedFields, {
    address1,
    address2,
    city,
    state,
    postalCode,
    country,
  }, {
    allowAddressLine1CityFallback: true,
  });

  window.setTimeout(() => { suppressPopupOpen = false; }, 250);
}

async function fillEntry(entry: EntryItem): Promise<void> {
  if (entry.kind === "credit-card") {
    await fillCreditCardEntry(entry);
    return;
  }
  if (entry.kind === "identity") {
    await fillIdentityEntry(entry);
    return;
  }

  const initialAnchorField = getCurrentAutofillAnchor();

  hidePopup();
  suppressPopupOpen = true;

  const fullEntry = await loadEntryDetail(entry);

  const anchorField = initialAnchorField?.isConnected && isEditableInput(initialAnchorField)
    ? initialAnchorField
    : getCurrentAutofillAnchor();

  if (!(anchorField instanceof HTMLInputElement)) {
    suppressPopupOpen = false;
    return;
  }

  const passwordField = getPreferredPasswordField(anchorField);
  if (passwordField && fullEntry.password) {
    if (simulateFill(passwordField, fullEntry.password)) {
      const trimmedPw = fullEntry.password.trim();
      if (trimmedPw) {
        lastExtensionAutofillPasswordByField.set(passwordField, trimmedPw);
      }
      autofilledFields.add(passwordField);
    }
  }

  const usernameField = getPreferredUsernameField(anchorField);
  if (usernameField && fullEntry.username) {
    simulateFill(usernameField, fullEntry.username);
    autofilledFields.add(usernameField);
  }

  // TOTP
  if (fullEntry.totp) {
    const totpField = getTotpInputField();
    if (totpField) {
      simulateFill(totpField, fullEntry.totp);
      autofilledFields.add(totpField);
    }
  }

  if (autoSubmitEnabled) {
    const scope: ParentNode = anchorField.form ?? anchorField.closest("form") ?? document;
    window.setTimeout(() => {
      const btn = findSubmitButton(scope);
      btn?.click();
    }, 300);
  }

  hidePopup();
  window.setTimeout(() => {
    suppressPopupOpen = false;
  }, 250);
}

function dispatchFillEvents(el: HTMLElement, value: string): void {
  el.dispatchEvent(new Event("focus", { bubbles: true }));
  try {
    el.dispatchEvent(new InputEvent("beforeinput", { bubbles: true, cancelable: true, inputType: "insertText", data: value }));
  } catch {
    el.dispatchEvent(new Event("beforeinput", { bubbles: true }));
  }
  try {
    el.dispatchEvent(new InputEvent("input", { bubbles: true, cancelable: false, inputType: "insertText", data: value }));
  } catch {
    el.dispatchEvent(new Event("input", { bubbles: true }));
  }
  el.dispatchEvent(new Event("change", { bubbles: true }));
  el.dispatchEvent(new Event("blur", { bubbles: true }));
}

function setInputLikeValue(el: HTMLInputElement | HTMLTextAreaElement, value: string): void {
  const prototype = el instanceof HTMLTextAreaElement
    ? window.HTMLTextAreaElement.prototype
    : window.HTMLInputElement.prototype;
  const ownSetter = Object.getOwnPropertyDescriptor(el, "value")?.set;
  const prototypeSetter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;

  if (prototypeSetter && ownSetter !== prototypeSetter) {
    prototypeSetter.call(el, value);
  } else if (ownSetter) {
    ownSetter.call(el, value);
  } else {
    el.value = value;
  }
}

function isCardFormattedValueAccepted(el: HTMLInputElement, value: string): boolean {
  const autocomplete = getFieldAutocomplete(el);
  const descriptor = getFieldDescriptor(el);
  if (!ALL_CARD_AUTOCOMPLETE.has(autocomplete) && !CARD_FIELD_DESCRIPTOR_PATTERN.test(descriptor)) {
    return false;
  }

  return compactLookupValue(el.value) === compactLookupValue(value);
}

function fillInputLikeValue(el: HTMLInputElement | HTMLTextAreaElement, value: string): boolean {
  setInputLikeValue(el, value);
  dispatchFillEvents(el, value);

  if (el.value === value) return true;
  if (el instanceof HTMLInputElement && isCardFormattedValueAccepted(el, value)) return true;

  el.value = value;
  dispatchFillEvents(el, value);
  return el.value === value || (el instanceof HTMLInputElement && isCardFormattedValueAccepted(el, value));
}

function simulateFill(el: FillableField, value: string): boolean {
  const trimmedValue = value.trim();
  if (!trimmedValue) return false;

  el.focus();

  if (el instanceof HTMLSelectElement) {
    const options = Array.from(el.options);
    const matchIndex = findBestSelectOptionIndex(
      options.map((option) => ({
        text: option.textContent ?? "",
        value: option.value,
      })),
      trimmedValue,
    );
    if (matchIndex < 0) return false;

    const matched = options[matchIndex];

    el.value = matched.value;
    if (el.value !== matched.value) {
      el.selectedIndex = matchIndex;
    }
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    return true;
  }

  if (el instanceof HTMLTextAreaElement) {
    return fillInputLikeValue(el, trimmedValue);
  }

  return fillInputLikeValue(el, trimmedValue);
}

function findSubmitButton(scope: ParentNode = document): HTMLElement | null {
  // 1. Explicit submit button inside the scope
  const explicitSubmit = Array.from(
    scope.querySelectorAll<HTMLElement>("button[type='submit'], input[type='submit']"),
  ).filter(isVisible);
  if (explicitSubmit.length > 0) return explicitSubmit[0];

  // 2. Any visible button matching common "next/continue/login" labels
  const keywords = /next|continue|sign[\s-]?in|log[\s-]?in|proceed|submit|tiếp theo|đăng nhập/i;
  const labelledBtn = Array.from(scope.querySelectorAll<HTMLElement>("button, [role='button']"))
    .filter(isVisible)
    .find((el) => keywords.test(el.textContent ?? "") || keywords.test(el.getAttribute("aria-label") ?? ""));
  if (labelledBtn) return labelledBtn;

  // 3. First visible button in scope as last resort
  return Array.from(scope.querySelectorAll<HTMLElement>("button")).filter(isVisible)[0] ?? null;
}

/**
 * Auto-fills the username/email field on the current page with the passkey's
 * username, then clicks the primary submit button. Returns true if a field was
 * found and filled (regardless of whether a submit button existed).
 */
async function autofillUsernameAndSubmit(entry: PasskeyEntry): Promise<boolean> {
  if (!entry.username) return false;

  const usernameField = getVisibleInputs().find(
    (f) => f.type === "email" || isLikelyUsernameField(f),
  );
  if (!usernameField) return false;

  simulateFill(usernameField, entry.username);

  // Give the page's JS a moment to react to the input event before clicking submit
  await new Promise<void>((r) => setTimeout(r, 350));

  const scope: ParentNode = usernameField.form ?? usernameField.closest("form") ?? document;
  const submitBtn = findSubmitButton(scope);
  submitBtn?.click();

  return true;
}

// ─── Domain-matched search ────────────────────────────────────────────────────

async function fetchEntriesForPage(): Promise<void> {
  if (fetchController) fetchController.abort();
  fetchController = new AbortController();
  const currentToken = ++entriesSearchToken;

  try {
    let payload: Record<string, string>;
    let identifierQuery = "";
    if (activeFieldKind === "card" || activeFieldKind === "identity") {
      payload = { query: "", type: getEntrySearchType() };
    } else if (activeFieldKind === "identifier") {
      identifierQuery = activeAutofillField instanceof HTMLInputElement ? activeAutofillField.value.trim() : "";
      if (!identifierQuery && !identifierHintAllowsEmptyQuery) {
        entries = [];
        socialEntries = [];
        if (popupEl?.style.display === "block") renderPopupEntries();
        return;
      }
      payload = { query: "", type: getEntrySearchType() };
    } else {
      payload = { query: "", url: window.location.href };
    }
    const res = await browser.runtime.sendMessage({
      type: "SEARCH_ENTRIES",
      payload,
    });
    if (currentToken !== entriesSearchToken) return;
    if (res?.ok && Array.isArray(res.data)) {
      const rawEntries = (res.data as EntryItem[]).filter((entry) => entry.kind !== "passkey");
      const isSocial = (e: EntryItem): boolean => !!e.socialProvider || (e.password ?? "").startsWith("__social:");
      socialEntries = rawEntries.filter(isSocial);
      const nonSocial = rawEntries.filter((e) => !isSocial(e));
      const filteredEntries = nonSocial.filter((entry) => entryMatchesFieldKind(entry));
      entries = activeFieldKind === "identifier"
        ? dedupeIdentifierEntries(filteredEntries, identifierQuery)
        : filteredEntries;
      selectedIndex = 0;
      if (popupEl?.style.display === "block" && activeAutofillField) {
        renderPopupEntries();
      }
    }
  } catch {
    // Silently ignore (no connection, no token, etc.)
  }
}

// ─── Form detection + keyboard nav ───────────────────────────────────────────

async function openSuggestionsForField(field: FillableField, refresh = true, allowEmptyIdentifier = false): Promise<void> {
  if (suppressPopupOpen) return;
  if (isAutofillDisabledForCurrentDomain()) return;
  if (field instanceof HTMLInputElement && isSignupPasswordField(field)) return;
  activeAutofillField = field;
  activeFieldKind = detectFieldKind(field);
  if (activeFieldKind === "card" && shouldSuppressCardAutofillPopup(field)) {
    hidePopup();
    return;
  }
  identifierHintAllowsEmptyQuery = activeFieldKind === "identifier" && allowEmptyIdentifier;
  if (
    activeFieldKind === "identifier"
    && desktopConnected
    && desktopVaultOpen
    && (!(field instanceof HTMLInputElement) || !field.value.trim())
    && !identifierHintAllowsEmptyQuery
  ) {
    hidePopup();
    return;
  }
  proactiveLoginPromptShown = false;
  dismissLoginAutofillPrompt();
  popupSearchQuery = "";
  selectedIndex = 0;
  const icon = fieldIcons.get(field);
  if (icon) positionIconEl(field, icon);

  if (!desktopConnected || !desktopVaultOpen) {
    showPopup(field);
    return;
  }

  if (refresh) {
    await fetchEntriesForPage();
  }

  showPopup(field);
  if (activeFieldKind === "login" && socialEntries.length > 0) {
    maybeShowSocialFloatingSuggestion();
  }
}

function scheduleIdentifierHintSearch(field: HTMLInputElement): void {
  if (identifierHintDebounceTimer !== null) {
    window.clearTimeout(identifierHintDebounceTimer);
    identifierHintDebounceTimer = null;
  }

  if (!field.value.trim()) {
    identifierHintAllowsEmptyQuery = false;
    entries = [];
    if (activeAutofillField === field) hidePopup();
    return;
  }

  identifierHintDebounceTimer = window.setTimeout(() => {
    identifierHintDebounceTimer = null;
    if (!field.isConnected || !isEditableInput(field) || !isCredentialHintField(field)) return;
    void openSuggestionsForField(field);
  }, 180);
}

function attachToAutofillField(field: FillableField): void {
  attachIconToField(field);
  let wasFocusedOnMouseDown = false;

  field.addEventListener("focus", async () => {
    const isPasswordSuggestionField = field instanceof HTMLInputElement && isSignupPasswordField(field);
    const fieldKind = detectFieldKind(field);
    focusedFields.add(field);
    refreshIconForField(field);
    showIconForField(field);
    if (isPasswordSuggestionField) return;
    if (suppressPopupOpen) return;
    if (!hasUserInteracted) return;
    if (dismissedFields.has(field)) return;
    if (fieldKind === "identifier" && field instanceof HTMLInputElement && !field.value.trim()) return;
    if (fieldKind === "card" && shouldSuppressCardAutofillPopup(field)) return;
    // Don't auto-open on focus if field was autofilled by us
    if (autofilledFields.has(field)) return;
    await openSuggestionsForField(field);
  });

  field.addEventListener("blur", () => {
    focusedFields.delete(field);
    // Delay hiding so clicking the icon (which briefly blurs the field)
    // doesn't cause the icon to vanish before the click registers.
    window.setTimeout(() => {
      // If the popup is still open for this field, keep the icon visible.
      const popupVisible = popupEl && popupEl.style.display === "block" && activeAutofillField === field;
      if (!popupVisible && !focusedFields.has(field)) {
        hideIconForField(field);
      }
    }, 200);
  });

  field.addEventListener("mousedown", () => {
    wasFocusedOnMouseDown = document.activeElement === field;
  });

  field.addEventListener("click", () => {
    const isPasswordSuggestionField = field instanceof HTMLInputElement && isSignupPasswordField(field);
    const fieldKind = detectFieldKind(field);
    if (isPasswordSuggestionField) return;
    if (suppressPopupOpen) return;
    hasUserInteracted = true;
    refreshIconForField(field);
    if (!wasFocusedOnMouseDown) return;
    if (dismissedFields.has(field)) return;
    if (fieldKind === "identifier" && field instanceof HTMLInputElement && !field.value.trim()) return;
    if (fieldKind === "card" && shouldSuppressCardAutofillPopup(field)) return;
    // Don't auto-open on click if field was autofilled by us
    if (autofilledFields.has(field)) return;
    void openSuggestionsForField(field, entries.length === 0);
  });

  field.addEventListener("input", () => {
    // User is manually typing, remove from autofilled set
    autofilledFields.delete(field);
    refreshIconForField(field);
    if (suppressPopupOpen) return;
    if (detectFieldKind(field) === "card" && shouldSuppressCardAutofillPopup(field)) {
      if (popupEl?.style.display === "block" && activeFieldKind === "card") {
        hidePopup();
      }
      return;
    }
    if (field instanceof HTMLInputElement && isCredentialHintField(field)) {
      scheduleIdentifierHintSearch(field);
    }
  });

  field.addEventListener("change", () => {
    refreshIconForField(field);
    if (detectFieldKind(field) === "card" && shouldSuppressCardAutofillPopup(field)) {
      if (popupEl?.style.display === "block" && activeFieldKind === "card") {
        hidePopup();
      }
    }
  });

  field.addEventListener("keydown", (e) => {
    const evt = e as KeyboardEvent;
    if (!popupEl || popupEl.style.display !== "block") return;
    const visibleEntries = getVisiblePopupEntries();
    if (evt.key === "ArrowDown") {
      evt.preventDefault();
      if (visibleEntries.length > 0) {
        selectedIndex = Math.min(selectedIndex + 1, visibleEntries.length - 1);
      }
      renderPopupEntries();
    } else if (evt.key === "ArrowUp") {
      evt.preventDefault();
      selectedIndex = visibleEntries.length > 0 ? Math.max(selectedIndex - 1, 0) : 0;
      renderPopupEntries();
    } else if (evt.key === "Enter") {
      if (visibleEntries[selectedIndex]) {
        evt.preventDefault();
        selectPopupEntry(visibleEntries[selectedIndex]);
      }
    } else if (evt.key === "Escape") {
      hidePopup(true);
    }
  });
}

// ─── Save login detection ─────────────────────────────────────────────────────

let saveLoginPromptEl: HTMLDivElement | null = null;
let saveResultToastEl: HTMLDivElement | null = null;
let loginAutofillPromptEl: HTMLDivElement | null = null;
let proactiveLoginPromptShown = false;
let proactiveLoginPromptRetryTimer: number | null = null;
let proactiveLoginPromptDismissedKey: string | null = null;
let proactiveLoginPromptLastAttemptAt = 0;

function getProactiveLoginPromptPageKey(): string {
  return `${window.location.origin}${window.location.pathname}${window.location.search}`;
}

function clearScheduledProactiveLoginPromptCheck(): void {
  if (proactiveLoginPromptRetryTimer !== null) {
    window.clearTimeout(proactiveLoginPromptRetryTimer);
    proactiveLoginPromptRetryTimer = null;
  }
}

function isProactiveLoginPromptDismissedForCurrentPage(): boolean {
  return proactiveLoginPromptDismissedKey === getProactiveLoginPromptPageKey();
}

function markProactiveLoginPromptDismissedForCurrentPage(): void {
  proactiveLoginPromptDismissedKey = getProactiveLoginPromptPageKey();
  clearScheduledProactiveLoginPromptCheck();
}

function isInlineAutofillPopupVisible(): boolean {
  return popupEl?.style.display === "block";
}

function shouldConsiderProactiveLoginPrompt(): boolean {
  if (isAutofillDisabledForCurrentDomain()) return false;
  if (proactiveLoginPromptShown || proactiveShown || activePasskeyRequest) return false;
  if (isProactiveLoginPromptDismissedForCurrentPage()) return false;
  if (loginAutofillPromptEl || passkeyPromptEl || saveLoginPromptEl || saveSocialPromptEl) return false;
  if (isInlineAutofillPopupVisible()) return false;
  if (!isLikelyLoginSurface()) return false;
  return getAutofillFields().length > 0;
}

function scheduleProactiveLoginPromptCheck(
  delay = PROACTIVE_LOGIN_RETRY_DEBOUNCE_MS,
  options: { force?: boolean } = {},
): void {
  if (!shouldConsiderProactiveLoginPrompt()) return;

  clearScheduledProactiveLoginPromptCheck();

  const minIntervalDelay = options.force
    ? 0
    : Math.max(0, PROACTIVE_LOGIN_RETRY_MIN_INTERVAL_MS - (Date.now() - proactiveLoginPromptLastAttemptAt));
  const waitMs = Math.max(delay, minIntervalDelay);

  proactiveLoginPromptRetryTimer = window.setTimeout(() => {
    proactiveLoginPromptRetryTimer = null;
    void checkForLoginsOnLoad();
  }, waitMs);
}

function showSaveResultToast(success: boolean, message: string): void {
  if (saveResultToastEl) {
    saveResultToastEl.remove();
    saveResultToastEl = null;
  }

  ensurePkAnimStyle();

  const background = success ? "#16a34a" : "#dc2626";
  const icon = success
      ? `<polyline points="20 6 9 17 4 12"/>`
      : `<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>`;
  const el = document.createElement("div");
  el.style.cssText = `
    position: fixed;
    z-index: 2147483647;
    top: 72px;
    right: 24px;
    max-width: 320px;
    background: ${background};
    color: white;
    font-size: 13px;
    font-weight: 600;
    padding: 10px 14px;
    border-radius: 12px;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    box-shadow: 0 10px 30px rgba(15, 23, 42, 0.24);
    display: flex;
    align-items: center;
    gap: 8px;
    animation: lp-slide-up 0.18s ease-out;
  `;
  el.innerHTML = `
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">${icon}</svg>
    <span style="line-height:1.35;">${message}</span>
  `;
  lpAppend(el);
  saveResultToastEl = el;
  setTimeout(() => {
    if (saveResultToastEl === el) {
      el.remove();
      saveResultToastEl = null;
    }
  }, 3200);
}

interface SaveLoginCandidateEntry {
  id: string;
  title: string;
}

interface SaveLoginPromptInfo {
  title: string;
  username: string;
  password: string;
  mode?: "new" | "update" | "multi-choice";
  existingEntryId?: string;
  existingTitle?: string;
  candidates?: SaveLoginCandidateEntry[];
}

type SaveLoginMetadataField = { id: string; label: string; value: string; secret?: boolean };

type SaveLoginEditedValues = {
  title: string;
  username: string;
  password: string;
  url: string;
  metadata: SaveLoginMetadataField[];
};

function showSaveLoginPrompt(
  info: SaveLoginPromptInfo,
  onSave: (values: SaveLoginEditedValues, categoryUuid: string, opts?: { existingEntryId?: string }) => void,
  onCancel: () => void,
): void {
  proactiveLoginPromptShown = false;
  dismissLoginAutofillPrompt();
  if (saveLoginPromptEl) saveLoginPromptEl.remove();

  ensurePkAnimStyle();

  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1f2937" : "#ffffff";
  const text = isDark ? "#f3f4f6" : "#111827";
  const subText = isDark ? "#9ca3af" : "#6b7280";
  const border = isDark ? "#374151" : "#e5e7eb";
  const inputBg = isDark ? "#111827" : "#f8fafc";
  const danger = "#dc2626";
  const isUpdate = info.mode === "update" && !!info.existingEntryId;
  const isMultiChoice = info.mode === "multi-choice" && Array.isArray(info.candidates) && info.candidates.length > 0;
  const headerLabel = (isUpdate || isMultiChoice) ? "Update login" : "Save login";
  const initialUrl = window.location.href;
  let metadataFields: SaveLoginMetadataField[] = [
    { id: `meta-${Date.now()}-initial`, label: "", value: "", secret: false },
  ];

  const escapeHtml = (value: string): string => value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#39;");

  const fieldStyle = `width:100%;box-sizing:border-box;padding:7px 10px;background:${inputBg};border:1px solid ${border};border-radius:7px;font-size:12px;color:${text};outline:none;`;
  const labelStyle = `font-size:10px;color:${subText};margin:0 0 3px 0;font-weight:600;text-transform:uppercase;letter-spacing:0.4px;`;

  const el = document.createElement("div");
  el.setAttribute("data-lp-prompt-modal", "true");
  el.style.cssText = `
    position: fixed; z-index: 2147483647; top: 72px; right: 24px;
    width: 320px; max-height: calc(100vh - 96px); background: ${bg}; border: 1px solid ${border};
    border-radius: 12px; box-shadow: 0 6px 24px rgba(0,0,0,0.14);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    overflow: hidden; animation: lp-slide-up 0.2s ease-out;
  `;

  const multiChoiceCandidateHtml = isMultiChoice
    ? (info.candidates ?? []).map((c, i) => `
        <label style="display:flex;align-items:center;gap:8px;padding:7px 9px;border:1px solid ${border};border-radius:7px;cursor:pointer;margin-bottom:5px;background:${i === 0 ? (isDark ? "#1e2a45" : "#eef4ff") : inputBg};">
          <input type="radio" name="lp-save-candidate" value="${escapeHtml(c.id)}" ${i === 0 ? "checked" : ""} style="accent-color:#444ce7;flex-shrink:0;" />
          <span style="font-size:12px;color:${text};overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(c.title)}</span>
        </label>
      `).join("")
    : "";

  const footerHtml = isMultiChoice || isUpdate
    ? `
      <div style="display:flex;flex-direction:column;gap:6px;">
        <button id="lp-save-update-btn" type="button" style="width:100%;background:#444ce7;color:white;border:none;border-radius:8px;padding:8px 0;font-size:12px;font-weight:600;cursor:pointer;">${isMultiChoice ? "Update selected" : "Update saved item"}</button>
        <button id="lp-save-newdup-btn" type="button" style="width:100%;background:${bg};color:#444ce7;border:1px solid #c7d8ff;border-radius:8px;padding:8px 0;font-size:12px;font-weight:600;cursor:pointer;">Save as new item</button>
        <button id="lp-save-cancel" type="button" style="width:100%;background:none;border:1px solid ${border};border-radius:8px;padding:7px 0;font-size:12px;color:${subText};cursor:pointer;font-weight:500;">Cancel</button>
      </div>
    `
    : `
      <div style="display:flex;gap:6px;">
        <button id="lp-save-cancel" type="button" style="flex:0 0 auto;background:none;border:1px solid ${border};border-radius:8px;padding:7px 12px;font-size:12px;color:${subText};cursor:pointer;font-weight:500;">Cancel</button>
        <button id="lp-save-btn" type="button" style="flex:1;background:#444ce7;color:white;border:none;border-radius:8px;padding:7px 0;font-size:12px;font-weight:600;cursor:pointer;">Save</button>
      </div>
    `;

  const headerLockSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#444ce7" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`;

  el.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;padding:10px 12px;border-bottom:1px solid ${isDark ? "#2d2d3d" : "#f3f4f6"};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:18px;height:18px;flex-shrink:0;">${headerLockSvg}</span>
      <p style="color:${text};font-size:13px;font-weight:600;margin:0;flex:1;">${headerLabel}</p>
      <button id="lp-save-close" type="button" style="background:none;border:none;cursor:pointer;color:${subText};font-size:18px;padding:0 4px;line-height:1;">&times;</button>
    </div>
    <div style="padding:12px;max-height:calc(100vh - 150px);overflow:auto;">
      ${isUpdate ? `<p id="lp-save-hint" style="font-size:11px;color:${subText};margin:0 0 10px 0;line-height:1.45;"></p>` : ""}
      ${isMultiChoice ? `<p style="font-size:11px;color:${subText};margin:0 0 6px 0;line-height:1.45;">The password changed. Choose which record to update:</p><div id="lp-save-candidates" style="margin-bottom:10px;">${multiChoiceCandidateHtml}</div>` : ""}
      <div style="margin-bottom:8px;"><div id="lp-save-category-wrap" style="position:relative;"><button id="lp-save-category-trigger" type="button" style="width:100%;display:flex;align-items:center;gap:8px;border:1px solid ${border};border-radius:999px;background:${inputBg};padding:6px 12px;cursor:pointer;text-align:left;"><span style="display:flex;align-items:center;justify-content:center;width:16px;height:16px;flex-shrink:0;"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#64748b" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"/></svg></span><span id="lp-save-category-label" style="min-width:0;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:12px;font-weight:500;color:${text};">Uncategorized</span><span id="lp-save-category-chevron" style="display:flex;align-items:center;justify-content:center;flex-shrink:0;color:#6b7280;transition:transform 0.16s ease;"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg></span></button><div id="lp-save-category-menu" style="display:none;position:absolute;top:calc(100% + 6px);left:0;right:0;z-index:2;overflow:hidden;border:1px solid ${isDark ? "#374151" : "#d9e5ff"};border-radius:12px;background:${bg};box-shadow:0 8px 24px rgba(15,23,42,0.18);max-height:200px;"><div id="lp-save-category-options" style="padding:6px 0;max-height:200px;overflow:auto;"></div></div></div></div>
      <div style="display:flex;flex-direction:column;gap:8px;margin-bottom:8px;">
        <label><p style="${labelStyle}">Name</p><input id="lp-save-title" type="text" value="${escapeHtml(info.title)}" style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">Username</p><input id="lp-save-username" type="text" value="${escapeHtml(info.username)}" placeholder="Username or email" style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">Password</p><div style="display:flex;gap:5px;"><input id="lp-save-password" type="password" value="${escapeHtml(info.password)}" style="${fieldStyle}font-family:ui-monospace,SFMono-Regular,Menlo,monospace;" /><button id="lp-save-toggle-password" type="button" aria-pressed="false" style="flex:0 0 auto;border:1px solid ${border};background:${bg};color:${text};border-radius:7px;padding:0 9px;font-size:11px;font-weight:600;cursor:pointer;">Show</button></div></label>
        <label><p style="${labelStyle}">URL</p><input id="lp-save-url" type="url" value="${escapeHtml(initialUrl)}" style="${fieldStyle}" /></label>
      </div>
      <div style="margin-bottom:10px;"><div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:5px;"><p style="${labelStyle.replace('margin:0 0 3px 0;', 'margin:0;')}">Metadata</p><button id="lp-save-add-meta" type="button" style="border:none;background:none;color:#444ce7;font-size:11px;font-weight:600;cursor:pointer;padding:0;">+ Add field</button></div><div id="lp-save-metadata-fields" style="display:flex;flex-direction:column;gap:6px;"></div></div>
      <p id="lp-save-validation" style="display:none;color:${danger};font-size:11px;margin:0 0 8px 0;line-height:1.4;"></p>
      ${footerHtml}
    </div>
  `;

  lpAppend(el);
  saveLoginPromptEl = el as HTMLDivElement;

  const titleInput = el.querySelector<HTMLInputElement>("#lp-save-title");
  const usernameInput = el.querySelector<HTMLInputElement>("#lp-save-username");
  const passwordInput = el.querySelector<HTMLInputElement>("#lp-save-password");
  const urlInput = el.querySelector<HTMLInputElement>("#lp-save-url");
  const validationEl = el.querySelector<HTMLParagraphElement>("#lp-save-validation");
  const metadataContainer = el.querySelector<HTMLDivElement>("#lp-save-metadata-fields");
  const primaryButtons = Array.from(el.querySelectorAll<HTMLButtonElement>("#lp-save-btn,#lp-save-update-btn,#lp-save-newdup-btn"));

  const hint = el.querySelector("#lp-save-hint");
  if (hint && isUpdate && info.existingTitle) {
    hint.textContent = `The password you used does not match "${info.existingTitle}". You can update that item or save a separate copy.`;
  }

  const validate = (): boolean => {
    const errors: string[] = [];
    if (!titleInput?.value.trim()) errors.push("Name is required.");
    if (!passwordInput?.value) errors.push("Password is required.");
    const rawUrl = urlInput?.value.trim() ?? "";
    if (!rawUrl) errors.push("URL is required.");
    else {
      try {
        const parsed = new URL(rawUrl);
        if (!["http:", "https:"].includes(parsed.protocol)) errors.push("URL must start with http:// or https://.");
      } catch {
        errors.push("URL must be valid.");
      }
    }
    metadataFields.forEach((field) => {
      if (field.value.trim() && !field.label.trim()) errors.push("Metadata labels are required when values are filled.");
    });
    const ok = errors.length === 0;
    if (validationEl) {
      validationEl.textContent = errors[0] ?? "";
      validationEl.style.display = ok ? "none" : "block";
    }
    primaryButtons.forEach((button) => {
      button.disabled = !ok;
      button.style.opacity = ok ? "1" : "0.55";
      button.style.cursor = ok ? "pointer" : "not-allowed";
    });
    return ok;
  };

  const renderMetadata = (): void => {
    if (!metadataContainer) return;
    metadataContainer.innerHTML = "";
    metadataFields.forEach((field) => {
      const row = document.createElement("div");
      row.style.cssText = `display:grid;grid-template-columns:1fr 1.25fr auto;gap:6px;align-items:center;`;
      row.innerHTML = `<input data-meta-label="${escapeHtml(field.id)}" type="text" value="${escapeHtml(field.label)}" placeholder="Label" style="${fieldStyle}" /><input data-meta-value="${escapeHtml(field.id)}" type="text" value="${escapeHtml(field.value)}" placeholder="Value" style="${fieldStyle}" /><button data-meta-remove="${escapeHtml(field.id)}" type="button" style="border:1px solid ${border};background:${bg};color:${subText};border-radius:8px;padding:8px 9px;cursor:pointer;font-size:12px;">Delete</button>`;
      metadataContainer.appendChild(row);
    });
    metadataContainer.querySelectorAll<HTMLInputElement>("[data-meta-label]").forEach((input) => {
      input.addEventListener("input", () => {
        const field = metadataFields.find((item) => item.id === input.dataset.metaLabel);
        if (field) field.label = input.value;
        validate();
      });
    });
    metadataContainer.querySelectorAll<HTMLInputElement>("[data-meta-value]").forEach((input) => {
      input.addEventListener("input", () => {
        const field = metadataFields.find((item) => item.id === input.dataset.metaValue);
        if (field) field.value = input.value;
        validate();
      });
    });
    metadataContainer.querySelectorAll<HTMLButtonElement>("[data-meta-remove]").forEach((button) => {
      button.addEventListener("click", () => {
        metadataFields = metadataFields.filter((item) => item.id !== button.dataset.metaRemove);
        renderMetadata();
        validate();
      });
    });
  };

  renderMetadata();

  el.querySelector("#lp-save-add-meta")?.addEventListener("click", () => {
    metadataFields.push({ id: `meta-${Date.now()}-${metadataFields.length}`, label: "", value: "", secret: false });
    renderMetadata();
    validate();
  });

  el.querySelector("#lp-save-toggle-password")?.addEventListener("click", () => {
    if (!passwordInput) return;
    const reveal = passwordInput.type === "password";
    passwordInput.type = reveal ? "text" : "password";
    const button = el.querySelector<HTMLButtonElement>("#lp-save-toggle-password");
    if (button) {
      button.textContent = reveal ? "Hide" : "Show";
      button.setAttribute("aria-pressed", reveal ? "true" : "false");
    }
  });

  [titleInput, usernameInput, passwordInput, urlInput].forEach((input) => input?.addEventListener("input", validate));

  if (isMultiChoice) {
    const candidatesContainer = el.querySelector<HTMLDivElement>("#lp-save-candidates");
    candidatesContainer?.querySelectorAll<HTMLInputElement>("input[type='radio']").forEach((radio) => {
      radio.addEventListener("change", () => {
        candidatesContainer.querySelectorAll<HTMLLabelElement>("label").forEach((lbl) => {
          const isChecked = lbl.querySelector("input")?.checked ?? false;
          lbl.style.background = isChecked ? (isDark ? "#1e2a45" : "#eef4ff") : inputBg;
        });
        const selectedCandidate = info.candidates?.find((c) => c.id === radio.value);
        if (selectedCandidate && titleInput) {
          titleInput.value = selectedCandidate.title;
        }
      });
    });
  }

  const categoryTrigger = el.querySelector<HTMLButtonElement>("#lp-save-category-trigger");
  const categoryLabel = el.querySelector<HTMLSpanElement>("#lp-save-category-label");
  const categoryChevron = el.querySelector<HTMLSpanElement>("#lp-save-category-chevron");
  const categoryMenu = el.querySelector<HTMLDivElement>("#lp-save-category-menu");
  const categoryOptions = el.querySelector<HTMLDivElement>("#lp-save-category-options");
  const categoryWrap = el.querySelector<HTMLDivElement>("#lp-save-category-wrap");
  let selectedCategoryId = "";
  let menuOpen = false;
  let categories: CategoryItem[] = [];
  let removeOutsideClickListener: (() => void) | null = null;

  const setMenuOpen = (open: boolean): void => {
    menuOpen = open;
    if (categoryMenu) categoryMenu.style.display = open ? "block" : "none";
    if (categoryChevron) categoryChevron.style.transform = open ? "rotate(180deg)" : "rotate(0deg)";
  };

  const renderCategoryOptions = (): void => {
    if (!categoryOptions) return;
    const optionList: CategoryItem[] = [{ id: "", name: "Uncategorized" }, ...categories];
    categoryOptions.innerHTML = "";
    optionList.forEach((category) => {
      const selected = category.id === selectedCategoryId;
      const option = document.createElement("button");
      option.type = "button";
      option.style.cssText = `width:100%;display:flex;align-items:center;gap:10px;padding:10px 14px;border:none;background:${selected ? (isDark ? "#1f2937" : "#eef4ff") : "transparent"};cursor:pointer;text-align:left;`;
      option.innerHTML = `<span style="display:flex;align-items:center;justify-content:center;width:20px;height:20px;flex-shrink:0;"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="${selected ? "#444ce7" : "#64748b"}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"/></svg></span><span style="min-width:0;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:14px;font-weight:${selected ? "600" : "500"};color:${text};">${escapeHtml(category.name)}</span>${selected ? `<span style="display:flex;align-items:center;justify-content:center;color:#444ce7;flex-shrink:0;"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg></span>` : ""}`;
      option.addEventListener("click", () => {
        selectedCategoryId = category.id;
        if (categoryLabel) categoryLabel.textContent = category.name;
        setMenuOpen(false);
        renderCategoryOptions();
      });
      categoryOptions.appendChild(option);
    });
  };

  renderCategoryOptions();
  void browser.runtime.sendMessage({ type: "GET_CATEGORIES" }).then((response) => {
    if (response?.ok && Array.isArray(response.data)) {
      categories = (response.data as CategoryItem[]).filter((category) => category.id && category.name.toLowerCase() !== "uncategorized");
      renderCategoryOptions();
    }
  }).catch(() => {});

  categoryTrigger?.addEventListener("click", (event) => {
    event.stopPropagation();
    setMenuOpen(!menuOpen);
  });

  const closePrompt = (): void => {
    removeOutsideClickListener?.();
    removeOutsideClickListener = null;
    el.remove();
    saveLoginPromptEl = null;
  };

  const collectValues = (): SaveLoginEditedValues | null => {
    if (!validate() || !titleInput || !usernameInput || !passwordInput || !urlInput) return null;
    return {
      title: titleInput.value.trim(),
      username: usernameInput.value.trim(),
      password: passwordInput.value,
      url: urlInput.value.trim(),
      metadata: metadataFields
        .map((field) => ({ ...field, label: field.label.trim(), value: field.value.trim() }))
        .filter((field) => field.label || field.value),
    };
  };

  const saveWith = (opts: { existingEntryId?: string }): void => {
    const values = collectValues();
    if (!values) return;
    closePrompt();
    onSave(values, selectedCategoryId, opts);
  };

  el.querySelector("#lp-save-btn")?.addEventListener("click", () => saveWith({}));
  el.querySelector("#lp-save-update-btn")?.addEventListener("click", () => {
    if (isMultiChoice) {
      const selected = el.querySelector<HTMLInputElement>("input[name='lp-save-candidate']:checked");
      saveWith({ existingEntryId: selected?.value });
    } else {
      saveWith({ existingEntryId: info.existingEntryId });
    }
  });
  el.querySelector("#lp-save-newdup-btn")?.addEventListener("click", () => saveWith({}));
  el.querySelector("#lp-save-cancel")?.addEventListener("click", () => { closePrompt(); onCancel(); });
  el.querySelector("#lp-save-close")?.addEventListener("click", () => { closePrompt(); onCancel(); });

  const outsideClickHandler = (event: MouseEvent): void => {
    if (!menuOpen || !categoryWrap) return;
    if (event.composedPath().includes(categoryWrap)) return;
    setMenuOpen(false);
  };
  document.addEventListener("click", outsideClickHandler, { capture: true });
  removeOutsideClickListener = () => {
    document.removeEventListener("click", outsideClickHandler, { capture: true });
  };

  validate();
}

function normalizeCapturedCardDate(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return "";
  const parsed = parseCardExpiry(trimmed);
  if (parsed) {
    return `${parsed.month}/${parsed.year}`;
  }
  return trimmed;
}

function buildCreditCardDraftTitle(cardType: string, cardNumber: string): string {
  const last4 = getCardDigits(cardNumber).slice(-4);
  const inferredType = cardType.trim() || inferCardTypeFromNumber(cardNumber);
  if (inferredType && last4) return `${inferredType} ending ${last4}`;
  if (inferredType) return inferredType;
  if (last4) return `Card ending ${last4}`;
  return "Credit Card";
}

function getCurrentPageSaveUrl(): string {
  try {
    const url = new URL(window.location.href);
    return `${url.protocol}//${url.host}`;
  } catch {
    return window.location.href;
  }
}

interface QuickCreateCreditCardInfo {
  title: string;
  cardholder: string;
  cardType: string;
  cardNumber: string;
  verificationNumber: string;
  expiryDate: string;
  validFrom: string;
  issuingBank: string;
  url: string;
  metadata: SaveLoginMetadataField[];
}

interface QuickCreateCreditCardValues extends QuickCreateCreditCardInfo {}

let quickCreateCreditCardPromptEl: HTMLDivElement | null = null;

function collectCreditCardDraft(anchor: FillableField): QuickCreateCreditCardInfo | null {
  const scopeFields = getFieldScopeFillFields(anchor);
  if (scopeFields.length === 0) return null;

  const cardNumber = findScopeFieldValue(scopeFields, {
    autocompletes: ["cc-number"],
    matcher: CARD_NUMBER_DESCRIPTOR_PATTERN,
  });
  const verificationNumber = findScopeFieldValue(scopeFields, {
    autocompletes: ["cc-csc"],
    matcher: /^cvv$|^cvc$|^cvn$|^csc$|^cid$|cvv2|cc.?csc|card.?cvv|card.?cvc|card.?verification|security.?code|security.?number|verification.?number|verification.?code|^ccv$/,
  });
  const cardholder = findScopeFieldValue(scopeFields, {
    autocompletes: ["cc-name"],
    matcher: /cardholder|card.?holder|card.?user.?name|card.?owner|billing.?name|cc.?uname|cc.?name|name.?on.?card|card.?name/,
  });
  const explicitType = findScopeFieldValue(scopeFields, {
    autocompletes: ["cc-type"],
    matcher: /cc.?type|card.?type|credit.?card.?type|payment.?type|card.?brand|card.?network|\btype\b/,
  });
  const expirySingle = findScopeFieldValue(scopeFields, {
    autocompletes: ["cc-exp"],
    matcher: CARD_EXPIRY_DESCRIPTOR_PATTERN,
  });
  const expiryMonth = findScopeFieldValue(scopeFields, {
    autocompletes: ["cc-exp-month"],
    matcher: /exp.?month|cc.?exp.?month|cc.?exp.?(mm|mo)|card.?month|card.?exp.?(mm|mo)|expiry.?month|expiry.?(mm|mo)|\bexp.?mm\b|\bccexp.?mm\b/,
  });
  const expiryYear = findScopeFieldValue(scopeFields, {
    autocompletes: ["cc-exp-year"],
    matcher: /exp.?year|cc.?exp.?year|cc.?exp.?(yy|yyyy)|card.?year|card.?exp.?(yy|yyyy)|expiry.?year|expiry.?(yy|yyyy)|\bexp.?yy\b|\bccexp.?yy\b/,
  });
  const validFrom = normalizeCapturedCardDate(findScopeFieldValue(scopeFields, {
    matcher: /valid.?from|start.?date|member.?since/,
  }));
  const issuingBank = findScopeFieldValue(scopeFields, {
    matcher: /issuing.?bank|bank.?name|card.?issuer|issuer/,
  });
  const billingAddress = findScopeFieldValue(scopeFields, {
    matcher: /^address$|billing.?address|street.?address|address.?line.?1|^street$|street(?!.*2)/,
  });
  const billingAddress2 = findScopeFieldValue(scopeFields, {
    matcher: /address.?line.?2|address.?2|billing.?address.?2|apartment|suite|unit|building/,
  });
  const billingCity = findScopeFieldValue(scopeFields, {
    matcher: /^city$|^town$|town.?city|municipality|suburb|locality/,
  });
  const billingState = findScopeFieldValue(scopeFields, {
    matcher: /^state$|province|state.?or.?province|state.?or.?territory|region|county|district|prefecture|territory/,
  });
  const billingPostalCode = findScopeFieldValue(scopeFields, {
    matcher: /^zip$|zip.?code|postal.?code|postcode|pin.?code/,
  });
  const billingCountry = findScopeFieldValue(scopeFields, {
    matcher: /^country$|country.?name|country.?region/,
  });

  const expiryDate = expirySingle
    ? normalizeCapturedCardDate(expirySingle)
    : normalizeCapturedCardDate(
        expiryMonth && expiryYear ? `${expiryMonth}/${expiryYear}` : expiryMonth || expiryYear,
      );
  const cardType = explicitType.trim() || inferCardTypeFromNumber(cardNumber);
  const metadata: SaveLoginMetadataField[] = [];
  const addMetadata = (label: string, value: string, secret = false) => {
    const trimmed = value.trim();
    if (!trimmed) return;
    metadata.push({
      id: `cc-meta-${metadata.length}-${Date.now()}`,
      label,
      value: trimmed,
      secret,
    });
  };

  addMetadata("Billing Address", billingAddress);
  addMetadata("Billing Address Line 2", billingAddress2);
  addMetadata("Billing City", billingCity);
  addMetadata("Billing State", billingState);
  addMetadata("Billing Postal Code", billingPostalCode);
  addMetadata("Billing Country", billingCountry);

  const digits = getCardDigits(cardNumber);
  if (!digits) return null;

  return {
    title: buildCreditCardDraftTitle(cardType, cardNumber),
    cardholder: cardholder.trim(),
    cardType: cardType.trim(),
    cardNumber: cardNumber.trim(),
    verificationNumber: verificationNumber.trim(),
    expiryDate,
    validFrom,
    issuingBank: issuingBank.trim(),
    url: getCurrentPageSaveUrl(),
    metadata,
  };
}

function showQuickCreateCreditCardPrompt(
  info: QuickCreateCreditCardInfo,
  onSave: (values: QuickCreateCreditCardValues, categoryUuid: string) => void,
  onCancel: () => void,
): void {
  if (quickCreateCreditCardPromptEl) quickCreateCreditCardPromptEl.remove();

  ensurePkAnimStyle();

  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1f2937" : "#ffffff";
  const text = isDark ? "#f3f4f6" : "#111827";
  const subText = isDark ? "#9ca3af" : "#6b7280";
  const border = isDark ? "#374151" : "#e5e7eb";
  const inputBg = isDark ? "#111827" : "#f8fafc";
  const overlayBg = isDark ? "rgba(2,6,23,0.55)" : "rgba(15,23,42,0.32)";
  const danger = "#dc2626";
  let metadataFields: SaveLoginMetadataField[] = info.metadata.map((field, index) => ({
    ...field,
    id: field.id || `cc-meta-${Date.now()}-${index}`,
  }));

  const fieldStyle = `width:100%;box-sizing:border-box;padding:9px 11px;background:${inputBg};border:1px solid ${border};border-radius:8px;font-size:13px;color:${text};outline:none;font-family:inherit;`;
  const labelStyle = `font-size:10px;color:${subText};margin:0 0 4px 0;font-weight:600;text-transform:uppercase;letter-spacing:0.4px;`;

  const overlay = document.createElement("div");
  overlay.setAttribute("data-lp-prompt-modal", "true");
  overlay.style.cssText = `
    position: fixed; inset: 0; z-index: 2147483647;
    background: ${overlayBg};
    display: flex; align-items: flex-start; justify-content: center;
    padding: 48px 16px; overflow-y: auto;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    animation: lp-slide-up 0.18s ease-out;
  `;

  const card = document.createElement("div");
  card.style.cssText = `
    width: 100%; max-width: 460px; background: ${bg};
    border: 1px solid ${border}; border-radius: 14px;
    box-shadow: 0 24px 60px rgba(15,23,42,0.28);
    overflow: hidden;
  `;
  overlay.appendChild(card);

  const cardIconSvg = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#0f766e" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="2.5" y="5" width="19" height="14" rx="2.5"/><path d="M2.5 10h19"/><path d="M12 13.5v5"/><path d="M9.5 16h5"/></svg>`;
  const eyeSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>`;

  card.innerHTML = `
    <div style="display:flex;align-items:center;gap:10px;padding:14px 16px;border-bottom:1px solid ${isDark ? "#2d2d3d" : "#f3f4f6"};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:22px;height:22px;flex-shrink:0;border-radius:7px;background:${isDark ? "#042f2e" : "#ecfdf5"};">${cardIconSvg}</span>
      <p style="color:${text};font-size:14px;font-weight:700;margin:0;flex:1;">Save credit card</p>
      <button id="lp-qcc-close" type="button" aria-label="Close" style="background:none;border:none;cursor:pointer;color:${subText};font-size:22px;padding:0 4px;line-height:1;">&times;</button>
    </div>
    <div style="padding:14px 16px;max-height:calc(100vh - 160px);overflow:auto;">
      <div style="margin-bottom:10px;"><div id="lp-qcc-category-wrap" style="position:relative;"><button id="lp-qcc-category-trigger" type="button" style="width:100%;display:flex;align-items:center;gap:8px;border:1px solid ${border};border-radius:999px;background:${inputBg};padding:7px 13px;cursor:pointer;text-align:left;"><span style="display:flex;align-items:center;justify-content:center;width:16px;height:16px;flex-shrink:0;"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#64748b" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"/></svg></span><span id="lp-qcc-category-label" style="min-width:0;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:500;color:${text};">Uncategorized</span><span id="lp-qcc-category-chevron" style="display:flex;align-items:center;justify-content:center;flex-shrink:0;color:#6b7280;transition:transform 0.16s ease;"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg></span></button><div id="lp-qcc-category-menu" style="display:none;position:absolute;top:calc(100% + 6px);left:0;right:0;z-index:2;overflow:hidden;border:1px solid ${isDark ? "#374151" : "#d9e5ff"};border-radius:12px;background:${bg};box-shadow:0 8px 24px rgba(15,23,42,0.18);max-height:220px;"><div id="lp-qcc-category-options" style="padding:6px 0;max-height:220px;overflow:auto;"></div></div></div></div>
      <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:10px;">
        <label><p style="${labelStyle}">Name</p><input id="lp-qcc-title" type="text" value="${lpEscapeHtml(info.title)}" placeholder="e.g. Personal Visa" style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">Cardholder name</p><input id="lp-qcc-cardholder" type="text" value="${lpEscapeHtml(info.cardholder)}" placeholder="Name on card" style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">Type</p><input id="lp-qcc-type" type="text" value="${lpEscapeHtml(info.cardType)}" placeholder="Visa, Mastercard, ..." style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">Card number</p><input id="lp-qcc-number" type="text" value="${lpEscapeHtml(info.cardNumber)}" placeholder="1234 5678 9012 3456" style="${fieldStyle}font-family:ui-monospace,SFMono-Regular,Menlo,monospace;" /></label>
        <label><p style="${labelStyle}">Verification number</p><div style="display:flex;gap:6px;"><input id="lp-qcc-verification" type="password" value="${lpEscapeHtml(info.verificationNumber)}" placeholder="CVC / CVV" style="${fieldStyle}font-family:ui-monospace,SFMono-Regular,Menlo,monospace;" /><button id="lp-qcc-toggle-verification" type="button" aria-pressed="false" title="Reveal" style="flex:0 0 auto;border:1px solid ${border};background:${bg};color:${text};border-radius:8px;padding:0 9px;font-size:12px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;">${eyeSvg}</button></div></label>
        <label><p style="${labelStyle}">Expiry date</p><input id="lp-qcc-expiry" type="text" value="${lpEscapeHtml(info.expiryDate)}" placeholder="MM / YYYY" style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">Valid from</p><input id="lp-qcc-valid-from" type="text" value="${lpEscapeHtml(info.validFrom)}" placeholder="MM / YYYY" style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">Issuing bank</p><input id="lp-qcc-bank" type="text" value="${lpEscapeHtml(info.issuingBank)}" placeholder="Optional" style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">Website</p><input id="lp-qcc-url" type="url" value="${lpEscapeHtml(info.url)}" placeholder="https://example.com" style="${fieldStyle}" /></label>
      </div>
      <div style="margin-bottom:12px;"><div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;"><p style="${labelStyle.replace('margin:0 0 4px 0;', 'margin:0;')}">Additional fields</p><button id="lp-qcc-add-meta" type="button" style="border:none;background:none;color:#444ce7;font-size:11px;font-weight:600;cursor:pointer;padding:0;">+ Add field</button></div><div id="lp-qcc-metadata-fields" style="display:flex;flex-direction:column;gap:6px;"></div></div>
      <p id="lp-qcc-validation" style="display:none;color:${danger};font-size:12px;margin:0 0 10px 0;line-height:1.4;"></p>
      <div style="display:flex;gap:8px;">
        <button id="lp-qcc-cancel" type="button" style="flex:0 0 auto;background:none;border:1px solid ${border};border-radius:9px;padding:9px 14px;font-size:13px;color:${subText};cursor:pointer;font-weight:500;">Cancel</button>
        <button id="lp-qcc-save" type="button" style="flex:1;background:#0f766e;color:white;border:none;border-radius:9px;padding:9px 0;font-size:13px;font-weight:600;cursor:pointer;">Save card</button>
      </div>
    </div>
  `;

  lpAppend(overlay);
  quickCreateCreditCardPromptEl = overlay as HTMLDivElement;

  const titleInput = card.querySelector<HTMLInputElement>("#lp-qcc-title");
  const cardholderInput = card.querySelector<HTMLInputElement>("#lp-qcc-cardholder");
  const cardTypeInput = card.querySelector<HTMLInputElement>("#lp-qcc-type");
  const cardNumberInput = card.querySelector<HTMLInputElement>("#lp-qcc-number");
  const verificationInput = card.querySelector<HTMLInputElement>("#lp-qcc-verification");
  const expiryInput = card.querySelector<HTMLInputElement>("#lp-qcc-expiry");
  const validFromInput = card.querySelector<HTMLInputElement>("#lp-qcc-valid-from");
  const bankInput = card.querySelector<HTMLInputElement>("#lp-qcc-bank");
  const urlInput = card.querySelector<HTMLInputElement>("#lp-qcc-url");
  const validationEl = card.querySelector<HTMLParagraphElement>("#lp-qcc-validation");
  const metadataContainer = card.querySelector<HTMLDivElement>("#lp-qcc-metadata-fields");
  const saveButton = card.querySelector<HTMLButtonElement>("#lp-qcc-save");

  const validate = (): boolean => {
    const errors: string[] = [];
    if (!titleInput?.value.trim()) errors.push("Name is required.");
    const cardDigits = getCardDigits(cardNumberInput?.value ?? "");
    if (!cardDigits) errors.push("Card number is required.");
    else if (cardDigits.length < 12) errors.push("Card number looks incomplete.");

    const rawUrl = urlInput?.value.trim() ?? "";
    if (rawUrl) {
      try {
        const parsed = new URL(rawUrl);
        if (!["http:", "https:"].includes(parsed.protocol)) {
          errors.push("Website must start with http:// or https://.");
        }
      } catch {
        errors.push("Website must be a valid URL.");
      }
    }

    metadataFields.forEach((field) => {
      if (field.value.trim() && !field.label.trim()) {
        errors.push("Additional field labels are required when values are filled.");
      }
    });

    const ok = errors.length === 0;
    if (validationEl) {
      validationEl.textContent = errors[0] ?? "";
      validationEl.style.display = ok ? "none" : "block";
    }
    if (saveButton) {
      saveButton.disabled = !ok;
      saveButton.style.opacity = ok ? "1" : "0.55";
      saveButton.style.cursor = ok ? "pointer" : "not-allowed";
    }
    return ok;
  };

  const renderMetadata = (): void => {
    if (!metadataContainer) return;
    metadataContainer.innerHTML = "";
    metadataFields.forEach((field) => {
      const row = document.createElement("div");
      row.style.cssText = "display:grid;grid-template-columns:1fr 1.25fr auto;gap:6px;align-items:center;";
      row.innerHTML = `<input data-meta-label="${lpEscapeHtml(field.id)}" type="text" value="${lpEscapeHtml(field.label)}" placeholder="Label" style="${fieldStyle}" /><input data-meta-value="${lpEscapeHtml(field.id)}" type="${field.secret ? "password" : "text"}" value="${lpEscapeHtml(field.value)}" placeholder="Value" style="${fieldStyle}" /><button data-meta-remove="${lpEscapeHtml(field.id)}" type="button" style="border:1px solid ${border};background:${bg};color:${subText};border-radius:8px;padding:8px 9px;cursor:pointer;font-size:12px;">Delete</button>`;
      metadataContainer.appendChild(row);
    });
    metadataContainer.querySelectorAll<HTMLInputElement>("[data-meta-label]").forEach((input) => {
      input.addEventListener("input", () => {
        const field = metadataFields.find((item) => item.id === input.dataset.metaLabel);
        if (field) field.label = input.value;
        validate();
      });
    });
    metadataContainer.querySelectorAll<HTMLInputElement>("[data-meta-value]").forEach((input) => {
      input.addEventListener("input", () => {
        const field = metadataFields.find((item) => item.id === input.dataset.metaValue);
        if (field) field.value = input.value;
        validate();
      });
    });
    metadataContainer.querySelectorAll<HTMLButtonElement>("[data-meta-remove]").forEach((button) => {
      button.addEventListener("click", () => {
        metadataFields = metadataFields.filter((item) => item.id !== button.dataset.metaRemove);
        renderMetadata();
        validate();
      });
    });
  };

  renderMetadata();

  card.querySelector("#lp-qcc-add-meta")?.addEventListener("click", () => {
    metadataFields.push({ id: `cc-meta-${Date.now()}-${metadataFields.length}`, label: "", value: "", secret: false });
    renderMetadata();
    validate();
  });

  card.querySelector("#lp-qcc-toggle-verification")?.addEventListener("click", () => {
    if (!verificationInput) return;
    const reveal = verificationInput.type === "password";
    verificationInput.type = reveal ? "text" : "password";
    const button = card.querySelector<HTMLButtonElement>("#lp-qcc-toggle-verification");
    if (button) button.setAttribute("aria-pressed", reveal ? "true" : "false");
  });

  [titleInput, cardholderInput, cardTypeInput, cardNumberInput, verificationInput, expiryInput, validFromInput, bankInput, urlInput]
    .forEach((input) => input?.addEventListener("input", validate));

  const categoryTrigger = card.querySelector<HTMLButtonElement>("#lp-qcc-category-trigger");
  const categoryLabel = card.querySelector<HTMLSpanElement>("#lp-qcc-category-label");
  const categoryChevron = card.querySelector<HTMLSpanElement>("#lp-qcc-category-chevron");
  const categoryMenu = card.querySelector<HTMLDivElement>("#lp-qcc-category-menu");
  const categoryOptions = card.querySelector<HTMLDivElement>("#lp-qcc-category-options");
  const categoryWrap = card.querySelector<HTMLDivElement>("#lp-qcc-category-wrap");
  let selectedCategoryId = "";
  let menuOpen = false;
  let categories: CategoryItem[] = [];

  const setMenuOpen = (open: boolean): void => {
    menuOpen = open;
    if (categoryMenu) categoryMenu.style.display = open ? "block" : "none";
    if (categoryChevron) categoryChevron.style.transform = open ? "rotate(180deg)" : "rotate(0deg)";
  };

  const renderCategoryOptions = (): void => {
    if (!categoryOptions) return;
    const optionList: CategoryItem[] = [{ id: "", name: "Uncategorized" }, ...categories];
    categoryOptions.innerHTML = "";
    optionList.forEach((category) => {
      const selected = category.id === selectedCategoryId;
      const option = document.createElement("button");
      option.type = "button";
      option.style.cssText = `width:100%;display:flex;align-items:center;gap:10px;padding:10px 14px;border:none;background:${selected ? (isDark ? "#1f2937" : "#eef4ff") : "transparent"};cursor:pointer;text-align:left;`;
      option.innerHTML = `<span style="display:flex;align-items:center;justify-content:center;width:20px;height:20px;flex-shrink:0;"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="${selected ? "#444ce7" : "#64748b"}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"/></svg></span><span style="min-width:0;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:${selected ? "600" : "500"};color:${text};">${lpEscapeHtml(category.name)}</span>${selected ? `<span style="display:flex;align-items:center;justify-content:center;color:#444ce7;flex-shrink:0;"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg></span>` : ""}`;
      option.addEventListener("click", () => {
        selectedCategoryId = category.id;
        if (categoryLabel) categoryLabel.textContent = category.name;
        setMenuOpen(false);
        renderCategoryOptions();
      });
      categoryOptions.appendChild(option);
    });
  };

  renderCategoryOptions();
  void browser.runtime.sendMessage({ type: "GET_CATEGORIES" }).then((response) => {
    if (response?.ok && Array.isArray(response.data)) {
      categories = (response.data as CategoryItem[]).filter((category) => category.id && category.name.toLowerCase() !== "uncategorized");
      renderCategoryOptions();
    }
  }).catch(() => {});

  categoryTrigger?.addEventListener("click", (event) => {
    event.stopPropagation();
    setMenuOpen(!menuOpen);
  });

  const closePrompt = (): void => {
    overlay.remove();
    quickCreateCreditCardPromptEl = null;
    document.removeEventListener("keydown", escHandler, true);
    document.removeEventListener("click", outsideClickHandler, { capture: true });
  };

  const collectValues = (): QuickCreateCreditCardValues | null => {
    if (!validate() || !titleInput || !cardholderInput || !cardTypeInput || !cardNumberInput || !verificationInput || !expiryInput || !validFromInput || !bankInput || !urlInput) {
      return null;
    }

    return {
      title: titleInput.value.trim(),
      cardholder: cardholderInput.value.trim(),
      cardType: cardTypeInput.value.trim(),
      cardNumber: cardNumberInput.value.trim(),
      verificationNumber: verificationInput.value.trim(),
      expiryDate: normalizeCapturedCardDate(expiryInput.value),
      validFrom: normalizeCapturedCardDate(validFromInput.value),
      issuingBank: bankInput.value.trim(),
      url: urlInput.value.trim(),
      metadata: metadataFields
        .map((field) => ({ ...field, label: field.label.trim(), value: field.value.trim() }))
        .filter((field) => field.label || field.value),
    };
  };

  saveButton?.addEventListener("click", () => {
    const values = collectValues();
    if (!values) return;
    closePrompt();
    onSave(values, selectedCategoryId);
  });

  const cancel = () => {
    closePrompt();
    onCancel();
  };

  card.querySelector("#lp-qcc-cancel")?.addEventListener("click", cancel);
  card.querySelector("#lp-qcc-close")?.addEventListener("click", cancel);
  overlay.addEventListener("click", (event) => {
    if (event.composedPath()[0] === overlay) cancel();
  });

  const escHandler = (event: KeyboardEvent) => {
    if (event.key === "Escape") {
      event.preventDefault();
      cancel();
    }
  };
  document.addEventListener("keydown", escHandler, true);

  const outsideClickHandler = (event: MouseEvent): void => {
    if (!menuOpen || !categoryWrap) return;
    if (event.composedPath().includes(categoryWrap)) return;
    setMenuOpen(false);
  };
  document.addEventListener("click", outsideClickHandler, { capture: true });

  validate();
  setTimeout(() => cardNumberInput?.focus(), 60);
}

async function openCreditCardSavePrompt(field: FillableField): Promise<void> {
  const draft = collectCreditCardDraft(field);
  if (!draft) {
    showSaveResultToast(false, "Enter a card number before saving");
    return;
  }

  hidePopup();
  dismissLoginAutofillPrompt();

  showQuickCreateCreditCardPrompt(
    draft,
    async (values, categoryUuid) => {
      try {
        const response = await browser.runtime.sendMessage({
          type: "SAVE_CREDIT_CARD",
          payload: {
            title: values.title,
            cardholder: values.cardholder,
            cardType: values.cardType,
            cardNumber: values.cardNumber,
            verificationNumber: values.verificationNumber,
            expiryDate: values.expiryDate,
            validFrom: values.validFrom,
            issuingBank: values.issuingBank,
            url: values.url,
            categoryUuid,
            customFields: values.metadata.map((field) => ({
              label: field.label,
              value: field.value,
              secret: field.secret ?? false,
            })),
          },
        });
        if (response?.ok) {
          showSaveResultToast(true, "Credit card saved to LumenPass");
        } else {
          showSaveResultToast(false, response?.error ?? "Failed to save credit card");
        }
      } catch {
        showSaveResultToast(false, "Failed to save credit card");
      }
    },
    () => { /* user dismissed */ },
  );
}

// ─── Quick Create Login modal (right-click → LumenPass) ──────────────────────

interface QuickCreateLoginInfo {
  title: string;
  url: string;
}

interface QuickCreateLoginValues {
  title: string;
  username: string;
  password: string;
  url: string;
  totp: string;
  notes: string;
  metadata: SaveLoginMetadataField[];
}

let quickCreatePromptEl: HTMLDivElement | null = null;

function showQuickCreateLoginPrompt(
  info: QuickCreateLoginInfo,
  onSave: (values: QuickCreateLoginValues, categoryUuid: string) => void,
  onCancel: () => void,
): void {
  if (quickCreatePromptEl) quickCreatePromptEl.remove();

  ensurePkAnimStyle();

  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1f2937" : "#ffffff";
  const text = isDark ? "#f3f4f6" : "#111827";
  const subText = isDark ? "#9ca3af" : "#6b7280";
  const border = isDark ? "#374151" : "#e5e7eb";
  const inputBg = isDark ? "#111827" : "#f8fafc";
  const overlayBg = isDark ? "rgba(2,6,23,0.55)" : "rgba(15,23,42,0.32)";
  const danger = "#dc2626";
  let metadataFields: SaveLoginMetadataField[] = [];

  const escapeHtml = (value: string): string => value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#39;");

  const fieldStyle = `width:100%;box-sizing:border-box;padding:9px 11px;background:${inputBg};border:1px solid ${border};border-radius:8px;font-size:13px;color:${text};outline:none;font-family:inherit;`;
  const labelStyle = `font-size:10px;color:${subText};margin:0 0 4px 0;font-weight:600;text-transform:uppercase;letter-spacing:0.4px;`;

  const overlay = document.createElement("div");
  overlay.setAttribute("data-lp-prompt-modal", "true");
  overlay.style.cssText = `
    position: fixed; inset: 0; z-index: 2147483647;
    background: ${overlayBg};
    display: flex; align-items: flex-start; justify-content: center;
    padding: 48px 16px; overflow-y: auto;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    animation: lp-slide-up 0.18s ease-out;
  `;

  const card = document.createElement("div");
  card.style.cssText = `
    width: 100%; max-width: 460px; background: ${bg};
    border: 1px solid ${border}; border-radius: 14px;
    box-shadow: 0 24px 60px rgba(15,23,42,0.28);
    overflow: hidden;
  `;
  overlay.appendChild(card);

  const headerLockSvg = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#444ce7" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`;
  const eyeSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>`;
  const refreshSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>`;
  const copySvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>`;

  card.innerHTML = `
    <div style="display:flex;align-items:center;gap:10px;padding:14px 16px;border-bottom:1px solid ${isDark ? "#2d2d3d" : "#f3f4f6"};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:22px;height:22px;flex-shrink:0;border-radius:7px;background:${isDark ? "#1e1b4b" : "#eef4ff"};">${headerLockSvg}</span>
      <p style="color:${text};font-size:14px;font-weight:700;margin:0;flex:1;">New login</p>
      <button id="lp-qc-close" type="button" aria-label="Close" style="background:none;border:none;cursor:pointer;color:${subText};font-size:22px;padding:0 4px;line-height:1;">&times;</button>
    </div>
    <div style="padding:14px 16px;max-height:calc(100vh - 160px);overflow:auto;">
      <div style="margin-bottom:10px;"><div id="lp-qc-category-wrap" style="position:relative;"><button id="lp-qc-category-trigger" type="button" style="width:100%;display:flex;align-items:center;gap:8px;border:1px solid ${border};border-radius:999px;background:${inputBg};padding:7px 13px;cursor:pointer;text-align:left;"><span style="display:flex;align-items:center;justify-content:center;width:16px;height:16px;flex-shrink:0;"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#64748b" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"/></svg></span><span id="lp-qc-category-label" style="min-width:0;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:500;color:${text};">Uncategorized</span><span id="lp-qc-category-chevron" style="display:flex;align-items:center;justify-content:center;flex-shrink:0;color:#6b7280;transition:transform 0.16s ease;"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg></span></button><div id="lp-qc-category-menu" style="display:none;position:absolute;top:calc(100% + 6px);left:0;right:0;z-index:2;overflow:hidden;border:1px solid ${isDark ? "#374151" : "#d9e5ff"};border-radius:12px;background:${bg};box-shadow:0 8px 24px rgba(15,23,42,0.18);max-height:220px;"><div id="lp-qc-category-options" style="padding:6px 0;max-height:220px;overflow:auto;"></div></div></div></div>
      <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:10px;">
        <label><p style="${labelStyle}">Name</p><input id="lp-qc-title" type="text" value="${escapeHtml(info.title)}" placeholder="e.g. Gmail" style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">Username</p><input id="lp-qc-username" type="text" placeholder="Username or email" style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">Password</p>
          <div style="display:flex;gap:6px;">
            <input id="lp-qc-password" type="password" value="" placeholder="Strong password" style="${fieldStyle}font-family:ui-monospace,SFMono-Regular,Menlo,monospace;" />
            <button id="lp-qc-toggle-password" type="button" aria-pressed="false" title="Reveal" style="flex:0 0 auto;border:1px solid ${border};background:${bg};color:${text};border-radius:8px;padding:0 9px;font-size:12px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;">${eyeSvg}</button>
            <button id="lp-qc-gen-password" type="button" title="Generate" style="flex:0 0 auto;border:1px solid ${border};background:${bg};color:${text};border-radius:8px;padding:0 9px;font-size:12px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;">${refreshSvg}</button>
            <button id="lp-qc-copy-password" type="button" title="Copy" style="flex:0 0 auto;border:1px solid ${border};background:${bg};color:${text};border-radius:8px;padding:0 9px;font-size:12px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;">${copySvg}</button>
          </div>
          <div style="display:flex;align-items:center;gap:8px;margin-top:6px;flex-wrap:wrap;">
            <span style="font-size:10px;color:${subText};font-weight:600;text-transform:uppercase;letter-spacing:0.4px;">Generator</span>
            <select id="lp-qc-gen-type" style="border:1px solid ${border};background:${inputBg};color:${text};border-radius:6px;padding:3px 7px;font-size:11px;outline:none;cursor:pointer;">
              <option value="smart">Smart</option>
              <option value="memorable">Memorable</option>
              <option value="pin">PIN</option>
            </select>
            <span id="lp-qc-strength" style="font-size:11px;color:${subText};"></span>
          </div>
        </label>
        <label><p style="${labelStyle}">URL</p><input id="lp-qc-url" type="url" value="${escapeHtml(info.url)}" style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">One-time password (optional)</p><input id="lp-qc-totp" type="text" placeholder="otpauth:// or Base32 secret" style="${fieldStyle}font-family:ui-monospace,SFMono-Regular,Menlo,monospace;" /></label>
        <label><p style="${labelStyle}">Notes</p><textarea id="lp-qc-notes" rows="3" placeholder="Anything else worth remembering" style="${fieldStyle}resize:vertical;min-height:64px;font-family:inherit;"></textarea></label>
      </div>
      <div style="margin-bottom:12px;"><div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;"><p style="${labelStyle.replace('margin:0 0 4px 0;', 'margin:0;')}">Custom fields</p><button id="lp-qc-add-meta" type="button" style="border:none;background:none;color:#444ce7;font-size:11px;font-weight:600;cursor:pointer;padding:0;">+ Add field</button></div><div id="lp-qc-metadata-fields" style="display:flex;flex-direction:column;gap:6px;"></div></div>
      <p id="lp-qc-validation" style="display:none;color:${danger};font-size:12px;margin:0 0 10px 0;line-height:1.4;"></p>
      <div style="display:flex;gap:8px;">
        <button id="lp-qc-cancel" type="button" style="flex:0 0 auto;background:none;border:1px solid ${border};border-radius:9px;padding:9px 14px;font-size:13px;color:${subText};cursor:pointer;font-weight:500;">Cancel</button>
        <button id="lp-qc-save" type="button" style="flex:1;background:#444ce7;color:white;border:none;border-radius:9px;padding:9px 0;font-size:13px;font-weight:600;cursor:pointer;">Save login</button>
      </div>
    </div>
  `;

  lpAppend(overlay);
  quickCreatePromptEl = overlay as HTMLDivElement;

  const titleInput = card.querySelector<HTMLInputElement>("#lp-qc-title");
  const usernameInput = card.querySelector<HTMLInputElement>("#lp-qc-username");
  const passwordInput = card.querySelector<HTMLInputElement>("#lp-qc-password");
  const urlInput = card.querySelector<HTMLInputElement>("#lp-qc-url");
  const totpInput = card.querySelector<HTMLInputElement>("#lp-qc-totp");
  const notesInput = card.querySelector<HTMLTextAreaElement>("#lp-qc-notes");
  const validationEl = card.querySelector<HTMLParagraphElement>("#lp-qc-validation");
  const metadataContainer = card.querySelector<HTMLDivElement>("#lp-qc-metadata-fields");
  const saveButton = card.querySelector<HTMLButtonElement>("#lp-qc-save");
  const strengthEl = card.querySelector<HTMLSpanElement>("#lp-qc-strength");
  const genTypeSelect = card.querySelector<HTMLSelectElement>("#lp-qc-gen-type");

  const validate = (): boolean => {
    const errors: string[] = [];
    if (!titleInput?.value.trim()) errors.push("Name is required.");
    if (!passwordInput?.value) errors.push("Password is required.");
    const rawUrl = urlInput?.value.trim() ?? "";
    if (!rawUrl) errors.push("URL is required.");
    else {
      try {
        const parsed = new URL(rawUrl);
        if (!["http:", "https:"].includes(parsed.protocol)) errors.push("URL must start with http:// or https://.");
      } catch {
        errors.push("URL must be valid.");
      }
    }
    metadataFields.forEach((field) => {
      if (field.value.trim() && !field.label.trim()) errors.push("Custom field labels are required when values are filled.");
    });
    const ok = errors.length === 0;
    if (validationEl) {
      validationEl.textContent = errors[0] ?? "";
      validationEl.style.display = ok ? "none" : "block";
    }
    if (saveButton) {
      saveButton.disabled = !ok;
      saveButton.style.opacity = ok ? "1" : "0.55";
      saveButton.style.cursor = ok ? "pointer" : "not-allowed";
    }
    return ok;
  };

  const updateStrength = (): void => {
    if (!strengthEl || !passwordInput) return;
    const value = passwordInput.value;
    if (!value) {
      strengthEl.textContent = "";
      strengthEl.style.color = subText;
      return;
    }
    const length = value.length;
    const hasLower = /[a-z]/.test(value);
    const hasUpper = /[A-Z]/.test(value);
    const hasDigit = /\d/.test(value);
    const hasSymbol = /[^A-Za-z0-9]/.test(value);
    const variety = [hasLower, hasUpper, hasDigit, hasSymbol].filter(Boolean).length;
    let label = "Weak", color = "#dc2626";
    if (length >= 16 && variety >= 3) { label = "Strong"; color = "#16a34a"; }
    else if (length >= 12 && variety >= 3) { label = "Good"; color = "#0891b2"; }
    else if (length >= 8 && variety >= 2) { label = "Fair"; color = "#d97706"; }
    strengthEl.textContent = `Strength: ${label} (${length} chars)`;
    strengthEl.style.color = color;
  };

  const renderMetadata = (): void => {
    if (!metadataContainer) return;
    metadataContainer.innerHTML = "";
    metadataFields.forEach((field) => {
      const row = document.createElement("div");
      row.style.cssText = `display:grid;grid-template-columns:1fr 1.25fr auto;gap:6px;align-items:center;`;
      row.innerHTML = `<input data-meta-label="${escapeHtml(field.id)}" type="text" value="${escapeHtml(field.label)}" placeholder="Label" style="${fieldStyle}" /><input data-meta-value="${escapeHtml(field.id)}" type="${field.secret ? "password" : "text"}" value="${escapeHtml(field.value)}" placeholder="Value" style="${fieldStyle}" /><button data-meta-remove="${escapeHtml(field.id)}" type="button" style="border:1px solid ${border};background:${bg};color:${subText};border-radius:8px;padding:8px 9px;cursor:pointer;font-size:12px;">Delete</button>`;
      metadataContainer.appendChild(row);
    });
    metadataContainer.querySelectorAll<HTMLInputElement>("[data-meta-label]").forEach((input) => {
      input.addEventListener("input", () => {
        const field = metadataFields.find((item) => item.id === input.dataset.metaLabel);
        if (field) field.label = input.value;
        validate();
      });
    });
    metadataContainer.querySelectorAll<HTMLInputElement>("[data-meta-value]").forEach((input) => {
      input.addEventListener("input", () => {
        const field = metadataFields.find((item) => item.id === input.dataset.metaValue);
        if (field) field.value = input.value;
        validate();
      });
    });
    metadataContainer.querySelectorAll<HTMLButtonElement>("[data-meta-remove]").forEach((button) => {
      button.addEventListener("click", () => {
        metadataFields = metadataFields.filter((item) => item.id !== button.dataset.metaRemove);
        renderMetadata();
        validate();
      });
    });
  };

  renderMetadata();

  card.querySelector("#lp-qc-add-meta")?.addEventListener("click", () => {
    metadataFields.push({ id: `qcmeta-${Date.now()}-${metadataFields.length}`, label: "", value: "", secret: false });
    renderMetadata();
    validate();
  });

  card.querySelector("#lp-qc-toggle-password")?.addEventListener("click", () => {
    if (!passwordInput) return;
    const reveal = passwordInput.type === "password";
    passwordInput.type = reveal ? "text" : "password";
    const button = card.querySelector<HTMLButtonElement>("#lp-qc-toggle-password");
    if (button) button.setAttribute("aria-pressed", reveal ? "true" : "false");
  });

  card.querySelector("#lp-qc-gen-password")?.addEventListener("click", () => {
    if (!passwordInput || !genTypeSelect) return;
    const type = (genTypeSelect.value || "smart") as GeneratorType;
    try {
      passwordInput.value = generatePassword(type);
      passwordInput.dispatchEvent(new Event("input", { bubbles: true }));
    } catch { /* ignore */ }
  });

  card.querySelector("#lp-qc-copy-password")?.addEventListener("click", async () => {
    if (!passwordInput?.value) return;
    try {
      await navigator.clipboard.writeText(passwordInput.value);
      showSaveResultToast(true, "Password copied");
    } catch {
      showSaveResultToast(false, "Copy failed");
    }
  });

  [titleInput, usernameInput, urlInput, totpInput].forEach((input) => input?.addEventListener("input", validate));
  notesInput?.addEventListener("input", validate);
  passwordInput?.addEventListener("input", () => {
    updateStrength();
    validate();
  });

  // Category picker
  const categoryTrigger = card.querySelector<HTMLButtonElement>("#lp-qc-category-trigger");
  const categoryLabel = card.querySelector<HTMLSpanElement>("#lp-qc-category-label");
  const categoryChevron = card.querySelector<HTMLSpanElement>("#lp-qc-category-chevron");
  const categoryMenu = card.querySelector<HTMLDivElement>("#lp-qc-category-menu");
  const categoryOptions = card.querySelector<HTMLDivElement>("#lp-qc-category-options");
  const categoryWrap = card.querySelector<HTMLDivElement>("#lp-qc-category-wrap");
  let selectedCategoryId = "";
  let menuOpen = false;
  let categories: CategoryItem[] = [];

  const setMenuOpen = (open: boolean): void => {
    menuOpen = open;
    if (categoryMenu) categoryMenu.style.display = open ? "block" : "none";
    if (categoryChevron) categoryChevron.style.transform = open ? "rotate(180deg)" : "rotate(0deg)";
  };

  const renderCategoryOptions = (): void => {
    if (!categoryOptions) return;
    const optionList: CategoryItem[] = [{ id: "", name: "Uncategorized" }, ...categories];
    categoryOptions.innerHTML = "";
    optionList.forEach((category) => {
      const selected = category.id === selectedCategoryId;
      const option = document.createElement("button");
      option.type = "button";
      option.style.cssText = `width:100%;display:flex;align-items:center;gap:10px;padding:10px 14px;border:none;background:${selected ? (isDark ? "#1f2937" : "#eef4ff") : "transparent"};cursor:pointer;text-align:left;`;
      option.innerHTML = `<span style="display:flex;align-items:center;justify-content:center;width:20px;height:20px;flex-shrink:0;"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="${selected ? "#444ce7" : "#64748b"}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"/></svg></span><span style="min-width:0;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:${selected ? "600" : "500"};color:${text};">${escapeHtml(category.name)}</span>${selected ? `<span style="display:flex;align-items:center;justify-content:center;color:#444ce7;flex-shrink:0;"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg></span>` : ""}`;
      option.addEventListener("click", () => {
        selectedCategoryId = category.id;
        if (categoryLabel) categoryLabel.textContent = category.name;
        setMenuOpen(false);
        renderCategoryOptions();
      });
      categoryOptions.appendChild(option);
    });
  };

  renderCategoryOptions();
  void browser.runtime.sendMessage({ type: "GET_CATEGORIES" }).then((response) => {
    if (response?.ok && Array.isArray(response.data)) {
      categories = (response.data as CategoryItem[]).filter((category) => category.id && category.name.toLowerCase() !== "uncategorized");
      renderCategoryOptions();
    }
  }).catch(() => {});

  categoryTrigger?.addEventListener("click", (event) => {
    event.stopPropagation();
    setMenuOpen(!menuOpen);
  });

  const closePrompt = (): void => {
    overlay.remove();
    quickCreatePromptEl = null;
  };

  const collectValues = (): QuickCreateLoginValues | null => {
    if (!validate() || !titleInput || !usernameInput || !passwordInput || !urlInput) return null;
    return {
      title: titleInput.value.trim(),
      username: usernameInput.value.trim(),
      password: passwordInput.value,
      url: urlInput.value.trim(),
      totp: totpInput?.value.trim() ?? "",
      notes: notesInput?.value.trim() ?? "",
      metadata: metadataFields
        .map((field) => ({ ...field, label: field.label.trim(), value: field.value.trim() }))
        .filter((field) => field.label || field.value),
    };
  };

  saveButton?.addEventListener("click", () => {
    const values = collectValues();
    if (!values) return;
    closePrompt();
    onSave(values, selectedCategoryId);
  });

  const cancel = () => { closePrompt(); onCancel(); };
  card.querySelector("#lp-qc-cancel")?.addEventListener("click", cancel);
  card.querySelector("#lp-qc-close")?.addEventListener("click", cancel);
  overlay.addEventListener("click", (event) => {
    if (event.composedPath()[0] === overlay) cancel();
  });

  const escHandler = (event: KeyboardEvent) => {
    if (event.key === "Escape") {
      event.preventDefault();
      cancel();
      document.removeEventListener("keydown", escHandler, true);
    }
  };
  document.addEventListener("keydown", escHandler, true);

  const outsideClickHandler = (event: MouseEvent): void => {
    if (!menuOpen || !categoryWrap) return;
    if (event.composedPath().includes(categoryWrap)) return;
    setMenuOpen(false);
  };
  document.addEventListener("click", outsideClickHandler, { capture: true });

  updateStrength();
  validate();
  setTimeout(() => titleInput?.focus(), 60);
}

// ─── Track last right-clicked input for Password Generator ──────────────────
document.addEventListener("contextmenu", (e) => {
  const target = e.target;
  if (
    target instanceof HTMLInputElement
    && target.isConnected
    && isEditableInput(target)
  ) {
    lastContextMenuField = target;
  }
}, true);

// ─── Password Generator modal (right-click → LumenPass → Password Generator) ──

let passwordGeneratorModalEl: HTMLDivElement | null = null;

interface PasswordGeneratorOptions {
  initialTargetField?: HTMLInputElement | null;
}

function showPasswordGeneratorModal(options: PasswordGeneratorOptions = {}): void {
  if (passwordGeneratorModalEl) passwordGeneratorModalEl.remove();

  ensurePkAnimStyle();

  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1f2937" : "#ffffff";
  const text = isDark ? "#f3f4f6" : "#111827";
  const subText = isDark ? "#9ca3af" : "#6b7280";
  const border = isDark ? "#374151" : "#e5e7eb";
  const inputBg = isDark ? "#111827" : "#f8fafc";
  const overlayBg = isDark ? "rgba(2,6,23,0.55)" : "rgba(15,23,42,0.32)";
  const accent = "#444ce7";

  let currentType: GeneratorType = "smart";
  let length = getGeneratorConfig(currentType).length;
  let includeLetters = true;
  let includeNumbers = true;
  let includeSymbols = true;
  let password = "";

  const passwordTargetField = options.initialTargetField && options.initialTargetField.isConnected
    ? options.initialTargetField
    : null;

  const escapeHtml = (value: string): string => value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#39;");

  const overlay = document.createElement("div");
  overlay.setAttribute("data-lp-prompt-modal", "true");
  overlay.style.cssText = `
    position: fixed; inset: 0; z-index: 2147483647;
    background: ${overlayBg};
    display: flex; align-items: flex-start; justify-content: center;
    padding: 56px 16px; overflow-y: auto;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    animation: lp-slide-up 0.18s ease-out;
  `;

  const card = document.createElement("div");
  card.style.cssText = `
    width: 100%; max-width: 460px; background: ${bg};
    border: 1px solid ${border}; border-radius: 14px;
    box-shadow: 0 24px 60px rgba(15,23,42,0.28);
    overflow: hidden;
  `;
  overlay.appendChild(card);

  const keyIconSvg = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="${accent}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="7" cy="14" r="4"/><path d="M21 4l-9 9"/><path d="M14 10l3 3"/><path d="M17 7l3 3"/></svg>`;
  const refreshSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>`;
  const copySvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>`;
  const checkSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`;

  card.innerHTML = `
    <div style="display:flex;align-items:center;gap:10px;padding:14px 16px;border-bottom:1px solid ${isDark ? "#2d2d3d" : "#f3f4f6"};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:22px;height:22px;flex-shrink:0;border-radius:7px;background:${isDark ? "#1e1b4b" : "#eef4ff"};">${keyIconSvg}</span>
      <p style="color:${text};font-size:14px;font-weight:700;margin:0;flex:1;">Password Generator</p>
      <button id="lp-pg-close" type="button" aria-label="Close" style="background:none;border:none;cursor:pointer;color:${subText};font-size:22px;padding:0 4px;line-height:1;">&times;</button>
    </div>
    <div style="padding:14px 16px;display:flex;flex-direction:column;gap:14px;">
      <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;">
        <span style="font-size:13px;font-weight:600;color:${subText};">Type</span>
        <div style="position:relative;">
          <select id="lp-pg-type" style="appearance:none;-webkit-appearance:none;border:1px solid ${border};background:${inputBg};color:${text};border-radius:999px;padding:7px 32px 7px 14px;font-size:13px;font-weight:600;cursor:pointer;outline:none;">
            <option value="smart">Smart Password</option>
            <option value="memorable">Memorable Password</option>
            <option value="pin">PIN Code</option>
          </select>
          <span style="pointer-events:none;position:absolute;right:11px;top:50%;transform:translateY(-50%);color:${subText};display:inline-flex;"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg></span>
        </div>
      </div>

      <div style="border:1px solid ${border};background:${inputBg};border-radius:12px;padding:12px 14px;display:flex;align-items:center;gap:8px;">
        <span id="lp-pg-value" style="flex:1;min-width:0;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:14px;color:${text};word-break:break-all;letter-spacing:0.02em;">…</span>
        <button id="lp-pg-regen" type="button" title="Regenerate" style="flex:0 0 auto;border:1px solid ${border};background:${bg};color:${text};border-radius:8px;padding:6px 9px;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;">${refreshSvg}</button>
        <button id="lp-pg-copy" type="button" title="Copy" style="flex:0 0 auto;border:1px solid ${border};background:${bg};color:${text};border-radius:8px;padding:6px 9px;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;">${copySvg}</button>
      </div>
      <span id="lp-pg-strength" style="font-size:12px;color:${subText};margin-top:-6px;"></span>

      <div>
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;">
          <span style="font-size:13px;font-weight:600;color:${subText};">Length</span>
          <span id="lp-pg-length-value" style="font-size:13px;font-weight:700;color:${text};">${length}</span>
        </div>
        <input id="lp-pg-length" type="range" min="6" max="64" value="${length}" style="width:100%;accent-color:${accent};" />
      </div>

      <div style="display:flex;flex-direction:column;gap:8px;border:1px solid ${border};border-radius:12px;padding:10px 12px;background:${inputBg};">
        <label style="display:flex;align-items:center;gap:10px;font-size:13px;color:${text};cursor:pointer;">
          <input id="lp-pg-letters" type="checkbox" ${includeLetters ? "checked" : ""} style="width:16px;height:16px;accent-color:${accent};cursor:pointer;" />
          <span style="flex:1;">Letters <span style="color:${subText};font-size:11px;">(A-Z, a-z)</span></span>
        </label>
        <label style="display:flex;align-items:center;gap:10px;font-size:13px;color:${text};cursor:pointer;">
          <input id="lp-pg-numbers" type="checkbox" ${includeNumbers ? "checked" : ""} style="width:16px;height:16px;accent-color:${accent};cursor:pointer;" />
          <span style="flex:1;">Numbers <span style="color:${subText};font-size:11px;">(0-9)</span></span>
        </label>
        <label style="display:flex;align-items:center;gap:10px;font-size:13px;color:${text};cursor:pointer;">
          <input id="lp-pg-symbols" type="checkbox" ${includeSymbols ? "checked" : ""} style="width:16px;height:16px;accent-color:${accent};cursor:pointer;" />
          <span style="flex:1;">Symbols <span style="color:${subText};font-size:11px;">(!@#$ …)</span></span>
        </label>
      </div>

      <p id="lp-pg-toast" style="display:none;font-size:12px;color:${accent};margin:0;line-height:1.4;font-weight:600;"></p>

      <div style="display:flex;gap:8px;">
        <button id="lp-pg-cancel" type="button" style="flex:0 0 auto;background:none;border:1px solid ${border};border-radius:9px;padding:9px 14px;font-size:13px;color:${subText};cursor:pointer;font-weight:500;">Close</button>
        <button id="lp-pg-fill" type="button" style="flex:1;background:${accent};color:white;border:none;border-radius:9px;padding:9px 0;font-size:13px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:6px;">${passwordTargetField ? "Copy & Fill" : "Copy & close"}</button>
      </div>
    </div>
  `;

  lpAppend(overlay);
  passwordGeneratorModalEl = overlay as HTMLDivElement;

  const valueEl = card.querySelector<HTMLSpanElement>("#lp-pg-value");
  const strengthEl = card.querySelector<HTMLSpanElement>("#lp-pg-strength");
  const lengthInput = card.querySelector<HTMLInputElement>("#lp-pg-length");
  const lengthValueEl = card.querySelector<HTMLSpanElement>("#lp-pg-length-value");
  const typeSelect = card.querySelector<HTMLSelectElement>("#lp-pg-type");
  const lettersInput = card.querySelector<HTMLInputElement>("#lp-pg-letters");
  const numbersInput = card.querySelector<HTMLInputElement>("#lp-pg-numbers");
  const symbolsInput = card.querySelector<HTMLInputElement>("#lp-pg-symbols");
  const toastEl = card.querySelector<HTMLParagraphElement>("#lp-pg-toast");

  let toastTimer: number | null = null;
  const showInlineToast = (msg: string) => {
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.style.display = "block";
    if (toastTimer !== null) window.clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => {
      toastEl.style.display = "none";
    }, 1800);
  };

  const updateStrength = (): void => {
    if (!strengthEl) return;
    if (!password) {
      strengthEl.textContent = "";
      strengthEl.style.color = subText;
      return;
    }
    const len = password.length;
    const hasLower = /[a-z]/.test(password);
    const hasUpper = /[A-Z]/.test(password);
    const hasDigit = /\d/.test(password);
    const hasSymbol = /[^A-Za-z0-9]/.test(password);
    const variety = [hasLower, hasUpper, hasDigit, hasSymbol].filter(Boolean).length;
    let label = "Weak", color = "#dc2626";
    if (len >= 16 && variety >= 3) { label = "Strong"; color = "#16a34a"; }
    else if (len >= 12 && variety >= 3) { label = "Good"; color = "#0891b2"; }
    else if (len >= 8 && variety >= 2) { label = "Fair"; color = "#d97706"; }
    strengthEl.textContent = `Strength: ${label} (${len} chars)`;
    strengthEl.style.color = color;
  };

  const regenerate = (): void => {
    try {
      password = generatePasswordFromConfig({
        length,
        includeUppercase: includeLetters,
        includeLowercase: includeLetters,
        includeNumbers,
        includeSymbols,
      });
    } catch {
      password = "";
      showInlineToast("Choose at least one character set");
    }
    if (valueEl) valueEl.textContent = password || "—";
    updateStrength();
  };

  const applyType = (type: GeneratorType): void => {
    currentType = type;
    const config = getGeneratorConfig(type);
    length = config.length;
    includeLetters = config.includeLowercase || config.includeUppercase;
    includeNumbers = config.includeNumbers;
    includeSymbols = config.includeSymbols;
    if (lengthInput) lengthInput.value = String(length);
    if (lengthValueEl) lengthValueEl.textContent = String(length);
    if (lettersInput) lettersInput.checked = includeLetters;
    if (numbersInput) numbersInput.checked = includeNumbers;
    if (symbolsInput) symbolsInput.checked = includeSymbols;
    regenerate();
  };

  applyType("smart");
  if (typeSelect) typeSelect.value = currentType;

  typeSelect?.addEventListener("change", () => {
    applyType((typeSelect.value || "smart") as GeneratorType);
  });

  lengthInput?.addEventListener("input", () => {
    length = Number(lengthInput.value);
    if (lengthValueEl) lengthValueEl.textContent = String(length);
    regenerate();
  });

  const handleSetToggle = (key: "letters" | "numbers" | "symbols", checked: boolean) => {
    const next = { letters: includeLetters, numbers: includeNumbers, symbols: includeSymbols, [key]: checked } as Record<"letters"|"numbers"|"symbols", boolean>;
    if (!next.letters && !next.numbers && !next.symbols) {
      showInlineToast("Choose at least one character set");
      if (key === "letters" && lettersInput) lettersInput.checked = includeLetters;
      if (key === "numbers" && numbersInput) numbersInput.checked = includeNumbers;
      if (key === "symbols" && symbolsInput) symbolsInput.checked = includeSymbols;
      return;
    }
    includeLetters = next.letters;
    includeNumbers = next.numbers;
    includeSymbols = next.symbols;
    regenerate();
  };

  lettersInput?.addEventListener("change", () => handleSetToggle("letters", lettersInput.checked));
  numbersInput?.addEventListener("change", () => handleSetToggle("numbers", numbersInput.checked));
  symbolsInput?.addEventListener("change", () => handleSetToggle("symbols", symbolsInput.checked));

  card.querySelector("#lp-pg-regen")?.addEventListener("click", regenerate);

  card.querySelector("#lp-pg-copy")?.addEventListener("click", async () => {
    if (!password) return;
    try {
      await navigator.clipboard.writeText(password);
      showInlineToast("Password copied to clipboard");
    } catch {
      showInlineToast("Copy failed — select and copy manually");
    }
  });

  const closeModal = (): void => {
    if (toastTimer !== null) window.clearTimeout(toastTimer);
    overlay.remove();
    passwordGeneratorModalEl = null;
    document.removeEventListener("keydown", escHandler, true);
  };

  card.querySelector("#lp-pg-cancel")?.addEventListener("click", closeModal);
  card.querySelector("#lp-pg-close")?.addEventListener("click", closeModal);
  overlay.addEventListener("click", (event) => {
    if (event.composedPath()[0] === overlay) closeModal();
  });

  const escHandler = (event: KeyboardEvent) => {
    if (event.key === "Escape") {
      event.preventDefault();
      closeModal();
    }
  };
  document.addEventListener("keydown", escHandler, true);

  card.querySelector("#lp-pg-fill")?.addEventListener("click", async () => {
    if (!password) return;
    if (passwordTargetField && passwordTargetField.isConnected) {
      try {
        passwordTargetField.focus();
        const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value")?.set;
        setter?.call(passwordTargetField, password);
        passwordTargetField.dispatchEvent(new Event("input", { bubbles: true }));
        passwordTargetField.dispatchEvent(new Event("change", { bubbles: true }));
        lastExtensionAutofillPasswordByField.set(passwordTargetField, password);
        showInlineToast("Filled into the page");
      } catch {
        showInlineToast("Could not fill the page field");
      }
    }
    try {
      await navigator.clipboard.writeText(password);
      if (!passwordTargetField) showInlineToast("Password copied to clipboard");
    } catch { /* ignore */ }
    setTimeout(closeModal, 600);
  });

  // Mark password value field — we'll keep last value escaped just in case
  if (valueEl) valueEl.textContent = password || "—";
  // Use escapeHtml to silence unused warnings — title preview tooltips
  if (valueEl && password) valueEl.title = escapeHtml(password);

  updateStrength();
}

// ─── Quick Create Note modal (right-click → LumenPass) ──────────────────────

interface QuickCreateNoteInfo {
  title: string;
  url: string;
  notes: string;
}

interface QuickCreateNoteValues {
  title: string;
  notes: string;
  url: string;
  tags: string[];
  metadata: SaveLoginMetadataField[];
}

let quickCreateNotePromptEl: HTMLDivElement | null = null;

function showQuickCreateNotePrompt(
  info: QuickCreateNoteInfo,
  onSave: (values: QuickCreateNoteValues, categoryUuid: string) => void,
  onCancel: () => void,
): void {
  if (quickCreateNotePromptEl) quickCreateNotePromptEl.remove();

  ensurePkAnimStyle();

  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1f2937" : "#ffffff";
  const text = isDark ? "#f3f4f6" : "#111827";
  const subText = isDark ? "#9ca3af" : "#6b7280";
  const border = isDark ? "#374151" : "#e5e7eb";
  const inputBg = isDark ? "#111827" : "#f8fafc";
  const overlayBg = isDark ? "rgba(2,6,23,0.55)" : "rgba(15,23,42,0.32)";
  const danger = "#dc2626";
  const tagBg = isDark ? "#1e1b4b" : "#eef4ff";
  const tagFg = isDark ? "#c7d2fe" : "#3730a3";

  let metadataFields: SaveLoginMetadataField[] = [];
  let tags: string[] = [];

  const escapeHtml = (value: string): string => value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#39;");

  const fieldStyle = `width:100%;box-sizing:border-box;padding:9px 11px;background:${inputBg};border:1px solid ${border};border-radius:8px;font-size:13px;color:${text};outline:none;font-family:inherit;`;
  const labelStyle = `font-size:10px;color:${subText};margin:0 0 4px 0;font-weight:600;text-transform:uppercase;letter-spacing:0.4px;`;

  const overlay = document.createElement("div");
  overlay.setAttribute("data-lp-prompt-modal", "true");
  overlay.style.cssText = `
    position: fixed; inset: 0; z-index: 2147483647;
    background: ${overlayBg};
    display: flex; align-items: flex-start; justify-content: center;
    padding: 48px 16px; overflow-y: auto;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    animation: lp-slide-up 0.18s ease-out;
  `;

  const card = document.createElement("div");
  card.style.cssText = `
    width: 100%; max-width: 460px; background: ${bg};
    border: 1px solid ${border}; border-radius: 14px;
    box-shadow: 0 24px 60px rgba(15,23,42,0.28);
    overflow: hidden;
  `;
  overlay.appendChild(card);

  const noteIconSvg = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#ca8a04" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><line x1="10" y1="9" x2="8" y2="9"/></svg>`;

  card.innerHTML = `
    <div style="display:flex;align-items:center;gap:10px;padding:14px 16px;border-bottom:1px solid ${isDark ? "#2d2d3d" : "#f3f4f6"};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:22px;height:22px;flex-shrink:0;border-radius:7px;background:${isDark ? "#3b2f0a" : "#fef9c3"};">${noteIconSvg}</span>
      <p style="color:${text};font-size:14px;font-weight:700;margin:0;flex:1;">New secure note</p>
      <button id="lp-qn-close" type="button" aria-label="Close" style="background:none;border:none;cursor:pointer;color:${subText};font-size:22px;padding:0 4px;line-height:1;">&times;</button>
    </div>
    <div style="padding:14px 16px;max-height:calc(100vh - 160px);overflow:auto;">
      <div style="margin-bottom:10px;"><div id="lp-qn-category-wrap" style="position:relative;"><button id="lp-qn-category-trigger" type="button" style="width:100%;display:flex;align-items:center;gap:8px;border:1px solid ${border};border-radius:999px;background:${inputBg};padding:7px 13px;cursor:pointer;text-align:left;"><span style="display:flex;align-items:center;justify-content:center;width:16px;height:16px;flex-shrink:0;"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#64748b" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"/></svg></span><span id="lp-qn-category-label" style="min-width:0;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:500;color:${text};">Uncategorized</span><span id="lp-qn-category-chevron" style="display:flex;align-items:center;justify-content:center;flex-shrink:0;color:#6b7280;transition:transform 0.16s ease;"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg></span></button><div id="lp-qn-category-menu" style="display:none;position:absolute;top:calc(100% + 6px);left:0;right:0;z-index:2;overflow:hidden;border:1px solid ${isDark ? "#374151" : "#d9e5ff"};border-radius:12px;background:${bg};box-shadow:0 8px 24px rgba(15,23,42,0.18);max-height:220px;"><div id="lp-qn-category-options" style="padding:6px 0;max-height:220px;overflow:auto;"></div></div></div></div>
      <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:10px;">
        <label><p style="${labelStyle}">Title</p><input id="lp-qn-title" type="text" value="${escapeHtml(info.title)}" placeholder="e.g. Server credentials" style="${fieldStyle}" /></label>
        <label><p style="${labelStyle}">Note</p><textarea id="lp-qn-notes" rows="6" placeholder="Write your secure note here…" style="${fieldStyle}resize:vertical;min-height:120px;font-family:inherit;line-height:1.5;">${escapeHtml(info.notes)}</textarea><div style="display:flex;align-items:center;justify-content:space-between;margin-top:4px;"><span id="lp-qn-char-count" style="font-size:11px;color:${subText};">0 chars</span></div></label>
        <label><p style="${labelStyle}">URL (optional)</p><input id="lp-qn-url" type="url" value="${escapeHtml(info.url)}" placeholder="https://…" style="${fieldStyle}" /></label>
        <div>
          <p style="${labelStyle}">Tags</p>
          <div id="lp-qn-tags-wrap" style="display:flex;flex-wrap:wrap;gap:6px;align-items:center;padding:6px 8px;background:${inputBg};border:1px solid ${border};border-radius:8px;min-height:38px;">
            <input id="lp-qn-tag-input" type="text" placeholder="Add a tag and press Enter" style="flex:1;min-width:140px;border:none;outline:none;background:transparent;color:${text};font-size:13px;padding:4px 2px;font-family:inherit;" />
          </div>
        </div>
      </div>
      <div style="margin-bottom:12px;"><div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;"><p style="${labelStyle.replace('margin:0 0 4px 0;', 'margin:0;')}">Custom fields</p><button id="lp-qn-add-meta" type="button" style="border:none;background:none;color:#444ce7;font-size:11px;font-weight:600;cursor:pointer;padding:0;">+ Add field</button></div><div id="lp-qn-metadata-fields" style="display:flex;flex-direction:column;gap:6px;"></div></div>
      <p id="lp-qn-validation" style="display:none;color:${danger};font-size:12px;margin:0 0 10px 0;line-height:1.4;"></p>
      <div style="display:flex;gap:8px;">
        <button id="lp-qn-cancel" type="button" style="flex:0 0 auto;background:none;border:1px solid ${border};border-radius:9px;padding:9px 14px;font-size:13px;color:${subText};cursor:pointer;font-weight:500;">Cancel</button>
        <button id="lp-qn-save" type="button" style="flex:1;background:#444ce7;color:white;border:none;border-radius:9px;padding:9px 0;font-size:13px;font-weight:600;cursor:pointer;">Save note</button>
      </div>
    </div>
  `;

  lpAppend(overlay);
  quickCreateNotePromptEl = overlay as HTMLDivElement;

  const titleInput = card.querySelector<HTMLInputElement>("#lp-qn-title");
  const notesInput = card.querySelector<HTMLTextAreaElement>("#lp-qn-notes");
  const urlInput = card.querySelector<HTMLInputElement>("#lp-qn-url");
  const validationEl = card.querySelector<HTMLParagraphElement>("#lp-qn-validation");
  const metadataContainer = card.querySelector<HTMLDivElement>("#lp-qn-metadata-fields");
  const saveButton = card.querySelector<HTMLButtonElement>("#lp-qn-save");
  const charCountEl = card.querySelector<HTMLSpanElement>("#lp-qn-char-count");
  const tagsWrap = card.querySelector<HTMLDivElement>("#lp-qn-tags-wrap");
  const tagInput = card.querySelector<HTMLInputElement>("#lp-qn-tag-input");

  const validate = (): boolean => {
    const errors: string[] = [];
    if (!titleInput?.value.trim()) errors.push("Title is required.");
    if (!notesInput?.value.trim()) errors.push("Note body is required.");
    const rawUrl = urlInput?.value.trim() ?? "";
    if (rawUrl) {
      try {
        const parsed = new URL(rawUrl);
        if (!["http:", "https:"].includes(parsed.protocol)) errors.push("URL must start with http:// or https://.");
      } catch {
        errors.push("URL must be valid.");
      }
    }
    metadataFields.forEach((field) => {
      if (field.value.trim() && !field.label.trim()) errors.push("Custom field labels are required when values are filled.");
    });
    const ok = errors.length === 0;
    if (validationEl) {
      validationEl.textContent = errors[0] ?? "";
      validationEl.style.display = ok ? "none" : "block";
    }
    if (saveButton) {
      saveButton.disabled = !ok;
      saveButton.style.opacity = ok ? "1" : "0.55";
      saveButton.style.cursor = ok ? "pointer" : "not-allowed";
    }
    return ok;
  };

  const updateCharCount = (): void => {
    if (!charCountEl || !notesInput) return;
    const length = notesInput.value.length;
    charCountEl.textContent = `${length.toLocaleString()} char${length === 1 ? "" : "s"}`;
  };

  const renderTags = (): void => {
    if (!tagsWrap || !tagInput) return;
    Array.from(tagsWrap.querySelectorAll<HTMLSpanElement>("[data-lp-tag]")).forEach((node) => node.remove());
    tags.forEach((tag) => {
      const chip = document.createElement("span");
      chip.setAttribute("data-lp-tag", tag);
      chip.style.cssText = `display:inline-flex;align-items:center;gap:5px;background:${tagBg};color:${tagFg};border-radius:999px;padding:3px 9px;font-size:12px;font-weight:500;`;
      chip.innerHTML = `<span>${tag.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</span><button type="button" aria-label="Remove tag" style="border:none;background:none;color:inherit;cursor:pointer;font-size:14px;line-height:1;padding:0;">&times;</button>`;
      chip.querySelector("button")?.addEventListener("click", () => {
        tags = tags.filter((t) => t !== tag);
        renderTags();
      });
      tagsWrap.insertBefore(chip, tagInput);
    });
  };

  const addTagFromInput = (): void => {
    if (!tagInput) return;
    const raw = tagInput.value.trim();
    if (!raw) return;
    raw.split(/[\s,]+/).map((t) => t.trim()).filter(Boolean).forEach((part) => {
      if (!tags.includes(part)) tags.push(part);
    });
    tagInput.value = "";
    renderTags();
  };

  tagInput?.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === ",") {
      event.preventDefault();
      addTagFromInput();
    } else if (event.key === "Backspace" && !tagInput.value && tags.length > 0) {
      tags.pop();
      renderTags();
    }
  });
  tagInput?.addEventListener("blur", () => addTagFromInput());

  const fieldStyleStr = `width:100%;box-sizing:border-box;padding:9px 11px;background:${inputBg};border:1px solid ${border};border-radius:8px;font-size:13px;color:${text};outline:none;font-family:inherit;`;

  const renderMetadata = (): void => {
    if (!metadataContainer) return;
    metadataContainer.innerHTML = "";
    metadataFields.forEach((field) => {
      const row = document.createElement("div");
      row.style.cssText = `display:grid;grid-template-columns:1fr 1.25fr auto;gap:6px;align-items:center;`;
      row.innerHTML = `<input data-meta-label="${escapeHtml(field.id)}" type="text" value="${escapeHtml(field.label)}" placeholder="Label" style="${fieldStyleStr}" /><input data-meta-value="${escapeHtml(field.id)}" type="${field.secret ? "password" : "text"}" value="${escapeHtml(field.value)}" placeholder="Value" style="${fieldStyleStr}" /><button data-meta-remove="${escapeHtml(field.id)}" type="button" style="border:1px solid ${border};background:${bg};color:${subText};border-radius:8px;padding:8px 9px;cursor:pointer;font-size:12px;">Delete</button>`;
      metadataContainer.appendChild(row);
    });
    metadataContainer.querySelectorAll<HTMLInputElement>("[data-meta-label]").forEach((input) => {
      input.addEventListener("input", () => {
        const field = metadataFields.find((item) => item.id === input.dataset.metaLabel);
        if (field) field.label = input.value;
        validate();
      });
    });
    metadataContainer.querySelectorAll<HTMLInputElement>("[data-meta-value]").forEach((input) => {
      input.addEventListener("input", () => {
        const field = metadataFields.find((item) => item.id === input.dataset.metaValue);
        if (field) field.value = input.value;
        validate();
      });
    });
    metadataContainer.querySelectorAll<HTMLButtonElement>("[data-meta-remove]").forEach((button) => {
      button.addEventListener("click", () => {
        metadataFields = metadataFields.filter((item) => item.id !== button.dataset.metaRemove);
        renderMetadata();
        validate();
      });
    });
  };

  renderMetadata();

  card.querySelector("#lp-qn-add-meta")?.addEventListener("click", () => {
    metadataFields.push({ id: `qnmeta-${Date.now()}-${metadataFields.length}`, label: "", value: "", secret: false });
    renderMetadata();
    validate();
  });

  [titleInput, urlInput].forEach((input) => input?.addEventListener("input", validate));
  notesInput?.addEventListener("input", () => {
    updateCharCount();
    validate();
  });

  // Category picker
  const categoryTrigger = card.querySelector<HTMLButtonElement>("#lp-qn-category-trigger");
  const categoryLabel = card.querySelector<HTMLSpanElement>("#lp-qn-category-label");
  const categoryChevron = card.querySelector<HTMLSpanElement>("#lp-qn-category-chevron");
  const categoryMenu = card.querySelector<HTMLDivElement>("#lp-qn-category-menu");
  const categoryOptions = card.querySelector<HTMLDivElement>("#lp-qn-category-options");
  const categoryWrap = card.querySelector<HTMLDivElement>("#lp-qn-category-wrap");
  let selectedCategoryId = "";
  let menuOpen = false;
  let categories: CategoryItem[] = [];

  const setMenuOpen = (open: boolean): void => {
    menuOpen = open;
    if (categoryMenu) categoryMenu.style.display = open ? "block" : "none";
    if (categoryChevron) categoryChevron.style.transform = open ? "rotate(180deg)" : "rotate(0deg)";
  };

  const renderCategoryOptions = (): void => {
    if (!categoryOptions) return;
    const optionList: CategoryItem[] = [{ id: "", name: "Uncategorized" }, ...categories];
    categoryOptions.innerHTML = "";
    optionList.forEach((category) => {
      const selected = category.id === selectedCategoryId;
      const option = document.createElement("button");
      option.type = "button";
      option.style.cssText = `width:100%;display:flex;align-items:center;gap:10px;padding:10px 14px;border:none;background:${selected ? (isDark ? "#1f2937" : "#eef4ff") : "transparent"};cursor:pointer;text-align:left;`;
      option.innerHTML = `<span style="display:flex;align-items:center;justify-content:center;width:20px;height:20px;flex-shrink:0;"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="${selected ? "#444ce7" : "#64748b"}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"/></svg></span><span style="min-width:0;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:13px;font-weight:${selected ? "600" : "500"};color:${text};">${escapeHtml(category.name)}</span>${selected ? `<span style="display:flex;align-items:center;justify-content:center;color:#444ce7;flex-shrink:0;"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg></span>` : ""}`;
      option.addEventListener("click", () => {
        selectedCategoryId = category.id;
        if (categoryLabel) categoryLabel.textContent = category.name;
        setMenuOpen(false);
        renderCategoryOptions();
      });
      categoryOptions.appendChild(option);
    });
  };

  renderCategoryOptions();
  void browser.runtime.sendMessage({ type: "GET_CATEGORIES" }).then((response) => {
    if (response?.ok && Array.isArray(response.data)) {
      categories = (response.data as CategoryItem[]).filter((category) => category.id && category.name.toLowerCase() !== "uncategorized");
      renderCategoryOptions();
    }
  }).catch(() => {});

  categoryTrigger?.addEventListener("click", (event) => {
    event.stopPropagation();
    setMenuOpen(!menuOpen);
  });

  const closePrompt = (): void => {
    overlay.remove();
    quickCreateNotePromptEl = null;
  };

  const collectValues = (): QuickCreateNoteValues | null => {
    addTagFromInput();
    if (!validate() || !titleInput || !notesInput) return null;
    return {
      title: titleInput.value.trim(),
      notes: notesInput.value,
      url: urlInput?.value.trim() ?? "",
      tags: [...tags],
      metadata: metadataFields
        .map((field) => ({ ...field, label: field.label.trim(), value: field.value.trim() }))
        .filter((field) => field.label || field.value),
    };
  };

  saveButton?.addEventListener("click", () => {
    const values = collectValues();
    if (!values) return;
    closePrompt();
    onSave(values, selectedCategoryId);
  });

  const cancel = () => { closePrompt(); onCancel(); };
  card.querySelector("#lp-qn-cancel")?.addEventListener("click", cancel);
  card.querySelector("#lp-qn-close")?.addEventListener("click", cancel);
  overlay.addEventListener("click", (event) => {
    if (event.composedPath()[0] === overlay) cancel();
  });

  const escHandler = (event: KeyboardEvent) => {
    if (event.key === "Escape") {
      event.preventDefault();
      cancel();
      document.removeEventListener("keydown", escHandler, true);
    }
  };
  document.addEventListener("keydown", escHandler, true);

  const outsideClickHandler = (event: MouseEvent): void => {
    if (!menuOpen || !categoryWrap) return;
    if (event.composedPath().includes(categoryWrap)) return;
    setMenuOpen(false);
  };
  document.addEventListener("click", outsideClickHandler, { capture: true });

  updateCharCount();
  renderTags();
  validate();
  setTimeout(() => titleInput?.focus(), 60);
}

// ─── Social login save prompt ────────────────────────────────────────────────────────

let saveSocialPromptEl: HTMLDivElement | null = null;

function showSaveSocialLoginPrompt(
  info: { provider: SocialProviderDef; username: string; title: string },
  onSave: (title: string, categoryUuid: string) => void,
  onCancel: () => void,
): void {
  proactiveLoginPromptShown = false;
  dismissLoginAutofillPrompt();
  if (saveSocialPromptEl) saveSocialPromptEl.remove();

  ensurePkAnimStyle();

  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1f2937" : "#ffffff";
  const text = isDark ? "#f3f4f6" : "#111827";
  const subText = isDark ? "#9ca3af" : "#6b7280";
  const border = isDark ? "#374151" : "#e5e7eb";
  const rowBdr = isDark ? "#2d2d3d" : "#f3f4f6";
  const inputBg = isDark ? "#374151" : "#f9fafb";
  const { provider } = info;
  const titleIcon = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="${isDark ? "#a5b4fc" : "#444ce7"}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`;

  const el = document.createElement("div");
  el.setAttribute("data-lp-prompt-modal", "true");
  el.style.cssText = `
    position: fixed; z-index: 2147483647; top: 72px; right: 24px;
    width: 320px; background: ${bg}; border: 1px solid ${border};
    border-radius: 12px; box-shadow: 0 6px 24px rgba(0,0,0,0.12);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    overflow: hidden; animation: lp-slide-up 0.18s ease-out;
  `;

  el.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;padding:10px 12px;border-bottom:1px solid ${rowBdr};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:18px;height:18px;flex-shrink:0;">${titleIcon}</span>
      <span style="font-size:13px;font-weight:600;color:${text};flex:1;">Save sign-in method?</span>
      <button id="lp-social-close" style="background:none;border:none;cursor:pointer;padding:0 4px;color:${subText};font-size:18px;line-height:1;">&times;</button>
    </div>
    <div style="padding:14px;">
      <div style="display:flex;align-items:center;gap:12px;padding:10px 12px;background:${isDark ? "#374151" : "#f8fafc"};border:1px solid ${border};border-radius:10px;margin-bottom:12px;">
        <div style="flex-shrink:0;width:36px;height:36px;border-radius:9px;background:${isDark ? "#1f2937" : "white"};display:flex;align-items:center;justify-content:center;box-shadow:0 1px 4px rgba(0,0,0,0.12);">
          ${provider.svg}
        </div>
        <div style="flex:1;min-width:0;">
          <div style="font-size:13px;font-weight:600;color:${text};">Sign in with ${provider.label}</div>
          <div style="font-size:12px;color:${subText};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${info.username || info.title}</div>
        </div>
      </div>
      <div style="margin-bottom:12px;">
        <p style="font-size:11px;color:${subText};margin:0 0 4px 0;font-weight:500;text-transform:uppercase;letter-spacing:0.5px;">Name</p>
        <input id="lp-social-title" type="text" value="${info.title.replace(/"/g, "&quot;")}" style="width:100%;padding:8px 10px;background:${inputBg};border:1px solid ${border};border-radius:8px;font-size:13px;color:${text};outline:none;box-sizing:border-box;" />
      </div>
      <div style="display:flex;gap:8px;">
        <button id="lp-social-cancel" style="flex:0 0 auto;background:none;border:1px solid ${border};border-radius:8px;padding:9px 14px;font-size:13px;color:${subText};cursor:pointer;font-weight:500;">Not now</button>
        <button id="lp-social-save" style="flex:1;background:#444ce7;color:white;border:none;border-radius:8px;padding:9px 0;font-size:13px;font-weight:600;cursor:pointer;">Save</button>
      </div>
    </div>
  `;

  lpAppend(el);
  saveSocialPromptEl = el as HTMLDivElement;

  const titleInput = el.querySelector<HTMLInputElement>("#lp-social-title");

  const closePrompt = (): void => {
    el.remove();
    saveSocialPromptEl = null;
  };

  el.querySelector("#lp-social-save")?.addEventListener("click", () => {
    const title = titleInput?.value.trim() || info.title;
    closePrompt();
    onSave(title, "");
  });
  el.querySelector("#lp-social-cancel")?.addEventListener("click", () => { closePrompt(); onCancel(); });
  el.querySelector("#lp-social-close")?.addEventListener("click", () => { closePrompt(); onCancel(); });
}

// ─── Social login button listeners ─────────────────────────────────────────────────────

function attachSocialButtonListeners(): void {
  if (!isLikelyLoginSurface()) return;

  getSocialLoginButtons().forEach(({ el, provider }) => {
    const tagged = el as HTMLElement & { _lpSocialAttached?: boolean };
    if (tagged._lpSocialAttached) return;
    tagged._lpSocialAttached = true;

    el.addEventListener("click", () => {
      const surface = describeLoginSurface();
      if (!surface.isLoginSurface) {
        console.debug("[LumenPass] ignoring social sign-in capture outside login surface", {
          provider: provider.id,
          reason: surface.reason,
          url: window.location.href,
        });
        return;
      }

      const emailRe = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/;
      let emailHint = el.getAttribute("data-hint_email")
        ?? el.closest("[data-hint_email]")?.getAttribute("data-hint_email")
        ?? el.getAttribute("data-login_hint")
        ?? "";
      if (!emailHint) {
        const ariaLabel = el.getAttribute("aria-label") ?? "";
        const m = ariaLabel.match(emailRe);
        if (m) emailHint = m[0];
      }
      void browser.runtime.sendMessage({
        type: "CAPTURE_SOCIAL_LOGIN",
        payload: {
          provider: provider.id,
          providerLabel: provider.label,
          fromUrl: window.location.href,
          emailHint,
          loginSurfaceReason: surface.reason,
        },
      });
    }, { capture: true, passive: true });
  });
}

/**
 * For entries already saved as social logins (password sentinel = "__social:"),
 * inject a "Sign in with Google" suggestion row at the top of the autofill popup.
 * Only applies when the current page has matching social buttons.
 */
function renderSocialSuggestionRows(
  socialItems: Array<{ entry: typeof entries[0]; provider: SocialProviderDef }>,
): string {
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  return socialItems.map((item, idx) => {
    const { provider } = item;
    return `<div
        data-social-idx="${idx}"
        style="display:flex;align-items:center;gap:10px;padding:9px 12px;cursor:pointer;border-bottom:1px solid ${isDark ? "#374151" : "#eef2f7"};background:${isDark ? "#1e264a" : "#f0f4ff"};transition:background 0.1s;"
        onmouseenter="this.style.background='${isDark ? "#263060" : "#e3e9ff"}'"
        onmouseleave="this.style.background='${isDark ? "#1e264a" : "#f0f4ff"}'"
      >
        <div style="flex-shrink:0;width:24px;height:24px;border-radius:6px;background:${isDark ? "#1f2937" : "white"};display:flex;align-items:center;justify-content:center;box-shadow:0 1px 3px rgba(0,0,0,0.15);">
          ${provider.svg}
        </div>
        <div style="flex:1;min-width:0;">
          <div style="font-weight:600;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:${isDark ? "#e0e7ff" : "#3730a3"};">Sign in with ${provider.label}</div>
          <div style="font-size:11px;color:${isDark ? "#9ca3af" : "#6b7280"};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${item.entry.username || item.entry.title}</div>
        </div>
        <div style="flex-shrink:0;padding:3px 8px;background:#444ce7;color:white;border-radius:5px;font-size:11px;font-weight:500;">Use</div>
      </div>`;
  }).join("");
}

function dismissSocialFloatingSuggestion(): void {
  if (!socialFloatEl) return;
  socialFloatEl.remove();
  socialFloatEl = null;
}

function maybeShowSocialFloatingSuggestion(): void {
  if (!socialEntries.length) return;
  const matchedItems = socialEntries
    .map((entry) => {
      const provId = (entry.socialProvider ?? (entry.password ?? "").slice(9)) as SocialProvider;
      const pDef = SOCIAL_PROVIDERS.find((p) => p.id === provId);
      return pDef ? { entry, provider: pDef } : null;
    })
    .filter((x): x is NonNullable<typeof x> => x !== null);
  if (matchedItems.length > 0) {
    showSocialLoginFloatingSuggestion(matchedItems);
  }
}

function showSocialLoginFloatingSuggestion(
  items: Array<{ entry: EntryItem; provider: SocialProviderDef }>,
): void {
  if (socialFloatEl) socialFloatEl.remove();

  const buttons = getSocialLoginButtons();
  const matched = items.filter((item) => buttons.some((b) => b.provider.id === item.provider.id));
  if (matched.length === 0) return;

  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1e1e2e" : "#ffffff";
  const border = isDark ? "#374151" : "#e5e7eb";
  const text = isDark ? "#f3f4f6" : "#111827";
  const sub = isDark ? "#9ca3af" : "#6b7280";
  const rowBdr = isDark ? "#2d2d3d" : "#f3f4f6";
  const hoverBg = isDark ? "#2a2a3d" : "#f9fafb";

  ensureOverlayStyles();

  const lockSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="${isDark ? "#a5b4fc" : "#444ce7"}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`;
  const chevronSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="${sub}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>`;

  const emailRe = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/;

  const rowsHtml = matched.map((item, idx) => {
    const { entry, provider } = item;

    const domain = (() => {
      try { return new URL(entry.url || "").hostname || entry.title; } catch { return entry.title; }
    })() || window.location.hostname;

    const matchedBtn = buttons.find((b) => b.provider.id === provider.id);
    let emailHint = entry.username || "";
    if (!emailHint && matchedBtn) {
      const ariaLabel = matchedBtn.el.getAttribute("aria-label") ?? "";
      const ariaMatch = ariaLabel.match(emailRe);
      if (ariaMatch) emailHint = ariaMatch[0];
    }
    if (!emailHint && matchedBtn) {
      emailHint = matchedBtn.el.getAttribute("data-hint_email")
        ?? matchedBtn.el.closest("[data-hint_email]")?.getAttribute("data-hint_email")
        ?? "";
    }

    return `<div data-social-float-idx="${idx}" style="display:flex;align-items:center;gap:12px;padding:12px 16px;cursor:pointer;border-bottom:1px solid ${rowBdr};transition:background 0.1s;">
      <div style="flex-shrink:0;width:36px;height:36px;border-radius:9px;background:${isDark ? "#1f2937" : "white"};border:1px solid ${isDark ? "#374151" : "#e5e7eb"};display:flex;align-items:center;justify-content:center;box-shadow:0 1px 3px rgba(0,0,0,0.1);">
        ${provider.svg}
      </div>
      <div style="flex:1;min-width:0;">
        <div style="font-size:13px;font-weight:600;color:${text};overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">Sign in with ${provider.label}</div>
        <div style="font-size:11px;color:${sub};overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${domain}</div>
        ${emailHint ? `<div style="font-size:11px;color:${sub};overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${emailHint}</div>` : ""}
      </div>
      ${chevronSvg}
    </div>`;
  }).join("");

  const el = document.createElement("div");
  el.style.cssText = `position:fixed;z-index:2147483647;top:72px;right:24px;width:320px;background:${bg};border:1px solid ${border};border-radius:12px;box-shadow:0 6px 24px rgba(0,0,0,0.12);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;overflow:hidden;animation:lp-slide-up 0.18s ease-out;`;
  el.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;padding:10px 12px;border-bottom:1px solid ${rowBdr};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:18px;height:18px;flex-shrink:0;">${lockSvg}</span>
      <span style="font-size:13px;font-weight:600;color:${text};flex:1;">Sign-in options</span>
      <button id="lp-social-float-close" style="background:none;border:none;cursor:pointer;padding:0 4px;color:${sub};font-size:18px;line-height:1;">&times;</button>
    </div>
    <div>${rowsHtml}</div>
  `;

  lpAppend(el);
  socialFloatEl = el as HTMLDivElement;

  el.querySelector("#lp-social-float-close")?.addEventListener("click", () => {
    dismissSocialFloatingSuggestion();
  });

  el.querySelectorAll<HTMLElement>("[data-social-float-idx]").forEach((row) => {
    row.addEventListener("mouseenter", () => { row.style.background = hoverBg; });
    row.addEventListener("mouseleave", () => { row.style.background = ""; });
    row.addEventListener("click", () => {
      const idx = parseInt(row.dataset.socialFloatIdx ?? "0", 10);
      const target = matched[idx];
      if (!target) return;
      dismissSocialFloatingSuggestion();
      hidePopup();
      const btns = getSocialLoginButtons();
      const match = btns.find((b) => b.provider.id === target.provider.id);
      if (match) {
        match.el.click();
      } else {
        showSaveResultToast(false, `Could not find "${target.provider.label}" button on this page`);
      }
    });
  });
}

function dismissLoginAutofillPrompt(): void {
  if (!loginAutofillPromptEl) return;
  loginAutofillPromptEl.remove();
  loginAutofillPromptEl = null;
}

// ─── Fill Email / Fill Username picker ───────────────────────────────────────

function fillValueToField(field: FillableField, value: string): void {
  simulateFill(field, value);
  autofilledFields.add(field);
}

interface FillValuePromptOptions {
  kind: "email" | "username";
  targetField: HTMLInputElement | null;
}

async function showFillValuePrompt(options: FillValuePromptOptions): Promise<void> {
  const { kind, targetField } = options;
  if (fillValuePromptEl) fillValuePromptEl.remove();

  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1f2937" : "#ffffff";
  const text = isDark ? "#f3f4f6" : "#111827";
  const sub = isDark ? "#9ca3af" : "#6b7280";
  const border = isDark ? "#374151" : "#e5e7eb";
  const inputBg = isDark ? "#111827" : "#f8fafc";
  const rowBorder = isDark ? "#2d2d3d" : "#f3f4f6";
  const hoverBg = isDark ? "#2a2a3d" : "#f5f5f7";

  const label = kind === "email" ? "Email" : "Username";
  const searchPlaceholder = kind === "email" ? "Search emails…" : "Search usernames…";
  const lockSvg = kind === "email"
    ? `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#444ce7" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/></svg>`
    : `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#444ce7" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21a8 8 0 0 0-16 0"/><circle cx="12" cy="7" r="4"/></svg>`;

  ensureOverlayStyles();

  const el = document.createElement("div");
  el.style.cssText = `position:fixed;z-index:2147483647;top:72px;right:24px;width:340px;max-width:calc(100vw - 48px);background:${bg};border:1px solid ${border};border-radius:12px;box-shadow:0 6px 24px rgba(0,0,0,0.12);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;overflow:hidden;animation:lp-slide-up 0.18s ease-out;`;
  el.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;padding:10px 12px;border-bottom:1px solid ${rowBorder};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:18px;height:18px;flex-shrink:0;">${lockSvg}</span>
      <span style="font-size:13px;font-weight:600;color:${text};flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">Fill ${label}</span>
      <button id="lp-fv-close" aria-label="Close" style="all:unset;box-sizing:border-box;width:22px;height:22px;border-radius:6px;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;color:${sub};"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg></button>
    </div>
    <div style="padding:8px 12px;border-bottom:1px solid ${rowBorder};">
      <input
        id="lp-fv-search"
        type="text"
        placeholder="${searchPlaceholder}"
        style="width:100%;padding:7px 10px;border:1px solid ${border};border-radius:8px;background:${inputBg};color:${text};font-size:12px;outline:none;box-sizing:border-box;"
      />
    </div>
    <div id="lp-fv-list" class="lp-scroll" style="max-height:min(360px, calc(100vh - 180px));">
      <div style="padding:14px 12px;color:${sub};font-size:12px;text-align:center;">Loading…</div>
    </div>
  `;

  lpAppend(el);
  fillValuePromptEl = el as HTMLDivElement;

  const listEl = el.querySelector<HTMLDivElement>("#lp-fv-list");
  const searchEl = el.querySelector<HTMLInputElement>("#lp-fv-search");

  let allEntries: EntryItem[] = [];
  let searchTimer: number | null = null;

  const renderRows = (query: string): void => {
    if (!listEl) return;
    const filtered = filterEntryItems(allEntries, query).filter((entry) => {
      const u = entry.username.trim();
      if (!u) return false;
      if (kind === "email") return EMAIL_LIKE_IDENTIFIER_RE.test(u);
      return !EMAIL_LIKE_IDENTIFIER_RE.test(u);
    });
    if (filtered.length === 0) {
      listEl.innerHTML = `<div style="padding:14px 12px;color:${sub};font-size:12px;text-align:center;">No ${label.toLowerCase()}s found</div>`;
      return;
    }
    listEl.innerHTML = filtered.map((entry) => {
      const colour = seedColour(entry.username || entry.title);
      const abbr = initials(entry.username || entry.title);
      const faviconSrc = entry.favicon ? googleFaviconUrlForDisplay(entry.favicon, 128) : "";
      const avatarHtml = faviconSrc
        ? `<div style="width:30px;height:30px;border-radius:8px;overflow:hidden;display:flex;align-items:center;justify-content:center;position:relative;flex-shrink:0;">
             <img src="${faviconSrc}" style="width:30px;height:30px;border-radius:8px;object-fit:contain;background:white;" onerror="this.style.display='none';this.nextElementSibling.style.display='flex'" />
             <div style="display:none;position:absolute;inset:0;border-radius:8px;background:${colour};align-items:center;justify-content:center;color:white;font-size:10px;font-weight:700;">${abbr}</div>
           </div>`
        : `<div style="width:30px;height:30px;border-radius:8px;background:${colour};display:flex;align-items:center;justify-content:center;color:white;font-size:10px;font-weight:700;flex-shrink:0;">${abbr}</div>`;
      const usernameEsc = entry.username.replace(/"/g, "&quot;");
      return `<div data-fv-username="${usernameEsc}" style="display:flex;align-items:center;gap:10px;padding:8px 12px;cursor:pointer;border-bottom:1px solid ${rowBorder};transition:background 0.1s;">
        ${avatarHtml}
        <div style="flex:1;min-width:0;">
          <p style="font-size:13px;font-weight:600;color:${text};margin:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${entry.username}</p>
          <p style="font-size:11px;color:${sub};margin:1px 0 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${entry.title}</p>
        </div>
      </div>`;
    }).join("");

    listEl.querySelectorAll<HTMLElement>("[data-fv-username]").forEach((row) => {
      const img = row.querySelector("img");
      if (img) {
        img.addEventListener("error", () => {
          img.style.display = "none";
          const fb = img.nextElementSibling as HTMLElement | null;
          if (fb) fb.style.display = "flex";
        });
      }
      row.addEventListener("mouseenter", () => { row.style.background = hoverBg; });
      row.addEventListener("mouseleave", () => { row.style.background = ""; });
      row.addEventListener("click", () => {
        const username = row.dataset.fvUsername ?? "";
        if (targetField && targetField.isConnected && username) {
          fillValueToField(targetField, username);
        }
        closeFillValuePrompt();
        showSaveResultToast(true, `${label} filled`);
      });
    });
  };

  const closeFillValuePrompt = (): void => {
    if (searchTimer !== null) { window.clearTimeout(searchTimer); searchTimer = null; }
    el.remove();
    fillValuePromptEl = null;
  };

  el.querySelector("#lp-fv-close")?.addEventListener("click", closeFillValuePrompt);
  el.addEventListener("click", (e) => {
    if (e.composedPath()[0] === el) closeFillValuePrompt();
  });

  searchEl?.addEventListener("input", () => {
    if (searchTimer !== null) { window.clearTimeout(searchTimer); }
    searchTimer = window.setTimeout(() => { searchTimer = null; renderRows(searchEl.value); }, 250);
  });

  // Fetch all login entries
  try {
    const res = await browser.runtime.sendMessage({
      type: "SEARCH_ENTRIES",
      payload: { query: "", type: "login" },
    });
    if (res?.ok && Array.isArray(res.data)) {
      allEntries = (res.data as EntryItem[]).filter(
        (e) => e.kind !== "passkey" && e.kind !== "credit-card" && e.kind !== "identity",
      );
    }
  } catch { /* ignore */ }

  renderRows("");
  searchEl?.focus();
}

async function showFillOtpPrompt(targetField: HTMLInputElement | null): Promise<void> {
  if (fillValuePromptEl) fillValuePromptEl.remove();

  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1f2937" : "#ffffff";
  const text = isDark ? "#f3f4f6" : "#111827";
  const sub = isDark ? "#9ca3af" : "#6b7280";
  const border = isDark ? "#374151" : "#e5e7eb";
  const inputBg = isDark ? "#111827" : "#f8fafc";
  const rowBorder = isDark ? "#2d2d3d" : "#f3f4f6";
  const hoverBg = isDark ? "#2a2a3d" : "#f5f5f7";

  ensureOverlayStyles();

  const el = document.createElement("div");
  el.style.cssText = `position:fixed;z-index:2147483647;top:72px;right:24px;width:360px;max-width:calc(100vw - 48px);background:${bg};border:1px solid ${border};border-radius:12px;box-shadow:0 6px 24px rgba(0,0,0,0.12);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;overflow:hidden;animation:lp-slide-up 0.18s ease-out;`;
  el.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;padding:10px 12px;border-bottom:1px solid ${rowBorder};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:18px;height:18px;flex-shrink:0;"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#444ce7" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 6v6l4 2"/><circle cx="12" cy="12" r="9"/></svg></span>
      <span style="font-size:13px;font-weight:600;color:${text};flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">Fill OTP</span>
      <button id="lp-fv-close" aria-label="Close" style="all:unset;box-sizing:border-box;width:22px;height:22px;border-radius:6px;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;color:${sub};"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg></button>
    </div>
    <div style="padding:8px 12px;border-bottom:1px solid ${rowBorder};">
      <input id="lp-fotp-search" type="text" placeholder="Search OTP items" style="width:100%;padding:7px 10px;border:1px solid ${border};border-radius:8px;background:${inputBg};color:${text};font-size:12px;outline:none;box-sizing:border-box;" />
    </div>
    <div id="lp-fotp-list" class="lp-scroll" style="max-height:min(420px, calc(100vh - 180px));"><div style="padding:14px 12px;color:${sub};font-size:12px;text-align:center;">Loading…</div></div>
  `;
  lpAppend(el);
  fillValuePromptEl = el as HTMLDivElement;

  const listEl = el.querySelector<HTMLDivElement>("#lp-fotp-list");
  const searchEl = el.querySelector<HTMLInputElement>("#lp-fotp-search");
  let searchTimer: number | null = null;
  let tickTimer: number | null = null;
  let otpItems: Array<{ entry: EntryItem; detail: EntryDetail; suggested: boolean; display: string }> = [];

  const closePrompt = (): void => {
    if (searchTimer !== null) { window.clearTimeout(searchTimer); searchTimer = null; }
    if (tickTimer !== null) { window.clearInterval(tickTimer); tickTimer = null; }
    el.remove();
    fillValuePromptEl = null;
  };

  const formatOtpCode = (code: string): string =>
    /^\d{6}$/.test(code) ? `${code.slice(0, 3)} ${code.slice(3)}` : code;

  const renderRows = (query: string): void => {
    if (!listEl) return;
    const filtered = otpItems.filter((item) => matchesSearchQuery(query, item.entry.title, item.entry.username, item.entry.url, item.display));
    const suggested = filtered.filter((item) => item.suggested);
    const others = filtered.filter((item) => !item.suggested);

    const renderSection = (title: string, items: Array<{ entry: EntryItem; detail: EntryDetail; suggested: boolean; display: string }>) => {
      if (items.length === 0) return "";
      return `
        <div style="padding:8px 12px 6px;font-size:11px;font-weight:700;color:${sub};text-transform:uppercase;letter-spacing:0.04em;">${title}</div>
        ${items.map((item) => {
          const colour = seedColour(item.entry.title || item.entry.username);
          const abbr = initials(item.entry.title || item.entry.username);
          const faviconSrc = item.entry.favicon ? googleFaviconUrlForDisplay(item.entry.favicon, 128) : "";
          const avatarHtml = faviconSrc
            ? `<div style="width:30px;height:30px;border-radius:8px;overflow:hidden;display:flex;align-items:center;justify-content:center;position:relative;flex-shrink:0;"><img src="${faviconSrc}" style="width:30px;height:30px;border-radius:8px;object-fit:contain;background:white;" /><div style="display:none;position:absolute;inset:0;border-radius:8px;background:${colour};align-items:center;justify-content:center;color:white;font-size:10px;font-weight:700;">${abbr}</div></div>`
            : `<div style="width:30px;height:30px;border-radius:8px;background:${colour};display:flex;align-items:center;justify-content:center;color:white;font-size:10px;font-weight:700;flex-shrink:0;">${abbr}</div>`;
          const idEsc = item.entry.id.replace(/"/g, '&quot;');
          const code = item.display || "······";
          const otpRightHtml = `
            <div style="display:flex;align-items:center;gap:8px;flex-shrink:0;">
              <span data-fotp-code="${idEsc}" style="font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:15px;font-weight:700;letter-spacing:0.12em;color:#059669;white-space:nowrap;">${formatOtpCode(code)}</span>
              <span data-fotp-ring="${idEsc}" style="position:relative;width:22px;height:22px;flex-shrink:0;display:inline-flex;align-items:center;justify-content:center;">
                <svg width="22" height="22" viewBox="0 0 22 22" style="transform:rotate(-90deg);"><circle cx="11" cy="11" r="9" fill="none" stroke="${isDark ? '#374151' : '#e5e7eb'}" stroke-width="2.5"/><circle data-fotp-arc cx="11" cy="11" r="9" fill="none" stroke="#10b981" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="56.5" stroke-dashoffset="0"/></svg>
                <span data-fotp-secs style="position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:9px;font-weight:700;color:${sub};">30</span>
              </span>
            </div>`;
          return `<div data-fotp-id="${idEsc}" style="display:flex;align-items:center;gap:10px;padding:8px 12px;cursor:pointer;border-top:1px solid ${rowBorder};transition:background 0.1s;">${avatarHtml}<div style="flex:1;min-width:0;"><p style="font-size:13px;font-weight:600;color:${text};margin:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${item.entry.title}</p><p style="font-size:11px;color:${sub};margin:1px 0 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${item.entry.username || item.entry.url || ''}</p></div>${item.suggested ? `<span style="padding:3px 8px;border-radius:999px;background:${isDark ? '#312e81' : '#eef2ff'};color:#444ce7;font-size:10px;font-weight:700;flex-shrink:0;">Suggested</span>` : ''}${otpRightHtml}</div>`;
        }).join('')}`;
    };

    if (filtered.length === 0) {
      listEl.innerHTML = `<div style="padding:14px 12px;color:${sub};font-size:12px;text-align:center;">No OTP items found</div>`;
      return;
    }

    listEl.innerHTML = `${renderSection('Suggestions', suggested)}${renderSection('All OTP Items', others)}`;

    listEl.querySelectorAll<HTMLElement>('[data-fotp-id]').forEach((row) => {
      const img = row.querySelector('img');
      if (img) {
        const showFallback = (): void => {
          img.style.display = 'none';
          const fb = img.nextElementSibling as HTMLElement | null;
          if (fb) fb.style.display = 'flex';
        };
        img.addEventListener('error', showFallback);
        // Google's s2 service returns a generic globe (small bitmap) when a site
        // has no real favicon — prefer our initials avatar in that case.
        img.addEventListener('load', () => {
          const w = (img as HTMLImageElement).naturalWidth || 0;
          const h = (img as HTMLImageElement).naturalHeight || 0;
          if (w > 0 && h > 0 && (w < 48 || h < 48)) showFallback();
        });
      }
      row.addEventListener('mouseenter', () => { row.style.background = hoverBg; });
      row.addEventListener('mouseleave', () => { row.style.background = ''; });
      row.addEventListener('click', async () => {
        const id = row.dataset.fotpId ?? '';
        const item = otpItems.find((candidate) => candidate.entry.id === id);
        if (!item) return;
        const code = await resolveTotpDisplayValue(item.detail.totp ?? '');
        if (!code) return;
        const field = targetField && targetField.isConnected ? targetField : getTotpInputField();
        if (field) {
          simulateFill(field, code);
          autofilledFields.add(field);
          showSaveResultToast(true, 'OTP filled');
        } else {
          try { await navigator.clipboard.writeText(code); showSaveResultToast(true, 'OTP copied'); } catch { showSaveResultToast(false, 'Could not fill or copy OTP'); }
        }
        closePrompt();
      });
    });

    startTimers();
  };

  // Live countdown + code refresh. The desktop returns an already-computed
  // 6-digit code (not the secret), so when the 30s period rolls over we
  // re-fetch the codes from the desktop to keep them current.
  let lastRemaining = totpCountdown();
  const CIRCUMFERENCE = 2 * Math.PI * 9; // r=9 → ~56.5

  const refreshCodes = async (): Promise<void> => {
    await Promise.all(otpItems.map(async (item) => {
      try {
        const res = await browser.runtime.sendMessage({ type: 'GET_ENTRY', payload: { id: item.entry.id } });
        if (res?.ok && res.data) {
          item.detail = res.data as EntryDetail;
          item.display = item.detail.totp ? await resolveTotpDisplayValue(item.detail.totp) : '';
        }
      } catch { /* keep previous code */ }
      const codeEl = listEl?.querySelector<HTMLElement>(`[data-fotp-code="${CSS.escape(item.entry.id)}"]`);
      if (codeEl) codeEl.textContent = formatOtpCode(item.display || "······");
    }));
  };

  const updateRings = (remaining: number): void => {
    const offset = CIRCUMFERENCE * (1 - remaining / 30);
    const colour = remaining <= 5 ? "#ef4444" : remaining <= 10 ? "#f59e0b" : "#10b981";
    listEl?.querySelectorAll<SVGCircleElement>('[data-fotp-arc]').forEach((arc) => {
      arc.style.strokeDashoffset = String(offset);
      arc.setAttribute('stroke', colour);
    });
    listEl?.querySelectorAll<HTMLElement>('[data-fotp-secs]').forEach((secs) => {
      secs.textContent = String(remaining);
      secs.style.color = colour;
    });
  };

  const startTimers = (): void => {
    if (tickTimer !== null) return;
    updateRings(totpCountdown());
    tickTimer = window.setInterval(() => {
      const remaining = totpCountdown();
      updateRings(remaining);
      if (remaining > lastRemaining) void refreshCodes();
      lastRemaining = remaining;
    }, 1000);
  };

  el.querySelector('#lp-fv-close')?.addEventListener('click', closePrompt);
  el.addEventListener('click', (event) => {
    if (event.composedPath()[0] === el) closePrompt();
  });
  searchEl?.addEventListener('input', () => {
    if (searchTimer !== null) window.clearTimeout(searchTimer);
    searchTimer = window.setTimeout(() => {
      searchTimer = null;
      renderRows(searchEl.value);
    }, 250);
  });

  try {
    // Fetch all OTP entries (same request as the extension popup's "One-time
    // passwords" filter: query='', type='totp', no URL).
    const totpRes = await browser.runtime.sendMessage({ type: 'SEARCH_ENTRIES', payload: { query: '', type: 'totp' } });
    const totpEntries = totpRes?.ok && Array.isArray(totpRes.data) ? totpRes.data as EntryItem[] : [];

    // Determine which entries are "suggested" by matching the current page domain.
    const currentDomain = (() => { try { return new URL(window.location.href).hostname.replace(/^www\./, ''); } catch { return ''; } })();
    const isSuggested = (entry: EntryItem): boolean => {
      if (!currentDomain || !entry.url) return false;
      try {
        const entryDomain = new URL(entry.url.includes('://') ? entry.url : `https://${entry.url}`).hostname.replace(/^www\./, '');
        return entryDomain === currentDomain || entryDomain.endsWith(`.${currentDomain}`) || currentDomain.endsWith(`.${entryDomain}`);
      } catch { return false; }
    };

    const deduped = new Map<string, EntryItem>();
    totpEntries.forEach((entry) => {
      if (!deduped.has(entry.id)) {
        deduped.set(entry.id, entry);
      }
    });
    // The desktop already filtered to OTP items (type=totp). Do NOT drop any
    // entry client-side — just fetch each entry's detail to resolve the live
    // code for display/fill. The search result (EntryItem) never carries the
    // `totp` field; only the GET_ENTRY detail does (desktop computes it).
    const detailed = await Promise.all(Array.from(deduped.values()).map(async (entry) => {
      let detail: EntryDetail = entry as EntryDetail;
      try {
        const res = await browser.runtime.sendMessage({ type: 'GET_ENTRY', payload: { id: entry.id } });
        if (res?.ok && res.data) detail = res.data as EntryDetail;
      } catch { /* keep the search payload we already have */ }
      const display = detail.totp ? await resolveTotpDisplayValue(detail.totp) : '';
      return { entry, detail, suggested: isSuggested(entry), display };
    }));
    otpItems = detailed;
    otpItems.sort((a, b) => {
      if (a.suggested !== b.suggested) return a.suggested ? -1 : 1;
      return a.entry.title.toLowerCase().localeCompare(b.entry.title.toLowerCase());
    });
  } catch { /* leave list empty on failure */ }

  renderRows('');
  searchEl?.focus();
}

function showLoginAutofillPrompt(
  loginEntries: EntryItem[],
  onSelect: (entry: EntryItem) => void,
  onCancel: () => void,
): void {
  dismissLoginAutofillPrompt();

  const closePrompt = (rememberDismissal = false): void => {
    if (rememberDismissal) {
      markProactiveLoginPromptDismissedForCurrentPage();
    }
    dismissLoginAutofillPrompt();
    onCancel();
  };

  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1f2937" : "#ffffff";
  const text = isDark ? "#f3f4f6" : "#111827";
  const sub = isDark ? "#9ca3af" : "#6b7280";
  const border = isDark ? "#374151" : "#e5e7eb";
  const rowBorder = isDark ? "#2d2d3d" : "#f3f4f6";
  const hoverBg = isDark ? "#2a2a3d" : "#f5f5f7";

  ensureOverlayStyles();

  const lockSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#444ce7" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>`;
  const domain = extractDomain(window.location.href);

  const el = document.createElement("div");
  el.style.cssText = `position:fixed;z-index:2147483647;top:72px;right:24px;width:340px;max-width:calc(100vw - 48px);background:${bg};border:1px solid ${border};border-radius:12px;box-shadow:0 6px 24px rgba(0,0,0,0.12);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;overflow:hidden;animation:lp-slide-up 0.18s ease-out;`;
  el.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;padding:10px 12px;border-bottom:1px solid ${rowBorder};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:18px;height:18px;flex-shrink:0;">${lockSvg}</span>
      <span style="font-size:13px;font-weight:600;color:${text};flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="Fill with LumenPass — ${domain}">Fill with LumenPass</span>
      <button id="lp-login-disable-autofill" type="button" style="all:unset;box-sizing:border-box;padding:5px 8px;border-radius:7px;cursor:pointer;color:${isDark ? "#fca5a5" : "#b42318"};font-size:11px;font-weight:700;white-space:nowrap;">Disable</button>
      <button id="lp-login-close" aria-label="Close" style="all:unset;box-sizing:border-box;width:22px;height:22px;border-radius:6px;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;color:${sub};"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg></button>
    </div>
    <div data-disable-autofill-options data-open="false" style="display:none;gap:2px;margin:8px 12px 0;padding:4px;border:1px solid ${border};border-radius:10px;background:${isDark ? "#111827" : "#ffffff"};"></div>
    <div style="padding:8px 12px;border-bottom:1px solid ${rowBorder};">
      <input
        id="lp-login-search"
        type="text"
        placeholder="Search items"
        style="width:100%;padding:7px 10px;border:1px solid ${isDark ? "#374151" : "#e5e7eb"};border-radius:8px;background:${isDark ? "#111827" : "#f8fafc"};color:${text};font-size:12px;outline:none;box-sizing:border-box;"
      />
    </div>
    <div id="lp-login-list" class="lp-scroll" style="max-height:min(360px, calc(100vh - 180px));"></div>
  `;

  lpAppend(el);
  loginAutofillPromptEl = el as HTMLDivElement;

  const listEl = el.querySelector<HTMLDivElement>("#lp-login-list");
  const searchEl = el.querySelector<HTMLInputElement>("#lp-login-search");

  const renderRows = (query: string): void => {
    if (!listEl) return;
    const filteredEntries = filterEntryItems(loginEntries, query);
    listEl.innerHTML = filteredEntries.map((entry, index) => {
      const avatarHtml = itemAvatarHtml({
        title: entry.title,
        favicon: entry.favicon,
        size: 30,
        radius: 8,
        fontSize: 11,
      });

      return `<div data-login-idx="${index}" style="display:flex;align-items:center;gap:10px;padding:8px 12px;cursor:pointer;border-bottom:1px solid ${rowBorder};transition:background 0.1s;">
        ${avatarHtml}
        <div style="flex:1;min-width:0;">
          <p style="font-size:13px;font-weight:600;color:${text};margin:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${entry.title}</p>
          <p style="font-size:11px;color:${sub};margin:1px 0 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${entry.username || "Fill saved credentials"}</p>
        </div>
        <span data-login-fill style="padding:4px 10px;border-radius:999px;background:${isDark ? "#312e81" : "#eef2ff"};color:#444ce7;font-size:11px;font-weight:600;flex-shrink:0;">Fill</span>
      </div>`;
    }).join("") || `<div style="padding:14px 12px;color:${sub};font-size:12px;text-align:center;">No matching items</div>`;

    bindItemAvatarFallbacks(listEl);

    listEl.querySelectorAll<HTMLElement>("[data-login-idx]").forEach((row) => {
      row.addEventListener("mouseenter", () => { row.style.background = hoverBg; });
      row.addEventListener("mouseleave", () => { row.style.background = ""; });
      row.addEventListener("click", () => {
        const index = parseInt(row.dataset.loginIdx ?? "0", 10);
        dismissLoginAutofillPrompt();
        onSelect(filteredEntries[index]);
      });
    });
  };

  renderRows("");
  searchEl?.addEventListener("input", () => renderRows(searchEl.value));

  el.querySelector("#lp-login-close")?.addEventListener("click", () => {
    closePrompt(true);
  });
  el.querySelector("#lp-login-disable-autofill")?.addEventListener("click", (event) => {
    event.stopPropagation();
    renderDisableAutofillOptions(el, isDark, () => {
      closePrompt(true);
    });
  });
}

function findUsernameValue(excludeField: HTMLInputElement): string {
  const visibleSelectors = [
    "input[type='email']",
    "input[autocomplete='username']",
    "input[autocomplete='email']",
    "input[name*='user']",
    "input[name*='email']",
    "input[name*='login']",
    "input[type='text']",
  ];
  for (const sel of visibleSelectors) {
    const candidates = Array.from(document.querySelectorAll<HTMLInputElement>(sel)).filter(
      (el) => isVisible(el) && el !== excludeField && el.value.trim().length > 0,
    );
    if (candidates.length > 0) return candidates[candidates.length - 1].value.trim();
  }

  const hiddenSelectors = [
    "input[type='email']",
    "input[autocomplete='username']",
    "input[autocomplete='email']",
    "input[name*='user']",
    "input[name*='email']",
    "input[name*='login']",
    "input[type='hidden'][name*='user']",
    "input[type='hidden'][name*='email']",
    "input[type='hidden'][name*='login']",
    "input[type='text']",
  ];
  for (const sel of hiddenSelectors) {
    const candidates = Array.from(document.querySelectorAll<HTMLInputElement>(sel)).filter(
      (el) => el !== excludeField && el.value.trim().length > 0,
    );
    if (candidates.length > 0) return candidates[candidates.length - 1].value.trim();
  }

  const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  const textCandidates = Array.from(
    document.querySelectorAll<HTMLElement>("[class*='email'],[class*='user'],[data-email],[data-username]"),
  ).filter((el) => {
    const t = (el.textContent ?? "").trim();
    return t.length > 0 && emailPattern.test(t);
  });
  if (textCandidates.length > 0) {
    return (textCandidates[textCandidates.length - 1].textContent ?? "").trim();
  }

  return "";
}

async function captureLoginForSave(passwordField: HTMLInputElement): Promise<void> {
  const autofillSnapshot = lastExtensionAutofillPasswordByField.get(passwordField);
  const submittedTrimmed = passwordField.value.trim();
  if (autofillSnapshot !== undefined && submittedTrimmed === autofillSnapshot) {
    return;
  }

  const passwordValue = passwordField.value;
  if (!passwordValue.trim()) return;

  const usernameValue = findUsernameValue(passwordField);

  try {
    await browser.runtime.sendMessage({
      type: "CAPTURE_LOGIN",
      payload: {
        username: usernameValue,
        password: passwordValue,
        fromUrl: window.location.href,
      },
    });
  } catch {
    // Silently fail
  }
}

function attachSaveDetectionToForm(form: HTMLFormElement, passwordField: HTMLInputElement): void {
  const key = "_lpSaveAttached";
  const tagged = form as HTMLFormElement & { [key: string]: boolean };
  if (tagged[key]) return;
  tagged[key] = true;

  form.addEventListener("submit", () => { void captureLoginForSave(passwordField); });
}

function attachSaveDetectionToButton(btn: HTMLElement, passwordField: HTMLInputElement): void {
  const key = "_lpSaveBtnAttached";
  const tagged = btn as HTMLElement & { [key: string]: boolean };
  if (tagged[key]) return;
  tagged[key] = true;

  btn.addEventListener("click", () => { void captureLoginForSave(passwordField); });
}

function attachSaveDetectionToPasswordField(passwordField: HTMLInputElement): void {
  const key = "_lpSaveKeyAttached";
  const tagged = passwordField as HTMLInputElement & { [key: string]: boolean };
  if (tagged[key]) return;
  tagged[key] = true;

  passwordField.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      void captureLoginForSave(passwordField);
    }
  });
}

function attachSaveDetection(): void {
  getPasswordFields().forEach((passwordField) => {
    attachSaveDetectionToPasswordField(passwordField);

    const form = passwordField.closest("form");
    if (form) {
      attachSaveDetectionToForm(form as HTMLFormElement, passwordField);
    }

    getActionableAuthElements().forEach((btn) => {
      attachSaveDetectionToButton(btn, passwordField);
    });
  });
}

// ─── Passkey interception ─────────────────────────────────────────────────────

const LP = "LUMENPASS_PK";

interface PasskeyEntry {
  id: string;
  title: string;
  username: string;
  credentialId: string;
  rpId: string;
}

interface ActivePasskeyRequest {
  requestId: string;
  publicKey: {
    challenge: number[];
    rpId: string;
    allowCredentials: { id: number[] }[];
  };
}

let passkeyPromptEl: HTMLDivElement | null = null;
let pendingPasskeyEntry: PasskeyEntry | null = null;
let proactiveShown = false;
let cachedPasskeyEntries: PasskeyEntry[] | null = null;
let cachedForHostname: string | null = null;
let activePasskeyRequest: ActivePasskeyRequest | null = null;

function clearActivePasskeyRequest(requestId: string): void {
  if (activePasskeyRequest?.requestId === requestId) {
    activePasskeyRequest = null;
  }
}

function cancelPasskeyRequest(requestId: string): void {
  clearActivePasskeyRequest(requestId);
  window.postMessage({ [LP]: true, requestId, cancel: true }, "*");
}

function decodeBase64Url(input: string): number[] {
  const padded = input.replace(/-/g, "+").replace(/_/g, "/") + "==".slice(0, (4 - input.length % 4) % 4);
  return Array.from(Uint8Array.from(atob(padded), (c) => c.charCodeAt(0)));
}

function entryMatchesAllowCredentials(
  entry: PasskeyEntry,
  allowCredentials: { id: number[] }[],
): boolean {
  if (!allowCredentials.length) return true;
  const credentialId = decodeBase64Url(entry.credentialId);
  return allowCredentials.some((credential) =>
    credential.id.length === credentialId.length &&
    credential.id.every((value, index) => value === credentialId[index]));
}

async function assertPasskeyEntry(
  request: ActivePasskeyRequest,
  entry: PasskeyEntry,
): Promise<void> {
  if (!entryMatchesAllowCredentials(entry, request.publicKey.allowCredentials)) {
    console.warn("[LumenPass Passkey] selected entry not allowed for request", {
      requestId: request.requestId,
      entryId: entry.id,
      allowCredentials: request.publicKey.allowCredentials.length,
    });
    cancelPasskeyRequest(request.requestId);
    return;
  }

  console.log("[LumenPass Passkey] asserting entry", entry.id, entry.title);
  const assertRes = await browser.runtime.sendMessage({
    type: "PASSKEY_ASSERT",
    payload: {
      entryId: entry.id,
      rpId: request.publicKey.rpId,
      challenge: request.publicKey.challenge,
      origin: window.location.origin,
    },
  });
  console.log("[LumenPass Passkey] PASSKEY_ASSERT response", assertRes);
  clearActivePasskeyRequest(request.requestId);
  if (assertRes?.ok && assertRes.data) {
    window.postMessage({ [LP]: true, requestId: request.requestId, credential: assertRes.data }, "*");
  } else {
    console.warn("[LumenPass Passkey] assertion failed:", assertRes?.error);
    window.postMessage({ [LP]: true, requestId: request.requestId, cancel: true }, "*");
  }
}

function showPasskeyPrompt(
  passkeyEntries: PasskeyEntry[],
  onSelect: (entry: PasskeyEntry) => void,
  onCancel: () => void,
): void {
  proactiveLoginPromptShown = false;
  dismissLoginAutofillPrompt();
  if (passkeyPromptEl) passkeyPromptEl.remove();

  const isDark  = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg      = isDark ? "#1f2937" : "#ffffff";
  const text    = isDark ? "#f3f4f6" : "#111827";
  const sub     = isDark ? "#9ca3af" : "#6b7280";
  const border  = isDark ? "#374151" : "#e5e7eb";
  const rowBdr  = isDark ? "#2d2d3d" : "#f3f4f6";
  const hoverBg = isDark ? "#2a2a3d" : "#f5f5f7";

  ensureOverlayStyles();

  const passkeyIconUrl = browser.runtime.getURL("icons/passkey_icon.png");
  const titleIcon = `<img src="${passkeyIconUrl}" style="display:block;width:14px;height:auto;max-width:14px;max-height:14px;object-fit:contain;" />`;
  const listItemIcon = `<img src="${passkeyIconUrl}" style="display:block;width:12px;height:auto;max-width:12px;max-height:12px;object-fit:contain;" />`;
  const listIconBadge = `<div style="width:18px;height:18px;border-radius:50%;background:${isDark ? "#374151" : "#eef2ff"};display:flex;align-items:center;justify-content:center;flex-shrink:0;">${listItemIcon}</div>`;
  const chevronSvg = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="${sub}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>`;

  const el = document.createElement("div");
  el.style.cssText = `position:fixed;z-index:2147483647;top:72px;right:24px;width:320px;background:${bg};border:1px solid ${border};border-radius:12px;box-shadow:0 6px 24px rgba(0,0,0,0.12);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;overflow:hidden;animation:lp-slide-up 0.18s ease-out;`;
  el.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;padding:10px 12px;border-bottom:1px solid ${rowBdr};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:18px;height:18px;flex-shrink:0;">${titleIcon}</span>
      <span style="font-size:13px;font-weight:600;color:${text};flex:1;">Sign in with a passkey</span>
      <button id="lp-pk-close" style="background:none;border:none;cursor:pointer;padding:0 4px;color:${sub};font-size:18px;line-height:1;">&times;</button>
    </div>
    <div style="padding:8px 12px;border-bottom:1px solid ${rowBdr};">
      <input
        id="lp-pk-search"
        type="text"
        placeholder="Search passkeys"
        style="width:100%;padding:7px 10px;border:1px solid ${isDark ? "#374151" : "#e5e7eb"};border-radius:8px;background:${isDark ? "#111827" : "#f8fafc"};color:${text};font-size:12px;outline:none;box-sizing:border-box;"
      />
    </div>
    <div id="lp-pk-list" class="lp-scroll" style="max-height:min(360px, calc(100vh - 180px));"></div>`;

  lpAppend(el);
  passkeyPromptEl = el as HTMLDivElement;

  const listEl = el.querySelector<HTMLDivElement>("#lp-pk-list");
  const searchEl = el.querySelector<HTMLInputElement>("#lp-pk-search");

  const renderRows = (query: string): void => {
    if (!listEl) return;
    const filteredEntries = filterPasskeyEntries(passkeyEntries, query);
    listEl.innerHTML = filteredEntries.map((entry, index) => {
      const domain = entry.rpId || window.location.hostname;
      const favicon = `https://www.google.com/s2/favicons?sz=64&domain=${encodeURIComponent(domain)}`;
      const avatarHtml = itemAvatarHtml({ title: entry.title, favicon });
      return `<div data-pk-idx="${index}" style="display:flex;align-items:center;gap:10px;padding:8px 12px;cursor:pointer;border-bottom:1px solid ${rowBdr};transition:background 0.1s;">
        ${avatarHtml}
        <div style="flex:1;min-width:0;">
          <p style="font-size:13px;font-weight:600;color:${text};margin:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${entry.title}</p>
          <p style="font-size:11px;color:${sub};margin:1px 0 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${entry.username}</p>
        </div>
        <div style="display:flex;align-items:center;gap:4px;flex-shrink:0;">${listIconBadge}${chevronSvg}</div>
      </div>`;
    }).join("") || `<div style="padding:14px 12px;color:${sub};font-size:12px;text-align:center;">No matching passkeys</div>`;

    bindItemAvatarFallbacks(listEl);

    listEl.querySelectorAll<HTMLElement>("[data-pk-idx]").forEach((row) => {
      row.addEventListener("mouseenter", () => { row.style.background = hoverBg; });
      row.addEventListener("mouseleave", () => { row.style.background = ""; });
      row.addEventListener("click", () => {
        const idx = parseInt(row.dataset.pkIdx ?? "0", 10);
        el.remove();
        passkeyPromptEl = null;
        onSelect(filteredEntries[idx]);
      });
    });
  };

  renderRows("");
  searchEl?.addEventListener("input", () => renderRows(searchEl.value));

  el.querySelector("#lp-pk-close")?.addEventListener("click", () => {
    el.remove();
    passkeyPromptEl = null;
    onCancel();
  });
}

function showPasskeySavePrompt(
  info: { rpName: string; rpId: string; userName: string },
  onSave: () => void,
  onCancel: () => void,
): void {
  proactiveLoginPromptShown = false;
  dismissLoginAutofillPrompt();
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1f2937" : "#ffffff";
  const text = isDark ? "#f3f4f6" : "#111827";
  const subText = isDark ? "#9ca3af" : "#6b7280";
  const border = isDark ? "#374151" : "#e5e7eb";

  const inputBg = isDark ? "#111827" : "#f8fafc";
  const rowBdr = isDark ? "#2d2d3d" : "#f3f4f6";
  const rpDomain = info.rpId;
  const favicon = `https://www.google.com/s2/favicons?sz=64&domain=${encodeURIComponent(rpDomain)}`;
  const rpAvatarHtml = itemAvatarHtml({ title: info.rpName || info.rpId, favicon });

  const el = document.createElement("div");
  el.style.cssText = `
    position: fixed; z-index: 2147483647; top: 72px; right: 24px;
    width: 320px; background: ${bg}; border: 1px solid ${border};
    border-radius: 12px; box-shadow: 0 6px 24px rgba(0,0,0,0.14);
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    overflow: hidden; animation: lp-slide-up 0.2s ease-out;
  `;
  el.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;padding:10px 12px;border-bottom:1px solid ${rowBdr};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:18px;height:18px;flex-shrink:0;">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#444ce7" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0 3 3L22 7l-3-3m-3.5 3.5L19 4"/></svg>
      </span>
      <p style="color:${text};font-size:13px;font-weight:600;margin:0;flex:1;">Save passkey</p>
      <button id="lp-pk-save-close" style="background:none;border:none;cursor:pointer;color:${subText};font-size:18px;padding:0 4px;line-height:1;">&times;</button>
    </div>
    <div style="padding:10px 12px;display:flex;align-items:center;gap:10px;background:${inputBg};border-bottom:1px solid ${rowBdr};">
      ${rpAvatarHtml}
      <div style="flex:1;min-width:0;">
        <p style="font-size:13px;font-weight:600;color:${text};margin:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${info.rpName || info.rpId}</p>
        <p style="font-size:11px;color:${subText};margin:1px 0 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${info.userName || info.rpId}</p>
      </div>
    </div>
    <div style="padding:10px 12px;display:flex;gap:6px;justify-content:flex-end;">
      <button id="lp-pk-skip-btn" style="background:none;border:1px solid ${border};border-radius:8px;padding:6px 12px;font-size:12px;color:${subText};cursor:pointer;font-weight:500;">Skip</button>
      <button id="lp-pk-save-btn" style="background:#444ce7;color:white;border:none;border-radius:8px;padding:6px 14px;font-size:12px;font-weight:600;cursor:pointer;">Save</button>
    </div>`;

  lpAppend(el);

  bindItemAvatarFallbacks(el);

  el.querySelector("#lp-pk-save-btn")?.addEventListener("click", () => { el.remove(); onSave(); });
  el.querySelector("#lp-pk-skip-btn")?.addEventListener("click", () => { el.remove(); onCancel(); });
  el.querySelector("#lp-pk-save-close")?.addEventListener("click", () => { el.remove(); onCancel(); });
}

function showPasskeyConflictPrompt(
  info: { rpName: string; rpId: string; userName: string },
  matches: PasskeyMatchItem[],
  onUpdate: (entryId: string) => void,
  onCreateNew: () => void,
  onCancel: () => void,
): void {
  proactiveLoginPromptShown = false;
  dismissLoginAutofillPrompt();
  const isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg = isDark ? "#1f2937" : "#ffffff";
  const text = isDark ? "#f3f4f6" : "#111827";
  const sub = isDark ? "#9ca3af" : "#6b7280";
  const border = isDark ? "#374151" : "#e5e7eb";
  const rowBorder = isDark ? "#2d2d3d" : "#f3f4f6";
  const hoverBg = isDark ? "#2a2a3d" : "#f5f5f7";
  const tabBg = isDark ? "#111827" : "#f3f4f6";
  const hasMatches = matches.length > 0;
  const hasUsernameMatches = matches.some((entry) => entry.usernameMatched);
  const hasIncomingUsername = !!info.userName.trim();
  let activeTab: "update" | "new" = hasUsernameMatches || !hasIncomingUsername ? "update" : "new";
  let selectedExistingEntryId: string | null = hasMatches ? (matches.find((entry) => entry.usernameMatched)?.id ?? matches[0].id) : null;
  ensureOverlayStyles();

  const description = hasUsernameMatches
    ? `${matches.length} existing record${matches.length > 1 ? "s" : ""} found — recommended to update.`
    : `${matches.length} existing record${matches.length > 1 ? "s" : ""} found.`;

  const el = document.createElement("div");
  el.style.cssText = `position:fixed;z-index:2147483647;top:72px;right:24px;width:340px;background:${bg};border:1px solid ${border};border-radius:12px;box-shadow:0 6px 24px rgba(0,0,0,0.12);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;overflow:hidden;animation:lp-slide-up 0.18s ease-out;`;
  el.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;padding:10px 12px;border-bottom:1px solid ${rowBorder};">
      <span style="display:inline-flex;align-items:center;justify-content:center;width:18px;height:18px;flex-shrink:0;">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#444ce7" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0 3 3L22 7l-3-3m-3.5 3.5L19 4"/></svg>
      </span>
      <div style="flex:1;min-width:0;">
        <p style="font-size:13px;font-weight:600;color:${text};margin:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">Save passkey</p>
        <p style="font-size:11px;color:${sub};margin:1px 0 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${info.rpName || info.rpId} • ${info.userName || "No username"}</p>
      </div>
      <button id="lp-pk-conflict-close" style="background:none;border:none;cursor:pointer;padding:0 4px;color:${sub};font-size:18px;line-height:1;">&times;</button>
    </div>
    <div style="padding:8px 12px 6px;color:${sub};font-size:11px;line-height:1.4;">
      ${description}
    </div>
    <div style="padding:0 12px 8px;">
      <div style="display:flex;gap:4px;padding:3px;background:${tabBg};border-radius:8px;">
        <button id="lp-pk-tab-update" style="flex:1;border:none;border-radius:6px;padding:6px 8px;font-size:11px;font-weight:600;cursor:pointer;">Update</button>
        <button id="lp-pk-tab-new" style="flex:1;border:none;border-radius:6px;padding:6px 8px;font-size:11px;font-weight:600;cursor:pointer;">New</button>
      </div>
    </div>
    <div id="lp-pk-update-panel" style="display:none;">
      <div style="padding:0 12px 8px;">
        <input
          id="lp-pk-conflict-search"
          type="text"
          placeholder="Search existing records"
          style="width:100%;padding:7px 10px;border:1px solid ${isDark ? "#374151" : "#e5e7eb"};border-radius:8px;background:${isDark ? "#111827" : "#f8fafc"};color:${text};font-size:12px;outline:none;box-sizing:border-box;"
        />
      </div>
      <div id="lp-pk-conflict-list" class="lp-scroll" style="max-height:min(260px, calc(100vh - 320px));border-top:1px solid ${rowBorder};border-bottom:1px solid ${rowBorder};"></div>
    </div>
    <div id="lp-pk-new-panel" style="display:none;padding:8px 12px 10px;">
      <div style="padding:9px 10px;border:1px solid ${border};border-radius:8px;background:${isDark ? "#111827" : "#f8fafc"};color:${sub};font-size:11px;line-height:1.45;">
        Create a separate passkey record for this website.
      </div>
    </div>
    <div style="padding:10px 12px;display:flex;justify-content:flex-end;gap:6px;border-top:1px solid ${rowBorder};">
      <button id="lp-pk-choice-cancel" style="background:none;border:1px solid ${border};border-radius:8px;padding:6px 12px;font-size:12px;color:${text};cursor:pointer;font-weight:500;">Cancel</button>
      <button id="lp-pk-choice-confirm" style="background:#444ce7;color:white;border:none;border-radius:8px;padding:6px 14px;font-size:12px;font-weight:600;cursor:pointer;">Continue</button>
    </div>
  `;

  lpAppend(el);
  passkeyPromptEl = el as HTMLDivElement;

  const listEl = el.querySelector<HTMLDivElement>("#lp-pk-conflict-list");
  const searchEl = el.querySelector<HTMLInputElement>("#lp-pk-conflict-search");
  const confirmBtn = el.querySelector<HTMLButtonElement>("#lp-pk-choice-confirm");
  const updatePanel = el.querySelector<HTMLElement>("#lp-pk-update-panel");
  const newPanel = el.querySelector<HTMLElement>("#lp-pk-new-panel");
  const updateTabBtn = el.querySelector<HTMLButtonElement>("#lp-pk-tab-update");
  const newTabBtn = el.querySelector<HTMLButtonElement>("#lp-pk-tab-new");

  const setActiveTab = (tab: "update" | "new"): void => {
    activeTab = tab;
    const updateActive = tab === "update";
    const activeBg = "#444ce7";
    const activeText = "#ffffff";
    const inactiveBg = "transparent";
    const inactiveText = isDark ? "#d1d5db" : "#4b5563";

    if (updateTabBtn) {
      updateTabBtn.style.background = updateActive ? activeBg : inactiveBg;
      updateTabBtn.style.color = updateActive ? activeText : inactiveText;
    }
    if (newTabBtn) {
      newTabBtn.style.background = updateActive ? inactiveBg : activeBg;
      newTabBtn.style.color = updateActive ? inactiveText : activeText;
    }

    if (updatePanel) updatePanel.style.display = updateActive ? "block" : "none";
    if (newPanel) newPanel.style.display = updateActive ? "none" : "block";
    if (confirmBtn) confirmBtn.textContent = updateActive ? "Update Selected" : "Create New Record";
  };

  const renderRows = (query: string): void => {
    if (!listEl) return;
    const filteredMatches = filterPasskeyEntries(matches, query);
    listEl.innerHTML = filteredMatches.map((entry, index) => {
      const favicon = `https://www.google.com/s2/favicons?sz=64&domain=${encodeURIComponent(entry.rpId)}`;
      const avatarHtml = itemAvatarHtml({ title: entry.title, favicon });
      const checked = selectedExistingEntryId === entry.id ? "checked" : "";
      const subtitle = entry.username || entry.rpId;
      const badge = entry.usernameMatched ? `<span style="margin-left:5px;font-size:9px;color:white;background:#444ce7;border-radius:999px;padding:1px 5px;font-weight:600;">Match</span>` : "";
      return `<label data-passkey-match="${index}" style="display:flex;align-items:center;gap:10px;padding:8px 12px;cursor:pointer;border-bottom:1px solid ${rowBorder};transition:background 0.1s;">
        <input type="radio" name="lp-pk-target" value="match-${index}" ${checked} style="accent-color:#444ce7;" />
        ${avatarHtml}
        <div style="flex:1;min-width:0;">
          <p style="display:flex;align-items:center;font-size:13px;font-weight:600;color:${text};margin:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${entry.title}${badge}</p>
          <p style="font-size:11px;color:${sub};margin:1px 0 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${subtitle}</p>
        </div>
      </label>`;
    }).join("") || `<div style="padding:14px 12px;color:${sub};font-size:12px;text-align:center;">No matching records for this search.</div>`;

    bindItemAvatarFallbacks(listEl);

    listEl.querySelectorAll<HTMLElement>("[data-passkey-match]").forEach((row) => {
      row.addEventListener("mouseenter", () => { row.style.background = hoverBg; });
      row.addEventListener("mouseleave", () => { row.style.background = ""; });
      row.addEventListener("click", () => {
        const index = parseInt(row.dataset.passkeyMatch ?? "0", 10);
        const target = filteredMatches[index];
        if (!target) return;
        selectedExistingEntryId = target.id;
      });
    });
  };

  renderRows("");
  searchEl?.addEventListener("input", () => renderRows(searchEl.value));
  updateTabBtn?.addEventListener("click", () => setActiveTab("update"));
  newTabBtn?.addEventListener("click", () => setActiveTab("new"));
  setActiveTab(activeTab);

  el.querySelector("#lp-pk-choice-cancel")?.addEventListener("click", () => {
    el.remove();
    passkeyPromptEl = null;
    onCancel();
  });

  el.querySelector("#lp-pk-choice-confirm")?.addEventListener("click", () => {
    el.remove();
    passkeyPromptEl = null;
    if (activeTab === "update" && selectedExistingEntryId) {
      onUpdate(selectedExistingEntryId);
      return;
    }
    onCreateNew();
  });

  el.querySelector("#lp-pk-conflict-close")?.addEventListener("click", () => {
    el.remove();
    passkeyPromptEl = null;
    onCancel();
  });
}

window.addEventListener("message", async (evt) => {
  if (evt.source !== window || !evt.data?.[LP] || evt.data.direction !== "page") return;

  if (evt.data.type === "PASSKEY_CREATE") {
    const { requestId, publicKey } = evt.data as {
      requestId: string;
      publicKey: { challenge: number[]; rpId: string; rpName: string; userId: number[]; userName: string; userDisplayName: string };
    };
    console.log("[LumenPass Passkey] PASSKEY_CREATE intercepted", { rpId: publicKey.rpId, userName: publicKey.userName });

    const runCreate = async (existingEntryId?: string) => {
      const res = await browser.runtime.sendMessage({
        type: "PASSKEY_CREATE",
        payload: {
          rpId: publicKey.rpId,
          rpName: publicKey.rpName,
          userId: publicKey.userId,
          userName: publicKey.userName,
          userDisplayName: publicKey.userDisplayName,
          challenge: publicKey.challenge,
          origin: window.location.origin,
          existingEntryId,
        },
      });
      console.log("[LumenPass Passkey] PASSKEY_CREATE response", res);
      if (res?.ok && res.data) {
        window.postMessage({ [LP]: true, requestId, credential: res.data }, "*");
      } else {
        console.warn("[LumenPass Passkey] create failed:", res?.error);
        window.postMessage({ [LP]: true, requestId, cancel: true }, "*");
      }
    };

    try {
      const matchRes = await browser.runtime.sendMessage({
        type: "PASSKEY_FIND_MATCHES",
        payload: {
          rpId: publicKey.rpId,
          username: publicKey.userName,
          origin: window.location.origin,
        },
      });
      console.log("[LumenPass Passkey] PASSKEY_FIND_MATCHES response", matchRes);
      if (matchRes?.ok && Array.isArray(matchRes.data)) {
        const siteMatches = matchRes.data as PasskeyMatchItem[];
        if (siteMatches.length > 0) {
          showPasskeyConflictPrompt(
            { rpName: publicKey.rpName, rpId: publicKey.rpId, userName: publicKey.userName },
            siteMatches,
            (existingEntryId) => { void runCreate(existingEntryId); },
            () => { void runCreate(); },
            () => {
              console.log("[LumenPass Passkey] user cancelled save target selection");
              window.postMessage({ [LP]: true, requestId, cancel: true }, "*");
            },
          );
          return;
        }
      }
    } catch (err) {
      console.warn("[LumenPass Passkey] failed to search for existing passkeys:", err);
    }

    showPasskeySavePrompt(
      { rpName: publicKey.rpName, rpId: publicKey.rpId, userName: publicKey.userName },
      async () => {
        await runCreate();
      },
      () => {
        console.log("[LumenPass Passkey] user skipped save — falling through to browser");
        window.postMessage({ [LP]: true, requestId, cancel: true }, "*");
      },
    );
    return;
  }

  if (evt.data.type !== "PASSKEY_GET") return;

  const { requestId, publicKey } = evt.data as {
    requestId: string;
    publicKey: { challenge: number[]; rpId: string; allowCredentials: { id: number[] }[] };
  };

  console.log("[LumenPass Passkey] intercepted navigator.credentials.get", { rpId: publicKey.rpId, requestId });
  const request: ActivePasskeyRequest = { requestId, publicKey };
  activePasskeyRequest = request;
  proactiveLoginPromptShown = false;
  dismissLoginAutofillPrompt();

  async function doAssert(entry: PasskeyEntry): Promise<void> {
    await assertPasskeyEntry(request, entry);
  }

  function showEntries(entries: PasskeyEntry[]): void {
    if (passkeyPromptEl) { passkeyPromptEl.remove(); passkeyPromptEl = null; }
    proactiveShown = false;
    showPasskeyPrompt(
      entries,
      async (entry) => doAssert(entry),
      () => {
        console.log("[LumenPass Passkey] user cancelled");
        cancelPasskeyRequest(requestId);
      },
    );
  }

  try {
    // 1) User already clicked an entry from the proactive popup — auto-assert
    if (pendingPasskeyEntry) {
      const entry = pendingPasskeyEntry;
      pendingPasskeyEntry = null;
      proactiveShown = false;
      if (passkeyPromptEl) { passkeyPromptEl.remove(); passkeyPromptEl = null; }
      console.log("[LumenPass Passkey] auto-resolving with pre-selected entry", entry.title);
      await doAssert(entry);
      return;
    }

    // 2) Use cached results from the proactive check — instant popup, no extra API call
    if (cachedPasskeyEntries && cachedForHostname === publicKey.rpId) {
      const entries = cachedPasskeyEntries;
      cachedPasskeyEntries = null;
      cachedForHostname = null;
      console.log("[LumenPass Passkey] using cached entries:", entries.length);
      showEntries(entries);
      return;
    }

    // 3) No cache — show loading pill and query service worker
    const loadingPill = document.createElement("div");
    loadingPill.style.cssText = "position:fixed;z-index:2147483647;top:72px;right:24px;background:#444ce7;color:white;font-size:12px;font-weight:600;padding:8px 14px;border-radius:10px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;box-shadow:0 4px 16px rgba(68,76,231,0.35);display:flex;align-items:center;gap:8px;";
    loadingPill.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0 3 3L22 7l-3-3m-3.5 3.5L19 4"/></svg>Looking up passkeys…`;
    lpAppend(loadingPill);

    const res = await browser.runtime.sendMessage({
      type: "PASSKEY_GET",
      payload: { rpId: publicKey.rpId, origin: window.location.origin },
    });
    loadingPill.remove();
    console.log("[LumenPass Passkey] PASSKEY_GET response", res);

    if (!res?.ok || !res.data?.length) {
      console.log("[LumenPass Passkey] no matching entries — falling through to browser");
      cancelPasskeyRequest(requestId);
      return;
    }

    // Service worker found a pre-selected entry (user picked before page navigation) — auto-assert
    if (res.autoSelectId) {
      const autoEntry = (res.data as PasskeyEntry[]).find((e) => e.id === res.autoSelectId);
      if (autoEntry) {
        console.log("[LumenPass Passkey] auto-asserting pre-selected entry across navigation:", autoEntry.title);
        if (passkeyPromptEl) { passkeyPromptEl.remove(); passkeyPromptEl = null; }
        await doAssert(autoEntry);
        return;
      }
    }

    showEntries(res.data as PasskeyEntry[]);
  } catch (err) {
    console.error("[LumenPass Passkey] content script error:", err);
    cancelPasskeyRequest(requestId);
  }
});

// ─── TOTP field detection ─────────────────────────────────────────────────────

const TOTP_SELECTOR = [
  "input[autocomplete='one-time-code']",
  "input[name*='otp']",
  "input[name*='totp']",
  "input[name*='2fa']",
  "input[name*='mfa']",
  "input[name*='verification']",
  "input[name*='verif']",
  "input[name*='authenticat']",
  "input[name*='code']",
  "input[name*='pin']",
  "input[name*='token']",
  "input[id*='otp']",
  "input[id*='totp']",
  "input[id*='2fa']",
  "input[id*='mfa']",
  "input[id*='verification']",
  "input[id*='authenticat']",
  "input[id*='code']",
  "input[id*='pin']",
  "input[id*='token']",
].join(",");

function getTotpInputField(): HTMLInputElement | null {
  const matches = Array.from(document.querySelectorAll<HTMLInputElement>(TOTP_SELECTOR));
  return matches.find((el) => isEditableInput(el) && !isPasswordField(el)) ?? null;
}

// ─── Proactive login + passkey detection ──────────────────────────────────────

async function checkForOtpOnLoad(): Promise<void> {
  if (isAutofillDisabledForCurrentDomain()) return;
  const totpField = getTotpInputField();
  if (!totpField) return;

  // Only handle TOTP-only pages; login pages are handled by checkForLoginsOnLoad
  if (getAutofillFields().length > 0) return;

  try {
    let autofillOnPageLoad = false;
    try {
      const settingsRes = await browser.runtime.sendMessage({ type: "GET_SETTINGS" });
      if (settingsRes?.ok && settingsRes.data) {
        autofillOnPageLoad = (settingsRes.data as { autofillOnPageLoad?: boolean }).autofillOnPageLoad ?? false;
      }
    } catch {
      // Keep the fresh-install default.
    }

    if (!autofillOnPageLoad) return;

    await fetchEntriesForPage();
    if (!entries.length) return;

    const fullEntry = await loadEntryDetail(entries[0]);
    if (!fullEntry.totp) return;

    simulateFill(totpField, fullEntry.totp);
  } catch {
    // Ignore disconnected or invalid page
  }
}

async function checkForLoginsOnLoad(): Promise<void> {
  if (!shouldConsiderProactiveLoginPrompt()) return;

  proactiveLoginPromptLastAttemptAt = Date.now();
  clearScheduledProactiveLoginPromptCheck();

  try {
    // Read the autofill-on-page-load setting from the service worker's cached settings.
    let autofillOnPageLoad = false;
    try {
      const settingsRes = await browser.runtime.sendMessage({ type: "GET_SETTINGS" });
      if (settingsRes?.ok && settingsRes.data) {
        autofillOnPageLoad = (settingsRes.data as { autofillOnPageLoad?: boolean }).autofillOnPageLoad ?? false;
      }
    } catch {
      // Keep the fresh-install default.
    }

    await fetchEntriesForPage();
    if (socialEntries.length > 0) {
      maybeShowSocialFloatingSuggestion();
    }
    if (!entries.length || passkeyPromptEl || isInlineAutofillPopupVisible()) return;
    if (!autofillOnPageLoad && !shouldConsiderProactiveLoginPrompt()) return;

    if (autofillOnPageLoad) {
      // Silently fill the top matching entry without showing a picker.
      activeAutofillField = activeAutofillField ?? getPrimaryAutofillField();
      await fillEntry(entries[0]);
    } else {
      // Show the proactive picker so the user can choose which entry to fill.
      proactiveLoginPromptShown = true;
      showLoginAutofillPrompt(
        entries,
        async (entry) => {
          proactiveLoginPromptShown = false;
          markProactiveLoginPromptDismissedForCurrentPage();
          activeAutofillField = activeAutofillField ?? getPrimaryAutofillField();
          await fillEntry(entry);
        },
        () => {
          proactiveLoginPromptShown = false;
        },
      );
    }
  } catch {
    // Ignore if the extension is disconnected or the page is no longer valid.
  }
}

async function getVaultStatus(): Promise<{ connected: boolean; vaultOpen: boolean } | null> {
  try {
    const res = await browser.runtime.sendMessage({ type: "GET_VAULT_STATUS" });
    if (res?.ok && res.data) {
      return { connected: res.data.connected, vaultOpen: res.data.vaultOpen };
    }
  } catch {
    // Silent fail
  }
  return null;
}

async function checkForPasskeysOnLoad(): Promise<void> {
  if (proactiveShown || activePasskeyRequest) return;

  const surface = describeLoginSurface();
  if (!surface.isLoginSurface) {
    console.log(
      "[LumenPass Passkey] suppressing proactive prompt – not a login surface",
      { reason: surface.reason, url: window.location.href },
    );
    return;
  }

  const vaultStatus = await getVaultStatus();
  if (!vaultStatus?.connected || !vaultStatus.vaultOpen) {
    return;
  }

  try {
    const res = await browser.runtime.sendMessage({
      type: "PASSKEY_GET",
      payload: { rpId: window.location.hostname, origin: window.location.origin },
    });
    if (!res?.ok || !res.data?.length) return;

    const entries = res.data as PasskeyEntry[];

    // Cache results so the credentials.get() handler can use them instantly
    cachedPasskeyEntries = entries;
    cachedForHostname = window.location.hostname;

    proactiveShown = true;
    console.log("[LumenPass Passkey] proactive prompt shown for", window.location.hostname, "entries:", entries.length);

    showPasskeyPrompt(
      entries,
      async (entry) => {
        cachedPasskeyEntries = null;
        cachedForHostname = null;
        proactiveShown = false;

        if (activePasskeyRequest && activePasskeyRequest.publicKey.rpId === entry.rpId) {
          pendingPasskeyEntry = null;
          console.log("[LumenPass Passkey] proactive selection resolving active request", {
            requestId: activePasskeyRequest.requestId,
            title: entry.title,
          });
          await assertPasskeyEntry(activePasskeyRequest, entry);
          return;
        }

        pendingPasskeyEntry = entry;
        console.log("[LumenPass Passkey] entry pre-selected:", entry.title);

        // Register this selection with the service worker so it survives page navigation
        void browser.runtime.sendMessage({ type: "SET_PENDING_PASSKEY", payload: { entry } });

        // Show a "signing in…" spinner badge while we auto-fill + submit
        ensureOverlayStyles();
        const badge = document.createElement("div");
        badge.style.cssText = "position:fixed;z-index:2147483647;top:72px;right:24px;max-width:320px;background:#1e1b4b;color:white;font-size:12px;font-weight:500;padding:10px 14px;border-radius:12px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;box-shadow:0 4px 20px rgba(68,76,231,0.45);display:flex;align-items:center;gap:10px;line-height:1.45;";
        badge.innerHTML = `
          <svg style="flex-shrink:0;animation:lp-spin 1s linear infinite;" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#a5b4fc" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>
          <span style="flex:1;">Signing in as <strong style="font-weight:700;">${entry.username || entry.title}</strong>…</span>
        `;
        lpAppend(badge);

        // Attempt auto-fill + auto-submit; fall back to manual instruction if no field found
        const didAutofill = await autofillUsernameAndSubmit(entry);
        if (!didAutofill) {
          // Page may already be at the passkey challenge step — update badge
          badge.innerHTML = `
            <svg style="flex-shrink:0;margin-top:1px;" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#a5b4fc" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0 3 3L22 7l-3-3m-3.5 3.5L19 4"/></svg>
            <span style="flex:1;"><strong style="font-weight:700;">${entry.title}</strong> passkey ready — click Sign in on this page.</span>
            <button style="background:none;border:none;cursor:pointer;color:rgba(255,255,255,0.5);font-size:16px;line-height:1;padding:0;flex-shrink:0;" title="Dismiss">×</button>
          `;
          badge.querySelector("button")?.addEventListener("click", () => badge.remove());
        }

        setTimeout(() => badge.remove(), 8_000);
      },
      () => {
        proactiveShown = false;
        // Keep cache valid so credentials.get() can still use it
      },
    );
  } catch {
    // ignore — may not be a login page
  }
}

// ─── Save prompt message listener (from SW after successful navigation) ───────

browser.runtime.onMessage.addListener((rawMessage: unknown) => {
  const message = rawMessage as { type: string; payload?: unknown };

  if (message.type === "DISABLED_AUTOFILL_DOMAINS_UPDATED") {
    const payload = message.payload as { disabledAutofillDomains?: DisabledAutofillDomain[] };
    applyDisabledAutofillDomains(payload.disabledAutofillDomains ?? []);
    return;
  }

  if (message.type === "VAULT_STATUS_CHANGED") {
    const payload = message.payload as { connected: boolean; vaultOpen: boolean };
    desktopConnected = payload.connected;
    desktopVaultOpen = payload.vaultOpen;
    if (popupEl?.style.display === "block" && activeAutofillField) {
      showPopup(activeAutofillField);
    }
    if (payload.connected && payload.vaultOpen) {
      scheduleProactiveLoginPromptCheck(250, { force: true });
    }
    return;
  }

  if (message.type === "GET_LOGIN_SURFACE_STATE") {
    return Promise.resolve({
      isLikelyLoginSurface: isLikelyLoginSurface(),
      passwordFieldCount: getPasswordFields().length,
      otpFieldCount: getVisibleInputs().filter(isOneTimeCodeField).length,
      url: window.location.href,
      // Social: best-effort detect a logged-in email on the current page
      detectedEmail: detectLoggedInEmail(),
    });
  }

  if (message.type === "SHOW_SAVE_SOCIAL_PROMPT") {
    const { provider: providerId, providerLabel, username, fromUrl } = message.payload as {
      provider: string;
      providerLabel: string;
      username: string;
      fromUrl: string;
    };
    const providerDef = SOCIAL_PROVIDERS.find((p) => p.id === providerId)
      ?? { id: "other" as const, label: providerLabel || "Social", color: "#444ce7",
           pattern: /(?!)/u, svg: `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/></svg>` };
    const initialTitle = extractDomain(fromUrl || window.location.href);

    showSaveSocialLoginPrompt(
      { provider: providerDef as SocialProviderDef, username, title: initialTitle },
      async (title, categoryUuid) => {
        try {
          const response = await browser.runtime.sendMessage({
            type: "SAVE_SOCIAL_LOGIN",
            payload: {
              title,
              username,
              url: fromUrl || window.location.href,
              provider: providerId,
              providerLabel,
              categoryUuid,
            },
          });
          if (response?.ok) {
            showSaveResultToast(true, `${providerDef.label} sign-in saved to LumenPass`);
          } else {
            showSaveResultToast(false, response?.error ?? "Failed to save");
          }
        } catch {
          showSaveResultToast(false, "Failed to save sign-in method");
        }
      },
      () => { /* user dismissed */ },
    );
    return Promise.resolve({ ok: true });
  }

  if (message.type !== "SHOW_SAVE_PROMPT") {
    if (message.type === "OPEN_QUICK_CREATE_LOGIN") {
      const payload = message.payload as { url?: string; title?: string };
      const initialUrl = payload?.url || window.location.href;
      let initialTitle = (payload?.title || "").trim();
      if (!initialTitle) {
        try { initialTitle = new URL(initialUrl).hostname.replace(/^www\./, ""); } catch { initialTitle = ""; }
      }
      showQuickCreateLoginPrompt(
        { title: initialTitle, url: initialUrl },
        async (values, categoryUuid) => {
          try {
            const response = await browser.runtime.sendMessage({
              type: "SAVE_LOGIN",
              payload: {
                title: values.title,
                username: values.username,
                password: values.password,
                url: values.url,
                categoryUuid,
                notes: values.notes,
                totp: values.totp,
                customFields: values.metadata.map((field) => ({
                  label: field.label,
                  value: field.value,
                  secret: field.secret ?? false,
                })),
              },
            });
            if (response?.ok) {
              showSaveResultToast(true, "Login saved to LumenPass");
            } else {
              showSaveResultToast(false, response?.error ?? "Failed to save login");
            }
          } catch {
            showSaveResultToast(false, "Failed to save login");
          }
        },
        () => { /* user dismissed */ },
      );
      return Promise.resolve({ ok: true });
    }
    if (message.type === "OPEN_QUICK_CREATE_NOTE") {
      const payload = message.payload as { url?: string; title?: string; selection?: string };
      const initialUrl = payload?.url || window.location.href;
      let initialTitle = (payload?.title || "").trim();
      if (!initialTitle) {
        try { initialTitle = new URL(initialUrl).hostname.replace(/^www\./, ""); } catch { initialTitle = ""; }
      }
      const selection = (payload?.selection ?? "").trim();
      const initialNotes = selection
        ? `${selection}\n\n— ${initialUrl}`
        : initialUrl;
      showQuickCreateNotePrompt(
        { title: initialTitle || "Quick note", url: initialUrl, notes: initialNotes },
        async (values, categoryUuid) => {
          try {
            const response = await browser.runtime.sendMessage({
              type: "SAVE_NOTE",
              payload: {
                title: values.title,
                notes: values.notes,
                url: values.url,
                categoryUuid,
                tags: values.tags,
                customFields: values.metadata.map((field) => ({
                  label: field.label,
                  value: field.value,
                  secret: field.secret ?? false,
                })),
              },
            });
            if (response?.ok) {
              showSaveResultToast(true, "Note saved to LumenPass");
            } else {
              showSaveResultToast(false, response?.error ?? "Failed to save note");
            }
          } catch {
            showSaveResultToast(false, "Failed to save note");
          }
        },
        () => { /* user dismissed */ },
      );
      return Promise.resolve({ ok: true });
    }
    if (message.type === "OPEN_FILL_EMAIL") {
      const targetField: HTMLInputElement | null =
        (lastContextMenuField && lastContextMenuField.isConnected && isEditableInput(lastContextMenuField))
          ? lastContextMenuField
          : (activeAutofillField instanceof HTMLInputElement && activeAutofillField.isConnected && isEditableInput(activeAutofillField)
              ? activeAutofillField
              : null);
      void showFillValuePrompt({ kind: "email", targetField });
      return Promise.resolve({ ok: true });
    }
    if (message.type === "OPEN_FILL_USERNAME") {
      const targetField: HTMLInputElement | null =
        (lastContextMenuField && lastContextMenuField.isConnected && isEditableInput(lastContextMenuField))
          ? lastContextMenuField
          : (activeAutofillField instanceof HTMLInputElement && activeAutofillField.isConnected && isEditableInput(activeAutofillField)
              ? activeAutofillField
              : null);
      void showFillValuePrompt({ kind: "username", targetField });
      return Promise.resolve({ ok: true });
    }
    if (message.type === "OPEN_FILL_OTP") {
      const targetField = getTotpInputField()
        ?? ((lastContextMenuField && lastContextMenuField.isConnected && isEditableInput(lastContextMenuField))
          ? lastContextMenuField
          : (activeAutofillField instanceof HTMLInputElement && activeAutofillField.isConnected && isEditableInput(activeAutofillField)
              ? activeAutofillField
              : null));
      void showFillOtpPrompt(targetField);
      return Promise.resolve({ ok: true });
    }
    if (message.type === "OPEN_PASSWORD_GENERATOR") {
      // Prefer the field the user right-clicked on; fall back to activeAutofillField
      // (password-typed), then scan for any visible password input on the page.
      const targetField: HTMLInputElement | null = (() => {
        if (lastContextMenuField && lastContextMenuField.isConnected && isEditableInput(lastContextMenuField)) {
          return lastContextMenuField;
        }
        if (activeAutofillField instanceof HTMLInputElement && activeAutofillField.isConnected && isEditableInput(activeAutofillField)) {
          return activeAutofillField;
        }
        const visiblePasswords = Array.from(
          document.querySelectorAll<HTMLInputElement>("input[type='password']"),
        ).filter((field) => isVisible(field) && !field.disabled && !field.readOnly);
        return visiblePasswords[0] ?? null;
      })();
      showPasswordGeneratorModal({ initialTargetField: targetField });
      return Promise.resolve({ ok: true });
    }
    return;
  }

  const payload = message.payload as {
    username: string;
    password: string;
    mode?: "new" | "update" | "multi-choice";
    existingEntryId?: string;
    existingTitle?: string;
    candidates?: SaveLoginCandidateEntry[];
  };
  const { username, password, mode, existingEntryId, existingTitle, candidates } = payload;
  const isUpdate = mode === "update" && !!existingEntryId && !!existingTitle;
  const isMultiChoice = mode === "multi-choice" && Array.isArray(candidates) && candidates.length > 0;
  const initialTitle = isUpdate
    ? existingTitle
    : isMultiChoice
      ? candidates![0].title
      : extractDomain(window.location.href);
  showSaveLoginPrompt(
    {
      title: initialTitle,
      username,
      password,
      mode,
      existingEntryId,
      existingTitle,
      candidates,
    },
    async (values, categoryUuid, opts) => {
      try {
        const body: Record<string, unknown> = {
          title: values.title,
          username: values.username,
          password: values.password,
          url: values.url,
          categoryUuid,
          customFields: values.metadata.map((field) => ({
            label: field.label,
            value: field.value,
            secret: field.secret ?? false,
          })),
        };
        if (opts?.existingEntryId) {
          body.existingEntryId = opts.existingEntryId;
        }
        const response = await browser.runtime.sendMessage({
          type: "SAVE_LOGIN",
          payload: body,
        });
        if (response?.ok) {
          const savedMode = (response.data as { mode?: string } | undefined)?.mode;
          const okMsg =
            savedMode === "updated"
              ? "Login updated in LumenPass"
              : "Login saved to LumenPass";
          showSaveResultToast(true, okMsg);
        } else {
          showSaveResultToast(false, response?.error ?? "Failed to save login");
        }
      } catch {
        showSaveResultToast(false, "Failed to save login");
      }
    },
    () => { /* user dismissed */ },
  );

  return Promise.resolve({ ok: true });
});

// ─── Signup password suggestion ───────────────────────────────────────────────

let suggestEl: HTMLDivElement | null = null;
let activeSuggestField: HTMLInputElement | null = null;
let suggestPassword = "";
let suggestLength = 20;
let suggestUseNumbers = true;
let suggestUseSymbols = true;
let suggestExpanded = false;
let suppressSuggestPopup = false;
let _suggestClickInside = false;

function randSecure(max: number): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return buf[0] % max;
}

function buildSuggestPassword(): string {
  const lower = "abcdefghijkmnopqrstuvwxyz";
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const nums  = "23456789";
  const syms  = "!@#$%^&*-_";
  let pool = lower + upper;
  const required = [lower[randSecure(lower.length)], upper[randSecure(upper.length)]];
  if (suggestUseNumbers) { pool += nums; required.push(nums[randSecure(nums.length)]); }
  if (suggestUseSymbols) { pool += syms; required.push(syms[randSecure(syms.length)]); }
  const fill = Array.from({ length: Math.max(0, suggestLength - required.length) }, () => pool[randSecure(pool.length)]);
  const chars = [...required, ...fill];
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randSecure(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}

function colorPasswordHtml(pw: string): string {
  return pw.split("").map((c) => {
    if (/\d/.test(c)) return `<span style="color:#0F67D6;font-weight:700">${c}</span>`;
    if (/[^a-zA-Z0-9]/.test(c)) return `<span style="color:#EA8C00;font-weight:700">${c}</span>`;
    return c;
  }).join("");
}

function isSignupPasswordField(field: HTMLInputElement): boolean {
  if (!isPasswordField(field)) return false;
  const ac = (field.autocomplete ?? "").toLowerCase();
  if (ac === "current-password") return false;
  if (ac === "new-password") return true;
  const d = getFieldDescriptor(field);
  if (/confirm.?pass|repeat.?pass|retype.?pass|verify.?pass/.test(d)) return false;
  if (/new.?pass|create.?pass|choose.?pass|set.?pass/.test(d)) return true;
  const scope = field.closest("form") ?? document;
  const pwFields = Array.from(scope.querySelectorAll<HTMLInputElement>("input[type='password']")).filter(isEditableInput);
  const hasCurrentPasswordHint = pwFields.some((pwField) => {
    const pwAutocomplete = (pwField.autocomplete ?? "").toLowerCase();
    if (pwAutocomplete === "current-password") return true;
    const descriptor = getFieldDescriptor(pwField);
    return /current.?pass|old.?pass|existing.?pass/.test(descriptor);
  });
  if (hasCurrentPasswordHint) return false;
  if (pwFields.length >= 2) return pwFields[0] === field;
  const pathTitle = (window.location.pathname + " " + document.title).toLowerCase();
  if (/(sign.?up|register|create.?account|join|signup)/.test(pathTitle)) return true;
  const pageText = (document.body?.innerText ?? "").toLowerCase().slice(0, 2000);
  return /(sign.?up|create.?account|register|join now|get started)/.test(pageText)
    && !/(sign.?in|log.?in|login)/.test(pathTitle);
}

function positionSuggestPopup(): void {
  if (!suggestEl || !activeSuggestField) return;
  const rect = activeSuggestField.getBoundingClientRect();
  const popW = 320;
  const popH = suggestEl.offsetHeight || (suggestExpanded ? 290 : 72);
  const spaceBelow = window.innerHeight - rect.bottom;
  let top = rect.bottom + window.scrollY + 6;
  if (spaceBelow < popH + 10 && rect.top > popH + 10) top = rect.top + window.scrollY - popH - 6;
  let left = rect.left + window.scrollX;
  if (left + popW > document.documentElement.clientWidth - 8) left = Math.max(8, document.documentElement.clientWidth - popW - 8);
  suggestEl.style.top = `${top}px`;
  suggestEl.style.left = `${left}px`;
  suggestEl.style.width = `${popW}px`;
}

function renderSuggestPopup(): void {
  if (!suggestEl) return;
  const isDark  = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const bg      = isDark ? "#1e1e2e" : "#ffffff";
  const text    = isDark ? "#f3f4f6" : "#111827";
  const sub     = isDark ? "#9ca3af" : "#6b7280";
  const border  = isDark ? "#374151" : "#e5e7eb";
  const inputBg = isDark ? "#111827" : "#f8fafc";
  const trackOff = isDark ? "#4b5563" : "#d1d5db";
  suggestEl.style.background = bg;
  suggestEl.style.borderColor = border;

  const toggleHtml = (id: string, on: boolean): string =>
    `<label style="position:relative;display:inline-flex;width:36px;height:20px;cursor:pointer;" for="${id}">
      <input id="${id}" type="checkbox" ${on ? "checked" : ""} style="opacity:0;width:0;height:0;position:absolute;" />
      <span style="position:absolute;inset:0;border-radius:999px;background:${on ? "#444ce7" : trackOff};transition:background 0.2s;pointer-events:none;"></span>
      <span style="position:absolute;top:2px;left:${on ? "18px" : "2px"};width:16px;height:16px;border-radius:50%;background:white;transition:left 0.2s;pointer-events:none;"></span>
    </label>`;

  if (!suggestExpanded) {
    suggestEl.innerHTML = `
      <div id="lp-sg-use" style="display:flex;align-items:center;gap:10px;padding:10px 12px;cursor:pointer;">
        <div style="width:36px;height:36px;border-radius:9px;background:#444ce7;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 2l-2 2m-7.61 7.61a5.5 5.5 0 1 1-7.778 7.778 5.5 5.5 0 0 1 7.777-7.777zm0 0L15.5 7.5m0 0 3 3L22 7l-3-3m-3.5 3.5L19 4"/></svg>
        </div>
        <div style="flex:1;min-width:0;">
          <div style="font-size:13px;font-weight:600;color:${text};margin-bottom:1px;">Use Suggested Password</div>
          <div style="font-size:11px;color:${sub};font-family:'SF Mono',SFMono-Regular,Consolas,monospace;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${suggestPassword}</div>
        </div>
        <button id="lp-sg-regen-compact" title="Regenerate" style="width:30px;height:30px;border:1px solid ${border};border-radius:7px;background:none;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0;padding:0;">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="${sub}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
        </button>
        <button id="lp-sg-opts" title="Customize" style="width:30px;height:30px;border:1px solid ${border};border-radius:7px;background:none;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0;padding:0;">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="${sub}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><line x1="4" y1="21" x2="4" y2="14"/><line x1="4" y1="10" x2="4" y2="3"/><line x1="12" y1="21" x2="12" y2="12"/><line x1="12" y1="8" x2="12" y2="3"/><line x1="20" y1="21" x2="20" y2="16"/><line x1="20" y1="12" x2="20" y2="3"/><line x1="1" y1="14" x2="7" y2="14"/><line x1="9" y1="8" x2="15" y2="8"/><line x1="17" y1="16" x2="23" y2="16"/></svg>
        </button>
      </div>`;
    suggestEl.querySelector("#lp-sg-use")?.addEventListener("click", (e) => {
      if ((e.target as Element).closest("#lp-sg-opts") || (e.target as Element).closest("#lp-sg-regen-compact")) return;
      if (activeSuggestField) {
        const pwd = suggestPassword;
        void copyTextToClipboard(pwd);
        simulateFill(activeSuggestField, pwd);
        hideSuggestPopup(true);
      }
    });
    suggestEl.querySelector("#lp-sg-regen-compact")?.addEventListener("click", (e) => {
      e.stopPropagation();
      suggestPassword = buildSuggestPassword();
      renderSuggestPopup(); positionSuggestPopup();
    });
    suggestEl.querySelector("#lp-sg-opts")?.addEventListener("click", (e) => {
      e.stopPropagation();
      suggestExpanded = true;
      renderSuggestPopup();
      positionSuggestPopup();
    });
  } else {
    suggestEl.innerHTML = `
      <div style="padding:13px 13px 11px;">
        <div style="display:flex;align-items:center;gap:7px;margin-bottom:11px;">
          <button id="lp-sg-copy" style="padding:5px 13px;border:1px solid ${border};border-radius:8px;background:none;color:${text};font-size:12px;font-weight:500;cursor:pointer;">Copy</button>
          <button id="lp-sg-regen" title="Regenerate" style="width:30px;height:28px;border:1px solid ${border};border-radius:8px;background:none;cursor:pointer;display:flex;align-items:center;justify-content:center;padding:0;">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="${sub}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
          </button>
          <button id="lp-sg-fill" style="margin-left:auto;padding:5px 14px;border:none;border-radius:8px;background:#444ce7;color:white;font-size:12px;font-weight:600;cursor:pointer;">Autofill</button>
        </div>
        <div data-lp-pw style="font-family:'SF Mono',SFMono-Regular,Consolas,monospace;font-size:14px;font-weight:600;word-break:break-all;padding:8px 10px;background:${inputBg};border-radius:8px;margin-bottom:11px;line-height:1.6;">${colorPasswordHtml(suggestPassword)}</div>
        <div style="margin-bottom:8px;">
          <div style="display:flex;justify-content:space-between;margin-bottom:5px;">
            <span style="font-size:12px;color:${sub};">Length</span>
            <span id="lp-sg-len" style="font-size:12px;font-weight:600;color:${text};">${suggestLength}</span>
          </div>
          <input id="lp-sg-slider" type="range" min="8" max="64" value="${suggestLength}" style="width:100%;accent-color:#444ce7;cursor:pointer;" />
        </div>
        <div style="display:flex;justify-content:space-between;align-items:center;padding:7px 0;border-top:1px solid ${border};">
          <span style="font-size:12px;color:${text};">Numbers</span>
          ${toggleHtml("lp-sg-nums", suggestUseNumbers)}
        </div>
        <div style="display:flex;justify-content:space-between;align-items:center;padding:7px 0;border-top:1px solid ${border};">
          <span style="font-size:12px;color:${text};">Symbols</span>
          ${toggleHtml("lp-sg-syms", suggestUseSymbols)}
        </div>
        <div style="display:flex;justify-content:flex-end;padding-top:9px;border-top:1px solid ${border};">
          <button id="lp-sg-back" style="width:30px;height:28px;border:1px solid ${border};border-radius:8px;background:none;cursor:pointer;display:flex;align-items:center;justify-content:center;padding:0;">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="${sub}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>
          </button>
        </div>
      </div>`;
    suggestEl.querySelector("#lp-sg-copy")?.addEventListener("click", () => {
      void copyTextToClipboard(suggestPassword);
    });
    suggestEl.querySelector("#lp-sg-regen")?.addEventListener("click", () => {
      suggestPassword = buildSuggestPassword();
      renderSuggestPopup(); positionSuggestPopup();
    });
    suggestEl.querySelector("#lp-sg-fill")?.addEventListener("click", () => {
      if (activeSuggestField) {
        const pwd = suggestPassword;
        void copyTextToClipboard(pwd);
        simulateFill(activeSuggestField, pwd);
        hideSuggestPopup(true);
      }
    });
    const slider = suggestEl.querySelector<HTMLInputElement>("#lp-sg-slider");
    const lenLabel = suggestEl.querySelector<HTMLElement>("#lp-sg-len");
    slider?.addEventListener("input", () => {
      suggestLength = parseInt(slider!.value, 10);
      if (lenLabel) lenLabel.textContent = String(suggestLength);
      suggestPassword = buildSuggestPassword();
      const pwDiv = suggestEl?.querySelector<HTMLElement>("[data-lp-pw]");
      if (pwDiv) pwDiv.innerHTML = colorPasswordHtml(suggestPassword);
    });
    suggestEl.querySelector<HTMLInputElement>("#lp-sg-nums")?.addEventListener("change", (e) => {
      suggestUseNumbers = (e.target as HTMLInputElement).checked;
      suggestPassword = buildSuggestPassword(); renderSuggestPopup(); positionSuggestPopup();
    });
    suggestEl.querySelector<HTMLInputElement>("#lp-sg-syms")?.addEventListener("change", (e) => {
      suggestUseSymbols = (e.target as HTMLInputElement).checked;
      suggestPassword = buildSuggestPassword(); renderSuggestPopup(); positionSuggestPopup();
    });
    suggestEl.querySelector("#lp-sg-back")?.addEventListener("click", () => {
      suggestExpanded = false; renderSuggestPopup(); positionSuggestPopup();
    });
  }
}

function showSuggestPopup(field: HTMLInputElement): void {
  if (suppressSuggestPopup) return;
  if (suggestEl && activeSuggestField === field) return;
  hideSuggestPopup();
  activeSuggestField = field;
  suggestExpanded = false;
  suggestPassword = buildSuggestPassword();
  ensureOverlayStyles();
  const el = document.createElement("div");
  el.id = "lp-suggest-popup";
  el.style.cssText = `position:absolute;z-index:2147483647;border:1px solid #e5e7eb;border-radius:12px;box-shadow:0 4px 20px rgba(0,0,0,0.13);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;overflow:hidden;animation:lp-slide-up 0.15s ease-out;`;
  // Track clicks inside the popup so blur/document-click handlers don't dismiss it
  el.addEventListener("mousedown", () => {
    _suggestClickInside = true;
    window.setTimeout(() => { _suggestClickInside = false; }, 400);
  });
  lpAppend(el);
  suggestEl = el;
  renderSuggestPopup();
  positionSuggestPopup();
}

function hideSuggestPopup(suppressAfter = false): void {
  suggestEl?.remove();
  suggestEl = null;
  activeSuggestField = null;
  suggestExpanded = false;
  if (suppressAfter) {
    suppressSuggestPopup = true;
    window.setTimeout(() => { suppressSuggestPopup = false; }, 1500);
  }
}

function attachSuggestToPasswordField(field: HTMLInputElement): void {
  if ((field as HTMLInputElement & { _lpSuggestAttached?: boolean })._lpSuggestAttached) return;
  (field as HTMLInputElement & { _lpSuggestAttached?: boolean })._lpSuggestAttached = true;
  field.addEventListener("focus", () => {
    window.setTimeout(() => { if (document.activeElement === field) showSuggestPopup(field); }, 80);
  });
  field.addEventListener("blur", () => {
    window.setTimeout(() => {
      if (_suggestClickInside) return;
      const active = document.activeElement;
      if (active === field) return;
      if (lpShadowHost && active === lpShadowHost) return;
      hideSuggestPopup();
    }, 220);
  });
}

function reconcileSuggestPasswordFields(): void {
  getPasswordFields().forEach((field) => {
    if (isSignupPasswordField(field)) attachSuggestToPasswordField(field);
  });
}

// ─── Vault-status active polling ─────────────────────────────────────────────
//
// The background service worker polls the desktop on a chrome.alarms cadence,
// but those alarms can be throttled or skipped entirely while the SW is dormant
// (notably on Safari MV3). To guarantee the inline "Vault Locked" UI updates
// promptly after the user unlocks the desktop, the content script runs its own
// lightweight poll while a locked surface is visible to the user, and also
// refreshes on tab visibility / window focus changes.

const LOCKED_POLL_INTERVAL_MS = 2000;
const LOCKED_POLL_MAX_INTERVAL_MS = 8000;
let vaultStatusPollTimer: number | null = null;
let vaultStatusPollDelay = LOCKED_POLL_INTERVAL_MS;
let vaultStatusFetchInFlight = false;

function isLockedSurfaceVisible(): boolean {
  // The inline locked popup is the primary surface that needs to refresh.
  if (popupEl?.style.display === "block" && (!desktopConnected || !desktopVaultOpen)) {
    return true;
  }
  // While locked, also refresh whenever a LumenPass icon is rendered on a
  // visible field — the user may be hovering it waiting for unlock.
  if ((!desktopConnected || !desktopVaultOpen) && fieldIcons.size > 0) {
    return true;
  }
  return false;
}

async function refreshVaultStatus(): Promise<void> {
  if (vaultStatusFetchInFlight) return;
  vaultStatusFetchInFlight = true;
  try {
    const res = await browser.runtime.sendMessage({ type: "PING" }) as
      { ok: boolean; data?: { connected?: boolean; vaultOpen?: boolean } };
    const prevConnected = desktopConnected;
    const prevOpen = desktopVaultOpen;
    if (res?.ok && res.data) {
      desktopConnected = res.data.connected ?? true;
      desktopVaultOpen = res.data.vaultOpen ?? true;
    } else {
      desktopConnected = false;
      desktopVaultOpen = false;
    }
    // If the popup is showing, force a re-render so locked → unlocked flips
    // the UI from the locked state to the entry list (and vice versa).
    if (
      (prevConnected !== desktopConnected || prevOpen !== desktopVaultOpen)
      && popupEl?.style.display === "block"
      && activeAutofillField
    ) {
      showPopup(activeAutofillField);
    }
  } catch {
    // SW may be restarting (Chrome MV3 lifecycle). Treat as transient — the
    // next tick will retry; do not flip local state to disconnected here.
  } finally {
    vaultStatusFetchInFlight = false;
  }
}

function scheduleVaultStatusPoll(): void {
  if (vaultStatusPollTimer !== null) return;
  if (!isLockedSurfaceVisible()) {
    vaultStatusPollDelay = LOCKED_POLL_INTERVAL_MS;
    return;
  }
  vaultStatusPollTimer = window.setTimeout(async () => {
    vaultStatusPollTimer = null;
    await refreshVaultStatus();
    if (isLockedSurfaceVisible()) {
      // Stay tight while the locked UI is up; back off slightly on prolonged
      // disconnects so we don't burn cycles while the desktop is offline.
      if (!desktopConnected) {
        vaultStatusPollDelay = Math.min(vaultStatusPollDelay * 1.5, LOCKED_POLL_MAX_INTERVAL_MS);
      } else {
        vaultStatusPollDelay = LOCKED_POLL_INTERVAL_MS;
      }
      scheduleVaultStatusPoll();
    } else {
      vaultStatusPollDelay = LOCKED_POLL_INTERVAL_MS;
    }
  }, vaultStatusPollDelay);
}

function stopVaultStatusPoll(): void {
  if (vaultStatusPollTimer !== null) {
    window.clearTimeout(vaultStatusPollTimer);
    vaultStatusPollTimer = null;
  }
  vaultStatusPollDelay = LOCKED_POLL_INTERVAL_MS;
}

/** Public helper invoked from UI surfaces that should react to a vault state
 *  change (e.g. just rendered the locked popup, user clicked Unlock). */
function ensureVaultStatusFresh(): void {
  void refreshVaultStatus();
  scheduleVaultStatusPoll();
}

async function refreshAutofillSettings(): Promise<void> {
  try {
    const res = await browser.runtime.sendMessage({ type: "GET_SETTINGS" });
    if (res?.ok && res.data) {
      const data = res.data as {
        autofillEnabled?: boolean;
        autoSubmit?: boolean;
        disabledAutofillDomains?: DisabledAutofillDomain[];
      };
      const prevEnabled = autofillIconsEnabled;
      autofillIconsEnabled = data.autofillEnabled ?? true;
      autoSubmitEnabled = data.autoSubmit ?? false;
      applyDisabledAutofillDomains(data.disabledAutofillDomains ?? []);
      if (prevEnabled !== autofillIconsEnabled) reconcileAutofillFieldIcons();
    }
  } catch {
    // Ignore; content script will retry on focus/visibility changes.
  }
}

// ─── Init ─────────────────────────────────────────────────────────────────────

function init(): void {
  void browser.runtime.sendMessage({ type: "GET_VAULT_STATUS" }).then((res: { ok: boolean; data?: { connected: boolean; vaultOpen: boolean } }) => {
    if (res?.ok && res.data) {
      desktopConnected = res.data.connected;
      desktopVaultOpen = res.data.vaultOpen;
    }
  }).catch(() => {});

  void refreshAutofillSettings();

  const markUserInteraction = (): void => {
    hasUserInteracted = true;
  };

  document.addEventListener("pointerdown", markUserInteraction, {
    capture: true,
    passive: true,
  });
  document.addEventListener("keydown", markUserInteraction, {
    capture: true,
  });

  reconcileAutofillFieldIcons();
  reconcileSuggestPasswordFields();

  // Attach save detection to forms/buttons
  attachSaveDetection();

  // Observe DOM for dynamically added login fields
  const observer = new MutationObserver(() => {
    reconcileAutofillFieldIcons();
    attachSaveDetection();
    reconcileSuggestPasswordFields();
    attachSocialButtonListeners();
    scheduleProactiveLoginPromptCheck();
  });

  observer.observe(document.body, { childList: true, subtree: true });

  // Attach initial social button listeners
  attachSocialButtonListeners();

  // Let the page settle, then offer passkeys first and login fills shortly after.
  setTimeout(checkForPasskeysOnLoad, 1500);
  setTimeout(() => { void checkForLoginsOnLoad(); }, 1800);
  setTimeout(() => { void checkForOtpOnLoad(); }, 2100);

  // Close popups on outside clicks (don't hide icons)
  document.addEventListener("click", (e) => {
    const target = e.target as Node;
    const path = e.composedPath();
    let clickedIcon = false;
    fieldIcons.forEach((icon) => { if (path.includes(icon)) clickedIcon = true; });
    const clickedAutofillField = Array.from(fieldIcons.keys()).some((field) => field === target);
    if (clickedIcon || clickedAutofillField || (popupEl && path.includes(popupEl))) return;
    hidePopup();
    if (suggestEl && !_suggestClickInside && !path.includes(suggestEl) && target !== activeSuggestField) hideSuggestPopup();
  });

  // Reposition all icons + popup on scroll/resize
  window.addEventListener("scroll", () => {
    updateAllIconPositions();
    if (popupEl?.style.display === "block" && activeAutofillField) positionPopup(activeAutofillField);
    if (suggestEl) positionSuggestPopup();
  }, { passive: true });
  window.addEventListener("resize", () => {
    updateAllIconPositions();
    if (popupEl?.style.display === "block" && activeAutofillField) positionPopup(activeAutofillField);
    if (suggestEl) positionSuggestPopup();
  }, { passive: true });

  // Re-check vault status when the tab regains visibility / focus. This is
  // the most common way the user returns from the LumenPass desktop window
  // after unlocking, and we want the inline UI to update immediately.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      void refreshVaultStatus();
      void refreshAutofillSettings();
      scheduleVaultStatusPoll();
      scheduleProactiveLoginPromptCheck(250, { force: true });
    } else {
      // Pause active polling while the tab is hidden; resume on next visible.
      stopVaultStatusPoll();
    }
  });
  window.addEventListener("focus", () => {
    void refreshVaultStatus();
    void refreshAutofillSettings();
    scheduleVaultStatusPoll();
    scheduleProactiveLoginPromptCheck(250, { force: true });
  });
}

// ─── Signal readiness to passkey-inject.ts (MAIN world) ──────────────────────
// Some sites (e.g. Yahoo) call credentials.get() before document_idle fires.
// passkey-inject.ts buffers the request and replays it when it sees this signal.
const LP_INJECT = "LUMENPASS_PK";
window.postMessage({ [LP_INJECT]: true, type: "CONTENT_SCRIPT_READY" }, "*");

// Run when DOM is ready
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", () => {
    init();
    requestAnimationFrame(updateAllIconPositions);
  });
} else {
  init();
  // Re-position after first paint so any layout shifts are captured
  requestAnimationFrame(updateAllIconPositions);
  setTimeout(updateAllIconPositions, 300);
  setTimeout(updateAllIconPositions, 1500);
}
