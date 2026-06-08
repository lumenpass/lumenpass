function normalizeSelectValue(value: string): string {
  return value
    .toLowerCase()
    .replace(/[_./,-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function compactSelectValue(value: string): string {
  return normalizeSelectValue(value).replace(/[^a-z0-9]+/g, "");
}

export interface SelectOptionMatchCandidate {
  text: string;
  value: string;
}

export function findBestSelectOptionIndex(
  options: SelectOptionMatchCandidate[],
  rawTarget: string,
): number {
  const target = normalizeSelectValue(rawTarget);
  const targetCompact = compactSelectValue(rawTarget);
  if (!target) return -1;

  let bestScore = -1;
  let bestIndex = -1;

  for (const [index, option] of options.entries()) {
    const optionText = normalizeSelectValue(option.text);
    const optionValue = normalizeSelectValue(option.value);
    const optionTextCompact = compactSelectValue(option.text);
    const optionValueCompact = compactSelectValue(option.value);
    if (!optionText && !optionValue) continue;

    let score = -1;
    if (optionText === target) score = 500;
    else if (optionValue === target) score = 490;
    else if (!!targetCompact && optionTextCompact === targetCompact) score = 470;
    else if (!!targetCompact && optionValueCompact === targetCompact) score = 460;
    else if (
      targetCompact.length >= 3
      && optionTextCompact.length >= 3
      && (optionTextCompact.includes(targetCompact) || targetCompact.includes(optionTextCompact))
    ) {
      score = 320;
    } else if (
      targetCompact.length >= 3
      && optionValueCompact.length >= 3
      && (optionValueCompact.includes(targetCompact) || targetCompact.includes(optionValueCompact))
    ) {
      score = 300;
    } else if (
      target.length >= 3
      && optionText.length >= 3
      && (optionText.includes(target) || target.includes(optionText))
    ) {
      score = 260;
    } else if (
      target.length >= 3
      && optionValue.length >= 3
      && (optionValue.includes(target) || target.includes(optionValue))
    ) {
      score = 240;
    }

    if (score > bestScore) {
      bestScore = score;
      bestIndex = index;
    }
  }

  return bestIndex;
}
